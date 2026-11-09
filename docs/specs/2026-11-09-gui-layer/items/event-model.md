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

- **App-facing:** `gui.run(b, app)` allocates `chan Event` (cap 256
  default; `gui.set_event_buffer(n)` before `run` for control) and
  invokes `app(events)` — typically inside the app's `scope`, so the
  app fn can `go` workers that `select` on it. This chan is the ONLY
  event channel user code sees.
- **Backend-facing:** `pump` does NOT send on that chan directly.
  `gui.run` also allocates an `EventBuf` — a core-owned bounded deque
  guarded by a `sync` mutex, carrying a `dropped` count and a cap-1
  `ping` chan — and hands it to `pump`. A dispatcher task spawned by
  `gui.run` drains the buf onto `events` with ordinary blocking
  sends (it is a pool task; blocking is its job).

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
evict/reinsert cycle. `close_requested` is never drop-eligible and
never coalesces (a lost close is a wedged app). If the buf holds
only protected events — the degenerate case, an app that has
stopped draining — protected posts still append past `cap`: the
bound applies to the droppable backlog; correctness is preferred
over the bound for events that must not be lost, and saturation is
already being signaled via `dropped`.

Overflow reporting: `dropped` is a counter flag, NOT a queue entry.
When the dispatcher is about to emit a marker it first does
`n := eb.take_dropped()` — read-and-clear under the buf mutex —
then sends `Event{kind: overflow, data: Index(n)}` ahead of the
next real event. Drops landing during the blocked marker send are
counted into the NEXT marker, so accounting never loses increments.
The marker costs no buf slot, can never starve delivery at any
capacity, and a dropped `clicked` is always visible, never silent.

Coalescing is backend-defined otherwise; `text_changed` MAY coalesce
to latest-value inside `post` (payload stays current). FIFO ordering
otherwise.

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
internally — a supervisor task that observes the enclosing scope's
cancellation and calls `b.stop()` — so plain `scope { gui.run(...) }`
tears down correctly. Dispatcher lifecycle: it runs in an INNER
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
closed+empty returns the zero word — `nil` for the Event value,
so `e == nil` is the termination test. A worker `select`ing on
`events` therefore always resolves after `run` exits — with the
drained tail, then with the closed signal — and cannot outlive
`run` parked on a channel that will never produce again.
