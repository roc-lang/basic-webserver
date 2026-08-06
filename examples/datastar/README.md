# Datastar examples

This directory reproduces the public, non-Rocket examples from the
[Datastar example catalog](https://data-star.dev/examples/) in catalog order.
The examples are intentionally built into one Roc application so the release
matrix adds one realistic server binary rather than one binary per page.
Its entrypoint is `main.roc`, allowing Roc tooling opened from any component to
discover the application root.

Each reproduction is an executable API probe. Server-driven examples use the
example-local Datastar helpers together with the platform's generic `Sse` API;
browser-only examples remain ordinary HTML so they do not invent server state
or platform facilities.

## Example-local helpers

This directory owns an intentionally opinionated Datastar integration:

- `Datastar.roc` decodes signals and constructs Datastar wire events;
- `DatastarMarkup.roc` and `DatastarSignals.roc` provide the typed markup and
  signal-building approach used by these examples; and
- `ElementId.roc`, `Selector.roc`, `SignalName.roc`, and `RoutePath.roc` provide
  the validated values that support that approach.

These modules are part of the example, not the platform API. They demonstrate
one possible integration and are not intended to constrain a future reusable
Datastar package, which may choose different abstractions or tradeoffs. The
platform owns only generic SSE construction, scheduling, framing,
backpressure, compression, cancellation, and resource limits.

## Validation standard

The catalog uses layered coverage instead of repeating protocol edge cases in
every example:

- the Datastar example coverage owns signal transport, exact Datastar event
  framing, and finite-action response semantics;
- shared platform coverage owns generic SSE limits, framing, and
  identity/Brotli negotiation;
- every example's listener case checks its initial HTML, each server action,
  the resulting event semantics, and meaningful application error branches;
- retained-stream examples also check event order, completion or cancellation,
  and both identity and Brotli representations;
- browser checks drive the pinned Datastar client and assert the resulting DOM,
  since HTTP response assertions alone cannot prove client compatibility.

An example is checked off only after its applicable listener and browser
coverage passes. Purely browser-side examples still need a browser assertion;
serving their markup is not sufficient.

Run the native browser checks after building the showcase binary:

```sh
python scripts/test_datastar_browser.py \
  --binary dist/example-binaries/x64musl/datastar/main
```

The command requires Firefox and geckodriver. It deliberately runs once for a
native artifact; the portable listener suite remains responsible for the full
release target matrix.

Use a recent Roc `main` build. Roc builds before the erased-callable ownership
fixes merged in roc-lang/roc#10530 can abort with `bad allocation magic` after
repeated Datastar actions on one persistent connection. The listener suite
keeps 1,000 alternating Active Search actions on one connection as a regression
case; `--repeat N` applies the same stress to the Firefox checks.

The client is the repository's already-pinned Datastar v1.0.2 bundle. The
example pages are adaptations, not copies of the Datastar site's surrounding
navigation or visual design.

Unlike released examples, `main.roc` deliberately imports the repository's
local platform. Its Datastar helpers are local Roc modules in this directory,
so from the repository root `roc examples/datastar/main.roc` exercises both
the current generic platform and this example's integration.

Click To Load, Bulk Update, Click To Edit, and Animations exercise the local
typed-markup approach. They use nominal signals, expressions, actions, request
and patch targets, compile-time literal validation, composable signal record
builders, validated domain values, element-owning text bindings,
component-owned dispatch, closed timer state machines, and a captured component
inside retained SSE sources while retaining deliberate escape hatches at the
boundary. `scripts/test_datastar_markup_types.py` maintains the corresponding
compile-failure contract.

## Catalog progress

- [x] Active Search
- [x] Animations
- [x] Bad Apple
- [x] Bulk Update
- [x] Click To Edit
- [x] Click To Load
- [x] Custom Event
- [x] Custom Plugin
- [x] DBmon
- [x] Delete Row
- [x] Edit Row
- [x] Event Bubbling
- [x] File Upload
- [x] Form Data
- [x] Infinite Scroll
- [x] Inline Validation
- [x] Lazy Load
- [x] Lazy Tabs
- [x] On Signal Patch
- [x] Progress Bar
- [x] Progressive Load
- [x] Sortable
- [x] SVG Morphing
- [x] Templ Counter
- [x] Title Update
- [x] TodoMVC
- [x] Web Component
- [x] Match Media

The Rocket examples are deliberately excluded as requested.
