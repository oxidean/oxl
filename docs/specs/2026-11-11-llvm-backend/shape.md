# LLVM backend — Shaping Notes

## Scope

The parked LLVM backend from `docs/specs/2026-11-07-phase-2-plan/
parked.md`, un-parked on the second-consumer trigger: milestone W's
`--target js` emit lane — in flight on `feat/milestone-w` (PR #66),
sequenced to merge before L starts — puts a second emitter behind the
codegen seam, so the seam is proven: two sibling emitters consume
`check.CkRes` (`bootstrap/codegen/codegen.oxl`,
`bootstrap/codegen/js.oxl`). A third
lane is no longer a hypothetical the seam was designed for; it is a
pattern with two instances. Lands as `bootstrap/codegen/llvm.oxl` +
a `oxl --target llvm` driver lane + a clang-gated test section. No new
runtime: the lane links the same `runtime/rt.c` (compiled by clang)
that the C lane links.

Not this spec: `llvm.coro.*` native-SSA suspension splitting, a wasm32
rt port (rt.c is pthread/POSIX — wasm needs a W-style re-expression or
wasi-sdk; the triple flag is designed not to foreclose it), DWARF
debug info, libLLVM/LLVM-C linkage into the toolchain binary, a
Rust-seed LLVM emitter, replacing the C lane, or any change to
`codegen.oxl`'s emitted text (the C-text fixpoint is a hard
constraint, not a budget).

## Evidence

- `docs/semantics/interfaces.md` designed the swap: "an LLVM backend
  drops in behind the same `TAST → object` seam" and `codegen/` is
  the only cc-aware module. The W lane already proved a second
  consumer drops in as a sibling file in `package codegen` exporting
  its own `emit_*` — `cmd/oxl/main.oxl`'s `compile_res` picks the
  lane off `flag_value("--target")` (`codegen.emit` vs
  `codegen.emit_js`).
- The emit contract is `CkRes -> str`. `CkRes` is `{ck, items}`:
  `ck.tyv` interned type handles, `fnsv`/`structsv`/`enumsv`/`ifacesv`
  decl tables, `susp` suspendable names, `fnvals`, `globals`; `items`
  is the checked `[]It {node, mod, file}` — the AST plus module/file
  provenance. Generic instantiation is emitter-side
  (`subst_ty` + per-lane bind maps + the `ginst_queue` mono queue);
  nothing in `CkRes` is C-shaped.
- `js.oxl` demonstrated the mechanical reuse path: same `package
  codegen`, same `o_*` symbol scheme, and the G1 reachability
  machinery (`gubegin`/`gudrain`/`gdef`/`gscan`) verbatim — its token
  scan is language-agnostic, and `.ll` text spells the same
  `o_*`/extern identifier tokens under `@`/`%` sigils.
