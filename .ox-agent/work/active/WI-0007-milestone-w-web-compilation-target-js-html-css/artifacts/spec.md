# Spec — milestone W: web compilation target (JS/HTML/CSS)

Status: draft for review (W0)

## Problem

oxl compiles to native only: `codegen → C → cc`. The language's own
charter kept a web target parked behind one guardrail — the portable
widget tree had to exist and prove DOM-mappable before committing a
second backend's worth of emit surface. Milestone G landed that
guardrail: `extra/gui`'s `Backend` iface maps to DOM "without schema
changes … nothing GTK-shaped beyond the thread rule, and even that
holds in the DOM world" (`docs/gui-backends.md`). The parked item
un-parks into milestone W: a JavaScript compilation target covering
the language, the concurrency runtime, the portable std surface, and
the DOM story that justifies it.

## Direction (WI-0007 brainstorm — all forks resolved)

- **A sibling emitter, not a port.** `bootstrap/codegen/js/` is a new
  .oxl package consuming the same `check.CkRes` + `susp` set as
  `codegen.emit` — `emit(r, testm) -> str` signature mirrored. The
  Rust seed stays untouched: `--target js` is an OXL-driver-only
  flag, so no dual-driver parity is owed (the seed bootstraps gen1;
  the js emitter compiles through it like any source).
- **`int` is BigInt.** oxl i64 semantics (wrap, shifts, division)
  survive via emitted `rt_i*` helpers applying `BigInt.asIntN(64)`.
  `Number` would silently lie past 2^53 — a compiler target that
  changes integer semantics isn't the same language.
- **`str` is a byte substrate.** `OxlStr{u8: Uint8Array, off, len}`
  — `len`/`byteat`/`substr`/`str as []byte` stay byte-faithful;
  `std/unicode/utf8`'s manual decoder ports literally. JS `string`
  only exists at edges: literals decode via TextEncoder once, and
  `rt_print_str`/DOM/`__oxl_ffi` boundaries decode on crossing.
- **Slices are `{a: Array, off, len, cap}`** — one view type; same
  backing-store trick as strings (`[]byte` may share Uint8Array
  storage where interop needs it). `push` mutates within `cap`,
  bounds failures `rt_trap(10)`.
- **Executor is frame-task-only.** Every spawned call — susp fn,
  builtin call, anything — lowers to a poll-able micro-frame on a
  `queueMicrotask`/`setImmediate` run queue. The blocking surface
  (`rt_send`/`rt_recv` blocking forms, `rt_scope_join_named`,
  `spawnBlocking`, `usleep`) has no single-thread equivalent and
  emits `rt_trap(21)` — "blocking surface unsupported on this
  target". Timers map to `setTimeout` (strictly better than rt.c's
  detached timer threads). `Worker`/`Atomics` blocked-thread
  emulation is a stated non-goal — it needs COOP/COEP headers that
  plain hosting doesn't send.
- **Externs bind through `globalThis.__oxl_ffi`.** Emitted calls
  `__oxl_ffi.<name>(args…)`; pair-returns use `{val, err}`. The
  runtime ships env flavors: `rt-node.mjs` (fs/proc/net via Node
  builtins) auto-wires when `typeof process !== "undefined"`;
  `rt-browser.mjs` fills the same names with `err`-returning stubs.
- **Emit form: `out.mjs` + runtime siblings.** `emit` returns the
  program text; the driver writes `out.mjs` importing `./rt.mjs`,
  and copies `runtime/{rt.mjs,rt-node.mjs,rt-browser.mjs}` beside it —
  the `rt.c`-copy model verbatim. `oxl run --target js` execs
  `node out.mjs`. `--html` additionally writes a module-script
  `index.html` host page.
- **own/borrow heap machinery erases under GC.** `rt_alloc`→`new`,
  `rt_free`→no-op, `chan own T` drop thunks retained but empty.
  Dynamic borrow *checks* do not erase — `rt_borrow_*` port as a
  per-task ledger (overlap → `TrapAliasing`), since call-arg
  aliasing is observable independent of GC. Move rules remain
  compile-time.
