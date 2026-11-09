# Backend protocol contract (G1 contract)

The portability seam is one iface plus two core-owned mailboxes.
Backends: `extra/gui/mock` (pure-oxl, test), `extra/gui/gtk` (GTK4
shim), later a DOM-protocol backend. Everything the tree needs from
a toolkit fits in seven methods; the pilot measured the GTK side of
this surface at ~15 C functions.

`EventBuf` and `CmdBuf` are `extra/gui`-core types — mutex-guarded
lists, not `chan`s — because the boundary needs semantics a chan
cannot express: event posts can never block `pump` (post is append
+ wake, not send), event eviction removes a mid-queue element, and
command publication must precede `wake` without ever stalling on a
full channel. The app-facing `chan Event` still exists — it is fed
by a dispatcher task inside `gui.run`, not by `pump` (see
`items/event-model.md`).

```oxl
// core-owned mailboxes — opaque to backends beyond post/drain
struct EventBuf { /* mutex-guarded deque, cap, dropped: int,
                     ping: chan int (cap-1 nudge) */ }
struct CmdBuf   { /* mutex-guarded list of Cmd */ }
// EventBuf.post(e) — never blocks (evict + append + ping)
// EventBuf.drain() — dispatcher-side: buffered events + drop count
// CmdBuf.post(c) — never blocks (append); caller then wake()s
// CmdBuf.drain() — pump-side: queued Cmds, oldest-first
```

## iface Backend

```oxl
iface Backend {
    new(kind: WidgetKind, props: []Prop) -> int
    set_prop(h: int, p: Prop)
    attach(parent: int, child: int)
    detach(parent: int, child: int)
    destroy(h: int)
    pump(events: EventBuf, cmds: CmdBuf)
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
- `pump` — runs the toolkit loop **on the calling task** (the root
  task — see the thread rule below). Two duties per iteration:
  decode toolkit signals into `Event` structs posted via
  `events.post(e)` — which never blocks, per
  `items/event-model.md` — AND drain `cmds` (`cmds.drain()` returns
  the queued `Cmd`s, oldest-first), executing each `Cmd` on this
  task. Returns when `stop` is honored or the toolkit loop ends.
  `pump` must never block on `events` or `cmds` themselves; its
  only waits are the toolkit's own event wait and `reply` sends on
  cap-1 channels (which cannot block by construction).
  Before returning, `pump` releases every handle it still owns —
  see the live-handle sweep in *Shutdown* below.
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
    reply: chan CmdResult    // new_kind + read: the response channel
}

struct CmdResult { e: err, handle: int, val: PropVal }

`CmdBuf.post` retains an OWNED copy of every `str` inside the `Cmd`
(prop text, widget strings) at post time: the caller's scope may
close before `pump` drains the queue, and a queued `Cmd` must never
alias storage that can die underneath it. Same rule as event
payloads — the copy boundary is the mailbox, not the pump.
```

`reply` carries `CmdResult`: reads fill `val` (the same payload
shape properties carry), `new_kind` fills `handle`, and both report
failure in `e` (`e == nil` on success) — creation failure reaches
the caller as an error, never as a dead handle. The layer
allocates `reply` as a **cap-1 channel per Cmd**, so `pump`'s reply
send can never block even if the caller has not reached its
receive yet.

`button.set_label(s)` on any task = `cmds.post(Cmd{set_prop, h, ...})`
+ `b.wake()`; `pump` applies it on the UI thread. `CmdBuf.post`
appends under a mutex — **it cannot block** — so publication always
completes before `wake` is called, and `wake` is called
unconditionally after every post: there is no
full-channel-before-wake interleaving for the pump to miss. Reads
(`entry.text()`) post a `read` Cmd carrying its reply chan and
block-receive — the reply crosses the boundary as an owned `str`,
satisfying the copy rule, and the app-side wait is an ordinary chan
op (suspendable, cancellable). `new_kind` uses the same shape: the
caller block-receives `CmdResult{handle: h}` (or `e`) — handlers
can create widgets too, and `attach` can name the returned handle.
`gui.run` allocates both mailboxes next to `events` and hands them
to `pump`.

## Shutdown

