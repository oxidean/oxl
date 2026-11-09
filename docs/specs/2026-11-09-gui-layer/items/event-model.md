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

- `gui.run(b, app)` allocates `chan Event` (cap 256 default;
  `gui.set_event_buffer(n)` before `run` for control) and invokes
  `app(events)` — typically inside the app's `scope`, so the app fn
  can `go` workers that `select` on it.
- Backend `pump` marshals toolkit signals into `Event`s and
  **try-sends**: on a full queue it scans from the head for the
  first *drop-eligible* event and evicts it, then posts an
  `Event{kind: overflow}` marker as its own queue entry — the
  marker never rewrites another event's `kind` — before the
  incoming event retries its send. A dropped `clicked` is a lost
  user action, so saturation is always visible, never silent.
  `close_requested` is never drop-eligible and never coalesces (a
  lost close is a wedged app); if the queue holds ONLY protected
  events — the degenerate case, an app that has stopped draining —
  the post degrades to a blocking send, which stalls the pump
  honestly rather than discarding shutdown.
- Coalescing is backend-defined otherwise; `text_changed` MAY
  coalesce to latest-value (payload stays current). FIFO ordering
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
tears down correctly. `pump` returning leaves any queued events for
the app to drain or drop — no event is delivered after the scope
that owns the tree has closed (widget handles it names would
already be destroyed).
