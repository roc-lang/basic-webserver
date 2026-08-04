import ./Page
import pf.Attribute
import pf.Datastar
import pf.DatastarMarkup
import pf.DatastarMarkup.RequestTarget
import pf.DatastarMarkup.Signal
import pf.ElementId
import pf.Html
import pf.RoutePath
import pf.Server
import pf.Sse

AnimationsSignals : { shouldRestore : Bool }

ThrobState := [BlueOnOrange, GrayOnRed, OrangeOnGray, RedOnBlue]

ThrobColors : { background : Str, foreground : Str }

FadeOutState := [FadeOutDone, FadeOutRemove, FadeOutRestore, FadeOutStart]

FadeInState := [FadeInDone, FadeInReveal, FadeInStart]

FadeOutAppearance := [FadeOutHidden, FadeOutReady]

FadeInAppearance := [FadeInHidden, FadeInReady, FadeInRevealing]

## A self-contained Animations component. It owns all five routes and keeps
## each timed stream's legal transitions in a dedicated state type.
Animations :: {
	fade_in_id : ElementId,
	fade_in_target : RequestTarget,
	fade_out_id : ElementId,
	fade_out_target : RequestTarget,
	page_target : RequestTarget,
	should_restore : Signal(Bool),
	throb_id : ElementId,
	throb_target : RequestTarget,
	view_transition_id : ElementId,
	view_transition_target : RequestTarget,
}.{
	Config : {
		fade_in_id : ElementId,
		fade_in_path : RoutePath,
		fade_out_id : ElementId,
		page_path : RoutePath,
		throb_id : ElementId,
		throb_path : RoutePath,
		view_transition_id : ElementId,
		view_transition_path : RoutePath,
	}

	default : Animations
	default = Animations.new({
		fade_in_id: "fade-me-in",
		fade_in_path: "/examples/animations/fade_me_in",
		fade_out_id: "fade-out-swap",
		page_path: "/examples/animations",
		throb_id: "throb",
		throb_path: "/examples/animations/throb",
		view_transition_id: "view-transition",
		view_transition_path: "/examples/animations/view_transition",
	})

	new : Config -> Animations
	new = |config|
		Animations.(
			{
				fade_in_id: config.fade_in_id,
				fade_in_target: RequestTarget.get(config.fade_in_path),
				fade_out_id: config.fade_out_id,
				fade_out_target: RequestTarget.delete(config.page_path),
				page_target: RequestTarget.get(config.page_path),
				should_restore: Signal.bool("shouldRestore"),
				throb_id: config.throb_id,
				throb_target: RequestTarget.get(config.throb_path),
				view_transition_id: config.view_transition_id,
				view_transition_target: RequestTarget.get(config.view_transition_path),
			},
		)

	## Handle the page, finite view transition, and three retained timer stream
	## routes owned by this component.
	respond! : Animations, Server.Request, Str => Try([Handled(Server.Outcome), NotHandled], [ServerErr(Str), ..])
	respond! = |component, request, raw_path| {
		method = request.method()
		if component.page_target.matches(method, raw_path) {
			Ok(Handled(Server.respond(Page.response(component.document()))))
		} else if component.throb_target.matches(method, raw_path) {
			Ok(Handled(Server.stream(Sse.unfold!(BlueOnOrange, |state| throb_transition!(component, state)))))
		} else if component.view_transition_target.matches(method, raw_path) {
			view_transition!(component, request).map_ok(|outcome| Handled(outcome))
		} else if component.fade_out_target.matches(method, raw_path) {
			Ok(Handled(Server.stream(Sse.unfold!(FadeOutStart, |state| fade_out_transition!(component, state)))))
		} else if component.fade_in_target.matches(method, raw_path) {
			Ok(Handled(Server.stream(Sse.unfold!(FadeInStart, |state| fade_in_transition!(component, state)))))
		} else {
			Ok(NotHandled)
		}
	}

	document : Animations -> Html.Document
	document = |component|
		Page.document(
			"Animations",
			[
				Html.h1([], [Html.text("Animations")]),
				Html.p([], [Html.text("Stable element IDs let CSS and the View Transitions API animate server-driven patches.")]),
				Html.h2([], [Html.text("Color Throb")]),
				demo_fieldset([throb_node(component, { foreground: "brown", background: "orange" })]),
				Html.h2([], [Html.text("View Transitions")]),
				demo_fieldset([view_transition_button(component, Bool.False)]),
				Html.h2([], [Html.text("Fade Out On Swap")]),
				demo_fieldset([fade_out_button(component, FadeOutReady)]),
				Html.h2([], [Html.text("Fade In On Addition")]),
				demo_fieldset([fade_in_button(component, FadeInReady)]),
				Html.h2([], [Html.text("What this validates")]),
				Html.p([], [Html.text("One typed component composes a finite view-transition response with captured host-scheduled timer streams and delayed multi-event transitions.")]),
			],
		)
}

