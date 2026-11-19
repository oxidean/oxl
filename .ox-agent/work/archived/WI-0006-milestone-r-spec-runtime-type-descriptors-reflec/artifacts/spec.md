# WI-0006 spec — milestone R: runtime type descriptors + reflection

Deliverable: `docs/specs/2026-11-11-type-descriptors/` (shape.md,
plan.md, items/descriptor-model.md) + ADR-0011 + roadmap entry.

Intent: un-park the descriptor-gated stdlib surface — `fmt %v` (#28),
`errors.As` (#27), then gob/xml/template/sql — via compiler-emitted
type descriptors resolved at monomorph time (no `any`, no runtime
tags). Stage map R0–R6 in plan.md; R1 is the both-drivers compiler
risk stage, R4 (gob) the correctness gate.
