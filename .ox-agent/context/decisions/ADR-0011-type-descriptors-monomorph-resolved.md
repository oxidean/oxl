# ADR-0011: runtime type descriptors — monomorph-resolved, layout-only

Status: accepted (WI-0006) — 2026-11-11

## Decision

Milestone R emits a `TypeDesc` table per program (name, kind, size,
align, fields `{name, off, td, tag, ptr}`, elem/key) and resolves
`tdesc(T)` at **monomorph time**: inside an instantiated generic
body the bound `T` is concrete, so the intrinsic folds to a static
descriptor index. `std/reflect` exposes `type_of`/`value_of`/
kind-checked field reads; `fmt` grows `%v`/`%+v`/`%T`/`%#v` over
single typed values; `std/errors` grows a typed `ErrBox` lane.
Spec: `docs/specs/2026-11-11-type-descriptors/`.

Spec-level forks resolved:

1. **Monomorph-resolved descriptors over runtime type-id tags** —
   every consumer is a generic fn (`sprintv[T]`, `gob.encode[T]`,
   `errors.as[T]`); monomorphization already specializes per `T`, so
   no `any` type, no value boxing, no per-allocation tag, and no
   change to *object* layout — rt.c still grows the `rt_desc_*`/
   `rt_field_*` helpers unconditionally and R3 extends `RtErrEnt`
   with `{td, pdata}` for the box lane, so "no rt.c change" is
   true of value representation only. The rejected alternative (tagging every
   value) buys dispatch-time reflection nothing in this scope pays
   for.
2. **Descriptors describe layout only** — no method tables (ifaces
   carry vtables), no value payloads (those live behind
   `reflect.Value{td, addr, w}` — field-opaque outside
   `std/reflect`, per the spec's fabrication rules).
3. **One `unsafe` seam, confined to `std/reflect`** — `Value` reads
   via `rt_field_*` externs; `value_of` is a compiler-lowered
   intrinsic and `Value` a scope-bound type under a *new*
   provenance pass (not the borrow rules — none exist to reuse):
   param-derived Values may be returned, local-`own`-derived ones
   may not, and no Value reaches a file-scope global, heap shape,
   escaping closure, or `spawn` — so a `Value` provably cannot
   outlive its source.
4. **`err` stays int64; typed errors are additive `ErrBox`** — the
   descriptor tag on the box gives `errors.as[T]` the identity match
   Go gets from a dynamic type, without re-shaping the `err` chain.
5. **Not D4** — D4 rejected type dictionaries for *code dedup*
   (measured zero shared shapes). Descriptors answer "what is T"
   inside an already-monomorphized body — a different device with a
   different cost model; the D4 verdict is unaffected and stays.
6. **Field tags ride the descriptor** — `tag "..."` on struct fields
   (added if absent) so `xml:`/`gob:` names arrive with the layout
   rather than a second metadata channel.

## Consequences

- `fmt`'s variadic multi-verb form (`sprintf("%v %v", a, b)`) stays
  impossible — no variadics; `vfmt` formats one value per call and
  the doc says so.
- Both drivers emit the table — `codegen.rs` and `codegen.oxl`
  parity is asserted per-fixture on layout contents, not just
  behavior (existing fixpoint covers the latter).
- Downstream consumers stack on R1's table: `encoding/gob` (R4),
  `encoding/xml` + `text/template` (R5), `database/sql` lite (R6).
- Parked list shrinks: `fmt %v` (#28), `errors.As` (#27) close;
  `runtime/pprof` and plugin loading remain parked on their own
  triggers (introspection ≠ descriptors — recorded in R6).
