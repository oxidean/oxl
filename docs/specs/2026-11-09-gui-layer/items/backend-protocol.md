# Backend protocol contract (G1 contract)

The portability seam is one iface plus two core-owned mailboxes.
Backends: `extra/gui/mock` (pure-oxl, test), `extra/gui/gtk` (GTK4
shim), later a DOM-protocol backend. Everything the tree needs from
a toolkit fits in eight methods; the pilot measured the GTK side of
this surface at ~15 C functions.

`EventBuf` and `CmdBuf` are `extra/gui`-core types — mutex-guarded
lists, not `chan`s — because the boundary needs semantics a chan
cannot express: event posts can never block `pump` (post is append
+ wake, not send), event eviction removes a mid-queue element, and
command publication must precede `wake` without ever stalling on a
full channel. The app-facing `chan own Event` still exists — it is fed
by a dispatcher task inside `gui.run`, not by `pump` (see
`items/event-model.md`).

```oxl
// core-owned mailboxes — opaque to backends beyond post/drain
struct EventBuf { /* mutex-guarded deque, cap, dropped: int,
                     ping: chan (cap-1 nudge, bare word chan) */ }
struct CmdBuf   { /* mutex-guarded BOUNDED list of Cmd: cap,
                     closed flag, parked-poster wakeup — the park
                     waits on a suspendable wakeup (chan/task-park),
                     not the std/sync spin Mutex: a parked poster
                     must not burn a pool worker */ }
// EventBuf.post(e) — never blocks (evict + append + ping)
// EventBuf.drain() — dispatcher-side: buffered events + drop count
// CmdBuf.post(c) — appends under the mutex; parks ONLY while the
// buf is full (bounded admission = backpressure — commands are
// never dropped: a lost `destroy` leaks a widget, a lost reply
// carrier wedges its caller). Ordering stays FIFO either way.
// Cap is fixed at `gui.run` time (default 512;
// `gui.set_cmd_buffer(n)` before `run`). Blocking here cannot
// deadlock: the only drainer is `pump` on the root task, which
// never posts to `cmds`, so a full buf always drains. A poster
// cancelled before its enqueue lands keeps its `own Cmd` — the
// enqueue is atomic under the buf mutex, so a command is either
// queued or never was; setting `closed` force-wakes parked
// posters, which then fail fast per the post-stop rule below.
// Caller then wake()s.
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
    // EventBuf/CmdBuf are shared core-owned objects, passed by
    // reference — sketches show them bare for brevity
    pump(events: EventBuf, cmds: CmdBuf)
    stop()
    wake()                                          // nudge a blocked pump
}
```

**Handles are opaque ints** (pilot-proven; the socket-fd idiom). The
backend owns whatever the handle refers to; `destroy` releases it.
Nothing `own`-typed crosses the boundary — the ownership story stays
entirely above the iface, in the `.oxl` tree.

**Suspendability bound.** Every `Backend` method must stay
non-susp-capable: a method *declared by* an iface its receiver
satisfies cannot suspend (vtable calls carry no task frame), so
`pump`'s event posts
are nonblocking `eb.post`s, its replies are `try_send`s, and
`stop`/`wake` are flag-and-nudge operations. The same bound applies
to `gui.Widget` (`shape.md`): the iface may only declare non-susp
methods (`handle()`, `kind()`, …) — mutators that post to `CmdBuf`
(which can park) and getters that block-receive a reply live on the
concrete typed wrappers (`gui.Button`, …), where a direct call
carries a task frame and suspending is legal.

## Method contracts

- `new` — create a native object of `kind`, applying `props` in
  order; returns its handle. Not yet attached anywhere.
  Creation happens during `gui.run` setup on the root task.
- `set_prop` — mutate one property post-creation. `Prop{id, val}`
  where `id` is a protocol-assigned property id and `val` a
  `PropVal` payload. Unknown id = protocol violation (mock
  records it; gtk reports it via the dev gate — see below).
- `attach` / `detach` — parent-edge management ONLY. `detach` never
  destroys: the single destruction rule is "`destroy` releases, and
  only `destroy`". `gui.remove` = `detach` then `destroy`, always —
  no detach-path teardown, no double-free ambiguity. The tree layer
  calls these under `gui.append`/`gui.remove`; backends translate to
  the toolkit's container ops (gtk: `box_append`, `listbox_insert`, …).
