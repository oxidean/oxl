# Portable GUI layer — Stage Plan

Spec: `shape.md`. Design contracts: `items/backend-protocol.md`,
`items/event-model.md`. Working artifacts: WI-0005 under
`.ox-agent/work/`. Every stage is a PR through the review loop
(approval + green CI); every stage lands with the suite green.
Automatic reviews are disabled repo-wide — request a pass manually
with `@coderabbitai review` on each stage PR after pushing the head
you want verdicted, and again after the last fix commit.

- [done] **G0 — spec** — PR #56 — this directory, WI-0005 artifacts,
      ADR for the six spec-level forks. *(this PR)*
- [done] **G1 — `extra/gui` core + mock backend** — the milestone-g PR
      `gui.oxl`: `Backend` iface, `WidgetKind`/`EventKind`,
      `Prop`/`PropVal`, `Event`/`EventData`, own-typed tree, typed
      kind wrappers, `gui.Widget` iface, `gui.append`/`gui.remove`,
      `gui.run`, the `CmdBuf`/`EventBuf` mailbox direction (mutators
      post + `wake`, `pump` drains on the root task) — `CmdBuf` and
      `post`/`wake` land here since mutators need them from day one
      — plus the drain dispatcher → app `chan own Event` (basic
      delivery only: the G1 mock test asserts dispatch end-to-end,
      so the delivery path cannot wait for G2's real backend; the
      full overflow policy still lands in G3). The internal
      `stop`-watcher lands here too — `gui.run` + cancellable
      scopes without it leave `pump` parked forever on the cancel
      path (the watcher `select`s scope-cancel vs `retire`, its
      `defer` calls `b.stop()`);
      `try_send` builtin added to the runtime here (the `ping`
      mechanism depends on it — `select` has receive arms only),
      covering `chan own T` payloads too: `pump`'s reply publication
      must be non-suspending (iface methods can't suspend across a
      vtable), so `try_send` on `chan own CmdResult` is the legal
      reply path — `true` moves the payload, `false` retains it.
      Also here: the runtime marks the task `rt_run_root` is
      ENTERED for (`is_root` — `external` can't discriminate the
      root task from `rt_spawnb_task` tasks) so `gui.run`'s
      `err_not_root()` check has something to test. The mark lands
      on the true root task only: a spawned frame that fell back
      to inline `rt_run_root` execution (thread creation failed,
      no pool workers) is NOT marked — it can sit on a non-entry
      thread where GTK must never run. Test binaries still pass
      legitimately (their main IS their root task), so the mock
      suite keeps its `pump`-driving path.
      `mock/`: pure-oxl backend recording protocol calls
      with a scriptable `pump`. `tests/gui_mock.oxl` +
      friends drive the whole surface headless.
      Language additions land here so G2's app chan is typed from
      its first selftest (parser + both checkers + a small runtime
      element-drop hook — word representation unchanged): `chan own
      T` — `send` type-checks the payload, `recv`/`select` bindings
      yield `own T`, bare `chan` unchanged — plus a `drop_elem`
      destructor registered on owned channels so the cancelled-send
      ownership contract and `chan own T` teardown reclaim of
      buffered payloads have the metadata they need, per
      `items/event-model.md`. Two more runtime surfaces land here:
      a scoped-cancel surface (heap/named scope value +
      `rt_scope_cancel` export + a `cancel`/`std/task` entry —
      G3's drain-grace abort has no other way to fire) and
      scope-targeted `mkchan` (cap-1 reply chans bind to the
      mailbox-owning scope, not the caller's innermost — a
      cancelled caller must not free a chan under a queued `Cmd`;
      see `items/backend-protocol.md`).
      Gate: `oxl test` green on both checkers; zero gtk4 dependency;
      typed-chan parity between Rust and self-hosted checkers;
      mock-driven dispatch asserted end-to-end and a cancellation
      test (`scope { gui.run(...) }` + cancel while `pump` waits →
      watcher fires `stop`, `run` returns, join completes).
- [done] **G2 — GTK4 backend** — the milestone-g PR — `extra/gui/gtk` +
      generalized `gtk_shim.c` from the pilot pattern; the GTK
      backend wires real toolkit signals into the G1 delivery path
      (`eb.post` → dispatcher → app chan — the chan is `chan own
      Event` from the start, typed channels landed in G1 above);
      events marshalled into `Event`; thread-affinity
      debug assert;
      `examples/gui-todo` re-expressed through `extra/gui`.
      Gate: gtk4-gated build + `--selftest` parity (add/remove,
      churn RSS); copy-at-boundary verified; headless CI
      compile-only.
- [done] **G3 — chan event model** — the milestone-g PR — extends `gui.run`'s
      event machinery (mailboxes + dispatcher land in G1/G2) with
      the full overflow policy: `eb.post` evicts drop-oldest among
      drop-eligible + counts drops + applies per-target
      `close_requested` dedup; dispatcher synthesizes the
      `overflow` marker;
      `gui.events_dropped()` loss reporting; demo mixing UI events
      with a timer chan on one `select`.
      Gate: select-composability + overflow policy (incl. cap-1 and
      all-protected cases) proven in selftests; `close_pending`
      dedup exercised from post through delivery and dismissal;
      `events_dropped()` reads the stashed count after `run`
      returns.
- [done] **G4 — widget tranche** — the milestone-g PR — pilot parity: window,
      vbox/hbox, label, button, entry, list, scrolled + whatever the
      reference app needs; per-kind Prop coverage table in
      `extra/gui/README.md`.
      Gate: every kind constructible + drivable via mock; GTK
      selftest exercises each kind's primary event.
- [done] **G5 — reference app** — the milestone-g PR — multi-widget state example
      (list + form + live edit, nested layout, scope-managed
      teardown) beyond the pilot's shape.
      Gate: scripted selftest via mock AND gtk backend.
- [done] **G6 — second-backend evidence + docs** — the milestone-g PR —
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
  unconditional check in `gui.run` verified (a call from a spawned
  task must resolve `gui.err_not_root()`).
- GTK availability: only gtk4-present environments run backend
  selftests; mock verification never blocks on a display.
