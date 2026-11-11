# WI-0010 spec — LLVM backend emit lane

Deliverable: `docs/specs/2026-11-11-llvm-backend/` (shape.md,
llvm-semantics.md, plan.md, items/{emit-seam,suspension,toolchain}.md)
+ ADR-0013 + roadmap/parked annotations.

Intent: un-park the LLVM backend on the second-consumer trigger —
milestone W landed `--target js`, so the codegen seam
(`docs/semantics/interfaces.md`) is proven with two emitters and a
third is pattern work, not exploration. Stage map L0–L5 in plan.md;
L1/L2 are the emitter (skeleton then poll machines), L3 the driver
lane, L4 the IR fixpoint + parity gate.

Locked forks: textual .ll (no libLLVM), shared frame+poll lowering
(coro parked), rt.c under clang (no new runtime), C-text fixpoint
untouched with the lane fixpoint at drv1.ll/drv2.ll.
