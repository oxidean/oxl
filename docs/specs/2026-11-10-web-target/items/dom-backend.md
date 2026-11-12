# items/dom-backend.md — the `extra/gui/dom` backend contract

W6's deliverable: a `Backend` implementation rendering to the
DOM. The iface is fixed (`docs/gui-backends.md`): `new`,
`set_prop`, `attach`, `detach`, `destroy`, `pump`, `stop`,
`wake` — the same thirteen methods — the five susp-pump additions ship in the W iface, no schema changes.

## Mapping

| gui concept | DOM |
|---|---|
| widget handle (monotonic int) | entry in a `{h: Element}` table — ints stay ints, elements stay opaque refs |
| `window` | a backend-owned child `<div>` created inside the root element (`#app` when the page embeds one, else `document.body` — an embedder supplies `#app`) — `destroy` removes the owned child, never the host element: unmapping a window must not remove the host page's body or an embedder's root |
| `hbox`/`vbox`/`scrolled` | `<div>` — `scrolled` gets `overflow:auto` inline; container layout CSS stays app-supplied |
| `label` | `<span>` |
| `button` | `<button>` |
| `entry` | `<input>` |
| `list` | `<ul>`/`role=listbox`; rows attach/detach as the row widget's own tag under it — the click carries the row index in aux; `P_ROWS` is read-only — a `read` returns the current child count, a `set_prop` is a contract violation (v1: eager render; virtual-list extension parked per `gui-backends.md`) |
| `Prop`/`PropVal` | `text`→`textContent` — except `entry`, where `P_TEXT` reads/writes the `<input>`'s `.value`; `placeholder`→property; `enabled`→`disabled`; style props→`element.style` |
| `Event` kinds | `clicked`→`click`; `text_changed`→`input`; `activated`→Enter `keydown` on `<input>` — never `change` and never form `submit`: blur-after-edit fires `change` and would submit without an Enter action (and double-activate after a real Enter); `row_activated`→`click` on a row under a `<ul>`, row index in `EventData.Index` — a click bubbling up from a nested widget element is filtered out (that widget's own event, not the row's); `close_requested`→host-defined (a custom `oxl-close` event the page or a window manager fires). No `selected` kind exists — row activation is `row_activated` |
| `pump` | a susp frame task: parks on `stop`/`wake` edges and drains CmdBuf → DOM calls between event deliveries; `wake()` = `queueMicrotask` nudge. It returns only after `stop` — `gui.run` begins shutdown on return, so an immediate or drain-and-exit pump would end the session |
| `stop`/`wake` | allowed off "root task" trivially — everything is the main thread |
| copy-at-boundary | `PropVal.Text` arrives as `OxlStr` → decoded to JS string at `set_prop` (the §7 boundary rule) |

## Test surface

`dom` ships `dom.Backend` + a `dom.Headless` variant: a tiny
in-rt.mjs DOM stub (createElement/appendChild/dispatch on a
JS object tree) so `tests/gui_*` can drive the backend under
node without a browser — the same ledger/inject pattern the
mock proved. Real-browser verification is `examples/web-todo`
+ the `--html` scaffold.

## Deferred

- Virtual list for large `P_ROWS` (spec watch item from
  `gui-backends.md`, unchanged)
- IME/a11y/canvas — out of scope per shape.md
