# WI-0008 plan — milestone R impl

Contract: `docs/specs/2026-11-11-type-descriptors/` (shape.md,
plan.md, items/descriptor-model.md) + ADR-0011. The spec's stage
map R0–R6 is the sequence; each stage is its own PR, stacked where
the spec's dependency order allows.

## Post-milestone-U mapping (spec text vs. current tree)

The spec was written while the Rust seed crate still lived. Its
"both drivers / both checkers" language maps today:

- `codegen.rs` → gone. The C emitter is `bootstrap/codegen/codegen.oxl`;
  the JS lane is `bootstrap/codegen/js.oxl`.
- `check.rs` → gone. The single checker is `bootstrap/check/check.oxl`.
  The spec's "rs-vs-oxl parity gap" notes (Ret::Pair ref/mut bans)
  collapse to the check.oxl side only — pick the documented shape.
- "Both drivers" parity → the stage0 snapshot binary
  (`scripts/stage0.sh` → `target/oxl-self`) vs the self-compiled
  binary — the suite's existing seed-vs-self compare pattern.
  `tests/desc_parity.oxl` asserts identical descriptor contents
  (name/kind/size/fields/offsets/variants) under both.
- Table emission happens in `bootstrap/codegen/codegen.oxl`;
  stage0 regeneration (`scripts/stage0.sh`) ships in the same PR
  whenever compiler sources change.

## Stage → PR map

- R1 (compiler risk): descriptor table emission in codegen.oxl
  (demand-driven on `tdesc` reach, first-mention order, dedup,
  sizeof/offsetof initializers so dead-decl reachability stays
  textual), intrinsics `tdesc`/`tqual`/`type_of`/`value_of`/
  `value_of_mut` folded at mono time, `tag "..."` field syntax
  threaded parser→checker→emitter, scope-bound `Value` provenance
  pass + field-opacity in check.oxl, `rt_desc_*`/`rt_field_*`
  extern helpers in runtime/rt.c (all width lanes, bounds-checked,
  weak-stub table when unpopulated), `--target js` diagnostic for
  all five intrinsics + the externs, `tests/desc_parity.oxl` + run.sh.
- R2: `std/reflect` lite + `fmt` sprintv/printv/vfmt (%v/%+v/%T/%#v).
  Depends on R1. `tests/reflect.oxl`, `tests/fmt_v.oxl`.
- R3: `std/errors` `box[T]`/`as[T]` typed payloads via the rt err
  registry (`RtErrEnt` gains {td, pdata}; pdata always a pointer).
  Depends on R1 only — may stack/parallel R2.
  `tests/errors_as.oxl` + `docs/semantics/errors.md`.
- R4: `encoding/gob` round-trip. Depends on R2's walk surface.
  `tests/enc_gob.oxl`.
- R5: `encoding/xml` + `text/template`. Depends on R1 tag slot
  + R2 walk. `tests/enc_xml.oxl`, `tests/text_template.oxl`.
- R6: `database/sql` lite `scan[T]` + `docs/reflection.md` +
  parked-stdlib re-measure + milestone archive. Depends on R2.

## Execution pattern

Same as milestone X: per-stage worktree on latest main, subagent
implements the stage with the spec files as contract, full
`tests/run.sh` green gate, PR → CodeRabbit (or self-review when
quota-skips) → squash-merge on green, next stage rebases/stacks.
