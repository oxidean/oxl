# extra/gui — portable GUI layer

A retained widget tree over a `Backend` interface. Apps mutate the
tree from any task; all toolkit calls run inside `gui.run`'s pump on
the root task. Events arrive on a `chan own Event` handed to the
app's entry point.

Backends shipped here:

- `mock/` — pure-oxl recording backend; scriptable `pump`, used by
  the suite headless.
- `gtk/` — GTK4 backend over `gtk_shim.c`; needs `pkg-config gtk4`
  at build time and a display at run time.

## Quick shape

    import "github.com/oxidean/oxl/extra/gui"
    import "github.com/oxidean/oxl/extra/gui/mock"

    fn app(events: chan own gui.Event) {
        [w, _] = gui.window("hi")
        [b, _] = gui.button("ok")
        gui.append(w, b)
        for {
            ev := recv(events)
            if ev == nil { break }
            if ev.kind == gui.EventKind.clicked { gui.stop() }
        }
    }

    fn main() {
        e := gui.run(mock.backend(), app)   // gtk.backend() for real
        if e != nil { /* err_not_root / err_stopped */ }
    }

`gui.run` must be called from the root task and runs one session at
a time; it returns `err_not_root()`/`err_stopped()` on violation.
See `docs/gui.md` for the full model and `docs/gui-backends.md` for
the backend-authoring notes.

## Kinds, props, events

`WidgetKind`: `window vbox hbox label button entry list scrolled`.
Props are `Prop{id, val}` with `PropVal = Text|Flag|Num`; event
payloads are `EventData = None|Text|Index`.

Prop coverage per kind (r/w = set + read, ro = read-only, — = none):

| kind     | P_TEXT | P_TITLE | P_PLACEHOLDER | P_ROWS |
|----------|--------|---------|---------------|--------|
| window   | —      | r/w     | —             | —      |
| vbox     | —      | —       | —             | —      |
| hbox     | —      | —       | —             | —      |
| label    | r/w    | —       | —             | —      |
| button   | r/w    | —       | —             | —      |
| entry    | r/w    | —       | r/w           | —      |
| list     | —      | —       | —             | ro     |
| scrolled | —      | —       | —             | —      |

`P_ROWS` is computed live by the backend (list child count) — reads
go through `List.rows()` / `read_prop(h, P_ROWS)`, never cached.

Primary event per kind (what the GTK selftest drives):

| kind   | events                                   |
|--------|------------------------------------------|
| window | `close_requested` (dedup'd by `close_pending`; `dismiss_close(w)` re-arms) |
| button | `clicked`                                |
| entry  | `text_changed` (data `Text`), `activated` |
| list   | `row_activated` (data `Index`)           |
| any    | `overflow` marker (data `Index(n)` dropped count) — synthesized by the core, not a backend |

Constructors: `window(title)`, `vbox()`, `hbox()`, `label(text)`,
`button(text)`, `entry(placeholder)`, `list()`, `scrolled()` — all
`-> [T, err]` with typed wrappers `handle()`/`kind()`. Tree ops:
`gui.append(parent, child)`, `gui.remove(w)` (destroys the subtree).
Setters: `w.set_title`, `l.set_text`, `b.set_label`, `e.set_text`,
or `gui.set_prop(h, id, v)` generically. Readers: `e.text()`,
`l.rows()`, or `gui.read_prop(h, id) -> [PropVal, err]`.

## Knobs (set before `gui.run`)

- `gui.set_event_buffer(n)` — EventBuf cap, default 256
- `gui.set_cmd_buffer(n)` — CmdBuf cap, default 512
- `gui.set_drain_grace(ms)` — dispatcher drain window on shutdown,
  default 250

After `run` returns: `gui.events_dropped()` reports the loss count
(evicted drop-eligible events + cancelled sends, minus credited
reposts); `gui.close_pending(w)` / `gui.dismiss_close(w)` manage
close-request dedup.
