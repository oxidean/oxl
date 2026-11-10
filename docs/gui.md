# GUI — the `extra/gui` layer

A portable GUI over a small `Backend` interface. The app builds a
retained widget tree; all toolkit calls run inside `gui.run`'s pump
on the root task; events come back on a typed channel. GTK4 is the
shipping backend (`extra/gui/gtk`); `extra/gui/mock` is the headless
test double.

    import "github.com/oxidean/oxl/extra/gui"
    import "github.com/oxidean/oxl/extra/gui/gtk"

    fn app(events: chan own gui.Event) { ... }

    fn main() {
        e := gui.run(gtk.backend(), app)
    }

## The thread rule

`gui.run` MUST be called from the **root task** — the task executing
`main`'s call chain. This is enforced, not a convention: the runtime
marks the root task (`rt_run_root` entered with no enclosing task),
and `run` returns `gui.err_not_root()` from anywhere else. Toolkits
like GTK4 require their loop on the process's main thread — the root
task is exactly that thread, so the rule is a mechanism, not a pin
primitive.

Only the pump touches the toolkit. Everything else — widget
constructors, `append`/`remove`, setters, readers — is a `Cmd` posted
to a mailbox and executed by `pump` inside `run`. Apps may call
mutators from any task.

One session at a time: a second `gui.run` while one is live returns
an error.

## Events

`gui.run` hands your entry point a `chan own gui.Event` (buffered,
default cap 256 — `gui.set_event_buffer(n)` before `run`). The
backend posts into a bounded `EventBuf`; a dispatcher drains it onto
your chan. Because the chan is typed, `select` composes UI events
with your own channels:

    select {
        ev := recv(events) => { /* ui event; ev == nil after close */ }
        t := recv(ticks)    => { /* app timer */ }
    }

Overflow is honest loss: the buf evicts the oldest **drop-eligible**
entry (everything except `close_requested`, which is protected and
deduplicated per window by `close_pending`/`dismiss_close`), counts
it, and the dispatcher synthesizes an `overflow` marker whose
`EventData.Index(n)` carries the dropped count. After `run` returns,
`gui.events_dropped()` reads the total — pull-based so it survives
shutdown even when no marker could be sent.

Shutdown keeps a drain grace (`gui.set_drain_grace(ms)`, default
250): when `pump` exits, buffered events still in flight get that
window to reach your chan before the dispatcher is cancelled; any
remainder is counted into `dropped`, then the chan closes — `recv`
yields `nil` and your loop exits.

## Mutations and errors

Reads reply on internal `chan own CmdResult` chans — they're
synchronous-looking (`[v, e] = e.text()`) but never suspend the root
task. After `pump` exits:

- reply-carrying calls (`read`, constructors) resolve
  `gui.err_stopped()`;
- fire-and-forget mutators (`set_prop`, `append`, `remove`,
  `dismiss_close`) are accepted-and-dropped — do not rely on an
  error to detect a dropped mutation.

Against a live loop, a destroyed handle resolves `gui.err_gone()` on
reply calls; fire-and-forget mutations to dead handles are dropped
the same way. Widgets own their subtrees: `gui.remove(w)` detaches
and destroys `w` and everything under it, and `pump` never returns
with live handles — the backend sweeps survivors on exit.

`close_requested` arrives once per window until dismissed
(`gui.dismiss_close(w)` re-arms it); `gui.close_pending(w)` reports
a pending unhandled close — use it to debounce close handlers.

## Copy at the boundary

Text getters return owned `str`. No borrowed `cstr` aliases cross
the public API — the GTK shim's borrowed buffers are copied at the
`gx_read_str` boundary inside the backend.

## Scope-capture rules

The session's internals are scope-bound so cancellation can't leave
handles dangling:

- the events chan is `smkchan(Event, cap, curscope())` — bound to
  the scope `run` was called from, so buffered `own Event` payloads
  are reclaimed if that scope tears down;
- reply chans bind to the mailbox-owning scope, not the caller's —
  a cancelled caller can't free a chan under a queued `Cmd`;
- the stop-watcher binds to the enclosing scope: `scope {
  gui.run(...) }` cancelled while `pump` waits wakes the watcher,
  its `defer` calls `b.stop()`, `run` returns, the scope joins —
  the tested cancel path (`tests/gui_cancel.oxl`).

Own-typed payloads (`chan own T`, `try_send`, `smkchan`, `scancel`,
`mkscope`/`goin`/`sjoin`/`curscope`, `is_root`) are the G1 language
additions this layer is built on — see `tests/chan_own.oxl`.

## Knobs

Set before `gui.run`: `gui.set_event_buffer(n)` (256),
`gui.set_cmd_buffer(n)` (512), `gui.set_drain_grace(ms)` (250).

## Building against GTK

    cc -O2 $(pkg-config --cflags gtk4) -c extra/gui/gtk/gtk_shim.c -o gtk_shim.o
    LANG_LDFLAGS="gtk_shim.o $(pkg-config --libs gtk4)" oxl build app.oxl

`examples/gui-todo/` is the reference app; `./build.sh` does the
above. `docs/gui-backends.md` covers the Backend contract and
second-backend evidence.