`CmdBuf` carries a `closed` flag next to the queue, mirroring
`EventBuf`. After `pump` returns — stop honored or toolkit loop
ended — `run` sets `closed` under the buf mutex and drains any
residual `Cmd`s **itself**: every reply-carrying `Cmd` gets
`CmdResult{e: gui.err_stopped()}` posted to its cap-1 chan, which
cannot block by construction. A blocked `read`/`new_kind` caller
therefore always resolves — the app-side receive unwinds with an
error instead of hanging on a dead pump.

Post-close, `CmdBuf.post` still cannot block, but mutators check
`closed` under the same mutex before enqueueing:

- reply-carrying calls (`read`, `new_kind`) short-circuit —
  `gui.err_stopped()` is returned WITHOUT enqueueing, so a handler
  that fires on a drained `close_requested` tail and calls
  `entry.text()` or creates a widget gets an error, not a wait;
- fire-and-forget `Cmd`s (`set_prop`, `attach`, `detach`,
  `destroy`) are accepted-and-dropped — post-stop mutation is a
  no-op under the same idempotence rule `destroy` already has.

`gui.err_stopped()` is the sentinel err for "backend loop exited"
(mirrors `io.eof()`-style sentinels; equality-comparable for
`if e == gui.err_stopped()`).

### Live-handle sweep

`pump` does not return with live handles. A backend tracks every
handle it has created that has not yet seen `destroy` (it needs
that set anyway for the dead-handle checks above); on its exit
path — `stop` honored or toolkit loop ended — it issues `destroy`
for each surviving handle on the UI task itself. Toolkits whose
parents cascade (a closed gtk window takes its children) already
satisfy the contract for descendants and need only sweep the
detached/top-level remainder; `destroy`'s idempotence makes a
double release a no-op, not a protocol error.

This is the only release path that survives shutdown: a widget
left attached when the loop ends is freed by the sweep, so a
`gui.remove` that would have named it afterwards degrades to the
documented post-stop no-op instead of a leak.

The sweep can never outrun a live close decision, because
`close_requested` is **veto-backed**: a backend posting it must
first veto the toolkit's native teardown (gtk: `delete-event`
returns TRUE; the window survives untouched). The toolkit loop's
natural end — last toplevel gone — is therefore unreachable while
a close decision is still pending: the app answers with
`gui.remove` (window dies, loop may then end) or keeps the window
(loop simply continues). A `close_requested` that arrives during
the event drain-grace consequently always refers to a still-live
handle *unless* shutdown was app-initiated (`stop`): on that path
the veto is moot — the app already chose teardown — the sweep
takes the widget, and reads against it resolve `err_stopped()`,
which is the documented "inspect after teardown" answer.

## Prop protocol

`Prop{id: int, val: PropVal}` with `PropVal` a payload enum
(`Text(str)`, `Flag(bool)`, `Num(int)`). Property ids are assigned
per widget kind in `extra/gui` — e.g. `prop_window_title`,
`prop_button_label`, `prop_entry_text` — and the typed kind
wrappers are the only callers users see. DOM-mappability: `Prop`
serializes to DOM attribute/property pairs without loss.

## Thread rule

`gui.run` MUST be called on the **root task** — the task executing
`main`'s call chain. This is a mechanism, not a convention: the
runtime drives the root task on the process's main OS thread via
its own external park loop (`rt_run_root`); it is never submitted
to the worker pool, so it cannot migrate across a channel
suspension the way a spawned task can. Root-task-only IS the pin —
and it matches GTK's own hard requirement (a main-thread main loop)
exactly. Calling `gui.run` from a `go`/`spawn`ed task is a contract
violation; a backend SHOULD debug-assert thread affinity on `new`/
`set_prop`/`pump` to catch it. `stop`, `wake`, `CmdBuf.post`, and
`EventBuf.post` are explicitly safe from ANY task — the watcher and
dispatcher use them, and widget mutators do too: app logic on other
tasks reaches the UI thread through the mailboxes alone. Widget fns
are safe from any task precisely because they only append.

## String ownership

Every `str` the backend hands up (text getters, event payloads) is
an owned copy. Borrowed `cstr`→`str` aliases may exist *inside* a
backend where the copy boundary is provable, but nothing borrowed
crosses the iface.
