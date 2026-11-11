# Runtime type descriptors — Stage Plan

Spec: `shape.md`. Design contract: `items/descriptor-model.md`.
Working artifacts: WI-0006 under `.ox-agent/work/`. Every stage is a
PR through the review loop; every stage lands with the suite green.
Automatic reviews are disabled repo-wide — request a pass manually
with `@coderabbitai review` on each stage PR after pushing the head
you want verdicted, and again after the last fix commit.

- [done] **R0 — spec** — *(this PR)* — this directory, WI-0006
      artifacts, ADR-0011 for the spec-level forks.
- [ ] **R1 — descriptor emission, both drivers.** `TypeDesc` records
      for every type reachable through a `tdesc` reference
      (demand-driven — no `tdesc`, no table), deduplicated, emitted
      into the binary's static data by `codegen.rs` AND
      `codegen.oxl`; `tdesc(T)` intrinsic folded at instantiation
      (yields the descriptor index); `value_of` intrinsic +
      scope-bound-`Value` escape rules in both checkers; the
      `type_of` builtin special form (type operand, `mkslice`
      precedent — NOT a callable generic, params bind only from
      args); `rt_desc_*` descriptor accessors (the lazy read lane
      `Type`/`Field` methods wrap), `rt_field_*` extern read AND
      `rt_field_set_*` write helpers (kind-checked byte access at
      `addr+off` — the write half is specced up front because
      R4–R6 decode through it); parity test
      `tests/desc_parity.oxl` asserting
      name/kind/size/fields/offsets/variants for fixture struct and
      enum types under both drivers, wired into `tests/run.sh`.
      Exit: table emits on tdesc-reach, intrinsics resolve, offsets
      match C layout on both drivers.
- [ ] **R2 — `std/reflect` lite + `fmt %v` (closes #28).**
      `std/reflect` (`Type`/`Field`/`Value`, `type_of`, `value_of`,
      kind-checked reads); `std/fmt`: `sprintv`/`printv`/`vfmt`
      verbs `%v` `%+v` `%T` `%#v` — `%v` prints Go's default forms
      (`{v1 v2}` for structs, `&{…}` for ptrs, scalar forms per
      kind, variant name for enums), `%+v` adds field names
      (`{f1:v1 f2:v2}`), `%T` the type name, `%#v` the
      source-literal form for the repr kinds that have one.
      `tests/fmt_v.oxl` + `tests/reflect.oxl` gate every kind,
      wired into `tests/run.sh`.
- [ ] **R3 — typed error payloads (completes #27).** `std/errors`:
      `box[T any](v: T)` minting int64 codes backed by the rt err
      registry (binds T from `v` — that is what `tdesc(T)` needs)
      (`{tdesc, payload}` stored out-of-band — a box IS an `err`),
      `as[T](e, out: mut T)`, interop with `wrap`/`unwrap`/`is`;
      `docs/semantics/errors.md` records the box lane.
      `tests/errors_as.oxl`: box → as round-trip incl. no-match
      and wrapped-chain cases, wired into `tests/run.sh`.
- [ ] **R4 — `encoding/gob`.** Descriptor-driven struct → bytes →
      struct round-trip (the canonical hard consumer — if the walk
      is wrong here, nothing downstream is trusted): wire format
      per Go's gob shape (type preamble + field-number deltas),
      `[]byte`/`str`/scalars/nested structs/slices.
      `tests/enc_gob.oxl`: round-trips incl. skip-zero, nested,
      and decode-under-missing-field tolerance; wired into
      `tests/run.sh`.
- [ ] **R5 — `encoding/xml` + `text/template`.** `xml` marshal/
      unmarshal with `xml:"name"` field tags read from descriptor
      field metadata — the `tag` slot is emitted in R1 per the
      contract (with parser/checker/emitter threading if tag syntax
      doesn't exist yet); `template`
      `{{.Field}}`/`{{range}}`/`{{if}}` against descriptor names.
      `tests/enc_xml.oxl`, `tests/text_template.oxl`; wired into
      `tests/run.sh`.
- [ ] **R6 — `database/sql` lite + closeout.** `scan[T any](rows,
      out: mut []T)` column-order-onto-fields + `std/reflect`
      surface documented in `docs/`; parked-stdlib.md re-measured
      (remaining descriptor-gated items: `runtime/pprof`, plugin
      loading — recorded with their own triggers);
      `docs/reflection.md` user doc. Milestone archived.

## Sequencing

R1 is the compiler-risk stage (both drivers must emit identical
layouts). R2 retires the headline feature early. R4 deliberately
precedes R5/R6 — gob's arbitrary-shape round-trip is the strongest
correctness signal the walk machinery can get before it is spent on
easier consumers. R3 is independent of R4–R6 and may land any time
after R2.
