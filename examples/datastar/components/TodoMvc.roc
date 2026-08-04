import ./Page
import pf.Attribute
import pf.Datastar
import pf.Html
import pf.Server

Todo : { completed : Bool, id : U64, title : Str }

TodoSignals : {
	editTitle : Str,
	editingId : I64,
	input : Str,
	mode : U64,
	todos : List(Todo),
}

## A stateless TodoMVC implementation. The browser carries the complete todo
## state in Datastar signals and every action returns the next state plus one
## stable application-root patch.
TodoMvc :: [].{

	respond! : Server.Request, Str => Try([Handled(Server.Outcome), NotHandled], [ServerErr(Str), ..])
	respond! = |request, path| {
		parts = Str.split_on(path, "/")
		match (request.method(), parts) {
			(GET, ["", "examples", "todomvc"]) => Ok(Handled(page))
			(GET, ["", "examples", "todomvc", "updates"]) => Ok(Handled(respond_state(default_state)))
			(PATCH, ["", "examples", "todomvc", "-1"]) => add!(request).map_ok(|outcome| Handled(outcome))
			(POST, ["", "examples", "todomvc", "-1", "toggle"]) => toggle_all!(request).map_ok(|outcome| Handled(outcome))
			(PUT, ["", "examples", "todomvc", "mode", "0"]) => set_mode!(request, 0).map_ok(|outcome| Handled(outcome))
			(PUT, ["", "examples", "todomvc", "mode", "1"]) => set_mode!(request, 1).map_ok(|outcome| Handled(outcome))
			(PUT, ["", "examples", "todomvc", "mode", "2"]) => set_mode!(request, 2).map_ok(|outcome| Handled(outcome))
			(DELETE, ["", "examples", "todomvc", "completed"]) => delete_completed!(request).map_ok(|outcome| Handled(outcome))
			(GET, ["", "examples", "todomvc", "cancel"]) => cancel_edit!(request).map_ok(|outcome| Handled(outcome))
			(PUT, ["", "examples", "todomvc", "reset"]) => reset!(request).map_ok(|outcome| Handled(outcome))
			(POST, ["", "examples", "todomvc", raw_id, "toggle"]) => route_id_action!(request, raw_id, Toggle).map_ok(|outcome| Handled(outcome))
			(GET, ["", "examples", "todomvc", raw_id, "edit"]) => route_id_action!(request, raw_id, StartEdit).map_ok(|outcome| Handled(outcome))
			(PUT, ["", "examples", "todomvc", raw_id]) => route_id_action!(request, raw_id, SaveEdit).map_ok(|outcome| Handled(outcome))
			(DELETE, ["", "examples", "todomvc", raw_id]) => route_id_action!(request, raw_id, Delete).map_ok(|outcome| Handled(outcome))
			(_, ["", "examples", "todomvc", ..]) => Ok(Handled(not_found))
			_ => Ok(NotHandled)
		}
	}
}

TodoAction : [Delete, SaveEdit, StartEdit, Toggle]

default_state : TodoSignals
default_state = {
	editTitle: "",
	editingId: -1,
	input: "",
	mode: 0,
	todos: [
		{ completed: Bool.False, id: 0, title: "Learn any backend language" },
		{ completed: Bool.False, id: 1, title: "Learn Datastar" },
		{ completed: Bool.False, id: 2, title: "???" },
		{ completed: Bool.True, id: 3, title: "Profit" },
	],
}

page : Server.Outcome
page =
	Server.respond(
		Page.response(
			Page.document(
				"TodoMVC",
				[
					Html.h1([], [Html.text("TodoMVC")]),
					Html.p([], [Html.text("Add, edit, complete, delete, and filter todos through finite Datastar actions.")]),
					Html.element(
						"fieldset",
						[],
						[
							Html.element("legend", [], [Html.text("Demo")]),
							todo_root(default_state, Bool.True),
						],
					),
					Html.h2([], [Html.text("What this validates")]),
					Html.p([], [Html.text("The complete TodoMVC state travels in bounded signals. The server validates each transition and returns escaped markup plus the next signal document without process-local mutable state.")]),
				],
			),
		),
	)

