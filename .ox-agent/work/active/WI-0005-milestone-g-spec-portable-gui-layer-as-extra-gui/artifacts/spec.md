# Spec — milestone G: portable GUI layer (`extra/gui` + `extra/gui/gtk`)

Status: draft for review (G0)

## Problem

The design charter keeps three GUI paths open; the milestone map
commits to path (b): a portable widget layer written in the language,
kept DOM-mappable so the parked web target stays open. The F1 pilot
(`examples/gui-todo`, GTK4 via C FFI) proved the FFI + event-closure
story works and documented exactly what a real layer needs
(`docs/gui-pilot.md`). Milestone E has now landed the `extra/`
monorepo machinery — workspace resolution, subdir-module fetch,
git-index publishing — that this layer is the first real consumer of.

## Direction (owner-decided, WI-0004 + this item's brainstorm)

- **Retained widget tree over a backend iface.** The widget tree is
  `.oxl` code in `extra/gui`; a `gui.Backend` iface is the
  portability seam. GTK4 (`extra/gui/gtk`) is the first backend; a
  DOM backend is the guardrail-preserving second.
- **Own-tree, scope-bound ownership.** Widget nodes are `own` values
  attached into a tree bound to an app `scope`; `defer` + scope
  cancel give free teardown. `gui.Widget` is the iface for
  user-visible widget *kinds*; the tree itself is own-typed.
- **Events are channel values.** The backend posts `Event` structs to
  a buffered `chan own Event` the app `select`s on next to its own
  channels. Callback-style `gui_connect` stays backend-internal.
