# Backend protocol contract (G1 contract)

The portability seam is one iface. Backends: `extra/gui/mock`
(pure-oxl, test), `extra/gui/gtk` (GTK4 shim), later a DOM-protocol
backend. Everything the tree needs from a toolkit fits in seven
methods; the pilot measured the GTK side of this surface at ~15 C
functions.

## iface Backend

```oxl
iface Backend {
    new(kind: WidgetKind, props: []Prop) -> int
    set_prop(h: int, p: Prop)
    attach(parent: int, child: int)
    detach(parent: int, child: int)
    destroy(h: int)
    pump(events: chan Event)
    stop()
}
```

**Handles are opaque ints** (pilot-proven; the socket-fd idiom). The
backend owns whatever the handle refers to; `destroy` releases it.
Nothing `own`-typed crosses the boundary — the ownership story stays
entirely above the iface, in the `.oxl` tree.

## Method contracts

- `new` — create a native object of `kind`, applying `props` in
  order; returns its handle. Not yet attached anywhere.
- `set_prop` — mutate one property post-creation. `Prop{id, val}`
  where `id` is a protocol-assigned property id and `val` a
  `PropVal` payload. Unknown id = backend-defined trap (mock
  records it; gtk asserts in debug).
- `attach` / `detach` — parent-edge management. The tree layer calls
  these under `gui.append`/`gui.remove`; backends translate to the
  toolkit's container ops (gtk: `box_append`, `listbox_insert`, …).
- `destroy` — final teardown; also fires on `detach` when the child
  has no other parent (documented per backend).
- `pump` — runs the toolkit loop **on the calling task** (the pinned
  UI task). Decodes toolkit signals into `Event` structs and posts
  them on `events` per `items/event-model.md`. Returns when `stop`
  is honored or the toolkit loop ends.
- `stop` — idempotent, safe from any task: asks `pump` to unwind
  and return. This is the scope-cancellation exit path — a scope
  closing around `gui.run` calls `stop` in its `defer`.

## Prop protocol

`Prop{id: int, val: PropVal}` with `PropVal` a payload enum
(`Text(str)`, `Flag(bool)`, `Num(int)`). Property ids are assigned
per widget kind in `extra/gui` — e.g. `prop_window_title`,
`prop_button_label`, `prop_entry_text` — and the typed kind
wrappers are the only callers users see. DOM-mappability: `Prop`
serializes to DOM attribute/property pairs without loss.

## Thread rule

Backend calls happen on the task that ran `gui.run` — same rule GTK
enforces natively, applied uniformly so every backend shares one
contract. A backend SHOULD debug-assert thread affinity on `new`/
`set_prop`/`pump`. App logic on other tasks reaches the UI thread
through channels — never by calling backend or widget fns directly.

## String ownership

Every `str` the backend hands up (text getters, event payloads) is
an owned copy. Borrowed `cstr`→`str` aliases may exist *inside* a
backend where the copy boundary is provable, but nothing borrowed
crosses the iface.