- `runtime/rt.h` is the ABI contract — `OxlStr`, `RtSlice`, `RtFnv`,
  `RtIface`, `RtFrame`+`RtPoll`, the `rt_*` fn surface. rt.c does not
  know which emitter produced its calls ("the runtime doesn't know
  which compiler emitted it" — c2-codegen spec). An IR lane emitting
  `call`s to the same symbols with ABI-matching types inherits the
  entire runtime unchanged: scope arenas, ObjHdr/borrow checks,
  executor pools, chans/select, traps, the extern shim table.
- The `o_frm_*`/`o_poll_*` poll machines are *already* a coroutine
  ABI (`RtFrame {cur_scope, state}` + `int (*)(RtFrame*, RtTask*)` +
  `RT_PENDING/READY/CANCEL`). The executor only ever sees the
  `RtFrame` header and the poll fn pointer (`rt_task_new` takes
  `bytes` as a runtime `int64_t` — frame size is an emitted argument,
  not a compile-time rt constant).
- Platform reach the C lane can't touch: wasm/wasi has no gcc
  (wasi-sdk/emscripten are clang-only); clang-only toolchains are the
  norm on newer target SDKs; `clang` accepts `.ll` and `.c` in one
  invocation, so `clang --target=<triple> out.ll rt.c`
  cross-compiles the emitted program AND the runtime to any triple
  the installed clang has headers+libs for — the C lane's
  `cc`-and-pray model has no equivalent story. The optimization
  ceiling is the second justification: the emitted C carries
  poll-machine dispatch, per-fn sections, and optimizer-opaque
  runtime calls; IR gives the optimizer TBAA, attribute, and
  inlining precision C text can't express — and the cc-parse-time
  tax on every build goes away (emitted C for `cmd/oxl` is the
  single largest compile unit in the build).
- Fixpoint mechanics (`tests/run.sh`, ADR-0006): `drv0.c`/`drv1.c`/
  `drv2.c` — seed emit vs gen1 emit vs gen2 emit of the driver
  sources, diffed byte-identical. The lane must not perturb this:
  `llvm.oxl` is a sibling file, `codegen.oxl`'s output stays
  byte-identical by construction, and the lane gets its own
  IR fixpoint as a separate gate (L4).

## The decision

**A sibling `.oxl` emitter producing textual `.ll` + the same `rt.c`
runtime under clang + a `--target llvm` driver lane.**

- `bootstrap/codegen/llvm.oxl` — `emit_llvm(r, testm) -> str` in
  `package codegen`. Emits one LLVM IR module: `%o_s_*`/`%o_en_*`/
  `%o_ret_*`/`%o_frm_*` named types, `define @o_f_*`/`@o_poll_*`,
  `declare` + direct `call` for externs and `rt_*` ABI, G1
  reachability reused verbatim. Textual IR, never libLLVM: the seam
  is `CkRes -> str`, and the toolchain binary stays
  standalone-language — clang is needed on the machine running
  `--target llvm`, never to build `oxl` itself.
- `emit_and_llvm` in `cmd/oxl/main.oxl` — the `emit_and_cc` shape:
  `out.ll` + `rt.c`/`rt.h` copies in the scratch dir, `clang -O2
  out.ll rt.c -o out` with the same feature-gate text scans
  (`rt_sqlite_`/`rt_sock_`/`rt_m_` tokens appear in `.ll` call sites
  identically), `LANG_CLANG` probe, `--triple` passthrough.
- **Suspension shares the frame+poll lowering** — the lane emits the
  same `o_frm_*`-equivalent frame types and `o_poll_*` poll drivers
  implementing the `RtPoll` ABI; `rt.c`'s executor drives them
  unchanged. `llvm.coro.*` splitting is the alternative and is
  *decided against* for v1: the poll protocol IS the semantic
  contract with the scope/executor/trap machinery, and a coro lane
  would need a second executor protocol inside rt.c plus a doubled
  concurrency conformance surface, for optimization headroom the
  non-susp surface (the overwhelming majority of emitted code)
  already captures. Parked with a measured-overhead trigger —
  `items/suspension.md` carries the fork.
- Representation/ABI contract in `llvm-semantics.md`: all rt.h public
  types declared field-for-field; lane-owned types self-consistent;
  `RtScope` never sized statically — dynamic-size regions
  (`alloca i8, i64 %n` for non-frame scope blocks, `rt_task_new`
  byte-count tail for frame scope slots) via a new additive
  `rt_scope_sizeof()` rt entry.
- Driver: `build|run|test --target llvm`; `run`/`test` exec the
  produced native binary directly — no launcher runtime (simpler
  than the js lane's node dependency). `clang` availability gates
  the lane's suite section the way `command -v node` gates the js
  lane's.

## Stage map

`plan.md` carries the stage contracts. L1 emitter skeleton +
non-concurrency surface; L2 poll machines + full concurrency
surface; L3 driver lane + feature gates + `--triple`; L4 IR fixpoint
+ cross-lane parity; L5 docs + flag polish. Each stage's gate is
observable suite green plus output-parity against the native lane —
the lane's conformance claim is *identical observable behavior*, and
L4's fixpoint is the byte-identical-IR self-compile modeled on
ADR-0006's C-text chain.

## Risk

- **ABI drift** — every `rt.h` type must be declared
  field-for-field identical in IR; a silent layout skew (e.g. an
  `i64` where rt.h has `int`) corrupts calls across the boundary.
  Mitigation: `llvm-semantics.md` pins the table + explicit-width
  rule; L1's gate includes a layout self-check (emitted ABI-type
  offsets asserted against a `clang`-compiled reference in a test).
- **`RtScope` platform size** — `pthread_mutex_t`/`pthread_cond_t`/
  `SRWLOCK` sizes differ across the three CI OSes; statically
  sizing scope slots is the easy wrong move. The dynamic-size rule
  (`items/emit-seam.md` §scope-storage) removes the dependency —
  the emitted IR never names an rt-internal layout.
- **IR-as-text correctness** — an invalid `.ll` fails inside clang
  with diagnostics aimed at generated text, not oxl source.
  Mitigation: keep `.ll` on failure (the `out.c`-on-failure model),
  an `--emit-llvm` flag keeps it always, and the lane's own corpus
  is the conformance gate.
- **Fixpoint adjacency** — `llvm.oxl` shares `package codegen` with
  `codegen.oxl`; a careless edit to shared helpers perturbs C
  output. Rule: the lane may *read* shared helpers (G1 machinery,
  type tables, `xty` inference) but C-lane output must stay
  byte-identical — the existing `drv0/drv1/drv2.c` diff in
  `tests/run.sh` is the enforcer and stays unmodified.
- **Version floor skew** — emitted IR uses opaque `ptr` (LLVM ≥15);
  an older clang produces a parser error, not wrong code. Floor is
  pinned at LLVM 15 in `items/toolchain.md`.