- `destroy` — final teardown. Backends define a destroyed handle as
  dead: `set_prop`/`attach` on a dead handle is a protocol error
  (mock records; gtk reports it via the dev gate). `destroy` itself
  is idempotent on a dead handle — repeated teardown is a no-op,
  not a trap.
  **Handles are never reissued within a `gui.run` session**: a
  backend allocates handles monotonically (or otherwise guarantees
  freshness), so a destroyed handle stays retired for the life of
  the run — a stale queued event or a `close_pending` flag can
  never bind to, or coalesce into, a DIFFERENT widget's lifetime
  that happened to recycle the number.
- `pump` — runs the toolkit loop **on the calling task** (the root
  task — see the thread rule below). Two duties per iteration:
  decode toolkit signals into `Event` structs posted via
  `events.post(e)` — which never blocks, per
  `items/event-model.md` — AND drain `cmds` (`cmds.drain()` returns
  the queued `Cmd`s, oldest-first), executing each `Cmd` on this
  task. Returns when `stop` is honored or the toolkit loop ends.
  `pump` must never block on `events` or `cmds` themselves; its
  only wait is the toolkit's own event wait. Reply publication is
  `try_send` on the cap-1 `reply` chan — NEVER a blocking `send`:
  `pump` is an iface method, and a suspendable method cannot be
  vtable-reachable (the checker rejects it — "vtable calls carry no
  task frame"), so every backend's `pump` MUST stay non-susp-capable
  end to end. `try_send` is legal here because the reply chan is
  freshly allocated per `Cmd` and receives exactly one send — the
  `false` branch is unreachable by construction — and because it is
  a non-suspending builtin.
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
thread rule — only the root task may touch the toolkit — means an
event handler running on an app task can never call the backend
directly. So **widget mutators enqueue, they do not call**:

```oxl
enum CmdKind { new_kind, set_prop, attach, detach, destroy, read,
             dismiss_close }
struct Cmd {
    kind: CmdKind,
    target: int,             // handle (or parent for attach/detach;
                                 // new_kind: optional attach-parent, 0 =
                                 // detached)
    widget: WidgetKind,      // new_kind only
    prop: Prop,              // set_prop: the write; read: prop.id
                             // selects the property (val unused)
    props: []Prop,           // new_kind only: creation props
    arg: int,                // attach/detach: the child handle
    reply: chan own CmdResult // new_kind + read: cap-1 response chan
}

struct CmdResult { e: err, handle: int, val: PropVal }

// `new_kind` is the single create verb: `pump` checks the
// attach-parent's liveness FIRST — a dead `target` resolves
// `err_gone` through the reply without creating anything (a
// create-then-fail-attach would orphan the fresh handle) — then
// passes `props` straight to `Backend.new(kind, props)` and applies
// `attach(target, child)` when `target` is nonzero — so `new`'s
// "not yet attached anywhere" contract holds and a create-and-attach
// stays one `Cmd`. `read` selects its property by `prop.id`.
//
// `dismiss_close` is the fire-and-forget veto-keep verb: the flag
// flip itself happens in the wrapper at `CmdBuf.post` time (see
// `items/event-model.md`); the Cmd exists as the *ordered settle
// record* in the queue — a backend reading the stream sees the
// dismissal where it landed relative to other Cmds, and the mock
// can log it as a protocol event. On a dead handle it is a no-op
// like `destroy`. It carries no reply — the dispatcher that posted
// the close does not need to learn the decision, only the flag's
// release matters.
//
// `CmdBuf.post` retains an OWNED copy of every `str` inside the `Cmd`
// (prop text, `props` entries, widget strings) at post time: the
// caller's scope may
// close before `pump` drains the queue, and a queued `Cmd` must never
// alias storage that can die underneath it. Same rule as event
// payloads — the copy boundary is the mailbox, not the pump.
```

`reply` is a **`chan own CmdResult`** — the same typed-channel
feature the app-facing `events` chan uses, so the struct payload
crosses with its ownership spelled out: `pump` allocates an owned
`CmdResult`, `try_send` moves it in (non-suspending, per the
vtable rule above), and the caller's `recv` takes
ownership (an ordinary drop after it reads `handle`/`val`/`e`).
The chan itself is allocated bound to the **mailbox-owning scope**
— the enclosing scope `gui.run` placed the mailboxes in — NOT the
caller task's innermost scope: a caller cancelled mid-`recv`
unwinds its inner scopes while its `Cmd` may still be queued, and
a scope-bound chan freed then would leave `pump`'s `try_send`
landing in reclaimed memory. Binding `reply` to the mailbox scope
(the scope-targeted `mkchan` in *Language additions*) keeps it
alive until the mailboxes die — by which point the queue is drained
and every pending reply answered (the residual-Cmd sweep below) —
and a caller that never receives still gets its result freed by the
chan's teardown under the `chan own T` reclaim rule — no leak in
either direction. Cancellation: the caller's
block-receive is an ordinary suspendable chan op, so a cancelled
waiter simply never receives; the queued `CmdResult` is reclaimed
by that same rule. reads fill `val` (the same payload shape
properties carry), `new_kind` fills `handle`, and both report
failure in `e` (`e == nil` on success) — creation failure reaches
the caller as an error, never as a dead handle. The layer
allocates `reply` as a **cap-1 channel per Cmd**, so `pump`'s
`try_send` always lands — the chan is empty when `pump` touches
it even if the caller has not reached its receive yet.

`button.set_label(s)` on any task = `cmds.post(Cmd{set_prop, h, ...})`
+ `b.wake()` when the post enqueued; `pump` applies it on the UI
thread. `CmdBuf.post` appends under a mutex and parks only while
the buf is full (see above) and reports internally whether it
enqueued (the caller never sees the flag — the accepted-and-dropped
contract stays silent) — so publication always completes before
`wake` is called, and `wake` fires after every *successful* post:
there is no full-channel-before-wake interleaving for the pump to
miss, and a poster that never lands its enqueue (cancelled while
parked, or `closed`) never wakes either, which is correct — there
is nothing queued for `pump` to see. Reads
(`entry.text()`) post a `read` Cmd carrying its reply chan and
block-receive — the reply crosses the boundary as an owned `str`,
satisfying the copy rule, and the app-side wait is an ordinary chan
op (suspendable, cancellable). `new_kind` uses the same shape: the
caller block-receives `CmdResult{handle: h}` (or `e`) — handlers
can create widgets too, and `attach` can name the returned handle.
`gui.run` allocates both mailboxes — `CmdBuf`, `EventBuf`, their
`closed` flags — plus `events`, bound to the **enclosing scope** it
was called from, not its own inner scope: widget wrappers carry
mailbox refs and are bound to that same scope, so a post-`run`
mutator call always finds a live `closed` flag and hits the
accepted-and-dropped rule instead of dangling — and the reply
chans the post path allocates bind there too (see `reply` above).
`run` hands the mailboxes to `pump` for the session.

## Shutdown

`CmdBuf` carries a `closed` flag next to the queue, mirroring
`EventBuf`. After `pump` returns — stop honored or toolkit loop
ended — `run` sets `closed` under the buf mutex and drains any
residual `Cmd`s **itself**: every reply-carrying `Cmd` gets
`CmdResult{e: gui.err_stopped()}` posted to its cap-1 chan, which
cannot block by construction. A blocked `read`/`new_kind` caller
therefore always resolves — the app-side receive unwinds with an
error instead of hanging on a dead pump.

Post-close, `CmdBuf.post` never parks: `closed` is set under the
buf mutex and force-wakes every parked poster, and mutators check
`closed` under the same mutex before enqueueing:

- reply-carrying calls (`read`, `new_kind`) short-circuit —
  `gui.err_stopped()` is returned WITHOUT enqueueing, so a handler
  that fires on a drained `close_requested` tail and calls
  `entry.text()` or creates a widget gets an error, not a wait;
- fire-and-forget `Cmd`s (`set_prop`, `attach`, `detach`,
  `destroy`, `dismiss_close`) are accepted-and-dropped — post-stop
  mutation is a no-op under the same idempotence rule `destroy`
  already has.

`gui.err_stopped()` is the sentinel err for "backend loop exited"
(mirrors `io.eof()`-style sentinels; equality-comparable for
`if e == gui.err_stopped()`). Its dead-handle sibling is
`gui.err_gone()` — "the target no longer exists" — resolved on
`read`/`new_kind` calls against destroyed handles while the loop
still runs, so `e` distinguishes "backend stopped" from "widget
gone".

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
first veto the toolkit's native teardown (gtk: `close-request`
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

**Pending close requests are bounded per window.** `EventBuf.post`
enforces per-handle close dedup via `close_pending` (see
`items/event-model.md`): a request for a handle that already has a
decision pending — in the buf, in flight, or delivered — absorbs
into it, so a window can occupy at most one close slot, an app
that stops draining can never accrue more protected backlog than
it has live windows, and the veto decision is still never lost.
The backend posts every close it vetoes; the
dedup lives in `post`, not in the backend.

**Removal resolves pending close requests.** `destroy` (directly or
via `gui.remove`) settles every pending `close_requested` for that
handle — and clears `close_pending`: the widget is gone, so the
veto the request awaited is moot. Settlement also ends the
request's drop-protection: a `close_requested` still queued for a
dead handle becomes DROP-ELIGIBLE in `EventBuf` (delivered in
order if it survives — handlers MUST treat it as a no-op, window
already removed) — so an app that stops draining can never pile
protected backlog behind dead handles: protected entries stay
bounded at the live-window count no matter how many windows cycle
through create/close/destroy.

Commands against a dead handle split by shape, mirroring the
post-stop rule: reply-carrying calls (`read`, `new_kind` naming it
as parent) resolve `gui.err_gone()` through their reply chan —
"widget gone" where the sweep path answers `err_stopped()`;
fire-and-forget `Cmd`s (`set_prop`, `attach`, `detach`, `destroy`,
`dismiss_close`) are accepted-and-dropped — there is no reply chan
to carry an error, and the caller-facing outcome matches the
post-stop contract exactly (the mock still records the dead-target
call as a protocol violation for diagnostics, and gtk reports it
via the dev gate; the app simply cannot observe it either way). A
`close_requested` emitted for a handle the backend already knows
is dead is likewise a backend-side protocol error (mock records;
gtk reports it via the dev gate); the live-then-removed interleave
is the only
legitimate dead-target delivery, and the contract makes it
harmless by construction.

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
violation `gui.run` itself enforces: the runtime knows the root
task's identity — a G1 runtime addition marks it (an `is_root`
flag set by `rt_run_root`; the existing `external` field cannot
discriminate — `rt_spawnb_task` sets it too). `is_root` reads
"driven inline by `rt_run_root`", which covers `main`'s task plus
two intentional passes: spawn-fallback frame tasks and
test-harness tasks are also `rt_run_root`-driven and pinned to
their driving thread — and tests need it to drive `pump` — so
`run` checks its
caller up front and returns `gui.err_not_root()` on a spawned task:
a named sentinel like `err_stopped()`, testable by the mock suite,
fatal to that `run` call and nothing else — no dev gate,
no counting, no silent UB. A backend SHOULD additionally check
thread affinity on `new`/`set_prop`/`pump` and report it via the
dev gate to catch direct-iface misuse.

Protocol violations are development aids, never runtime traps:
`gui.debug_protocol(true)` (off by default) turns every recorded
violation into a hard assert during backend development; with the
gate off — the only mode apps and CI ship — a queued dead-target or
unknown-id command is dropped after being counted on the backend's
violation counter (mock exposes it for test asserts; gtk logs to
stderr), so a late setter against a destroyed widget can never
terminate the process. This narrows nothing about the contract
itself — the commands are still errors — it only pins the
*response*: count and drop, nonfatally, unless the dev gate asked
for the trap. `stop`, `wake`, `CmdBuf.post`, and
`EventBuf.post` are explicitly safe from ANY task — the watcher and
dispatcher use them, and widget mutators do too: app logic on other
tasks reaches the UI thread through the mailboxes alone. Widget fns
are safe from any task precisely because they only append.

## String ownership

Every `str` the backend hands up (text getters, event payloads) is
an owned copy. Borrowed `cstr`→`str` aliases may exist *inside* a
backend where the copy boundary is provable, but nothing borrowed
crosses the iface.
