# WI-0022 brainstorm — milestone L impl

Resolved upstream: WI-0010 produced the milestone spec docset
(`docs/specs/2026-11-11-llvm-backend/`) with all forks locked —
textual .ll (no libLLVM), shared frame+poll suspension lowering
(coro parked), rt.c under clang (no new runtime), C-text fixpoint
untouched with the lane fixpoint at drv1.ll/drv2.ll. ADR-0013
records the spec-level forks. No open design forks remain.
