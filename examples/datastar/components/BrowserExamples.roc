import ./Page
import pf.Html
import pf.Server

## Browser-only Datastar examples. Their fixed scripts exercise the pinned
## client without introducing server-owned state or platform facilities.
BrowserExamples :: [].{

	custom_event : () -> Server.Outcome
	custom_event = || Server.respond(Page.response(custom_event_document))

	custom_plugin : () -> Server.Outcome
	custom_plugin = || Server.respond(Page.response(custom_plugin_document))
}

custom_event_document : Html.Document
custom_event_document =
	Page.document(
		"Custom Event",
		[
			Html.h1([], [Html.text("Custom Event")]),
			Html.p([], [Html.text("Listen for an application-defined browser event and expose its detail through a signal.")]),
			demo([
				Html.dangerously_include_unescaped_html(custom_event_demo),
			]),
			Html.h2([], [Html.text("What this validates")]),
			Html.p([], [Html.text("The pinned Datastar client can listen for arbitrary DOM events, make the event available to an expression, and update the page from its detail without a server request.")]),
		],
	)

custom_plugin_document : Html.Document
custom_plugin_document =
	Page.document(
		"Custom Plugin",
		[
			Html.h1([], [Html.text("Custom Plugin")]),
			Html.p([], [Html.text("Register one Datastar action and one Datastar attribute in the browser.")]),
			demo([
				Html.dangerously_include_unescaped_html(custom_plugin_demo),
			]),
			Html.h2([], [Html.text("What this validates")]),
			Html.p([], [Html.text("The pinned client exposes its plugin APIs to browser modules and applies both extension points to ordinary page markup without server-owned state.")]),
		],
	)

demo : List(Html.Node) -> Html.Node
demo = |children|
	Html.element(
		"fieldset",
		[],
		List.concat([Html.element("legend", [], [Html.text("Demo")])], children),
	)

custom_event_demo : Str
custom_event_demo =
	\\<p
	\\    id="custom-event-output"
	\\    data-signals:_event-details
	\\    data-on:myevent="$_eventDetails = evt.detail"
	\\    data-text="'Last Event Details: ' + $_eventDetails"
	\\></p>
	\\<script>
	\\    const customEventOutput = document.getElementById('custom-event-output')
	\\    setInterval(() => {
	\\        customEventOutput.dispatchEvent(new CustomEvent('myevent', {
	\\            detail: JSON.stringify({ eventTime: new Date().toLocaleTimeString() }),
	\\        }))
	\\    }, 1000)
	\\</script>

custom_plugin_demo : Str
custom_plugin_demo =
	\\<button data-plugin-kind="action" data-on:click="@alert('Hello from an action')">Alert using an action</button>
	\\<button data-plugin-kind="attribute" data-alert="'Hello from an attribute'">Alert using an attribute</button>
	\\<script type="module">
	\\    import { action, attribute } from '/datastar.js'
	\\
	\\    action({
	\\        name: 'alert',
	\\        apply(_ctx, message) {
	\\            window.alert(message)
	\\        },
	\\    })
	\\
	\\    attribute({
	\\        name: 'alert',
	\\        requirement: { key: 'denied', value: 'must' },
	\\        returnsValue: true,
	\\        apply({ el, rx }) {
	\\            const callback = () => window.alert(rx())
	\\            el.addEventListener('click', callback)
	\\            return () => el.removeEventListener('click', callback)
	\\        },
	\\    })
	\\
	\\    setTimeout(() => {
	\\        document.documentElement.dataset.customPluginReady = 'true'
	\\    })
	\\</script>
