# items/toolchain.md — LLVM toolchain surface, driver lane, CI

The lane's external dependency is a *clang* on the machine doing
`--target llvm` builds — mirroring the C lane's `cc`, never a
build-time dependency of `oxl` itself. This item pins the version
floor, the flag surface, the triple story, the opt/debug stance,
and CI coverage.

## Toolchain

- **Floor: LLVM/clang 15.** Emitted IR uses opaque `ptr` (default
  since 15; typed pointers were removed in 17 — opaque IR is the
  only form that spans the floor). `pick_clang()` probes
  `LANG_CLANG` first, then `clang`, validating
  `clang --version` major ≥15 at pick time — a stale clang fails
  fast with a named floor error rather than an IR parse error at
  `.ll` line N.
- **The toolchain binary stays standalone.** `emit_llvm` produces
  text; clang is invoked as a child process exactly like `cc`
  today. No libLLVM/LLVM-C linkage, no FFI into the driver —
  building `oxl` requires `cc` and nothing else.
- `clang` consumes `out.ll` and `rt.c` in one invocation — it is
  the only LLVM tool invoked (no `opt`/`llc`/`llvm-as`; clang's
  driver runs the same passes). `rt.c` compiles under the host
  triple by default or `--target`'s triple when given — same
  sources, same `-D` feature gates the C lane applies
  (`OXL_NET`/`OXL_MATH`/`OXL_SQLITE` + link libs, driven by the
  same emitted-text scans; `LANG_SQLITE_SRC`/`LANG_LDFLAGS`
  ride along identically).

## Flag surface

| flag | behavior |
|---|---|
| `--target llvm` | selects the lane on `build`/`run`/`test`; `run`/`test` exec the produced native binary directly (no launcher — unlike the js lane's `node` dependency) |
| `--target=<v>` | same value set + validation message naming `native`, `js`, `llvm` |
| `--triple <t>` / `--triple=<t>` | llvm lane only: passthrough to `clang -target <t>`; absent = host. Rejected on other lanes (a flag the native lane can't honor silently is a bug, not a warning) |
| `--emit-llvm` | keeps `out.ll` beside `-o` output (scratch intermediates are always removed on success otherwise — the inspectability story replacing emitted-C readability) |
| `LANG_CLANG` | toolchain override — the `LANG_CC` convention |

`--html` stays js-only; `--target js --triple` is an error.

## Triples + platform reach

`--triple` exists because cross-compilation is the platform-reach
argument the lane was un-parked on. The contract:

- The emitted `.ll` is triple-neutral (no `target triple`/
  `datalayout` lines — clang supplies both from `-target`).
- `clang --target=<t> out.ll rt.c` compiles *both* inputs to `t`;
  headers/libs/sysroot are the installed toolchain's problem —
  the lane's reach is exactly the local clang's configured reach,
  which is still strictly wider than `cc`'s (clang ships as a
  native cross-compiler; gcc does not).
- Lane-owned layouts stay correct on any triple by the
  `llvm-semantics.md` §6 rule (over-reservation is safe; boundary
  types re-derive under the real datalayout because both inputs
  compile under it).
- wasm32 is *reachable syntactically* and *not supported*: rt.c's
  pthread/POSIX veneer has no wasi spelling — a `--triple wasm32*`
  build fails in `rt.c`'s `#include <pthread.h>` long before
  codegen. The lane documents this as the known non-goal (wasm is
  the parked rt-port item, not a flag).
- Tier-1 triples for CI smoke: the three host triples
  (`x86_64-pc-linux-gnu`, `aarch64-apple-darwin`, `x86_64-pc-windows-
  msvc`/`x86_64-w64-mingw32` per the runner's clang config) — the
  lane gates on "the runner's clang compiles host", not on
  cross-compiling in CI.

## Opt pipeline + debug info

- `-O2` is the shipped default — same as `emit_and_cc`. The lane
  emits unoptimized but verifier-clean IR (entry-block allocas,
  mechanical load/store); `mem2reg`→SSA recovery is clang's job.
  An `-O`/`--llvm-opt` knob is an L5 convenience item, not a
  design surface — `emit_and_cc` hardcodes `-O2` today and the
  lane mirrors it.
- Section GC flags ride along (`-ffunction-sections`,
  `-fdata-sections`, `-Wl,--gc-sections`/`-dead_strip`) — the G2
  size discipline the C lane applies.
- **No debug info in v1.** The emitter holds the inputs (`It.file`,
  AST spans) but the DI metadata contract is its own design
  surface; parked with the native-debugger trigger (plan.md).
  `.ll` inspectability via `--emit-llvm` is the interim answer.

## CI coverage

`tests/run.sh` grows an `== llvm lane ==` section, `command -v
clang`-gated like the js lane's `command -v node` gate — the
section runs the conformance whitelist through `run/test/build
--target llvm` (plan.md L3 gate) plus the L4 fixpoint diffs, and
skips cleanly where clang is absent.

- ubuntu-latest + macos-latest legs: clang preinstalled — the lane
  runs unconditionally.
- windows-latest: LLVM is *not* preinstalled; the leg installs it
  (`choco install llvm`/`winget` — ~1min on the runner) OR the
  section skips on the same gate. Decision deferred to L3
  implementation: install if the time cost holds the windows leg
  near its current runtime, else skip — but the skip text must
  say *why* (a windows-clang gap is a coverage hole, not a
  shrug).
- Driver spelling: v1 supports the `clang` GNU-driver interface
  everywhere (the spelling `pick_cc` already accepts today) —
  `emit_and_llvm`'s `-O2`/`-target`/`-Wl,` args are GNU-style.
  `clang-cl`-only installs are out of scope for v1 (its `/`-args
  surface is a second invocation contract, not a flag swap).
- The native C lane's fixpoint (`drv0/1/2.c`) runs unmodified on
  every leg — the shared-package regression guard.

## Divergence surface (what the lane honestly can't do)

- `clang` diagnostics reference `.ll` text — a codegen bug reports
  at generated line numbers, not `.oxl` source (`--emit-llvm` +
  the `; source:` banner are the debugging story).
- `rt.c` remains a C compile inside the lane — a platform with an
  LLVM backend but no working C frontend for `rt.c`'s POSIX
  surface isn't covered (that platform needs the wasm-style rt
  port, parked).
- The js lane's trap21 blocking surface doesn't exist here —
  `spawnBlocking`/blocking recv/`usleep` all work (rt.c's pools
  are real threads). No parity gap to document; the divergence
  list is empty by design — the lane's contract is *same
  observable behavior as native*.
