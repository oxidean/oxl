# WI-0022 plan — milestone L impl (LLVM emit lane)

Contract: `docs/specs/2026-11-11-llvm-backend/` (shape.md,
llvm-semantics.md, plan.md, items/{emit-seam,suspension,toolchain}.md)
+ ADR-0013. Stage map L0–L5 in the spec's plan.md; L0 (spec)
shipped via PR #74. Each remaining stage is its own PR through the
review loop, sequential per the spec's ordering.

- L1: `bootstrap/codegen/llvm.oxl` skeleton + non-concurrency
  surface; `runtime/rt.h` additive `rt_scope_sizeof`; susp sites
  trap loud. `emit_llvm(r: own check.CkRes, testm: int) -> str`.
- L2: concurrency surface — frames + poll drivers + spawn/chans/
  select/scopes per items/suspension.md.
- L3: driver lane — `--target llvm`, `emit_and_llvm`, `--triple`,
  feature gates per items/toolchain.md.
- L4: IR fixpoint + cross-lane parity gate.
- L5: docs + flag polish.

Post-milestone-U note: the spec's references to a Rust seed crate
are stale — the tree has one checker (`bootstrap/check/check.oxl`),
the C emitter `bootstrap/codegen/codegen.oxl`, JS lane `js.oxl`.
llvm.oxl lands in `package codegen` reusing its G1 reachability
(gubegin/gudrain/gdef/gscan) + ginst_queue machinery verbatim.

Sequencing vs WI-0008 (milestone R): parallel worktrees — L1 is a
new file plus an additive rt.h entry; merge order settles rebase.
