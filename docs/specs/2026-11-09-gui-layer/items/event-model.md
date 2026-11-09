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
  256 default; `gui.set_event_buffer(n)` before `run` for control),
  spawns `app` as a task inside `run`'s inner scope, then calls
  `b.pump(events_buf, cmds_buf)` **inline on the root task** — the
  same task `gui.run` was called on. This is required, not
  incidental: the root task is the only one the runtime pins to the
  main OS thread (a spawned `pump` could pool-schedule onto a worker
  and break the toolkit's thread rule), and running `pump` inline is
  also what keeps the app's synchronous widget creation working —
  `app` posts `new_kind` and blocks on its reply while the root task
  is already inside `pump`'s `CmdBuf` drain, so the request is
  serviced and the reply lands. `app(events)` returning does NOT end
  the session — the GUI lives until `pump` exits; `app` is only the
  startup callback that builds the tree and `go`s the workers that
  `select` on it. This chan is the ONLY event channel user code
  sees. `chan own Event` is a **typed
  channel** — a language addition this spec requires (see *Language
  additions* below): `send` moves the `own Event` pointer word,
  `recv` and `select` arm bindings come back typed `own Event`.
- **Backend-facing:** `pump` does NOT send on that chan directly.
  `gui.run` also allocates an `EventBuf` — a core-owned bounded deque
  guarded by a `sync` mutex, carrying a `dropped` count and a cap-1
  `ping` chan — and hands it to `pump`. A dispatcher task spawned by
  `gui.run` into the same inner scope drains the buf onto `events`
  with ordinary blocking sends (it is a pool task; blocking is its
  job). `pump` itself is never spawned — it IS `gui.run`'s calling
  task, per the thread rule.

`eb.post(e)` is the only entry point the backend uses and it can
NEVER block: lock, evict if needed, append, unlock, `try_send(ping)`
— the ping is a nudge, not a queue. `try_send` is a new builtin
(nonblocking send returning a flag — `select` has receive arms
only, so this needs the G1 runtime addition listed in the stage
plan); cap-1 means a failed send implies a pending signal the
dispatcher will already consume, so no wake is ever lost. Eviction on a full buf: scan head→tail for the first
*drop-eligible* event and evict it, incrementing `dropped`, then
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
happens in the mutator wrapper at `CmdBuf.post` time — under the
same buf mutex that sets it — not deferred to `pump` execution,
so a settle-Cmd racing a second OS close serializes at post; the
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

Overflow reporting: `dropped` is a counter flag, NOT a queue entry.
When the dispatcher is about to emit a marker it first does
`n := eb.take_dropped()` — read-and-clear under the buf mutex —
then sends `Event{kind: overflow, target: 0, data: Index(n)}`
ahead of the next real event. If that marker send is cancelled
(grace expiry or scope cancel), `n` is credited back into
`dropped` before unwind — a cancelled marker loses no increments
either. Drops landing during the blocked marker send are counted
into the NEXT marker, so accounting never loses increments.
The marker costs no buf slot, can never starve delivery at any
capacity, and a dropped `clicked` is always visible, never silent.

`gui.events_dropped() -> int` is the pull-based loss report: it
reads the cumulative `dropped` count and stays valid after `run`
has returned or `events` observed `closed` — `run` stashes the
final count into package state before returning, and the
drain-grace/cancel path counts every still-unsent entry into
`dropped` first, so loss stays inspectable post-mortem without
holding a mailbox or chan slot.

`text_changed` MAY coalesce to latest-value inside `post` — a
core-side policy applied under the buf mutex (payload stays
current); all other coalescing is backend-internal, merged before
`post` is ever called. FIFO ordering otherwise.

## Dispatch

Routing lives app-side: the app `select`s on `events` and dispatches
on `(kind, target)`. `gui.on(w, kind, fn)` may grow as sugar over a
handler map — but sugar, not a second channel: the single stream
keeps global ordering and select-composability. Backend-internal
`gui_connect`-style trampolines remain invisible above the iface.

## Teardown

`backend.stop()` asks `pump` to unwind. It must be invoked from a
*different* task than the pump-blocked one: a `defer` inside the
scope around `gui.run` cannot run while `gui.run` itself is still
blocking that task, and scope cancellation does not interrupt an
inline foreign call. `gui.run` therefore wires the watcher
internally — a supervisor task that parks for the enclosing scope's
lifetime and whose `defer` calls `b.stop()` (a cancel-woken task
dies at its resume point, so `stop` must ride the unwind, not the
wake) — so plain `scope { gui.run(...) }` tears down correctly. Dispatcher lifecycle: it runs in an INNER
scope owned by `gui.run`, and `eb` carries a `closed` flag next to
`dropped`. After `pump` returns (stop honored or the toolkit loop
ended) `run` sets `closed` and posts a final `try_send` ping — then
enters a **bounded drain-grace window** instead of cancelling
immediately. During the window the dispatcher keeps forwarding the
buffered tail (including a pending overflow marker) with ordinary
blocking sends and signals a `done` chan on `closed`+empty. `run`
`select`s on `done` vs a timeout arm (`gui.set_drain_grace(d)`;
default ~250 ms):

- App draining normally → every queued event (and the marker) is
  delivered; `done` fires; no cancel is ever issued. A
  `close_requested` posted by `pump` as its last act is always
  preserved this way.
- App not draining → the window expires, `run` cancels the inner
  scope and joins it. Scope cancellation force-wakes whatever the
  dispatcher is parked on: a `ping` receive AND a blocked `events`
  send alike (a send blocked on a full app channel cannot observe a
  ping, so the cancel is the guaranteed wakeup — documented runtime
  semantics). Remaining events drop, but never silently: they are
  counted into `dropped`, and if a final marker still fits the
  dispatcher emits it before unwinding.

Either way a normal pump exit cannot hang `run`'s join, and no
buffered event is lost while the app is still receiving. On the
outer cancellation path the enclosing scope's own teardown kills
the dispatcher directly — no grace window, no delivery after the
scope that owns the tree has closed (widget handles it names would
already be destroyed).

Once the dispatcher has unwound — `done` observed or the
cancelled inner scope joined — `run` `close`s `events` before
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
  means full. `select` has receive arms only, so the EventBuf
  `ping` nudge and cap-1 reply channels need this primitive.
  **Payload is restricted to word-sized values in v1** (`int`,
  `err`, `str`/slice words by reference — the `ping` and reply-chan
  uses): the checker rejects `try_send` on an `own` argument, and
  owned payloads use blocking `send`, whose cancelled-send
  ownership contract below already covers every outcome. That
  keeps the `false` branch unambiguous — the caller retains
  ownership — instead of leaving implementations free to leak or
  double-free on a result the caller cannot distinguish. If a
  later spec widens `try_send` to `own` payloads the contract is
  already pinned: `false` leaves ownership with the caller (retry
  or drop is its choice), `true` moves it.

**Cancelled-send ownership contract.** Channel teardown and
cancellation must account for owned payloads exactly once:

- a `send` that is cancelled before its value lands reverts
  ownership to the sender — the word is either delivered or
  returned, never silently consumed. The dispatcher's unwind path
  then destroys the `own Event` it still holds (struct + `own`
  payloads) as an ordinary drop.
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
