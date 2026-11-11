# Milestone L — LLVM emit lane — Stage Plan

Spec: `shape.md`. Representation/ABI contract: `llvm-semantics.md`.
Item contracts: `items/emit-seam.md`, `items/suspension.md`,
`items/toolchain.md`. Working artifacts: WI-0010 under
`.ox-agent/work/`. Every stage is a PR through the review loop; every
stage lands with the suite green. Stages are sequential.

Sequencing: this spec assumes milestone W merged — the `--target`
flag plumbing, the `emit_js` lane precedent it cites, and
`target_is_js()` the L3 dispatch sits beside all ship with W.
If W somehow lands after L starts, L3's dispatch extends the
two-lane `compile_res` directly and the text reads the same with
one fewer sibling.

- [ ] **L0 — spec** — *(this PR)* — this directory, WI-0010
      artifacts, ADR-0013 for the spec-level forks, roadmap/parked
      annotations.
- [ ] **L1 — `bootstrap/codegen/llvm.oxl`: IR skeleton +
      non-concurrency surface.**
- [ ] **L2 — concurrency surface: frames + poll drivers + spawn/
      chans/select/scopes.**
- [ ] **L3 — driver lane: `--target llvm`, `emit_and_llvm`,
      `--triple`, feature gates.**
- [ ] **L4 — IR fixpoint + cross-lane parity gate.**
- [ ] **L5 — docs + flag polish.**

## L0 — spec (this docset)

`shape.md`, `llvm-semantics.md`, `plan.md`, `items/{emit-seam,
suspension,toolchain}.md`, ADR-0013, WI-0010 artifacts, roadmap +
`parked.md` trigger-fired annotations. Gate: merged.

## L1 — emitter skeleton + non-concurrency surface

`bootstrap/codegen/llvm.oxl` in `package codegen`, exporting
`emit_llvm(r: own check.CkRes, testm: int) -> str` — one `.ll`
module per `llvm-semantics.md`:

- Type mapping + boundary type decls (`%OxlStr`/`%RtSlice`/`%RtFnv`/
  `%RtIface`), `%o_s_*`/`%o_en_*`/`%o_ret_*` lane types incl. the
  largest-variant union rule + the §6 size model.
- Non-susp fns: `define @o_f_*`, expressions/statements through the
  alloca+mem2reg discipline, `match` (incl. expr-position, the
  stmt-expr replacement shape), `defer` (fn-exit drain), `assert`/
  bounds → `rt_trap`, globals + `ginit`, fn values + closures +
  `%o_denv_*`, ifaces + `@o_vt_*` tables + method thunks, generics
  through the shared `ginst_queue` machinery, externs as `declare` +
  direct calls (pair rets degrade to `i64`), `oxl_main` non-susp
  entry, testm `test_*` wrappers with dynamic-size `RtScope`
  allocas.
- G1 reachability reused verbatim (`gubegin`/`gudrain`/`gdef`/
  `gscan`) — same `o_*` def registry, same dead-decl pruning.
