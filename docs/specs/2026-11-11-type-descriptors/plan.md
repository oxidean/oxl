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
      `codegen.oxl` (records per the contract incl. `elem_ptr` for
      `[]own T` element slots and named-variant payload names;
      indices in first-mention order through the existing
      decl/inst emission traversal — cross-driver parity asserted
      by `tests/desc_parity.oxl` (the C-text fixpoint only diffs
      the self emitter across generations) — and initializers
      spelled `sizeof(struct
      o_s_*)`/`offsetof(...)`, which keeps layout C-truth AND
      pulls desc-referenced decls live through the textual-edge
      reachability that prunes dead decls);
      `tdesc(T)` intrinsic folded at instantiation (yields the
      descriptor index) plus sibling `tqual(T)` (0/own/ref/mut —
      `%v`'s `&{…}` mechanism, frozen decision per the contract);
      `value_of`/`value_of_mut` intrinsics + the scope-bound-`Value`
      rules in both checkers — the *provenance* rule (a `Value`
      returns only when derived from a `ref`/`mut`/`Value` param;
      no `Value` of any provenance stores into a file-scope
      global, a heap shape, or `spawn`) plus the fabrication
      guard — no struct literals AND no field writes on a `Value`
      outside `std/reflect`, NOT a reuse of the
      signature-level `ref` bans — note the pre-existing diag-parity
      gap this sits on: check.rs bans `ref`/`mut` under `Ret::One`
      only while check.oxl also bans `Ret::Pair`; the `type_of`
      builtin special form (type operand, `mkslice`
      precedent — NOT a callable generic, params bind only from
      args); the `--target js` diagnostic for all five
      intrinsics + the rt externs (native-lane only, per the
      contract's target gating); `rt_desc_*` descriptor accessors
      (the lazy read lane
      `Type`/`Field` methods wrap, incl. `rt_desc_v_base` for the
      codegen-pinned union-blob offset — never a fixed +8,
      `rt_desc_v_f_name` for named payload slots, and
      `rt_desc_alloc`, the decode lane's zeroed-pointee mint), the
      `rt_field_*` extern read AND `rt_field_set_*` write helpers in
      ALL width lanes (i64/i32/u8/f64/str/cstr/ptr — `bool`
      fields and enum tags are C `int` 4B, `byte` 1B; an i64-only
      lane would misread every one); parity test
      `tests/desc_parity.oxl` asserting
      name/kind/size/fields/offsets/variants for fixture struct and
      enum types under both drivers, wired into `tests/run.sh`.
      Exit: table emits on tdesc-reach, intrinsics resolve, offsets
      match C layout on both drivers.
- [ ] **R2 — `std/reflect` lite + `fmt %v` (closes #28).**
      `std/reflect` (`Type`/`Field`/`Variant`/`Value`, `type_of`,
      `value_of`/`value_of_mut`, kind-checked reads/writes incl.
      the enum lanes `tag`/`set_tag`/`vfield`/`fname`, the decode
      mint `alloc_field`, and the cstr/PTR lane); `std/fmt`:
      `sprintv`/`printv`/`vfmt` verbs `%v` `%+v` `%T` `%#v` — `%v`
      prints Go's default forms (`{v1 v2}` for structs, `&{…}`
      for ptrs, scalar forms per kind, variant name for enums),
      `%+v` adds field names (`{f1:v1 f2:v2}`), `%T` the type
      name, `%#v` the source-literal form for the repr kinds that
      have one.
      `tests/fmt_v.oxl` + `tests/reflect.oxl` gate every kind,
      wired into `tests/run.sh`.
- [ ] **R3 — typed error payloads (completes #27).** `std/errors`:
      `box[T any](v: T)` minting int64 codes backed by the rt err
      registry — `box` is a global compiler-lowered builtin in
      the `value_of`/`mkslice` family (no extern signature can
      carry a generic `T`/`own` payload into an int slot; binds T
      from `v` — that is what `tdesc(T)` needs). `as` stays an
      ordinary generic fn — `value_of_mut(out)` already yields
      the writable `*out` address its rt extern consumes.
      Rt change, named here because today's `RtErrEnt`
      (`{next, mlen, cause, msg}`) has no payload slots: extend the
      entry with `{td, pdata}` — a box IS an `err` end to end and
      chains through `wrap`/`unwrap`/`is` untouched. `pdata` is
      ALWAYS a pointer: `box` accepts any `T` that has a descriptor
      and heap-copies the payload into an own-lane `sizeof(T)`
      block (`rt_alloc_own`) — multi-word types (`str`, `[]T`,
      iface, `fn`, enums) can't ride a single int64 slot; an
      `own T` arg instead moves its handle into `pdata` (no copy).
      The box entry's other fields stay sentinel-pinned: `msg`
      carries the boxed type's descriptor name (so `Error()` and
      the unwrap chain stay readable), `next`/`cause` NULL.
      Ownership pins:
      `box` CONSUMES its `v` (the registry adopts the payload —
      call sites pass `own` values, or by-value `T` which the box
      copies then drops with its scope); `as[T](e, out: mut T)`
      copies the payload back out of `pdata` into `out` (moving
      the handle for `own` payloads) and clears the slot, so a
      given box answers `as` exactly once — the only move-safe
      shape (a shallow copy would alias `own` handles, a borrow
      can't be expressed); when R3 lands, `box`/`as` fold sites
      and their externs join the `--target js` diagnostic list
      alongside the R1 surface; `as` walks the `unwrap` chain like Go's As —
      first descriptor match wins; matching is exact-descriptor —
      an iface-typed `out` matches only a box that stored that
      same iface descriptor (no implementability walk:
      descriptors carry no method sets, so `as` on an iface
      target is strictly weaker than Go's, by design);
      `docs/semantics/errors.md` is created with a section
      recording the box lane — incl. payload lifetime: boxed
      payloads live in the capped, never-freed `RtErrEnt`
      registry (`RT_ERR_MAX` 65536; the *box lane* never dedupes —
      `rt_err_new` itself dedupes message text — and `as` clears
      the slots it consumes but frees nothing), so `box` is for error
      paths, not hot loops.
      `tests/errors_as.oxl`: box → as round-trip incl. no-match
      and wrapped-chain cases, wired into `tests/run.sh`.
- [ ] **R4 — `encoding/gob`.** Descriptor-driven struct → bytes →
      struct round-trip (the canonical hard consumer — if the walk
      is wrong here, nothing downstream is trusted): wire format
      per Go's gob shape (type preamble + field-number deltas),
      `[]byte`/`str`/scalars/nested structs/slices, enums (tag +
      payload slots) and `own`-ptr fields — decode mints pointees
      via `alloc_field`. Consumes R2's `std/reflect` walk surface
      (`field`/`vfield`/`set_*`/`alloc_field`), so it lands after
      R2.
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
      surface documented in `docs/` — `tests/db_sql.oxl`, wired
      into `tests/run.sh`; parked-stdlib.md re-measured
      (remaining descriptor-gated items: `runtime/pprof`, plugin
      loading — recorded with their own triggers);
      `docs/reflection.md` user doc. Milestone archived.

## Sequencing

R1 is the compiler-risk stage (both drivers must emit identical
layouts). R2 retires the headline feature early and lays the
`std/reflect` surface R4/R5/R6 all consume — every later stage
orders after it. R4 deliberately precedes R5/R6 — gob's
arbitrary-shape round-trip is the strongest correctness signal
the walk machinery can get before it is spent on easier
consumers. R3 is independent of R4–R6 and needs only R1
(`tdesc` + the registry change) — it may land any time after R1,
in parallel with R2. R1's `--target js` rejection assumes the
W lane on main (`feat/milestone-w` owns `--target` parsing and
the emit dispatch); if R1 lands first the diagnostic still
belongs in both drivers' target dispatch and W's lane wires it
on arrival.
