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

	event_bubbling : () -> Server.Outcome
	event_bubbling = || Server.respond(Page.response(event_bubbling_document))

	on_signal_patch : () -> Server.Outcome
	on_signal_patch = || Server.respond(Page.response(on_signal_patch_document))

	sortable : () -> Server.Outcome
	sortable = || Server.respond(Page.response(sortable_document))

	web_component : () -> Server.Outcome
	web_component = || Server.respond(Page.response(web_component_document))

	match_media : () -> Server.Outcome
	match_media = || Server.respond(Page.response(match_media_document))
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

event_bubbling_document : Html.Document
event_bubbling_document =
	Page.document(
		"Event Bubbling",
		[
			Html.h1([], [Html.text("Event Bubbling")]),
			Html.p([], [Html.text("Handle clicks from many buttons with one listener on their common container.")]),
			demo([Html.dangerously_include_unescaped_html(event_bubbling_demo)]),
			Html.h2([], [Html.text("What this validates")]),
			Html.p([], [Html.text("A Datastar event expression receives the native event and can inspect the originating descendant after the event bubbles.")]),
		],
	)

on_signal_patch_document : Html.Document
on_signal_patch_document =
	Page.document(
		"On Signal Patch",
		[
			Html.h1([], [Html.text("On Signal Patch")]),
			Html.p([], [Html.text("Observe all signal changes or filter the observer to one signal path.")]),
			demo([Html.dangerously_include_unescaped_html(on_signal_patch_demo)]),
			Html.h2([], [Html.text("What this validates")]),
			Html.p([], [Html.text("The pinned client exposes signal patches to reactive observers and applies path filters before evaluating an observer expression.")]),
		],
	)

sortable_document : Html.Document
sortable_document =
	Page.document(
		"Sortable",
		[
			Html.h1([], [Html.text("Sortable")]),
			Html.p([], [Html.text("Reorder a list with native drag events and report the new order through a Datastar custom-event listener.")]),
			demo([Html.dangerously_include_unescaped_html(sortable_demo)]),
			Html.h2([], [Html.text("What this validates")]),
			Html.p([], [Html.text("Browser-owned sorting can publish a domain event into Datastar signals without adding server-owned state or a third-party runtime dependency.")]),
		],
	)

web_component_document : Html.Document
web_component_document =
	Page.document(
		"Web Component",
		[
			Html.h1([], [Html.text("Web Component")]),
			Html.p([], [Html.text("Bind a signal into a custom element and consume the custom event it emits.")]),
			demo([Html.dangerously_include_unescaped_html(web_component_demo)]),
			Html.h2([], [Html.text("What this validates")]),
			Html.p([], [Html.text("Datastar attributes interoperate with custom-element attributes and bubbling CustomEvents in both directions.")]),
		],
	)