todo_root : TodoSignals, Bool -> Html.Node
todo_root = |state, include_init| {
	root_attrs = [
		Attribute.id("todomvc"),
		Attribute.attribute("data-signals", Json.to_str(state)),
	]
	attrs =
		if include_init {
			root_attrs.append(Attribute.attribute("data-init", "@get('/examples/todomvc/updates')"))
		} else {
			root_attrs
		}

	Html.element(
		"section",
		attrs,
		[
			todo_header(state),
			Html.ul([Attribute.id("todo-list")], visible_todos(state).map(|todo| todo_item(state, todo))),
			todo_actions(state),
		],
	)
}

todo_header : TodoSignals -> Html.Node
todo_header = |state| {
	toggle_attrs = [
		Attribute.type("checkbox"),
		Attribute.attribute("data-action", "toggle-all-todos"),
		Attribute.attribute("aria-label", "Toggle all todos"),
		Attribute.attribute("data-on:click__prevent", "@post('/examples/todomvc/-1/toggle')"),
	]
	toggle_attrs_with_state =
		if all_completed(state.todos) {
			toggle_attrs.append(Attribute.attribute("checked", ""))
		} else {
			toggle_attrs
		}

	Html.header(
		[Attribute.id("todo-header")],
		[
			Html.input(toggle_attrs_with_state),
			Html.input([
				Attribute.id("new-todo"),
				Attribute.type("text"),
				Attribute.attribute("placeholder", "What needs to be done?"),
				Attribute.attribute("data-bind:input", ""),
				Attribute.attribute("data-on:keydown", "evt.key === 'Enter' && $input.trim() && @patch('/examples/todomvc/-1')"),
			]),
		],
	)
}

todo_item : TodoSignals, Todo -> Html.Node
todo_item = |state, todo| {
	id = U64.to_str(todo.id)
	if state.editingId == U64.to_i64_wrap(todo.id) {
		Html.li(
			[Attribute.id("todo-${id}"), Attribute.attribute("data-todo-id", id), Attribute.class("editing")],
			[
				Html.input([
					Attribute.id("edit-todo-${id}"),
					Attribute.type("text"),
					Attribute.attribute("data-bind:edit-title", ""),
					Attribute.attribute("data-on:keydown", "evt.key === 'Enter' && $editTitle.trim() && @put('/examples/todomvc/${id}')"),
				]),
				Html.button(
					[Attribute.attribute("data-action", "save-todo-${id}"), Attribute.attribute("data-on:click", "@put('/examples/todomvc/${id}')")],
					[Html.text("Save")],
				),
				Html.button(
					[Attribute.attribute("data-action", "cancel-todo-edit"), Attribute.attribute("data-on:click", "@get('/examples/todomvc/cancel')")],
					[Html.text("Cancel")],
				),
			],
		)
	} else {
		checkbox_attrs = [
			Attribute.type("checkbox"),
			Attribute.attribute("data-action", "toggle-todo-${id}"),
			Attribute.attribute("data-on:click__prevent", "@post('/examples/todomvc/${id}/toggle')"),
		]
		checkbox_attrs_with_state =
			if todo.completed {
				checkbox_attrs.append(Attribute.attribute("checked", ""))
			} else {
				checkbox_attrs
			}
		item_class = if todo.completed {
			"completed"
		} else {
			"pending"
		}
		Html.li(
			[Attribute.id("todo-${id}"), Attribute.attribute("data-todo-id", id), Attribute.class(item_class)],
			[
				Html.input(checkbox_attrs_with_state),
				Html.span(
					[Attribute.attribute("data-todo-title", id), Attribute.attribute("data-on:dblclick", "@get('/examples/todomvc/${id}/edit')")],
					[Html.text(todo.title)],
				),
				Html.button(
					[Attribute.attribute("data-action", "edit-todo-${id}"), Attribute.attribute("data-on:click", "@get('/examples/todomvc/${id}/edit')")],
					[Html.text("Edit")],
				),
				Html.button(
					[Attribute.attribute("data-action", "delete-todo-${id}"), Attribute.attribute("data-on:click", "@delete('/examples/todomvc/${id}')")],
					[Html.text("Delete")],
				),
			],
		)
	}
}

