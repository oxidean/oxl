# WI-0005 brainstorm — milestone G spec: portable GUI layer

Context: all five paradigm-level forks are owner-decided (WI-0004):
retained widget tree over a backend iface; own-tree scope-bound
widgets with `gui.Widget` for kinds; buffered `chan gui.Event` +
`select`; retained-widget backend protocol; `extra/gui` +
`extra/gui/gtk` packaging. This brainstorm covers only the forks that
remain open *inside* those decisions — the spec-level design space.

## Fork G-a — UI-thread model: convention vs language primitive

The pilot doc's sharpest finding: GTK is thread-bound; the blocking
pool is wrong for toolkits; "if the language grows native GUI support
it needs pin-this-task, not more pool semantics."

| option | shape | tradeoff |
|---|---|---|
| **A. Convention: `gui.run()` claims the calling task** | the layer documents "the task that calls `gui.run` owns the toolkit"; backend calls from other tasks are UB (same as GTK's own rule); app reaches the UI thread via `chan` | zero language change; matches GTK/Cocoa/Win32 reality (every toolkit pins to *a* thread); reversible — a primitive can layer on later without API break |
| B. `pin`/`uithread` primitive now | checker+runtime surface: a task declared UI-bound; misuse = compile error | stronger guarantee, but a language change justified by one consumer; risks designing thread-affinity before a second backend exists to constrain it |

Recommendation: **A** — convention first, documented as sharply as
GTK documents its own rule. Revisit at G6 with two backends' worth of
evidence; a primitive added then is additive, not breaking.

## Fork G-b — event delivery: single stream vs per-widget routing

| option | shape | tradeoff |
|---|---|---|
| **A. One buffered `chan Event`; handler fns per subscription** | `gui.on(w, "clicked", fn)` registers intent; backend posts `Event{kind, target, data}` to the app's chan; app `select`s and dispatches — handler map lives app-side | events are ordinary chan values: composes with `select` next to app channels; no reentrancy; ordering = FIFO with backend-defined coalescing |
| B. Backend invokes handlers directly on the UI thread | handlers run inside `gui.run`'s pump | zero chan plumbing but handlers can't `select`/suspend cleanly — fights the concurrency model (fork-3 already rejected callback-direct) |
| C. Per-widget chans | each widget owns a chan | chan-per-widget explosion; no global ordering; select-arm sprawl |

Recommendation: **A**. `Event` = struct `{kind: EventKind enum,
target: Widget, data: EventData}` — typed payload union per kind
(click carries none; text-change carries str; close carries none).
Buffer default 256, `gui.set_event_buffer(n)` for control; overflow
policy: drop-oldest with a `EventKind.overflow` marker (input events
must not silently vanish — a dropped "clicked" is a lost action).

## Fork G-c — property typing: stringly vs typed

| option | shape | tradeoff |
|---|---|---|
| **A. Typed setter per widget kind** | `button.set_label(s)`, `entry.set_text(s)`, `window.set_title(s)` — kinds expose concrete fns; backend iface gets `set_prop(w, PropId, PropVal)` internally | user API is typed (checked); backend protocol stays narrow — one PropVal tagged union instead of per-kind methods exploding the iface |
| B. Stringly `set_prop(w, "label", v)` everywhere | one fn for everything | uncheckable, un-discoverable — wrong for a language whose pitch is checked-everything |
| C. Full typed unions in the public API too | `gui.set(w, Prop.button_label("x"))` | verbose for the common case; good as the *backend* representation though |

Recommendation: **A** — typed public fns desugar to a narrow
`Prop{id, val}` protocol on the backend iface. DOM-mappability bonus:
`Prop` serializes to DOM attribute/property names cleanly.

## Fork G-d — first widget tranche

| option | shape | tradeoff |
|---|---|---|
| **A. Pilot parity + the diff that proves the layer** | window, box(h/v), label, button, entry, list, scrolled, image? — the pilot's 8 + layout stretch + one composite | the todo app re-expressed in `extra/gui` IS the reference; every widget proves a protocol path (container, text-in, text-out, trigger, list) |
| B. Wide tranche now | + slider, check, radio, combo, multiline, menu | bigger surface before the protocol proves out; review cost per PR |
| C. Minimal trio | window/box/button only | doesn't exercise text-in/text-out/list — the interesting protocol paths |

Recommendation: **A** — pilot parity (the 8 the shim already wraps)
plus whatever the reference app (G5) needs. Widgets beyond that are
post-milestone growth; the *protocol* is the milestone, not widget
count.

## Fork G-e — backend interface shape

| option | shape | tradeoff |
|---|---|---|
| **A. `gui.Backend` iface: `new(kind, props) -> Handle`, `set_prop`, `attach(parent, child)`, `detach`, `destroy`, `pump(events chan)`** | one iface the tree talks to; mock backend = pure-oxl impl for tests; GTK backend = `extra/gui/gtk` wrapping the shim | testable without a display (mock records protocol calls — the suite's answer to headless CI); DOM backend is the same iface |
| B. Free fns per backend selected at build time | `gtk.window_new(...)` directly | no iface indirection but no mock either — untestable headless, and backend choice becomes a link-time flag (wrong inversion) |
| C. Codegen-level widget dispatch | widgets are language builtins | conflates language with library — rejected by the extra/ decision |

Recommendation: **A**. Handles stay opaque ints (pilot-proven).
`pump` blocks the pinned task, decodes toolkit events into `Event`
structs, posts to the app's chan.

## Fork G-f — string ownership at the FFI boundary

Pilot finding: `str(c)` borrows GTK's buffer — aliases until the
widget mutates it. That is the bug-breeding place.

| option | shape | tradeoff |
|---|---|---|
| **A. Copy at boundary, always** | backend copies cstr→str on every out-param; text getters return owned strs | one rule, no lifetime literacy needed; small alloc cost per text read — negligible at GUI rates |
| B. Documented borrow | `entry.text()` returns a borrow valid until next mutation | zero-copy but every user must know the rule — the pilot doc calls this exactly where bugs breed |

Recommendation: **A** — copy at boundary. The layer's own code may
borrow internally where provable, but nothing borrowed crosses the
public API.

## Residual open questions for the spec (not forks — details)

- Event enum coverage for the first tranche (clicked/activate/
  text-changed/close-request/list-row-activated/overflow).
- Whether `gui.run` is reentrant-safe across nested modals — deferred;
  no dialogs in the first tranche.
- HiDPI/layout units — the pilot used raw pixels; the layer inherits
  that honestly until a second backend forces the question.
- a11y: declared out-of-scope for the milestone (DOM backend will need
  it; note as parked-with-trigger).

## Decision record

All six forks carry recommendations the specify stage adopts as
proposed-decisions; none is milestone-shaping enough to park the item
(the owner already settled the paradigm-level calls). The one genuine
reversibility note is G-a: the convention-first choice gets revisited
at G6 with two backends of evidence.
