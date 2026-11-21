# LLVM target — `--target llvm`

`oxl` compiles to textual LLVM IR (`.ll`) and drives the installed
`clang` to compile it — the emitted module and the same
`runtime/rt.c` the C lane links, in one invocation. The product is a
native binary whose observable behavior is identical to the C lane's;
there is no launcher step (unlike the js lane's `node` dependency)
and no new runtime.

## Flags

```
oxl build <pkg|file.oxl> --target llvm [-o out] [--triple t] [--emit-llvm]
oxl run   <pkg|file.oxl> --target llvm        # execs the produced binary directly
oxl test  <pkg|file.oxl> --target llvm        # test_* fns, same `… ok` lines
```

- `--target llvm` selects the LLVM emitter
  (`bootstrap/codegen/llvm.oxl`). The accepted `--target` set is
  `native`/`c` (the C lane — default), `js`, `llvm`; anything else
  dies on `unknown --target … (want native, js, or llvm)`.
- `-o` names the binary — default `a.out` in the working directory
  (`.exe` appended on Windows).
- `--triple <t>` / `--triple=<t>` — cross-compile: passes through to
  `clang -target <t>` covering the emitted `.ll` *and* `rt.c` in one
  shot. Rejected off-lane: ``--triple needs `--target llvm` ``.
- `--emit-llvm` — `build`-only. On a successful build it keeps the
  emitted IR as `<out>.ll` beside the `-o` binary (the
  inspectability story replacing emitted-C readability — scratch
  intermediates are otherwise always removed on success; the name
  derives from the binary so it can't collide with `-o dir/out.ll`
  or across same-dir builds). Rejected under `run`/`test` — the
  kept file would land in scratch the driver removes, a silent
  no-op: ``--emit-llvm only applies to `build` ``. Rejected
  off-lane: ``--emit-llvm needs `--target llvm` ``.
- The raw emitter is also reachable without the driver:
  `oxl run bootstrap/cmd/codegen -- [--test] --emit llvm <file.oxl>`
  prints the `.ll` module to stdout (the suite's ABI probe and the
  IR fixpoint consume this path).

## Toolchain

The lane's external dependency is `clang` on the machine doing the
build — the same posture as the C lane's `cc`. Building `oxl` itself
needs no LLVM anything: no libLLVM/LLVM-C linkage, the toolchain
binary stays standalone, and `clang` is the only LLVM tool invoked
(no `opt`/`llc`/`llvm-as` — clang's driver runs the whole pipeline
on `out.ll rt.c` in one shot).

- **Floor: clang >= 15.** Emitted IR uses opaque `ptr` throughout —
  the only pointer form spanning the floor (typed pointers were
  removed in LLVM 17). `pick_clang` probes `LANG_CLANG` first, then
  `clang` on `PATH`, validating `clang --version` major >= 15 at pick
  time — a stale clang fails fast with
  `llvm toolchain floor: --target llvm needs clang >= 15 (… reports …)`
  rather than an IR parse error at `.ll` line N.
- The GNU-driver interface is the supported spelling everywhere —
  the args `emit_and_llvm` spells (`-O2`, `-target`, `-Wl,…`) are
  GNU-style. `clang-cl`-only installs are out of scope (its `/`-args
  surface is a second invocation contract, not a flag swap).

## Env surface

| env | behavior |
|---|---|
| `LANG_CLANG` | toolchain override — the `LANG_CC` convention; probed before `clang` on `PATH` and still held to the >=15 floor |
| `LANG_SQLITE_SRC` | sqlite amalgamation source — compiled in place of `-lsqlite3` when the program spells `rt_sqlite_*` (shared with the C lane) |
| `LANG_LDFLAGS` | extra link inputs appended verbatim — FFI shim objects, `pkg-config` output (shared with the C lane) |
| `OXL_LLVM_ABI` | emit-time ABI override — `sysv`/`aapcs64`/`win64`; the emitter reads it only when no explicit ABI pick arrived. The driver path always sends one — `--triple`-derived or host autodetect — so the hook is reachable solely on the raw `bootstrap/cmd/codegen --emit llvm` path |

## `--triple` and the ABI boundary

Two different things travel under one flag:

- **The `.ll` is triple-neutral.** No `target triple`/`target
  datalayout` lines — clang supplies both from `-target` (or the
  host) for the module and for `rt.c` alike, so boundary-type
  layouts re-derive under the real datalayout on both sides.
  (`emit_and_llvm` passes `-Wno-override-module`: clang warns that
  `-target` overrides a triple-less module, and the override is the
  design.)
- **Aggregate C-boundary spellings are ABI-shaped.** `OxlStr`,
  `RtSlice`, `RtFnv`, `RtIface` cross `rt_*`/extern boundaries as IR
  aggregates, and how an aggregate passes differs by ABI — SysV's
  stack-copy convention vs AAPCS64/win64's pointer-to-caller-copy in
  an arg register, plus `sret` for indirect returns. The emitter
  therefore spells call sites for one ABI: host autodetect by
  default; `--triple` overrides it (matched OS-tail first —
  `windows`/`win64`/`mingw` → `win64` when the arch is also 64-bit
  (`aarch64`/`arm64`/`x86_64`/`amd64`) and `sysv` for a 32-bit
  arch; otherwise `aarch64`/`arm64` → `aapcs64`; everything else →
  `sysv`). The pick must match the clang target — clang compiles
  both inputs under it.

Cross reach is the local clang's configured reach: headers, libs,
and the sysroot for the target are the installed toolchain's
problem — still strictly wider than `cc`'s, since clang ships as a
native cross-compiler. `wasm32*` is *reachable syntactically and not
supported*: `rt.c`'s pthread/POSIX veneer has no wasi spelling, so a
`--triple wasm32*` build fails in `rt.c`'s `#include <pthread.h>`
long before codegen. A real wasm port is parked (below).

## What the lane shares with the C lane

- The same checked-program input — `check.CkRes` is target-agnostic
  (no target input to `check`); `compile_res` picks
  `codegen.emit_llvm` beside `emit`/`emit_js`.
- The same runtime — `runtime/rt.c` + `rt.h` compiled by clang
  beside `out.ll`: scope arenas, ObjHdr/borrow checks, the executor
  pools, chans/select, traps, the extern shim table are unchanged.
  Suspension lowers to the same frame+poll protocol (`o_frm_*`
  frames, `o_poll_*` drivers implementing `RtPoll`) the executor
  already drives — rt.c cannot tell which emitter produced it.
- The same `o_*` symbol scheme and G1 reachability machinery —
  `o_f_`/`o_s_`/`o_en_`/`o_ret_`/`o_vt_`/`oxl_main` spell identically
  under `@`/`%` sigils, and dead decls prune identically.
- The same compile/link contract — `-O2`, `-ffunction-sections`/
  `-fdata-sections` + `-Wl,--gc-sections` (`-dead_strip` on macOS),
  `-pthread` off Windows, and the same emitted-text feature scans:
  `rt_sqlite_` → `-DOXL_SQLITE` + `-lsqlite3`/`LANG_SQLITE_SRC`,
  `rt_sock_*`/friends → `-DOXL_NET` (+`-lws2_32` on Windows),
  `rt_m_` → `-DOXL_MATH` + `-lm`, `rt_csrand(` → `-DOXL_CRYPTO`
  (+`-lbcrypt` on Windows). Windows additionally links
  `-ladvapi32`/`-lshell32` — clang doesn't fold in the Win32 libs
  MinGW gcc does.

## Parked

Reopen only on trigger; the full text lives in the spec
(`docs/specs/2026-11-11-llvm-backend/plan.md` §Parking rules).

- `llvm.coro.*` native splitting — trigger: measured poll-dispatch
  overhead on a real workload that mem2reg/regalloc can't recover,
  or an async-ABI consumer.
- wasm32/wasi rt port — trigger: a wasm product target + an rt port
  design (W-style re-expression or wasi-sdk threads — not a flag
  flip).
- DWARF/`DIBuilder` debug info — trigger: native-debugger workflows
  (gdb/lldb stepping oxl code) on lane-compiled binaries. The
  emitter already holds `It.file` + span data; the work is the
  metadata contract.
- Opt-metadata pass (`noalias`/`nonnull` on `own`, TBAA for ObjHdr,
  `inbounds` on slice GEPs) — trigger: a measured win, with every
  attribute audited against borrow-check semantics first (an
  over-strong `noalias` is a miscompile, not a speedup).
- `--emit-bc`/LTO/lld plumbing — trigger: a size/link-time consumer;
  clang's default pipeline already inlines `rt.c` at `-O2`.
- Rust-seed LLVM emitter — decided against, same stance as W: the
  lane is product-driver-only; the seed's role is bootstrap.

## Troubleshooting

- **clang diagnostics reference `.ll` text, not `.oxl` source** — a
  codegen bug reports at generated line numbers. There is no
  source-level debug info (parked above); the kept IR is the
  debugging story:
  - `--emit-llvm` keeps `<out>.ll` beside the binary on a clean
    build — inspect it, replay it through `clang` by hand.
  - On a clang failure the driver keeps the intermediates anyway:
    `clang failed (emitted LLVM IR kept at <scratch>/out.ll)` —
    `rt.h`/`rt.c` copies sit beside it, so the failing invocation
    reproduces standalone.
- **`llvm toolchain floor` error** — the picked clang reports <15;
  point `LANG_CLANG` at a newer install.
- **No clang at all** — the spawn error names the missing binary;
  the lane has no cc fallback (emitted IR is not C).
- **`-Woverride-module` noise** — already silenced
  (`-Wno-override-module`); the triple-less module is deliberate,
  not a warning worth heeding.
- **`--triple wasm32*` fails in `rt.c`'s POSIX includes** — expected;
  the wasm port is the parked item, not a bug.
- **No `-O` knob** — `-O2` is fixed, mirroring `emit_and_cc`; the
  spec leaves an `--llvm-opt` convenience knob unbuilt.