todo_actions : TodoSignals -> Html.Node
todo_actions = |state| {
	pending : U64
	pending = state.todos.fold(
		0,
		|count, todo| if todo.completed {
			count
		} else {
			count + 1
		},
	)
	completed : U64
	completed = state.todos.fold(
		0,
		|count, todo| if todo.completed {
			count + 1
		} else {
			count
		},
	)
	pending_label = if pending == 1 {
		"item pending"
	} else {
		"items pending"
	}
	delete_attrs = [
		Attribute.attribute("data-action", "delete-completed-todos"),
		Attribute.attribute("data-on:click", "@delete('/examples/todomvc/completed')"),
	]
	delete_attrs_with_state =
		if completed == 0 {
			delete_attrs.append(Attribute.disabled)
		} else {
			delete_attrs
		}

	Html.div(
		[Attribute.id("todo-actions")],
		[
			Html.span([Attribute.id("todo-pending")], [Html.element("strong", [], [Html.text(U64.to_str(pending))]), Html.text(" ${pending_label}")]),
			mode_button("All", 0, state.mode),
			mode_button("Pending", 1, state.mode),
			mode_button("Completed", 2, state.mode),
			Html.button(delete_attrs_with_state, [Html.text("Delete completed")]),
			Html.button(
				[Attribute.attribute("data-action", "reset-todos"), Attribute.attribute("data-on:click", "@put('/examples/todomvc/reset')")],
				[Html.text("Reset")],
			),
		],
	)
}

mode_button : Str, U64, U64 -> Html.Node
mode_button = |label, mode, current_mode| {
	mode_str = U64.to_str(mode)
	class_name = if mode == current_mode {
		"selected"
	} else {
		""
	}
	Html.button(
		[
			Attribute.class(class_name),
			Attribute.attribute("data-mode", mode_str),
			Attribute.attribute("data-on:click", "@put('/examples/todomvc/mode/${mode_str}')"),
		],
		[Html.text(label)],
	)
}

visible_todos : TodoSignals -> List(Todo)
visible_todos = |state|
	state.todos.keep_if(
		|todo|
			match state.mode {
				1 => Bool.not(todo.completed)
				2 => todo.completed
				_ => Bool.True
			},
	)

all_completed : List(Todo) -> Bool
all_completed = |todos| Bool.not(todos.is_empty()) and todos.all(|todo| todo.completed)

respond_state : TodoSignals -> Server.Outcome
respond_state = |state|
	Datastar.respond([
		Datastar.patch_signals(Json.to_str(state)),
		Datastar.patch_elements(Html.render_without_doc_type(todo_root(state, Bool.False))),
	])

ParsedState : [Parsed(TodoSignals), Rejected(Server.Outcome)]

read_state! : Server.Request => Try(ParsedState, [ServerErr(Str), ..])
read_state! = |request| {
	parsed : Try(TodoSignals, Datastar.SignalsError)
	parsed = Datastar.read_signals!(request)
	Ok(
		match parsed {
			Ok(state) => Parsed(state)
			Err(err) => Rejected(Server.respond(Page.text_response(400, "Invalid TodoMVC signals: ${Str.inspect(err)}")))
		},
	)
}

mutate! : Server.Request, (TodoSignals -> TodoSignals) => Try(Server.Outcome, [ServerErr(Str), ..])
mutate! = |request, transform|
	match read_state!(request)? {
		Rejected(outcome) => Ok(outcome)
		Parsed(state) => Ok(respond_state(transform(state)))
	}

add! : Server.Request => Try(Server.Outcome, [ServerErr(Str), ..])
add! = |request|
	match read_state!(request)? {
		Rejected(outcome) => Ok(outcome)
		Parsed(state) => {
			if state.input.is_empty() {
				Ok(Server.respond(Page.text_response(422, "A todo title is required")))
			} else {
				next_id : U64
				next_id = state.todos.fold(
					0,
					|candidate, todo| if todo.id >= candidate {
						todo.id + 1
					} else {
						candidate
					},
				)
				next = { ..state, input: "", todos: state.todos.append({ completed: Bool.False, id: next_id, title: state.input }) }
				Ok(respond_state(next))
			}
		}
	}