match_media_document : Html.Document
match_media_document =
	Page.document(
		"Match Media",
		[
			Html.h1([], [Html.text("Match Media")]),
			Html.p([], [Html.text("Mirror the browser's color-scheme media query into a reactive signal.")]),
			demo([Html.dangerously_include_unescaped_html(match_media_demo)]),
			Html.h2([], [Html.text("What this validates")]),
			Html.p([], [Html.text("A browser media-query source can feed ordinary Datastar event, signal, text, and class bindings while staying within the pinned public client.")]),
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

event_bubbling_demo : Str
event_bubbling_demo =
	\\<div id="event-bubbling-demo" data-signals:key="">
	\\    <p>Key pressed: <span id="event-bubbling-key" data-text="$key"></span></p>
	\\    <div id="event-bubbling-container" data-on:click="$key = evt.target.closest('button[data-id]')?.dataset.id ?? $key">
	\\        <button data-id="KEY ELSE">KEY ELSE</button>
	\\        <button data-id="CM">CM</button>
	\\        <button data-id="OM">OM</button>
	\\        <button data-id="FETCH">FETCH</button>
	\\        <button data-id="SET">SET</button>
	\\        <button data-id="EXEC">EXEC</button>
	\\        <button data-id="TEST ALARM">TEST ALARM</button>
	\\        <button data-id="3">3</button>
	\\        <button data-id="2">2</button>
	\\        <button data-id="1">1</button>
	\\        <button data-id="ENTER">ENTER</button>
	\\        <button data-id="CLEAR">CLEAR</button>
	\\    </div>
	\\</div>

on_signal_patch_demo : Str
on_signal_patch_demo =
	\\<div id="on-signal-patch-demo" data-signals="{counter: 0, message: 'Hello World', allChanges: [], counterChanges: []}">
	\\    <p>Message: <strong id="signal-patch-message" data-text="$message">Hello World</strong></p>
	\\    <p>Counter: <strong id="signal-patch-counter" data-text="$counter">0</strong></p>
	\\    <button data-action="signal-message" data-on:click="$message = 'Updated message'">Update Message</button>
	\\    <button data-action="signal-counter" data-on:click="$counter++">Increment Counter</button>
	\\    <button data-action="signal-clear" data-on:click="$allChanges = []; $counterChanges = []">Clear Logs</button>
	\\    <section data-on-signal-patch__delay.1ms="$allChanges = [...$allChanges, patch]" data-on-signal-patch-filter="{exclude: /allChanges|counterChanges/}">
	\\        <h2>All changes</h2>
	\\        <pre id="all-signal-patches" data-json-signals__terse="{include: /^allChanges/}"></pre>
	\\    </section>
	\\    <section data-on-signal-patch__delay.1ms="$counterChanges = [...$counterChanges, patch]" data-on-signal-patch-filter="{include: /^counter$/}">
	\\        <h2>Counter changes</h2>
	\\        <pre id="counter-signal-patches" data-json-signals__terse="{include: /^counterChanges/}"></pre>
	\\    </section>
	\\</div>

sortable_demo : Str
sortable_demo =
	\\<div id="sortable-demo" data-signals:sort-order="'Alpha, Bravo, Charlie'" data-on:reordered="$sortOrder = evt.detail.order">
	\\    <p>Current order: <strong id="sortable-order" data-text="$sortOrder">Alpha, Bravo, Charlie</strong></p>
	\\    <ol id="sortable-list">
	\\        <li draggable="true" data-sort-item="Alpha">Alpha</li>
	\\        <li draggable="true" data-sort-item="Bravo">Bravo</li>
	\\        <li draggable="true" data-sort-item="Charlie">Charlie</li>
	\\    </ol>
	\\    <button id="sortable-move-first">Move first item to end</button>
	\\</div>
	\\<script>
	\\    const sortableRoot = document.getElementById('sortable-demo')
	\\    const sortableList = document.getElementById('sortable-list')
	\\    const publishSortableOrder = () => {
	\\        const order = [...sortableList.children].map(item => item.dataset.sortItem).join(', ')
	\\        sortableRoot.dispatchEvent(new CustomEvent('reordered', { detail: { order } }))
	\\    }
	\\    let draggedItem = null
	\\    sortableList.addEventListener('dragstart', event => {
	\\        draggedItem = event.target.closest('[data-sort-item]')
	\\    })
	\\    sortableList.addEventListener('dragover', event => event.preventDefault())
	\\    sortableList.addEventListener('drop', event => {
	\\        event.preventDefault()
	\\        const target = event.target.closest('[data-sort-item]')
	\\        if (draggedItem && target && draggedItem !== target) target.before(draggedItem)
	\\        publishSortableOrder()
	\\    })
	\\    document.getElementById('sortable-move-first').addEventListener('click', () => {
	\\        sortableList.append(sortableList.firstElementChild)
	\\        publishSortableOrder()
	\\    })
	\\</script>

web_component_demo : Str
web_component_demo =
	\\<div id="web-component-demo" data-signals="{name: 'Your Name', reversed: 'emaN ruoY'}">
	\\    <label>Name <input id="web-component-name" data-bind:name value="Your Name"></label>
	\\    <reverse-component id="reverse-component" name="Your Name" data-attr:name="$name" data-on:reverse="$reversed = evt.detail.value"></reverse-component>
	\\    <p>Reversed: <strong id="web-component-reversed" data-text="$reversed">emaN ruoY</strong></p>
	\\</div>
	\\<script>
	\\    if (!customElements.get('reverse-component')) {
	\\        customElements.define('reverse-component', class extends HTMLElement {
	\\            static observedAttributes = ['name']
	\\            connectedCallback() { this.update() }
	\\            attributeChangedCallback() { this.update() }
	\\            update() {
	\\                const value = this.getAttribute('name') || ''
	\\                const reversed = [...value].reverse().join('')
	\\                this.textContent = reversed
	\\                this.dispatchEvent(new CustomEvent('reverse', { bubbles: true, detail: { value: reversed } }))
	\\            }
	\\        })
	\\    }
	\\    document.documentElement.dataset.webComponentReady = 'true'
	\\</script>

match_media_demo : Str
match_media_demo =
	\\<div id="match-media-demo" data-signals:is-dark="false" data-on:mediachange="$isDark = evt.detail.matches">
	\\    <p id="match-media-result" data-text="$isDark ? 'Dark color scheme' : 'Light color scheme'">Checking color scheme</p>
	\\    <div id="match-media-card" data-class:dark="$isDark">This card follows the browser preference.</div>
	\\</div>
	\\<script>
	\\    const matchMediaRoot = document.getElementById('match-media-demo')
	\\    const colorScheme = window.matchMedia('(prefers-color-scheme: dark)')
	\\    const publishColorScheme = () => matchMediaRoot.dispatchEvent(new CustomEvent('mediachange', {
	\\        detail: { matches: colorScheme.matches },
	\\    }))
	\\    colorScheme.addEventListener('change', publishColorScheme)
	\\    setTimeout(publishColorScheme)
	\\    document.documentElement.dataset.matchMediaReady = 'true'
	\\</script>
