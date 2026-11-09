# Plan — milestone G: portable GUI layer

Spec: `artifacts/spec.md` (AC1–AC8). Stage structure follows the
milestone map's sketch; each stage is one PR through the usual loop
(suite green + CodeRabbit approval). Publication layout on merge:
`docs/specs/<date>-gui-layer/{shape.md, plan.md, items/g1..g6.md}`.

## G0 — this spec (done when merged)

- Deliverable: spec + plan + items committed under `docs/specs/`.
- Gate: PR approved + green (docs-only CI fast path).

## G1 — `extra/gui` core + mock backend (AC2)

Depends on: E2 (`extra/` layout) — landed.

- Language additions landing in G1 (per the published plan):
  `chan own T` + `drop_elem` destructor plumbing; `try_send` on
  bare `chan` AND `chan own T` (the reply path needs it — `pump`
  is an iface method and can't suspend); an `is_root` runtime
  marker (`rt_run_root` sets it; `external` is shared with
  `rt_spawnb_task`) backing `gui.err_not_root()`.
- `extra/gui/gui.oxl`: `Backend` iface, `WidgetKind`/`EventKind`
  enums, `Prop`/`PropVal`, `Event`, own-typed tree (`Window`/`Button`/
  `Entry`/`Label`/`Box`/`List`/`Scrolled` typed wrappers over int
  handles), `gui.append`/`gui.remove`, `gui.run(b, app)` — `app`
  is a non-susp trampoline `fn(chan own Event)` whose body `go`s
  the real worker into `run`'s inner scope — plus
  the `CmdBuf`/`EventBuf` mailbox direction (mutators post +
  `wake`, `pump` drains on the root task), which mutators need
  from day one.
- `extra/gui/mock/mock.oxl`: pure-oxl `Backend` recording every
  protocol call in order; scriptable `pump` (test feeds an event
  script, asserts dispatch).
- `extra/oxl.mod` gains the gui packages; root `oxl.work` already
  covers `extra/`.
- `tests/gui_test.oxl` (mock-driven): tree attach/detach/own-move
  rules, prop forwarding, typed setter → `set_prop` mapping, event
  decode, overflow policy.
- Gate: `oxl test` on gui suites green both checkers; no gtk4 needed
  anywhere (headless is the point).

## G2 — GTK4 backend (AC3)

Depends on: G1.

- `extra/gui/gtk/gtk.oxl` + `gtk_shim.c` (generalize the pilot's
  `gui_shim.c`: same opaque-int handles, {env,fp} trampolines, but
  events marshalled into `Event` structs for `pump`).
- Basic event dispatch lands here: `EventBuf` + drain dispatcher
  → app `chan own Event` (cap 256 default, `gui.set_event_buffer(n)`).
- Thread-affinity convention enforced: backend records the `gtk_init`
  thread id; `pump`/`new`/`set_prop` assert on it (debug check).
- Re-express the pilot: `examples/gui-todo` rewritten on `extra/gui`
  (kept side-by-side or replaced — plan call: replace, since the
  pilot's raw-FFI teaching role is superseded; git history keeps the
  FFI example).
- Gate: gtk4-gated build + `--selftest` parity (rows add/remove,
  churn RSS curve); headless CI still compile-only. Copy-at-boundary
  verified: `entry.text()` returns owned str (selftest mutates the
  widget then re-reads).

## G3 — chan event model (AC4)

Depends on: G2 (a real backend to post events).

- `gui.run(b, app)`: extends the event machinery from G1/G2
  (mailboxes + dispatcher) with the full overflow policy; spawns
  `app`; runs `b.pump` inline on the root task.
- Backend `pump`: toolkit callbacks marshal → `Event`, `eb.post(e)`
  on the `EventBuf` (never blocks — lock, evict the first
  drop-eligible entry on full, append, `try_send` ping). A
  dispatcher task drains the buf onto `events` with blocking sends
  and synthesizes `Event{kind: overflow, Index(n)}` from the
  `dropped` count; `close_requested` is never drop-eligible while
  its target lives (per-handle `close_pending` dedup).
- Demo: `examples/gui-clock` or extend reference — `select` arm over
  `events` + a `time.tick`-style producer chan on one loop.
- Gate: selftest proves select-composability (UI click and timer
  interleave on one loop); overflow tests: saturated buf emits the
  marker; cap-1 and all-protected bufs still make progress;
  `close_pending` exercised post → delivery → `dismiss_close`;
  `events_dropped()` reads the stashed count after `run` returns.

## G4 — widget tranche (AC5)

Depends on: G3 (any widget is only real once events flow).

- Pilot parity: window, vbox/hbox, label, button, entry, list,
  scrolled — each with its typed setters + its events in the enum.
- Additions only as the G5 reference app demands (candidate:
  checkbox/toggle for a settings form).
- Per-kind Prop coverage table in `extra/gui/README.md`.
- Gate: every kind constructible + drivable via mock; GTK selftest
  exercises each kind's primary event.

## G5 — reference app (AC6)

Depends on: G4.

- `examples/gui-notes` (or similar): multi-widget state — list +
  form + live edit, real layout (scrolled + vbox/hbox nesting),
  state synchronized through the event loop, `scope`-managed
  teardown.
- This is the milestone's "real widgets beyond raw FFI" proof.
- Gate: runs interactively; scripted selftest through the mock AND
  the gtk backend.

## G6 — second-backend evidence + docs (AC7, exit)

Depends on: G5.

- `extra/gui/dom/` sketch OR `docs/gui-backends.md`: a DOM backend
  against the same `Backend` iface — `Prop{id,val}` maps to DOM
  attrs/props, `WidgetKind` to elements, `Event` to DOM events. A
  protocol-mock impl (no JS runtime — a serializer emitting
  DOM-protocol ops) suffices as evidence.
- `docs/gui.md`: user-facing layer docs (tree model, event model,
  UI-thread convention, copy-at-boundary rule, scope-capture rule).
- Revisit the `pin`-primitive question WITH evidence (two backend
  shapes known): document the outcome either way.
- Gate: exit criteria met — second backend sketched or honest written
  case; docs landed; `extra/gui` index-publishable.

## Parallelization

G1→G2→G3 is strictly sequential (each needs the prior's artifact).
G4 overlaps G3 partially (widget kinds can land against the mock
while the chan model is finishing). G5 needs G4. G6 needs G5 for the
"does the iface hold" evidence. Within a stage, mock-tests and
gtk-backend work split cleanly across files.

## Stage-order risk notes

- `PropVal` tagged-union expressiveness: if widget props outgrow the
  enum payload model, fall back to per-kind Prop structs — flagged in
  the spec; decide at G1 when the concrete prop list is written.
- GTK availability: only gtk4-present environments run the backend
  selftest; everything else is mock-verified — the milestone never
  blocks on a display.
- `gui.run` inside a cancellable scope is a SUPPORTED path, not a
  hazard: `run` wires an internal watcher that relays the enclosing
  scope's cancellation to `b.stop()`, so `scope { gui.run(...) }`
  tears down cleanly — verified by a mock-driven cancellation test.
  What teardown cannot ride is `defer` on the `gui.run` task itself
  (it can't fire while `pump` blocks that task) — the watcher exists
  precisely for that; `stop` remains the in-band exit path (no
  `quit` `Cmd` exists — `CmdBuf`'s `closed` flag carries the
  post-stop semantics).
