# Typed Datastar markup feasibility spike

Date: 2026-08-04

Status: validated experiment; API names and numeric/binding boundaries remain
provisional.

## Question

Can basic-webserver offer an idiomatic Roc API for Datastar markup which uses
receiver-style static dispatch, makes common protocol-invalid states
unrepresentable, and preserves static top-level rendering without becoming a
complete frontend, JavaScript, HTML-content-model, or routing framework?

The spike converts Click To Load, Bulk Update, and Click To Edit. Together they
exercise static pages, typed scalar and list signals, excluded-by-default fetch
indicators, backend requests, server dispatch, dynamic HTML fragments, explicit
append and replacement targets, signal updates, checkbox and text-input
bindings, event-local checked state, validated domain values, and coordinated
signal/element patches.

## Candidate boundary

The existing `Datastar` module continues to own request decoding and the wire
protocol. The pure `DatastarMarkup` companion owns browser markup descriptions:

- `Signal(a)` grounds one canonical name with an exact initial Roc type;
- `Expr(a)` represents a small typed expression subset;
- `Action` represents a client action before it is attached to a `DomEvent`;
- `RequestTarget` owns an HTTP verb and validated route path;
- `SignalDef` and `SignalUpdate` erase heterogeneous value types only after
  checking and JSON encoding;
- `ElementId` supplies both the HTML `id` attribute and patch target;
- `PatchTarget` requires a selector before append/prepend/remove operations can
  be constructed; and
- `Html.Fragment` and `Html.Document` distinguish rendered markup from ordinary
  `Str` values.

Representative application code is:

```roc
page = DatastarMarkup.Signal.u64("page", 0)
fetching = DatastarMarkup.Signal.excluded_bool("fetching", Bool.False)
more = DatastarMarkup.RequestTarget.get("/examples/click_to_load/more")
agents : DatastarMarkup.ElementId
agents = "agents"

button = Html.button(
    [
        fetching.indicator(),
        fetching.disabled_when_true(),
        more.request().unless(fetching.expr()).on_click(),
    ],
    [Html.text("Load More")],
)

events = [
    agents.descendant("tbody").append(rows),
    DatastarMarkup.patch_signals([page.update(next_page)]),
]
```

The receiver type owns each transformation. Constructors remain associated
functions because there is no receiver yet. Cross-domain finalizers remain
namespaced where receiver ownership would invert module dependencies.

Bulk Update also validates component-owned actions. `activate()` and
`deactivate()` each return a distinct browser action which owns its typed PUT
target. The component's `respond!` method owns matching those same targets and
selecting their transitions. The application can only receive `Handled` or
`NotHandled`; it never supplies the status transition. This removes the
previous independent route strings and boolean flag, and makes pairing an
action route with the wrong transition unrepresentable in the application API:

```roc
match bulk_update.respond!(request, path) {
    Ok(Handled(outcome)) => Ok(outcome)
    Ok(NotHandled) => # continue dispatch
    Err(err) => Err(err)
}
```

The importing app cannot currently name the local type module's nested
`BulkUpdate.Action` in an explicit annotation, although its values and receiver
methods compose through inference. Importantly, this is not an authority or
proof boundary: an adversarial compile probe established that a bare constructor
of a nested nominal tag union remains spellable when its expected type is
inferred. A rejected design had `match_action()` return a nominal
`MatchedAction` for `apply!`; an importer could forge `ActivateMatched`, so that
did not make the state impossible. `respond!` is stronger and simpler because
the application supplies no transition value at all. A component library that
needs action types in public records or signatures would still need a separately
importable action type module or broader compiler support for exposing nested
types from local type modules.

Click To Edit adds a deliberately element-owning binding operation:

```roc
handles.first_name.text_input([
    Attribute.type("text"),
    handles.fetching.disabled_when_true(),
])
```

Returning `Html.Node` instead of a generic `data-bind` attribute makes binding
a string signal to a non-input element unrepresentable through this operation.
Separate constructors can cover textareas or selects if later examples justify
them without pretending all signal/element combinations are valid.

The component validates a structural draft into a nominal `Contact` before any
save or cancel result is rendered. Saved browser signals are still untrusted
request data, so Cancel validates them too. The application config constructor
returns `Try(ClickToEdit, [InvalidInitialContact])`; only the known-valid static
default is constructed directly inside the module.

## Compile-time literal conversion

`SignalName`, `RoutePath`, `Selector`, and `ElementId` implement Roc's
well-known `from_quote` method. Their constructors take these nominal types, so
ordinary-looking arguments are parsed during checking:

```roc
Signal.u64("page", 0)
RequestTarget.get("/examples/click_to_load/more")
agents.descendant("tbody")
```

Invalid literals produce an `INVALID STRING` compiler diagnostic at the
literal. Dynamic strings must call the corresponding fallible `parse` method.
This gives leaf values concise syntax while receiver builders preserve the
relationships between separately typed values.

`parser_for` is not the literal mechanism. It is a generic format-decoding hook
used by APIs such as JSON. A `from_quote` implementation can share a pure
parser with dynamic `parse`, but routing the literal through `parser_for` adds
no checking or diagnostic capability.

