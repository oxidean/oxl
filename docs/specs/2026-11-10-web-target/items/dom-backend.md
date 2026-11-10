# items/dom-backend.md — the `extra/gui/dom` backend contract

W6's deliverable: a `Backend` implementation rendering to the
DOM. The iface is fixed (`docs/gui-backends.md`): `new`,
`set_prop`, `attach`, `detach`, `destroy`, `pump`, `stop`,
`wake` — the same eight methods, no schema changes.

## Mapping

| gui concept | DOM |
|---|---|
| widget handle (monotonic int) | entry in a `{h: Element}` table — ints stay ints, elements stay opaque refs |
| `window` | the host element (configurable root: `document.body` default, a given `#id` for embeds) |
| `hbox`/`vbox`/`scrolled` | `<div>` + flex/overflow CSS classes |
| `label` | `<span>` |
| `button` | `<button>` |
| `entry` | `<input>` |
| `list` | `<ul>`/`role=listbox`; `P_ROWS` → `<li>` children (v1: eager render; virtual-list extension parked per `gui-backends.md`) |
| `Prop`/`PropVal` | `text`→`textContent`; `placeholder`/`value`→properties; `rows`→children rebuild; `enabled`→`disabled`; style props→`element.style` |
| `Event` kinds | `clicked`→`click`; `text_changed`→`input`; `close_requested`→host-defined (a custom `oxl-close` event the page or a window manager fires); `selected`→`change`/`click` on rows |
| `pump` | microtask/rAF drain: CmdBuf → DOM calls between macrotask event deliveries; `stop` flag + `wake()` = `queueMicrotask` nudge |
| `stop`/`wake` | allowed off "root task" trivially — everything is the main thread |
| copy-at-boundary | `PropVal.Text` arrives as `OxlStr` → decoded to JS string at `set_prop` (the §7 boundary rule) |

## Test surface

`dom` ships `dom.Backend` + a `dom.Headless` variant: a tiny
in-rt.js DOM stub (createElement/appendChild/dispatch on a
JS object tree) so `tests/gui_*` can drive the backend under
node without a browser — the same ledger/inject pattern the
mock proved. Real-browser verification is `examples/web-todo`
+ the `--html` scaffold.

## Deferred

- Virtual list for large `P_ROWS` (spec watch item from
  `gui-backends.md`, unchanged)
- IME/a11y/canvas — out of scope per shape.md