- **UI-thread rule:** `gui.run` must be called on the **root task**
  (the task executing `main`'s call chain). The runtime drives that
  task on the process's main OS thread via its own park loop and
  never pool-schedules it — root-task-only is a real pin mechanism,
  not a documented convention, and it matches GTK's main-thread
  requirement exactly. `run` rejects other callers with
  `gui.err_not_root()` — which needs a G1 runtime marker (`is_root`
  set by `rt_run_root`; `external` is shared with `rt_spawnb_task`).
- **Narrow backend protocol.** Typed public setters
  (`button.set_label`) desugar to `set_prop(h, Prop{id, val})` on the
  backend; `Prop` serializes toward DOM attributes.
- **Copy at the boundary.** `str` getters return owned copies; no
  borrowed `cstr` aliases cross the public API.

## Package layout

```
extra/
  gui/            package gui — widget tree, Event, Backend iface,
                  typed widget kinds, run/pump loop, event dispatch
  gui/gtk/        package gtk — Backend impl over the gui_shim.c
                  pattern (per-toolkit C shim for macro APIs)
  gui/mock/       package mock — pure-oxl Backend recording protocol
                  calls; headless test support
```

## Public surface (sketch — the spec-grade contract)

```oxl
// extra/gui
iface Backend {
    new(kind: WidgetKind, props: []Prop) -> int     // opaque handle
    set_prop(h: int, p: Prop)
    attach(parent: int, child: int)
    detach(parent: int, child: int)
    destroy(h: int)
    // EventBuf/CmdBuf are shared core-owned objects, passed by ref
    pump(events: EventBuf, cmds: CmdBuf)            // blocks; root task only
    stop()                                          // asks pump to return
    wake()                                          // nudge a blocked pump
}

enum CmdKind { new_kind, set_prop, attach, detach, destroy, read,
               dismiss_close }
struct Cmd       { kind: CmdKind, target: int, widget: WidgetKind,
                   prop: Prop, props: []Prop, arg: int,
                   reply: chan own CmdResult }
// target: handle (parent for attach/detach; new_kind: optional
//   attach-parent, 0 = detached); prop.id also selects for `read`;
//   props feeds Backend.new(kind, props) on the new_kind path
struct CmdResult { e: err, handle: int, val: PropVal }
// reply is a cap-1 chan allocated per Cmd — pump publishes it via
// try_send (non-suspending: susp methods can't cross a vtable);
// fresh+empty means the send always lands

struct Prop   { id: int, val: PropVal }             // tagged union
struct Event  { kind: EventKind, target: int, data: EventData }

enum PropVal   { Text(str), Flag(bool), Num(int) }
enum EventData { None, Text(str), Index(int) }

enum WidgetKind { window, vbox, hbox, label, button, entry,
                  list, scrolled }
enum EventKind  { clicked, activated, text_changed, close_requested,
                  row_activated, overflow }

// typed kinds wrap handles: gui.Window/Button/Entry/... each with
// concrete setters (set_title, set_label, set_text, ...) and a
// common `gui.Widget` iface for kind-polymorphic app code —
// non-susp methods only (handle/kind): CmdBuf-posting mutators and
// reply-blocking getters live on the concrete wrappers
// tree: gui.append(parent, child) consumes child (own move into
// the tree); gui.remove(parent, child) detaches + destroys
// EventBuf / CmdBuf: core-owned mutex-guarded mailboxes (NOT chans)
// — pump posts via eb.post / drains via cb.drain(), both of which
// never block; a dispatcher task inside run drains eb onto the
// app-facing chan own Event, synthesizing the overflow marker from a
// dropped-count flag (never a queue entry)
// run: gui.run(b: Backend, app: fn(chan own Event)) -> err — must be
// called on the root task (else gui.err_not_root()); run allocates
// the mailboxes + `events`, calls `app(events)` synchronously inside
// its inner scope — `app` is a non-susp trampoline whose body `go`s
// the real worker (susp fns can't be fn values; spawn needs a static
// callee) — spawns the dispatcher, then calls `pump` INLINE on that
// same
// root task; an internal watcher relays scope cancellation to
// b.stop() — a defer on the blocked task can't run while pump blocks
```

## Acceptance criteria

- **AC1 (spec this stage):** this document + staged `plan.md` +
  per-stage `items/` committed; CodeRabbit-approved PR merged.
- **AC2 (G1):** `extra/gui` core — tree, kinds, `Event`, `Prop`,
  `Backend` iface — compiles under `oxl.work`; `extra/gui/mock`
  backend implements the iface; `oxl test` suites drive the full
  widget/protocol surface headless (no display).
- **AC3 (G2):** `extra/gui/gtk` backend over a generalized
  `gui_shim.c`; the todo pilot **re-expressed through `extra/gui`**
  builds and passes the same selftest assertions (real GTK signals,
  churn leak check) wherever gtk4 resolves.
- **AC4 (G3):** events flow through `chan own Event` + `select`; a demo
  mixes UI events with a `time`/`chan` producer on one select loop;
  overflow policy verified (drop-oldest among drop-eligible +
  synthesized `overflow` marker event).
- **AC5 (G4):** widget tranche = pilot parity: window, vbox/hbox,
  label, button, entry, list, scrolled — plus whatever the reference
  app needs; each kind's Prop coverage documented.
- **AC6 (G5):** a reference app beyond the pilot (multi-widget state,
  e.g. a notes/settings form with real layout) runs interactively on
  GTK4.
- **AC7 (G6):** either a second backend sketched against `Backend`
  (DOM-protocol mock counts) or a written case in
  `docs/gui-backends.md` for why the iface does/doesn't foreclose
  one — evidence that the guardrail held.
- **AC8 (milestone exit):** all of AC2–AC7 green on CI; `extra/gui`
  publishable via the git index (`extra/v*` lane).

## Non-goals (explicit)

- No `pin`/UI-thread language primitive — the root-task rule IS the
  mechanism (the root task cannot migrate); revisited at G6 only if
  non-root GUI driving is ever wanted (see brainstorm G-a).
- No dialogs/modals, menus, IME, a11y, HiDPI model beyond raw pixels,
  canvas/draw surface. Each is parked with a reopen trigger (a11y:
  DOM backend work).
- No platform-native trio backend (cocoa/win32) — GTK4 first; second
  backend is for abstraction evidence, not platform coverage.
- No widget-count milestone — the protocol is the deliverable.

## Risks / traps carried from pilot + brainstorm

- Macro-API toolkits always need a C shim — `extra/gui/gtk` carries
  `gui_shim.c` + build integration (existing `LANG_LDFLAGS` /
  pkg-config pattern; per-file link directives stay parked).
- Scope-arena capture dangle: borrowed data captured into a closure
  that escapes to the backend UAFs on scope close — documented rule +
  the chan-event model makes handler escapes unnecessary by design.
- GTK thread-affinity vs the worker pool: `pump` must only ever run
  on the root task — structurally guaranteed by the `gui.run`
  root-task rule + a debug assert in the backend.
- Enum/union expressiveness: `PropVal` tagged union leans on v0.2
  enum/match — if payload variety outgrows it, the fallback is
  per-kind Prop/EventData structs (noted in plan).