Whole Datastar actions should not implement `from_quote`. A parser could check
JavaScript-like syntax but could not prove that `$page` is the declared
`Signal(U64)`, that `@get(...)` uses the declared request target, or that the
server dispatches it. It would also require maintaining a JavaScript-adjacent
grammar. Similarly, `from_interpolation` has one homogeneous hole type and no
fallible compiler-unwrapped result, so it is not a sound foundation for mixed
typed Datastar templates. It may later support a narrow rendering convenience
after every hole has already been checked and erased to one `Part` type.

The current static-dispatch contract is documented in Roc's
[language reference](https://github.com/roc-lang/roc/blob/main/docs/langref/static-dispatch.md).

## Guarantees demonstrated

The typed surface prevents:

- toggling a `Signal(Str)`;
- updating a `Signal(Bool)` with a string;
- using `Expr(Str)` as a disabled condition;
- comparing expressions with different result types;
- passing a dynamic `Str` where a parsed `RoutePath` is required;
- accepting invalid literal signal names, route paths, selectors, or element
  IDs;
- duplicating the Click To Load signal name between initial markup and server
  updates;
- duplicating the request method/path between browser action and server
  dispatch;
- pairing Bulk Update's activate request target with its deactivate server
  transition, or vice versa;
- attaching the typed Click To Edit string binding to a non-input element;
- rendering an invalid Click To Edit draft or client-supplied saved contact as
  a valid contact;
- appending HTML without an explicit target;
- removing a target while also supplying an HTML fragment; and
- passing ordinary text or a complete document where a patchable fragment is
  required.

The compiler's inferred type for a generic `Signal.update` initially failed to
relate the phantom signal parameter to the supplied value, and a boolean signal
accepted a string update. An explicit private type-pinning helper repaired the
relationship without retaining an encoder callback in the signal. The
compile-failure suite now pins this regression. This finding validates why
negative compilation tests are required for phantom-typed APIs; plausible
source annotations are not evidence that inference preserved the intended
relationship.

## Explicit proof limits

The spike does not claim:

- globally unique signal names; independently constructed handles can still
  reuse one string with different types;
- agreement between browser signals and the independently inferred record
  passed to `Datastar.read_signals!`;
- fixed list lengths in a decoded signal record; Bulk Update validates its four
  selections and statuses once at the request boundary before constructing its
  fixed-shape state;
- that raw JavaScript, plugins, or server patches preserve a signal's type;
- full CSS selector validity or that a selector matches the current DOM;
- route registration completeness or uniqueness;
- complete HTML content-model validity;
- that a generic binding attribute is appropriate for the element receiving
  it; the spike intentionally omits generic `Signal.bind()`; or
- lossless browser representation of every `U64`. JavaScript integers are
  exact only through `2^53 - 1`, so a public API needs a checked browser integer
  type or a narrower numeric constructor.

Underscore-prefixed signals are called excluded-by-default, not private. A
Datastar request filter can include them, and they remain ordinary browser
state.

Raw expression/action and already-rendered-fragment constructors remain
conspicuous compatibility boundaries. They must not be described as providing
the guarantees of values assembled from typed handles.

## Evidence

The implementation currently passes:

- 231 platform `expect` tests, including literal conversion, heterogeneous
  definition/update erasure, JSON/JavaScript encoding, receiver expressions,
  event modifiers, checked-state expressions, patch targets, and rendered
  fragment/document states;
- eleven intentionally invalid application checks with required compiler
  diagnostics;
- `roc check`, an optimized `roc build`, and the complete 28-application
  validation suite;
- all 54 native runtime cases, including complete listener assertions for Click
  To Load, Bulk Update, and Click To Edit pages, actions, malformed signals,
  invalid contacts, and wrong-length lists; and
- the real Firefox suite for Active Search, Animations, Bad Apple, Bulk Update,
  Click To Edit, and Click To Load against pinned Datastar v1.0.2.

An uncached optimized build spent 218 ms in compile-time evaluation and 4.2 s
overall with a 284 MiB peak RSS on the research machine. The final complete
Click To Load document appears as one contiguous constant in the optimized
object, including the rendered initial rows and encoded attributes. This
confirms that the top-level `Html.Node -> Html.Document` builder is compile-time
work rather than request-path rendering.

Dynamic row fragments still construct and render nodes at request time. This
spike establishes correctness and static-page representation, not an
allocation win for genuinely dynamic HTML. Direct strings may remain a useful
low-level option if later allocation measurements show that the structured
renderer is material in a target workload.

## Decision

The direction passes the feasibility gate as a narrow typed companion. It does
not justify freezing the current names or expanding the platform into a full
router, DOM type-state system, or JavaScript parser.

Before treating the API as stable:

1. replace or constrain the provisional `Signal.u64` browser-number model;
2. try Animations for view transitions, timed actions, and attribute ordering;
3. count unchecked escapes and judge whether the typed subset remains honest;
4. measure dynamic fragment allocations and compiler/binary-size deltas; and
5. decide whether `DatastarMarkup` remains platform-exposed or becomes a
   separately versioned first-party Roc package.
