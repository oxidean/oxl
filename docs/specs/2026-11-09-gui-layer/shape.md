# Portable GUI layer (`extra/gui` + `extra/gui/gtk`) — Shaping Notes

## Scope

Milestone G from the phase-2 map: a portable widget layer written in
the language — the design charter's path (b). The widget tree must
stay DOM-mappable so the parked web target is not foreclosed. Lands
as `extra/gui` + `extra/gui/gtk`: the first real consumer of the
monorepo `extra/` machinery (workspace resolution, subdir-module
fetch, git-index publishing).

Not this spec: dialogs/modals, menus, IME, a11y, HiDPI, canvas/draw
surface, platform-native-trio backends (cocoa/win32), a `pin`
UI-thread language primitive, widget breadth beyond what the
reference app needs.

## Evidence

- `docs/gui-pilot.md` (F1): GTK4-via-C-FFI works — opaque int
  handles, `{env,fp}` closures as the event interface, ~15-function
  C shim per macro-heavy toolkit, real signal round-trips, no
  constant-slope leak at 100k churn cycles.
- Pilot friction that becomes requirements: `str(cstr)` borrow
  aliases toolkit memory; GTK is thread-bound (blocking pool is the
  wrong tool); closures that escape scopes must not capture borrowed
  scope-arena data.
- Design forks owner-decided (WI-0004 brainstorm, 2026-11-08):
  retained widget tree over backend iface; own-tree scope-bound
  ownership; `chan Event` + `select` events; retained-widget backend
  protocol; `extra/` packaging.
- Spec-level forks resolved in WI-0005 brainstorm: UI-thread
  convention over primitive; single buffered event chan with
  drop-oldest + marker; typed setters over a narrow `Prop` protocol;
  pilot-parity first tranche; copy-at-boundary strings.

## The decision

**Retained widget tree in `.oxl` over a `gui.Backend` iface.**

```oxl
iface Backend {
    new(kind: WidgetKind, props: []Prop) -> int     // opaque handle
    set_prop(h: int, p: Prop)
    attach(parent: int, child: int)
    detach(parent: int, child: int)
    destroy(h: int)
    pump(events: EventBuf, cmds: CmdBuf)            // blocks; pinned task
    stop()                                          // asks pump to return
    wake()                                          // nudge a blocked pump
}

struct Prop   { id: int, val: PropVal }
struct Event  { kind: EventKind, target: int, data: EventData }

enum WidgetKind { window, vbox, hbox, label, button, entry,
                  list, scrolled }
enum EventKind  { clicked, activated, text_changed, close_requested,
                  row_activated, overflow }
enum PropVal    { Text(str), Flag(bool), Num(int) }
enum EventData  { None, Text(str), Index(int) }
```

Typed kinds (`gui.Window`, `gui.Button`, …) wrap handles with
concrete setters; a `gui.Widget` iface covers kind-polymorphic app
code. `gui.append` consumes the child (`own` move into the tree);
`gui.remove` detaches + destroys (`detach` never destroys —
`destroy` is the single release op).

Two mailboxes cross the iface: `events` (an `EventBuf`) carries
`Event`s out to a dispatcher, which forwards them onto the
app-facing `chan own Event`; `cmds` (a `CmdBuf`) carries `Cmd`s
back in — widget mutators enqueue and `pump` executes them on the
pinned task, which is how an event handler on an app task can
update a widget without breaking the thread rule (see
`items/backend-protocol.md`). Mailboxes rather than chans because
the boundary needs semantics a chan cannot express (never-blocking
posts, mid-queue eviction); the typed `chan own Event` is a
language addition the event model depends on (see
`items/event-model.md`).

Three backends matter:

- **`extra/gui/mock`** — pure-oxl `Backend` recording protocol calls;
  scriptable `pump`. The headless-CI answer: the whole layer is
  testable without a display.
- **`extra/gui/gtk`** — `Backend` over a generalized `gui_shim.c`
  (the pilot's macro-shim pattern, events marshalled into `Event`).
- **Second backend (G6)** — DOM-protocol sketch or a written case in
  `docs/gui-backends.md`; evidence the guardrail held.

## Key decisions

- **UI-thread convention, not primitive.** The task that calls
  `gui.run` owns the toolkit — documented as sharply as GTK's own
  rule. A `pin` primitive stays parked; revisited at G6 with
  two-backend evidence (reversible either way).
- **Events are channel values.** Backend posts `Event` structs into
  a bounded `EventBuf`; a dispatcher forwards them onto a buffered
  `chan own Event` (default 256, `gui.set_event_buffer(n)`);
  the app `select`s UI events next to its own channels. Overflow:
  drop-oldest + an `overflow` marker event — input events must not
  silently vanish. Shutdown: a bounded drain-grace window
  (`gui.set_drain_grace(d)`) preserves the buffered tail on pump
  exit; post-exit reply-carrying commands (`read`, `new_kind`)
  resolve with `gui.err_stopped()` — while fire-and-forget
  commands (`set_prop`, `attach`, `detach`, `destroy`,
  `dismiss_close`) are accepted-and-dropped, so callers must not
  rely on an error to detect a dropped mutation. Loss reporting is
  pull-based so it survives shutdown without needing a chan slot:
  `gui.events_dropped()` reads the EventBuf `dropped` counter even
  after `run` has returned or `events` observed closed — when the
  drain grace expires or the dispatcher is cancelled, every
  still-unsent entry is counted into `dropped` before unwind, so a
  tail that overflowed the app channel can never vanish silently
  even when no marker event would fit.
- **Copy at the boundary.** Text getters return owned `str`; no
  borrowed `cstr` aliases cross the public API.
- **The protocol is the milestone,** not widget count — pilot parity
  (8 kinds) plus what the reference app needs.

## Acceptance (milestone exit)

Full criteria in `plan.md` stage gates. Headline: a reference app
with real widgets beyond raw FFI calls runs on GTK4; second-backend
evidence exists (sketch or honest written case); `extra/gui`
publishable through the git index; every stage PR green + approved.