toggle_all! : Server.Request => Try(Server.Outcome, [ServerErr(Str), ..])
toggle_all! = |request|
	mutate!(
		request,
		|state| {
			completed = Bool.not(all_completed(state.todos))
			{ ..state, todos: state.todos.map(|todo| { ..todo, completed }) }
		},
	)

set_mode! : Server.Request, U64 => Try(Server.Outcome, [ServerErr(Str), ..])
set_mode! = |request, mode| mutate!(request, |state| { ..state, mode })

delete_completed! : Server.Request => Try(Server.Outcome, [ServerErr(Str), ..])
delete_completed! = |request|
	mutate!(request, |state| { ..state, todos: state.todos.keep_if(|todo| Bool.not(todo.completed)) })

cancel_edit! : Server.Request => Try(Server.Outcome, [ServerErr(Str), ..])
cancel_edit! = |request| mutate!(request, |state| { ..state, editTitle: "", editingId: -1 })

reset! : Server.Request => Try(Server.Outcome, [ServerErr(Str), ..])
reset! = |request| mutate!(request, |_state| default_state)

route_id_action! : Server.Request, Str, TodoAction => Try(Server.Outcome, [ServerErr(Str), ..])
route_id_action! = |request, raw_id, action|
	match parse_id(raw_id) {
		Err(_) => Ok(not_found)
		Ok(id) =>
			match action {
				Toggle => toggle!(request, id)
				StartEdit => start_edit!(request, id)
				SaveEdit => save_edit!(request, id)
				Delete => delete!(request, id)
			}
		}

toggle! : Server.Request, U64 => Try(Server.Outcome, [ServerErr(Str), ..])
toggle! = |request, id|
	mutate!(
		request,
		|state| {
			..state,
			todos: state.todos.map(
				|todo| if todo.id == id {
					{ ..todo, completed: Bool.not(todo.completed) }
				} else {
					todo
				},
			),
		},
	)

start_edit! : Server.Request, U64 => Try(Server.Outcome, [ServerErr(Str), ..])
start_edit! = |request, id|
	match read_state!(request)? {
		Rejected(outcome) => Ok(outcome)
		Parsed(state) => {
			if Bool.not(state.todos.any(|todo| todo.id == id)) {
				Ok(not_found)
			} else {
				title = state.todos.fold(
					"",
					|found, todo| if todo.id == id {
						todo.title
					} else {
						found
					},
				)
				Ok(respond_state({ ..state, editTitle: title, editingId: U64.to_i64_wrap(id) }))
			}
		}
	}

save_edit! : Server.Request, U64 => Try(Server.Outcome, [ServerErr(Str), ..])
save_edit! = |request, id|
	match read_state!(request)? {
		Rejected(outcome) => Ok(outcome)
		Parsed(state) => {
			if Bool.not(state.todos.any(|todo| todo.id == id)) {
				Ok(not_found)
			} else if state.editTitle.is_empty() {
				Ok(Server.respond(Page.text_response(422, "A todo title is required")))
			} else {
				next_todos = state.todos.map(
					|todo| if todo.id == id {
						{ ..todo, title: state.editTitle }
					} else {
						todo
					},
				)
				Ok(respond_state({ ..state, editTitle: "", editingId: -1, todos: next_todos }))
			}
		}
	}

delete! : Server.Request, U64 => Try(Server.Outcome, [ServerErr(Str), ..])
delete! = |request, id|
	mutate!(request, |state| { ..state, todos: state.todos.keep_if(|todo| todo.id != id) })

parse_id : Str -> Try(U64, [InvalidTodoId])
parse_id = |raw| {
	bytes = Str.to_utf8(raw)
	if bytes.is_empty() or bytes.len() > 19 or Bool.not(bytes.all(|byte| byte >= 48 and byte <= 57)) {
		Err(InvalidTodoId)
	} else {
		Ok(bytes.fold(0, |value, byte| value * 10 + U8.to_u64(byte - 48)))
	}
}

not_found : Server.Outcome
not_found = Server.respond(Page.text_response(404, "Todo not found"))
