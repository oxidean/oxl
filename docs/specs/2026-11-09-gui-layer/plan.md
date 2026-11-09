# Portable GUI layer — Stage Plan

Spec: `shape.md`. Design contracts: `items/backend-protocol.md`,
`items/event-model.md`. Working artifacts: WI-0005 under
`.ox-agent/work/`. Every stage is a PR through the review loop
(approval + green CI); every stage lands with the suite green.

- [in progress] **G0 — spec** — this directory, WI-0005 artifacts,
      ADR for the six spec-level forks. *(this PR)*
- [not started] **G1 — `extra/gui` core + mock backend**
      `gui.oxl`: `Backend` iface, `WidgetKind`/`EventKind`,
      `Prop`/`PropVal`, `Event`/`EventData`, own-typed tree, typed
      kind wrappers, `gui.Widget` iface, `gui.append`/`gui.remove`,
      `gui.run`. `mock/`: pure-oxl backend recording protocol calls
      with a scriptable `pump`. `tests/gui_test.oxl` drives the
      whole surface headless.
      Gate: `oxl test` green on both checkers; zero gtk4 dependency.
- [not started] **G2 — GTK4 backend** — `extra/gui/gtk` +
      generalized `gtk_shim.c` from the pilot pattern; events
      marshalled into `Event`; thread-affinity debug assert;
      `examples/gui-todo` re-expressed through `extra/gui`.
      Gate: gtk4-gated build + `--selftest` parity (add/remove,
      churn RSS); copy-at-boundary verified; headless CI
      compile-only.
- [not started] **G3 — chan event model** — `gui.run` allocates the
      buffered `chan Event`; backend `pump` posts via try-send;
      drop-oldest + `overflow` marker on saturation; demo mixing UI
      events with a timer chan on one `select`.
      Gate: select-composability + overflow policy proven in
      selftests.
- [not started] **G4 — widget tranche** — pilot parity: window,
      vbox/hbox, label, button, entry, list, scrolled + whatever the
      reference app needs; per-kind Prop coverage table in
      `extra/gui/README.md`.
      Gate: every kind constructible + drivable via mock; GTK
      selftest exercises each kind's primary event.
- [not started] **G5 — reference app** — multi-widget state example
      (list + form + live edit, nested layout, scope-managed
      teardown) beyond the pilot's shape.
      Gate: scripted selftest via mock AND gtk backend.
- [not started] **G6 — second-backend evidence + docs** —
      `extra/gui/dom` protocol sketch or `docs/gui-backends.md`
      honest case; `docs/gui.md` user docs (tree/event model,
      UI-thread convention, copy-at-boundary, scope-capture rules);
      pin-primitive question revisited with evidence.
      Gate: exit criteria met; `extra/gui` index-publishable.

## Dependencies

G1→G2→G3 strictly sequential. G4 partially overlaps G3 (kinds land
against the mock while chan model finishes). G5 needs G4. G6 needs
G5. Within a stage, mock tests and backend work split cleanly.

## Watch items

- `PropVal`/`EventData` union expressiveness — decide at G1 when the
  concrete prop list is written; per-kind structs is the documented
  fallback.
- `gui.run` inside a cancellable scope needs the `stop()` exit path
  documented and tested.
- GTK availability: only gtk4-present environments run backend
  selftests; mock verification never blocks on a display.
