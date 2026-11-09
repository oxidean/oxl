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
NEVER block: lock, evict if needed, append, unlock, try-send `ping`
(`select { ping <- 1 {} else {} }` — the ping is a nudge, not a
queue). Eviction on a full buf: scan head→tail for the first
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
When the dispatcher sees `dropped > 0` it emits one synthesized
`Event{kind: overflow, data: Index(n)}` — n the count lost since
the last marker — ahead of the next real event, then clears the
flag. The marker therefore costs no buf slot, can never starve
delivery at any capacity, and a dropped `clicked` is always visible,
never silent.

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
tears down correctly. The dispatcher lives inside the same scope and
dies with it; `pump` returning leaves any buffered events for the
dispatcher to drain or drop — no event is delivered after the scope
that owns the tree has closed (widget handles it names would
already be destroyed).
