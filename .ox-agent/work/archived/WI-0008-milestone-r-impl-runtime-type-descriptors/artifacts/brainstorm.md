# WI-0008 brainstorm — milestone R impl

Resolved upstream: WI-0006 produced the milestone spec docset
(`docs/specs/2026-11-11-type-descriptors/`) with all forks decided
— monomorph-resolved descriptors (no `any`, no runtime tags),
layout-only descriptor records, provenance-enforced scope-bound
`reflect.Value`, typed `box`/`as` err lane, gob as the first hard
consumer, sequential stage map R0–R6. ADR-0011 records the
spec-level forks. No open design forks remain for impl; see
plan.md for the post-milestone-U driver mapping (codegen.rs /
check.rs retired — one checker, one C emitter, one JS lane).
