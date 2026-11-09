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
      `gui.run`, the `CmdBuf`/`EventBuf` mailbox direction (mutators
      post + `wake`, `pump` drains on the root task) — `CmdBuf` and
      `post`/`wake` land here since mutators need them from day one;
      `try_send` builtin added to the runtime here (the `ping`
      mechanism depends on it — `select` has receive arms only).
      `mock/`: pure-oxl backend recording protocol calls
      with a scriptable `pump`. `tests/gui_test.oxl` drives the
      whole surface headless.
      Gate: `oxl test` green on both checkers; zero gtk4 dependency.
- [not started] **G2 — GTK4 backend** — `extra/gui/gtk` +
      generalized `gtk_shim.c` from the pilot pattern; basic event
      dispatch lands here (`EventBuf` + drain dispatcher → app chan)
      since the selftest needs signals reaching the app; events
      marshalled into `Event`; thread-affinity debug assert;
      `examples/gui-todo` re-expressed through `extra/gui`.
      Gate: gtk4-gated build + `--selftest` parity (add/remove,
      churn RSS); copy-at-boundary verified; headless CI
      compile-only.
- [not started] **G3 — chan event model** — `gui.run` allocates the
      buffered `chan own Event`, the `EventBuf`/`CmdBuf` mailboxes,
      and the drain dispatcher; `eb.post` evicts drop-oldest among
      drop-eligible + counts drops + applies per-target
      `close_requested` dedup; dispatcher synthesizes the
      `overflow` marker; internal `stop`-watcher for scope teardown;
      demo mixing UI events with a timer chan on one `select`.
      Language additions land here (parser + both checkers, runtime
      representation unchanged): typed `chan own T` channels —
      `send` checks payload, `recv`/`select` bindings yield `own T`,
      bare `chan` unchanged — and the cancelled-send ownership
      contract from `items/event-model.md`.
      Gate: select-composability + overflow policy (incl. cap-1 and
      all-protected cases) proven in selftests; typed-chan parity
      between Rust and self-hosted checkers.
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
  documented and tested; root-task-only invocation needs the
  debug-assert verified (call from a spawned task must fail loudly).
- GTK availability: only gtk4-present environments run backend
  selftests; mock verification never blocks on a display.