- susp fns are L2's deliverable: L1 emits `call void @rt_trap(
  i64 21)` at every susp position (susp calls, spawn of susp
  callees, susp `main`) — a runtime trap, not a diag (check stays
  target-agnostic), the same loud-trap posture W2 used before W3.
- `runtime/rt.h`: additive `int64_t rt_scope_sizeof(void)` entry —
  the only rt change the whole milestone needs; the C lane's
  emitted text is untouched (it never spells it).

Gate: a curated pure-stdlib corpus (the W2 shape — `fmt`/`strconv`/
`collections`/`regexp`/`encoding`/`sort`-level tests, no chans/
spawn) emits `.ll`, `clang -O2 out.ll rt.c` compiles clean under
`-Wall -Werror`-equivalent IR strictness (verifier clean), and the
binary's output matches `oxl run` byte-for-byte on every corpus
file. Plus `tests/llvm_abi_check.oxl` (new): a fixture whose
emitted `o_s_*`/boundary-type field offsets are asserted against a
clang-compiled reference — the ABI-drift tripwire.

## L2 — concurrency surface

The poll-machine lowering per `items/suspension.md`:

- `%o_frm_*` frame types + `define i32 @o_poll_*(ptr, ptr)` drivers:
  `switch` on `fr->state`, `RT_PENDING`/`RT_READY`/`RT_CANCEL`
  returns, `tls_scope` save/restore, `fr->child` inline-poll,
  suspend-point hoisting parity with the C lane's statement-
  boundary rule.
- Scope slots via the §5 dynamic tail (`rt_task_new` bytes =
  fixed + `nscopes × rt_scope_sizeof()`), non-frame scope blocks via
  dynamic `alloca` (L1 already emits the wrapper sites; L2 enables
  them in-frame), named scopes (`rt_scope_new`/`rt_scope_named`/
  `curscope`/`scancel`/`sjoin`/`rt_scope_join_poll`/
  `rt_scope_finish_named`), `scope {}` blocks, cancel-unwind defer
  drain, `is_root` → `rt_is_root`.
- `spawn`/`go`/`goin`/`spawnBlocking`: susp callees →
  `rt_task_new`/`rt_task_new_in` + `rt_spawn_task`/`rt_spawnb_task`;
  non-susp callees → args struct + `l_tr_`-band `ptr(ptr)` thunks
  + `rt_spawn`/`rt_spawnb` — identical split to the C lane.
- Chans: `rt_mkchan`/`rt_mkchan_scoped` (+ `o_drop_*` elem dtors),
  `send`/`recv`/`try_send`/`close`, `rt_send_poll`/`rt_recv_poll`,
  `select` → `RtChan*[]` array + `rt_select_poll` + `rt_select_arm`
  cleanup, `rt_sleep_poll`/`rt_msleep_poll`, `usleep` inline.
- susp main → `rt_task_new` + `rt_run_root` in `oxl_main`.

Gate: the concurrency whitelist runs under a manual
`--target llvm` driver path with output identical to native:
`conc_ping conc_scale select select_fair chan_own chanbuf
chanbuf_close scope_exit orphan_join defer_order pairfwd
select_cancel cancel_join susp_closure zero_str` + the non-conc
L1 corpus — each file's success marker grepped, trap-expectation
files (`select_cancel`/`cancel_join`) asserting the
`escaped top scope` line + non-zero exit. This is the stage's
conformance claim: same runtime, same observable behavior, IR
instead of C.

## L3 — driver lane

`cmd/oxl/main.oxl`:

- `flag_value("--target")` accepts `llvm`; validation message grows
  to name all three lanes. `target_is_llvm()` beside
  `target_is_js()`; `compile_res` picks `codegen.emit_llvm` —
  check stays target-agnostic (the R/W precedent: no target input
  to `check`).
- `emit_and_llvm(llsrc, out, entry)` — the `emit_and_cc` shape:
  scratch dir, `out.ll` + `rt.h`/`rt.c` copies, `pick_clang()`
  (`LANG_CLANG` env → `clang` probe, `clang --version` ≥15 check —
  `items/toolchain.md` §floor), args mirroring `emit_and_cc`
  (`-O2`, `-pthread` off Windows, `-ffunction-sections`/
  `-fdata-sections` + `-Wl,--gc-sections`/`-dead_strip`), the same
  emitted-text feature scans (`rt_sqlite_` → `-DOXL_SQLITE` +
  `-lsqlite3`/`LANG_SQLITE_SRC`, `rt_sock_*` → `-DOXL_NET`/`ws2_32`,
  `rt_m_` → `-DOXL_MATH` + `-lm`), `LANG_LDFLAGS` tail, `.ll` kept
  on failure like `out.c`. `clang` compiles `out.ll rt.c` in one
  invocation — the runtime needs no separate build step.
- `--triple=<t>` → `clang -target <t>` (both inputs; sysroot/
  headers are the local clang's problem — `items/toolchain.md`).
- `run`/`test` exec the produced binary directly — no launcher.
- `oxl test --target llvm` on `_test.oxl` via the same path.
- `bootstrap/cmd/codegen` grows `--emit llvm` beside `--test`
  (its `run()` picks `emit_llvm` for the flag) — the L4 fixpoint's
  `drv*.ll` source and the parity harness's emit path.

Gate: `tests/run.sh` grows an `== llvm lane ==` section gated on
`command -v clang` (skips cleanly where absent — the node-gate
shape): the full L1+L2 whitelist through `run --target llvm` with
success markers, the `_test` corpus through `test --target llvm`,
the trap files through `build --target llvm` + exec. All three CI
OS legs run it (clang ships on ubuntu/macos runners; the windows
leg installs LLVM or skips by the same gate — `items/toolchain.md`
§CI).

## L4 — IR fixpoint + cross-lane parity

The ADR-0006 chain, one lane over — `tests/run.sh` grows:

- **IR fixpoint**: the C-lane-built product driver emits
  `drv1.ll` for the driver sources (`oxl run bootstrap/cmd/codegen
  -- cmd/oxl` equivalent for the llvm lane — the emit entry is
  `emit_llvm`, driven through `oxl build/run` flags or a
  `bootstrap/cmd/codegen` `--emit llvm` flag added in L3);
  `oxl-self2` rebuilt *via `--target llvm`* (`oxl build cmd/oxl
  --target llvm -o target/oxl-llvm`) emits `drv2.ll`; `diff`
  byte-identical. This is the lane's own fixpoint — the C-text
  fixpoint (`drv0/1/2.c`) stays byte-identical and unmodified as
  the shared-package regression guard.
- **Cross-lane parity**: the `llvm_abi_check` + conformance
  whitelist binaries built both ways run diffed output — already
  gated per-stage; L4 wires the table into run.sh permanently.
- The lane compiles the *whole* toolchain — `cmd/oxl` +
  `bootstrap/*` under `--target llvm` is the implicit coverage
  gate: every construct the toolchain sources exercise emits
  through the lane end-to-end.

Gate: `diff drv1.ll drv2.ll` clean in CI wherever clang exists;
`diff drv0.c drv1.c`/`drv1.c drv2.c` still clean; the llvm-built
driver passes the suite sections run under it (a
`OXL=target/oxl-llvm` re-run of the smoke sections — hello,
features, match, methods).

## L5 — docs + flag polish

- `docs/llvm-target.md` — flag surface (`--target llvm`, `--triple`,
  `--emit-llvm`), toolchain floor, what the lane shares with the C
  lane, the parked list below, troubleshooting (`clang` diagnostics
  on `.ll`, keeping intermediates).
- `--emit-llvm` flag — write `out.ll` beside the binary (the
  inspectability story that replaces emitted-C readability).
- `docs/semantics/interfaces.md` — the codegen section gains the
  three-lane reality note (C `.c` + LLVM `.ll` + W's `.mjs` behind
  one `CkRes` seam) — a docs edit only, no contract change.
- Roadmap + `parked.md` final annotations; plan markers `[done]`;
  WI-0010 → shipped.

Gate: docs merged; suite green; the llvm lane section runs on CI.

## Parking rules

- `llvm.coro.*` native splitting — trigger: measured poll-dispatch
  overhead on a real workload that mem2reg/regalloc can't recover,
  or an async-ABI consumer arrives. `items/suspension.md` keeps the
  fork analysis.
- wasm32/wasi triple — trigger: a wasm product target + an rt port
  design (rt.c's pthread/POSIX surface has no wasi spelling; the
  honest port is W-style re-expression or wasi-sdk threads, neither
  is a flag flip).
- DWARF/`DIBuilder` debug info — trigger: native-debugger workflows
  on lane-compiled binaries (gdb/lldb stepping oxl code). The
  `It.file` + span data the emitter already holds is the input;
  the work is the metadata emission contract.
- Opt-metadata pass (`noalias`/`nonnull` on `own`, TBAA for
  ObjHdr, `inbounds` on slice GEPs) — trigger: measured win; every
  attribute must be audited against observable borrow-check
  semantics first (an over-strong `noalias` is a miscompile, not a
  speedup).
- `--emit-bc`/LTO/lld plumbing — trigger: a size/link-time consumer;
  `clang`'s default pipeline already inlines `rt.c` at `-O2`.
- Rust-seed LLVM emitter — same stance as W: the lane is
  product-driver-only; the seed's role is bootstrap.