- **HTML/CSS scope = the GUI layer.** `extra/gui/dom` is a backend
  inside the existing `Backend` iface (WidgetKind→elements,
  Prop→attrs/props, Event→listeners). `pump` is a susp frame task
  parking on `stop`/`wake` edges — `gui.run` starts shutdown the
  moment it returns, so it must not return before `stop`; a
  microtask drain that exits would end the session and a
  synchronous wait would starve the single-threaded loop. The
  same contract applies to the mock under the JS lane. CSS is
  user assets beside `index.html`. Static-site/templating emit
  is a parked non-goal.

## Scope

- `runtime/rt.mjs`: run queue + poll scheduler; scope trees +
  cancellation + trap propagation; defer stacks; channels
  (unbuffered + buffered + `chan own T`), `select` with
  random-pick + timeout/`else`; named scopes (`mkscope`/`sjoin`/
  `scancel`/`smkchan`/`curscope`); `try_send`; `is_root` (scheduler-tracked root task); `shared`
  cells; err registry; slice/str ops + traps; `{val,err}` pairs.
- `runtime/rt-node.mjs`: `rt_*` extern impls over node:fs/process/
  child_process/net/dns (os, exec, net, filepath, log shims).
- `runtime/rt-browser.mjs`: same names as stubs — `err` returns or
  `rt_trap` per call contract.
- `bootstrap/codegen/js/`: the emitter — expressions, fns
  (incl. susp poll frames), generics, structs/enums/match,
  own/ref/mut (as refs), slices/strs, ifaces, fn vals, defer,
  go/spawn/goin (frame-only), chans/select, named scopes,
  `try_send`, `is_root`, externs→`__oxl_ffi`, `[v,err]`, traps.
- Driver: `--target js` on `build`/`run`/`test`; emit layout;
  node exec for `run`/`test`; `--html` scaffold.
- std: pure-oxl set ports unchanged (they compile through the new
  emitter); `os`/`exec`/`net`/`filepath`/`flag`/`log` and the
  `http` client paths work under Node via rt-node shims;
  `http.serve` is excluded from the node claim — its
  `spawnBlocking` accept/handler model traps under the §8
  blocking list pending a specified non-blocking serve path;
  browser env gets stubs.
- `extra/gui` + `extra/gui/mock` port unchanged (the conformance
  suite); `extra/gui/dom` new backend + `examples/web-todo`.
- Test lane: `command -v node`-gated section in `tests/run.sh`
  running the whitelisted set (`conc_*`, `gui_*` mock, pure-std
  corpus) through `oxl run --target js` with the same output
  greps; `oxl test` under node for `_test.oxl` files.

## Non-goals (parked with triggers)

- **Worker/SharedArrayBuffer blocked threads** — needs COOP/COEP;
  trigger: a real consumer needing `spawnBlocking` in-browser.
- **`--int-mode number`** — trigger: a measured BigInt hot path.
- **Static-site/template emit, CSS emit** — framework-layer work;
  trigger: a web-framework milestone above the language.
- **wasm target** — the LLVM-backend parked item owns that story;
  this milestone is JS only.
- **Rust-seed JS emitter** — OXL driver only; seed bootstraps.
- **Checker-level `spawnBlocking` rejection on js target** —
  runtime trap suffices; check stays target-agnostic.

## Acceptance

- `tests/run.sh` green incl. the node-gated JS lane: the
  whitelisted pure-std + `conc_*` + `gui_*` mock set passes under
  `oxl run --target js` on ubuntu/macos (windows lane optional —
  node there is image-dependent).
- `oxl build --target js examples/web-todo` + `--html` produces a
  page that renders the gui-todo app through `extra/gui/dom` —
  verified headless via the mock-equivalent DOM harness or a CI
  smoke asserting emitted structure.
- `oxl test --target js` runs `_test.oxl` files under node with
  `test_* … ok` output parity.
- A documented target doc (`docs/web-target.md`): flag surface,
  emit layout, env flavors, extern-binding convention, blocking
  traps, representation deltas vs native (BigInt/byte-str/no
  arenas).