view_transition! : Animations, Server.Request => Try(Server.Outcome, [ServerErr(Str), ..])
view_transition! = |component, request| {
	parsed : Try(AnimationsSignals, Datastar.SignalsError)
	parsed = Datastar.read_signals!(request)
	signals =
		match parsed {
			Ok(value) => value
			Err(err) => return Ok(Server.respond(Page.text_response(400, "Invalid Animations signals: ${Str.inspect(err)}")))
		}

	next = Bool.not(signals.shouldRestore)
	fragment = Html.render_fragment([view_transition_button(component, next)])
	Ok(Datastar.respond([component.view_transition_id.patch_target().replace_with_view_transition(fragment)]))
}

throb_transition! : Animations, ThrobState => Try(Sse.Step(ThrobState), [StreamFailed(Str)])
throb_transition! = |component, state| {
	(colors, next) =
		match state {
			BlueOnOrange => ({ foreground: "blue", background: "orange" }, OrangeOnGray)
			OrangeOnGray => ({ foreground: "orange", background: "gray" }, GrayOnRed)
			GrayOnRed => ({ foreground: "gray", background: "red" }, RedOnBlue)
			RedOnBlue => ({ foreground: "red", background: "blue" }, BlueOnOrange)
		}

	Ok(
		Emit({
			event: DatastarMarkup.patch_elements(Html.render_fragment([throb_node(component, colors)])),
			state: next,
			wake: After(1000),
		}),
	)
}

fade_out_transition! : Animations, FadeOutState => Try(Sse.Step(FadeOutState), [StreamFailed(Str)])
fade_out_transition! = |component, state|
	match state {
		FadeOutStart => Ok(
			Emit({
				event: DatastarMarkup.patch_elements(Html.render_fragment([fade_out_button(component, FadeOutHidden)])),
				state: FadeOutRemove,
				wake: After(1000),
			}),
		)
		FadeOutRemove => Ok(
			Emit({
				event: DatastarMarkup.patch_elements(Html.render_fragment([Html.div([component.fade_out_id.attribute()], [])])),
				state: FadeOutRestore,
				wake: After(1000),
			}),
		)
		FadeOutRestore => Ok(
			Emit({
				event: DatastarMarkup.patch_elements(Html.render_fragment([fade_out_button(component, FadeOutReady)])),
				state: FadeOutDone,
				wake: Immediately,
			}),
		)
		FadeOutDone => Ok(End)
	}

fade_in_transition! : Animations, FadeInState => Try(Sse.Step(FadeInState), [StreamFailed(Str)])
fade_in_transition! = |component, state|
	match state {
		FadeInStart => Ok(
			Emit({
				event: DatastarMarkup.patch_elements(Html.render_fragment([fade_in_button(component, FadeInHidden)])),
				state: FadeInReveal,
				wake: After(1000),
			}),
		)
		FadeInReveal => Ok(
			Emit({
				event: DatastarMarkup.patch_elements(Html.render_fragment([fade_in_button(component, FadeInRevealing)])),
				state: FadeInDone,
				wake: Immediately,
			}),
		)
		FadeInDone => Ok(End)
	}

view_transition_button : Animations, Bool -> Html.Node
view_transition_button = |component, should_restore| {
	label =
		if should_restore {
			"Restore It!"
		} else {
			"Swap It!"
		}
	Html.button(
		[
			component.view_transition_id.attribute(),
			DatastarMarkup.signals([component.should_restore.definition(should_restore)]),
			component.view_transition_target.request().on_click(),
		],
		[Html.text(label)],
	)
}

throb_node : Animations, ThrobColors -> Html.Node
throb_node = |component, colors|
	Html.div(
		[
			component.throb_id.attribute(),
			Attribute.style("color: var(--${colors.foreground}-8); background-color: var(--${colors.background}-5); padding: 2rem; transition: color 1s, background-color 1s"),
			component.throb_target.request().on_init(),
		],
		[Html.text("${colors.foreground} on ${colors.background}")],
	)

fade_out_button : Animations, FadeOutAppearance -> Html.Node
fade_out_button = |component, appearance| {
	appearance_attributes =
		match appearance {
			FadeOutReady => []
			FadeOutHidden => [Attribute.style("transition: opacity 1s ease-out; opacity: 0"), Attribute.disabled]
		}
	Html.button(
		List.concat(
			[
				component.fade_out_id.attribute(),
				component.fade_out_target.request().on_click(),
			],
			appearance_attributes,
		),
		[Html.text("Fade out then delete on click")],
	)
}

fade_in_button : Animations, FadeInAppearance -> Html.Node
fade_in_button = |component, appearance| {
	appearance_attributes =
		match appearance {
			FadeInReady => [Attribute.style("transition: opacity 1s ease-out")]
			FadeInHidden => [Attribute.style("opacity: 0"), Attribute.disabled]
			FadeInRevealing => [Attribute.style("transition: opacity 1s ease-out")]
		}
	Html.button(
		List.concat(
			[
				component.fade_in_id.attribute(),
				component.fade_in_target.request().on_click(),
			],
			appearance_attributes,
		),
		[Html.text("Fade me in on click")],
	)
}

demo_fieldset : List(Html.Node) -> Html.Node
demo_fieldset = |children|
	Html.element(
		"fieldset",
		[],
		List.concat([Html.element("legend", [], [Html.text("Demo")])], children),
	)
