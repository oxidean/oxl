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
      for every instantiated type, deduplicated, emitted into the
      binary's static data by `codegen.rs` AND `codegen.oxl`;
      `tdesc(T)` intrinsic resolvable inside a monomorphized body
      (yields the descriptor index); `rt_field_*` extern read helpers
      (kind-checked byte-load from `addr+off`); parity test
      `tests/desc_parity.oxl` asserting name/kind/size/fields/offsets
      for a fixture struct under both drivers. Exit: table emits,
      intrinsic resolves, offsets match C layout on both drivers.
- [ ] **R2 — `std/reflect` lite + `fmt %v` (closes #28).**
      `std/reflect` (`Type`/`Field`/`Value`, `type_of`, `value_of`,
      kind-checked reads); `std/fmt`: `sprintv`/`printv`/`vfmt`
      verbs `%v` `%+v` `%T` `%#v` — default format = Go's
      `{field:val}`/`&{}`/scalar forms per kind, `%+v` adds field
      names where the default omits, `%T` the type name, `%#v` the
      source-literal form for the repr kinds that have one.
      `tests/fmt_v.oxl` + `tests/reflect.oxl` gate every kind.
- [ ] **R3 — typed error payloads (completes #27).** `std/errors`:
      `ErrBox{code, td, payload}`, `box`, `as[T](e, out: ref T)`,
      `ErrBox` interop with `wrap`/`unwrap`/`is` (a box IS an err
      with a tag); semantics doc updated. `tests/errors_as.oxl`:
      box → as round-trip incl. no-match and wrapped-chain cases.
- [ ] **R4 — `encoding/gob`.** Descriptor-driven struct → bytes →
      struct round-trip (the canonical hard consumer — if the walk
      is wrong here, nothing downstream is trusted): wire format
      per Go's gob shape (type preamble + field-number deltas),
      `[]byte`/`str`/scalars/nested structs/slices.
      `tests/enc_gob.oxl`: round-trips incl. skip-zero, nested,
      and decode-under-missing-field tolerance.
- [ ] **R5 — `encoding/xml` + `text/template`.** `xml` marshal/
      unmarshal with `xml:"name"` field tags read from descriptor
      field metadata (tags need a descriptor extension — string
      table slot per field, spec'd in the contract); `template`
      `{{.Field}}`/`{{range}}`/`{{if}}` against descriptor names.
      `tests/enc_xml.oxl`, `tests/text_template.oxl`.
- [ ] **R6 — `database/sql` lite + closeout.** `scan[T any](rows,
      out: ref []T)` column-order-onto-fields + `std/reflect`
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
