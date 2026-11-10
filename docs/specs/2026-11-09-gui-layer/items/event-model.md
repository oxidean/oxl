# Event model contract (G3 contract)

UI events are ordinary channel values. The app `select`s them next
to its own channels — event handling IS the concurrency model, not
a callback convention bolted on.

## Shapes

```oxl
enum EventKind {
    clicked,          // button
    activated,        // entry: submit (GTK "activate")
    text_changed,     // entry: data = Text(current)
    close_requested,  // window: app decides whether to destroy
    row_activated,    // list: data = Index(row)
    overflow          // synthetic: queue dropped events
}

struct Event { kind: EventKind, target: int, data: EventData }
enum EventData { None, Text(str), Index(int) }
```

`target` is the emitting widget's handle — the app matches it
against the handles its typed wrappers hold.

## Delivery

Two channels' worth of machinery, split at the backend boundary:

- **App-facing:** `gui.run(b, app)` allocates `chan own Event` (cap
  256 default; `gui.set_event_buffer(n)` before `run` for control —
  the same knob sets `EventBuf.cap`, the drop-eligible bound below:
  one backlog budget, not two),
  calls `app(events)` synchronously inside `run`'s inner scope, then
  calls `b.pump(events_buf, cmds_buf)` **inline on the root task** —
  the same task `gui.run` was called on. `app` is a **non-suspending
  trampoline**: its body `go`s the real worker
  (`fn app(events: chan own Event) { go app_main(events) }`), and
  the spawn lands in the inner scope because `go` binds to the
  task's innermost *active* scope at call time, not to the callee's
  lexical home. `app` MUST be non-susp: suspendable fns cannot be
  passed as fn values (the checker rejects `suspendable fn … can't
  be a value` — a `(v0.2)` ban it marks explicitly), `run` cannot
  `spawn` a susp worker *through* a value either (spawn of a fn
  value exists for non-susp callees today, but a susp callee can
  never BE a value to reach), and a susp `app` iface or closure is
  banned for the same reasons — so the trampoline is the only legal
  shape today (a later spec could relax it with susp-fn-values).
  The `app_main` worker is what posts `new_kind` and blocks on its
  reply while the root task is already inside `pump`'s `CmdBuf`
  drain, so the request is serviced and the reply lands. This is
  required, not incidental: the root task is the only one the
  runtime pins to the main OS thread (a spawned `pump` could
  pool-schedule onto a worker and break the toolkit's thread rule),
  and running `pump` inline is also what keeps the app's synchronous
  widget creation working. `app(events)` returning does NOT end
  the session — `run` returns only after `pump` exits AND the inner
  scope joins, so a worker that never observes `events`-close holds
  `run` at the join; `app` is only the
  startup trampoline that builds the tree's first spawn; the workers
  it `go`s `select` on `events`. This chan is the ONLY event channel
  user code sees. `chan own Event` is a **typed
  channel** — a language addition this spec requires (see *Language
  additions* below): `send` moves the `own Event` pointer word,
  `recv` and `select` arm bindings come back typed `own Event`.
- **Backend-facing:** `pump` does NOT send on that chan directly.
  `gui.run` also allocates an `EventBuf` — a core-owned bounded deque
  guarded by a `sync` mutex, carrying
  `dropped`/`dropped_pending` counts and a cap-1 `ping` chan — and
  hands it to `pump`. A dispatcher task spawned by
  `gui.run` drains the buf onto `events` with ordinary blocking
  sends (it is a pool task; blocking is its job). It lives in its
  OWN dedicated scope nested inside `run`'s inner scope — NOT in
  the scope the app workers join: the
  drain-grace timeout cancels the dispatcher scope alone, so a slow
  app can never have its workers force-killed by event-channel
  backpressure (see *Teardown*). `pump` itself is never
  spawned — it IS `gui.run`'s calling task, per the thread rule.

`eb.post(e)` is the only entry point the backend uses and it can
NEVER block: lock, evict if needed, append, unlock, `try_send(ping)`
— the ping is a nudge, not a queue. `try_send` is a new builtin
(nonblocking send returning a flag — `select` has receive arms
only, so this needs the G1 runtime addition listed in the stage
plan); cap-1 means a failed send implies a pending signal the
dispatcher will already consume, so no wake is ever lost.
Eviction fires when a post would push the drop-eligible count past
`cap`: scan head→tail for the first
*drop-eligible* event and evict it, incrementing `dropped` and
`dropped_pending`, then
append the incoming event — the incoming event always lands in the
same post, so capacity-one bufs make progress and there is no
evict/reinsert cycle. `cap` bounds the DROP-ELIGIBLE backlog only:
when the scan finds no drop-eligible entry — the degenerate case,
a buf holding only protected events — nothing is evicted and the
incoming post (protected or not) still appends. Buf SIZE may
therefore exceed `cap` exactly by the protected surplus, and a
drop-eligible post landing behind an all-protected buf still
counts toward its own bound (at most `cap` drop-eligible entries
coexist). Saturation stays visible via `dropped`; correctness is
preferred over the bound only for events that must not be lost.

`close_requested` is never drop-eligible *while its target lives*
and never cross-target coalesces (a lost close is a wedged app).
Pending closes are deduplicated by a per-handle `close_pending`
flag in core's widget table — set under the buf mutex by `post`,
checked by the same `post`, so a second OS close absorbs at post
time whether the first request is still buffered, in flight to the
dispatcher, or already delivered and awaiting the app's decision.
The flag clears only on `destroy`/`gui.remove` (decision landed,
request settled) or `gui.dismiss_close(w)`, and the clearing
happens in the mutator wrapper only AFTER `CmdBuf.post` reports
the settle Cmd enqueued — a poster parked on a full buf and then
cancelled leaves the flag SET, which is the correct state: the
close decision never landed, the window is still live with a
pending request, and a later OS close absorbs into that pending
slot instead of stacking a second protected entry behind it. The
flag is
guarded by the **EventBuf** mutex everywhere (set + dedup-checked by
`eb.post`, cleared by the wrapper under that same lock before it
takes `CmdBuf`'s, so the two mutexes never nest) — not deferred
to `pump` execution, so a settle-Cmd racing a second OS close
serializes at post; the
pump-side exit sweep clears any remainder wholesale at teardown.
`gui.dismiss_close(w)` — an explicit
fire-and-forget `Cmd` meaning "keep this window": it resolves the
pending decision and re-arms the next user close. Without the flag
a second close arriving after the dispatcher forwards the first
would re-post and hand a keep-the-window app a stale second prompt;
with it, pending decisions are tracked from post until explicit
resolution, and the protected backlog is bounded at the
live-window count. A request whose target is destroyed while still
queued is settled the same way — and losing its protection with
its target's liveness (see `items/backend-protocol.md`), it
becomes drop-eligible so settled requests can never pile protected
backlog behind a dead handle.

Overflow reporting uses TWO counters, not one: `dropped` is the
cumulative total `gui.events_dropped()` reads (never cleared), and
`dropped_pending` accumulates the drops not yet covered by a
marker. Neither is a queue entry.
When the dispatcher is about to emit a marker it first does
`n := eb.take_dropped()` — read-and-clear of `dropped_pending`
under the buf mutex (`dropped` itself is untouched, so the query
never reads zero after a marker flush) —
then sends `Event{kind: overflow, target: 0, data: Index(n)}`
ahead of the next real event. If that marker send is cancelled
(grace expiry or scope cancel), `n` is credited back into
`dropped_pending` before unwind — a cancelled marker loses
no increments either. Drops landing during the blocked marker send
are counted into `dropped_pending` for the NEXT marker, so
accounting never loses increments.
The marker costs no buf slot, can never starve delivery at any
capacity, and a dropped `clicked` is always visible, never silent.

`gui.events_dropped() -> int` is the pull-based loss report: it
reads the cumulative `dropped` total — unaffected by
`take_dropped()`, which only clears the pending delta — and stays
valid after `run`
has returned or `events` observed `closed` — `run` stashes the
final count into package state before returning, and the
drain-grace/cancel path counts every still-unsent entry into
`dropped` first, so loss stays inspectable post-mortem without
holding a mailbox or chan slot.

`text_changed` MAY coalesce to latest-value inside `post` — a
core-side policy applied under the buf mutex (payload stays
current) — but ONLY against the buf's tail entry and only when it
is another `text_changed` for the same target: a keystroke event
queued behind a `clicked` or any other entry appends in order
instead of merging across it, so an intervening action is never
handled with a text value that arrived after it. All other
coalescing is backend-internal, merged before
`post` is ever called. FIFO ordering otherwise.

## Dispatch

Routing lives app-side: the app `select`s on `events` and dispatches
on `(kind, target)`. `gui.on(w, kind, fn)` may grow as sugar over a
handler map — with the same trampoline constraint as `app`, one
step stricter: the registered fn must be a NAMED non-susp fn, not
a closure (closures may not contain `go`/`spawn` — the checker
rejects it) — but sugar,
not a second channel: the single stream
keeps global ordering and select-composability. Backend-internal
`gui_connect`-style trampolines remain invisible above the iface.

## Teardown

`backend.stop()` asks `pump` to unwind. It must be invoked from a
*different* task than the pump-blocked one: a `defer` inside the
scope around `gui.run` cannot run while `gui.run` itself is still
blocking that task, and scope cancellation does not interrupt an
inline foreign call. `gui.run` therefore wires the watcher
internally — a supervisor task spawned BEFORE `run` enters its own
inner scope (`go` binds to the innermost active scope at call time,
so spawning after the inner `scope` opens would bind the watcher to
it and deadlock `join_scope` on the `retire` wait below) — a task
that parks for the enclosing scope's
lifetime, whose `defer` calls `b.stop()` (a cancel-woken task
dies at its resume point, so `stop` must ride the unwind, not the
wake), and which also `select`s on a `retire` chan `run` closes
before returning — the normal-path termination. Post-exit `stop`
is idempotent, so the retire path is a no-op; without it a watcher
only cancellation could wake would keep the enclosing scope's
`pending` nonzero and deadlock `join_scope` on a plain
`scope { gui.run(...) }`.

Dispatcher lifecycle: it runs in its OWN inner
scope nested in `run`'s — a sibling of the app workers' scope, so
cancelling it can never sweep application work — and `eb` carries
a `closed` flag next to `dropped`/`dropped_pending`. After `pump`
returns (stop honored or the toolkit loop ended) `run` sets
`closed` and posts a final `try_send` ping — then
enters a **bounded drain-grace window** instead of cancelling
immediately. During the window the dispatcher keeps forwarding the
buffered tail (including a pending overflow marker) with ordinary
blocking sends and signals a `done` chan on `closed`+empty. `run`
`select`s on `done` vs a timeout arm (`gui.set_drain_grace(d)`;
default ~250 ms — `d`/`n` knobs take `>= 1` like
`set_cmd_buffer`; a 0 grace means cancel-immediately, which IS
meaningful, so `set_drain_grace` accepts `0` explicitly and only
rejects negatives):

- App draining normally → every queued event (and the marker) is
  delivered; `done` fires; no cancel is ever issued. A
  `close_requested` posted by `pump` as its last act is always
  preserved this way.
- App not draining → the window expires, `run` cancels the
  DISPATCHER scope only (via the scoped-cancel surface in
  *Language additions*) and joins it — application workers are
  untouched; they observe `events` closing below and wind down on
  the ordinary path, so a worker suspended in a save is never
  force-cancelled mid-commit by event backpressure. Scope
  cancellation force-wakes whatever the
  dispatcher is parked on: a `ping` receive AND a blocked `events`
  send alike (a send blocked on a full app channel cannot observe a
  ping, so the cancel is the guaranteed wakeup — documented runtime
  semantics). Remaining events drop, but never silently: they are
  counted into `dropped`/`dropped_pending`, and if a final marker
  still fits the dispatcher emits it before unwinding.

Either way a normal pump exit cannot hang `run`'s join, and no
buffered event is lost while the app is still receiving. On the
outer cancellation path the enclosing scope's own teardown kills
the dispatcher directly — no grace window, no delivery after the
scope that owns the tree has closed (widget handles it names would
already be destroyed).

Once the dispatcher has unwound — `done` observed or the
cancelled dispatcher scope joined — `run` `close`s `events` before
returning. Closure is the consumer-facing termination signal:
close wakes every parked `recv`, the buffered tail still drains
first (documented runtime semantics), and a `recv` that observes
closed+empty returns the zero word — a `nil` `own Event` —
so `e == nil` is the termination test. A worker `select`ing on
`events` therefore always resolves after `run` exits — with the
drained tail, then with the closed signal — and cannot outlive
`run` parked on a channel that will never produce again.

## Language additions

The app-facing chan needs payload typing the language does not yet
have: `chan` today is an untyped word channel (`send` requires a
word-sized value and moves `own`s through it, but `recv`/`select`
bindings return `int` — nothing rebinds a word back to `own T`).
G1 therefore lands two language features ahead of the model
(typed channels in G1 so G2's app chan is `chan own Event` from
its first selftest):

- **Typed channels `chan own T`** — `chan` gains an optional
  payload parameter in type position. `send` type-checks the
  payload against `T` and still moves `own` semantics; `recv` and
  `select` arm bindings yield `own T`. Bare `chan` keeps its
  current word/`int` semantics so existing code is untouched.
  Word-sized representation is unchanged end to end — but owned
  payload cleanup is NOT free, so this is a parser + both-checkers
  + small-runtime feature: `chan own T` creation registers an
  element destructor on the channel object (codegen emits a
  `drop T` thunk per instantiated `T`; `rt` stores a `drop_elem`
  fn pointer on the channel — bare `chan` stores none), and the
  channel-teardown, `close`-drain, and cancelled-`recv` paths
  invoke it exactly once per unreceived payload per the
  cancelled-send contract below. Without that metadata the
  unread-tail reclaim rule could not free payload contents, so
  G1's scope is the type surface AND the destructor plumbing.
- **`try_send(chan, v) -> bool`** — nonblocking send; `false`
  means full OR closed (an ordinary `send` on a closed chan
  completes silently under the documented v0 rule — the
  nonblocking form pins `false` explicitly so `pump`'s reply
  publication can observe a cancelled caller). `select` has
  receive arms only, so the EventBuf
  `ping` nudge and cap-1 reply channels need this primitive.
  `try_send` works on a bare word `chan` (`int`, `err`,
  `str`/slice words by reference — the `ping` use) AND on
  `chan own T`, which the reply channels need: `pump` is an iface
  method and suspendable methods cannot cross a vtable, so its
  reply publication must be non-suspending and a blocking `send`
  is off the table there. The ownership contract is pinned
  regardless of payload kind: `true` moves the value in, `false`
  leaves a plain-word payload untouched and drops an `own`
  payload through the chan's drop thunk — the send is statically
  a move either way, so the `false` caller reconciles side
  effects rather than retrying the value. (The originally
  considered conditional-move — `false` returning ownership —
  needed a checker special-case on the builtin; v0 keeps the
  single move rule, matching the cancelled-send drop below.)
  For the `reply` use the `false` branch stays reachable: reply
  chans are pooled on the mailbox-owning scope rather than
  allocated per `Cmd`, and a cancelled caller's scope teardown
  closes its reply chan — `false` is then the caller-gone
  signal `pump` reconciles by freeing the reply's owned fields,
  as `items/backend-protocol.md` pins. A non-`own` `false`
  branch is unambiguous — nothing was owned to drop.
- **Scoped cancellation surface** — the drain-grace abort needs a
  first-class way to cancel a named scope: today only `rt_trap`
  cancels and only its own task's chain (`scope_cancel_tree` is a
  `static` runtime internal), so G1 adds a heap/named scope value
  the runtime cancels through an exported `rt_scope_cancel`,
  surfaced app-side as a `cancel` builtin or a `std/task` API —
  and `gui.run` holds its dispatcher's inner scope as that handle.
  Without it the abort path above has no mechanism to fire.
  Binding that named scope needs its own primitive too — an
  exported `rt_scope` handle a spawned task can be targeted into
  (scope-targeted `go`, or an `rt_scope_adopt`-style rebind):
  `rt_scope_new` today enters on the caller's TLS with no
  non-joining exit, so `run` cannot hand the dispatcher a scope it
  still holds otherwise.
- **Scope-bound chans + scope-targeted `mkchan`** — today
  `mkchan`'s object is heap-allocated and never freed; this
  addition gives a chan an OWNING SCOPE whose teardown frees it
  (draining any buffered tail per the `chan own T` reclaim rule),
  plus a `mkchan` form taking a scope handle (or an
  `rt_scope_adopt`-style rebind) so the owner can be a scope other
  than the caller's innermost one. The
  cap-1 `reply` chans need it: they bind to the mailbox-owning
  scope, never the caller's — a cancelled caller would otherwise
  free the chan under a queued `Cmd` (see `reply` lifetime in
  `items/backend-protocol.md`).

**Cancelled-send ownership contract.** Channel teardown and
cancellation must account for owned payloads exactly once:

- a `send` cancelled before its value lands loses the payload
  to the runtime, not back to the sender — the send is
  statically a move, so a moved `own` payload is dropped once
  and never returned. The mechanism: a parked send leaves its
  `SendReq` node in the chan's send queue; the cancel pass
  unlinks that node under the chan mutex and runs the chan's
  `drop_elem` on the payload (still queued = never delivered;
  already unlinked = a waker claimed it). A sender parked on
  the single deposit slot retracts only its own slot under the
  same drop rule. The checker keeps the binding moved — an
  unwind path that also destroyed the payload would free it
  twice. Plain-word payloads own nothing, so the drop is a
  no-op there.
- `close`d channel contents still drain before `recv` observes
  closed (documented runtime semantics); `EventBuf` teardown drops
  undelivered entries — each buffered `own Event` freed once by
  its owner.
- A `chan own T` reclaims its buffered tail at destruction: when
  the channel object itself is freed (its owning scope ends), every
  `own T` still queued in it is destroyed exactly once by the
  runtime. Receivers that keep draining take ownership at `recv`
  as usual — this rule covers only what no receiver can ever drain,
  so an app that stops reading `events` cannot leak the sent-but-
  unread tail or its payloads.
- Teardown never frees a delivered event: once `recv` returns the
  `own Event`, ownership is the receiver's.

This is the contract that makes a cancelled dispatcher safe: the
in-flight event is reclaimed by whoever holds it after the cancel
lands — sender on a failed send, buf on teardown — and nothing
already delivered is ever touched.
