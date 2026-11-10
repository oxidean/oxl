# WI-0007 plan — milestone W

Spec: `docs/specs/2026-11-10-web-target/` (shape + plan +
js-semantics + items/dom-backend), ADR-0010.

Stages per `docs/specs/2026-11-10-web-target/plan.md`:

- W1 `runtime/rt.js` core — run queue, frame scheduler, scopes/
  traps/defers, err registry, str/slice ops, shared cells,
  `__oxl_ffi` shell
- W2 `bootstrap/codegen/js` — non-concurrency emit surface,
  IIFE/temp lowering, `{a,off,len,cap}` + `{u8,off,len}` views
- W3 concurrency surface — susp poll frames, spawn/goin, chans/
  select/try_send, named scopes, blocking traps
- W4 driver `--target js` + emit layout + node run/test +
  `--html` + run.sh JS lane
- W5 rt-node/rt-browser std shims + `extra/gui`/`mock` port
  verification
- W6 `extra/gui/dom` + `examples/web-todo` + docs/web-target.md
  + closeout

Parking: Worker/SAB threads, `--int-mode number`, web-framework
emit, wasm (LLVM item owns), Rust-seed emitter, checker-level
blocking rejection.
