# ADR-0013: LLVM backend — sibling .ll emitter, shared poll machines, rt.c under clang, --target llvm lane

Status: accepted (WI-0010) — 2026-11-11

## Decision

Milestone L adds an LLVM emit lane: a sibling `.oxl` emitter
(`bootstrap/codegen/llvm.oxl`) over the same `check.CkRes`
producing textual LLVM IR, the same `runtime/rt.c` compiled by
clang beside it, a `oxl --target llvm` driver lane with
`--triple`/`--emit-llvm` flags, a clang-gated test section, and a
byte-identical IR fixpoint modeled on ADR-0006's C-text chain.
Spec: `docs/specs/2026-11-11-llvm-backend/`.

Forks resolved:

1. **Textual `.ll`, never libLLVM** — the emit seam is `CkRes ->
   str` + an external tool invocation (`cc` today, `clang` next).
   LLVM-C bindings would make libLLVM a link-time dependency of
   the toolchain binary — the exact external gate C emit was
   chosen to avoid (`interfaces.md`). Text IR keeps `oxl`
   standalone-language, keeps emitted output inspectable, and
   keeps the G1 reachability scan working verbatim (its token
   walk finds `o_*` defs/uses under `@`/`%` sigils unchanged).
2. **Suspension shares the frame+poll lowering** — susp fns emit
   `%o_frm_*` types + `o_poll_*` drivers implementing the
   `RtPoll` ABI (`RT_READY`/`RT_PENDING`/`RT_CANCEL`), driven by
   rt.c's executor unchanged. `llvm.coro.*` is rejected for v1:
   the poll protocol is the semantic contract with the scope/
   executor/trap machinery, and a coro lane needs a second
   executor protocol inside rt.c plus a doubled concurrency
   conformance surface — for headroom the non-susp surface (the
   bulk of emitted code) already captures. Parked on a
   measured-overhead trigger (`items/suspension.md`).
3. **`rt.c` stays the runtime, compiled by clang** — emitted IR
   declares and calls the same `rt_*` ABI; `clang out.ll rt.c`
   compiles both in one invocation (and cross-compiles both
   under `--triple`). The arena/ObjHdr/borrow-ledger/scope/
   executor/chan semantics inherit wholesale — no GC strategy
   exists to port (there is no tracing GC; ownership is scopes +
   compile-time moves + dynamic borrow checks, all rt.c).
   `rt_scope_sizeof()` is the only additive rt entry.
4. **Boundary types match `rt.h` field-for-field; lane-owned
   types are self-consistent** — `OxlStr`/`RtSlice`/`RtFnv`/
   `RtIface`/`RtFrame`-header at explicit widths so clang's
   datalayout derives identical layouts on both inputs;
   `%o_s_*`/`%o_en_*`/`%o_ret_*`/frame tails take the simplest
   self-consistent form (enums: `{i32 tag, [4 x i8] pad,
   largest-variant payload}`). `RtScope` storage is never
   statically sized — dynamic `alloca` for non-frame scope
   blocks, `rt_task_new` byte-tail for frame scope slots
   (pthread/Win32 sync sizes differ per platform).
5. **The C-text fixpoint is a hard constraint** — `llvm.oxl`
   shares `package codegen` but `codegen.oxl`'s emitted text
   must stay byte-identical (`drv0/1/2.c` diff unchanged). The
   lane's own fixpoint lives one level over: `drv1.ll` (C-built
   driver emit) vs `drv2.ll` (llvm-built driver emit),
   byte-identical — the ADR-0006 chain replicated on IR text.
6. **Driver surface** — `build|run|test --target llvm`;
   `run`/`test` exec the native binary (no launcher); `--triple`
   passthrough to `clang -target`; `--emit-llvm` keeps `out.ll`;
   `LANG_CLANG` overrides; LLVM 15 floor (opaque pointers).
   Product-driver only — no Rust-seed lane (the W8 precedent).
7. **wasm32 named and parked** — `--triple` makes wasm
   syntactically reachable but rt.c's pthread/POSIX veneer has
   no wasi spelling; a real wasm port needs a W-style runtime
   re-expression and is its own spec on a product trigger.

## Consequences

- A third consumer proves the `interfaces.md` seam permanently;
  any future lane is boilerplate-shaped (emit fn + emit_and_* +
  flag value).
- `clang` becomes an optional build-time tool on the machine
  doing `--target llvm` builds — never required to build `oxl`.
- CI carries a new gated section (`command -v clang`); the
  windows leg may skip with a stated reason.
- The native lane's compile-time tax (cc parsing the largest
  emitted-C unit in the build, `cmd/oxl`) gets a relief path —
  whether it *is* faster is an L4 observation, not a claim.
