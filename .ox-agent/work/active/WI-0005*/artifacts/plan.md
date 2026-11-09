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

- `extra/gui/gui.oxl`: `Backend` iface, `WidgetKind`/`EventKind`
  enums, `Prop`/`PropVal`, `Event`, own-typed tree (`Window`/`Button`/
  `Entry`/`Label`/`Box`/`List`/`Scrolled` typed wrappers over int
  handles), `gui.append`/`gui.remove`, `gui.run(b, app)`.
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

- `gui.run(b, app)`: allocates `chan Event` (cap 256 default,
  `gui.set_event_buffer(n)`), hands it to `b.pump` and to `app`.
- Backend `pump`: toolkit callbacks marshal → `Event`, `send` on the
  chan (non-blocking try-send; on full: drop oldest, mark next
  `Event.kind = overflow`).
- Demo: `examples/gui-clock` or extend reference — `select` arm over
  `events` + a `time.tick`-style producer chan on one loop.
- Gate: selftest proves select-composability (UI click and timer
  interleave on one loop); overflow test: saturated queue emits the
  marker.

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
- The `pump` blocking contract interacts with `select`: app code
  must NOT call `gui.run` inside a scope that expects to cancel the
  pump — document the exit path (backend-provided `stop`/quit
  event).
