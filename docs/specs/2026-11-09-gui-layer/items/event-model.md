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
  **try-sends**: on a full queue it drops the *oldest* pending event
  and marks the next post `kind = overflow` — a dropped `clicked`
  is a lost user action, so saturation is always visible, never
  silent. Coalescing is backend-defined but `text_changed` MAY
  coalesce to latest-value (payload stays current).
- FIFO ordering otherwise. `close_requested` never coalesces and is
  never drop-eligible (a lost close is a wedged app).

## Dispatch

Routing lives app-side: the app `select`s on `events` and dispatches
on `(kind, target)`. `gui.on(w, kind, fn)` may grow as sugar over a
handler map — but sugar, not a second channel: the single stream
keeps global ordering and select-composability. Backend-internal
`gui_connect`-style trampolines remain invisible above the iface.

## Teardown

`backend.stop()` asks `pump` to unwind; a scope closing around
`gui.run` calls it from `defer`. `pump` returning leaves any queued
events for the app to drain or drop — no event is delivered after
the scope that owns the tree has closed (widget handles it names
would already be destroyed).
