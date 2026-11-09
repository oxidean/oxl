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
    pump(events: chan Event, cmds: chan Cmd)
    stop()
    wake()                                          // nudge a blocked pump
}
```

**Handles are opaque ints** (pilot-proven; the socket-fd idiom). The
backend owns whatever the handle refers to; `destroy` releases it.
Nothing `own`-typed crosses the boundary — the ownership story stays
entirely above the iface, in the `.oxl` tree.

## Method contracts

- `new` — create a native object of `kind`, applying `props` in
  order; returns its handle. Not yet attached anywhere.
  Creation happens during `gui.run` setup on the pinned task.
- `set_prop` — mutate one property post-creation. `Prop{id, val}`
  where `id` is a protocol-assigned property id and `val` a
  `PropVal` payload. Unknown id = backend-defined trap (mock
  records it; gtk asserts in debug).
- `attach` / `detach` — parent-edge management ONLY. `detach` never
  destroys: the single destruction rule is "`destroy` releases, and
  only `destroy`". `gui.remove` = `detach` then `destroy`, always —
  no detach-path teardown, no double-free ambiguity. The tree layer
  calls these under `gui.append`/`gui.remove`; backends translate to
  the toolkit's container ops (gtk: `box_append`, `listbox_insert`, …).
- `destroy` — final teardown. Backends define a destroyed handle as
  dead: `set_prop`/`attach` on a dead handle is a protocol error
  (mock records; gtk debug-asserts). `destroy` itself is idempotent
  on a dead handle — repeated teardown is a no-op, not a trap.
- `pump` — runs the toolkit loop **on the calling task** (the pinned
  UI task). Two duties per iteration: decode toolkit signals into
  `Event` structs posted on `events` (per `items/event-model.md`),
  AND drain `cmds`, executing each `Cmd` on this task. Returns when
  `stop` is honored or the toolkit loop ends.
- `stop` — idempotent, safe from any task: asks `pump` to unwind
  and return. Must be callable from a different task than the
  pump-blocked one — a `defer` inside the scope around `gui.run`
  cannot run while `gui.run` still blocks (see
  `items/event-model.md` teardown for the watcher pattern).
- `wake` — safe from any task: interrupts pump's toolkit wait so it
  notices pending `cmds` promptly (gtk: `g_main_context_invoke`/
  `g_idle_add`; mock: no-op). The layer calls it after enqueueing a
  `Cmd` whenever pump may be asleep.

## The command direction

Events flow out on `events`; mutations flow back in on `cmds`. The
thread rule — only the pinned task may touch the toolkit — means an
event handler running on an app task can never call the backend
directly. So **widget mutators enqueue, they do not call**:

```oxl
enum CmdKind { new_kind, set_prop, attach, detach, destroy, read }
struct Cmd {
    kind: CmdKind,
    target: int,             // handle (or parent for attach/detach)
    widget: WidgetKind,      // new_kind only
    prop: Prop,              // set_prop only
    arg: int,                // attach/detach: the child handle
    reply: chan PropVal      // read only: the response channel
}
```

`reply` uses `PropVal` as the value union — reads return the same
payload shape properties carry.

`button.set_label(s)` on any task = enqueue `Cmd{set_prop, h, ...}`
+ `b.wake()`; `pump` applies it on the UI thread. Reads
(`entry.text()`) enqueue a `read` Cmd carrying a reply chan and
block-receive — the reply crosses the boundary as an owned `str`,
satisfying the copy rule. `gui.run` allocates the `cmds` chan next
to `events` and hands both to `pump`; widget handles are issued by
`new_kind` Cmds so handlers can create widgets too.

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
through channels — events arrive on `events`, mutations return via
`cmds` (the command direction above). Widget fns are safe from any
task precisely because they only enqueue.

## String ownership

Every `str` the backend hands up (text getters, event payloads) is
an owned copy. Borrowed `cstr`→`str` aliases may exist *inside* a
backend where the copy boundary is provable, but nothing borrowed
crosses the iface.
