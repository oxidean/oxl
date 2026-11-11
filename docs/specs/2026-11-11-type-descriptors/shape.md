# Runtime type descriptors + reflection surface — Shaping Notes

## Scope

Milestone R (letter reclaimed — the earlier "R — package
registry" row in `docs/specs/2026-11-07-phase-2-plan/plan.md` was
folded into milestone E and ships already; this spec is the only
live R) from the parked list
(`docs/specs/2026-11-06-0111-package-system/items/parked-stdlib.md`,
`docs/specs/2026-11-07-phase-2-plan/parked.md`): compiler-emitted
runtime type descriptors + the reflection-class stdlib they unlock —
`fmt` `%v`/`%+v`/`%T`/`%#v` (issue #28), `errors.As` typed binding (issue
#27 partial), then `encoding/gob`, `encoding/xml`, `text/template`,
`database/sql`, and a `std/reflect` lite as the public machinery.

Not this spec: an `any` type or boxed values, variadic call forms,
runtime type-id tags on every allocation, interface-dispatch
reflection (iface-typed `T` describes as IFACE and stops — no path
to the concrete payload), `unsafe` pointer arithmetic as a language
feature (`unsafe` is a scoping-block marker today — it silences
no checks; R adds no opt-out either), `runtime/pprof`-class introspection, and the `--target js`
emit lane (milestone W — landed ahead of this spec's
implementation): `addr:int` arithmetic and C `rt_field_*` loads
don't port to JS, so R is native-lane only — js-lane
descriptors/`%v` defer to their own trigger. R1 pins the guard,
not just the scope: `tdesc`/`tqual`/`type_of`/`value_of`/
`value_of_mut` and the `rt_desc_*`/`rt_field_*` externs are a
checker+emitter *target diagnostic* under `--target js` — rejected,
never silently emitted into a lane where they can't work.

## Evidence

- `std/fmt/fmt.oxl` header states the parked contract directly: "no
  variadics and no runtime `any`, so %v-style reflection stays
  parked". `sprintf` substitutes `%s` over `[]str` only — no typed
  value ever reaches a verb today.
- Generics monomorphize: `codegen.rs` emits one specialized copy per
  instantiation (`o_f_{mangled}`); `bind_generic` binds each `T` to a
  concrete `Ty`. Inside a monomorphized body the parameter type is
  *statically known* — this is the load-bearing fact for the design
  below.
- `err` is an int64 code: `errors.As` cannot match a typed target
  against it. A typed payload is additive machinery, not an `err`
  change.
- `D4 shape-based generics` is parked with a measured verdict: type-
  dictionary passing for *code dedup* pays nothing at this corpus
  size. Descriptors are a different device — they answer "what is T"
  inside an already-monomorphized body, not "share one body across
  T". The D4 verdict does not apply; this spec says why explicitly so
  the question stays answered.

## The forks, decided

1. **Monomorph-resolved descriptors, not runtime type tags.** Every
   reflection consumer in scope is a *generic fn*: `sprintv[T]`,
   `gob.encode[T]`, `errors.as[T]`. Each monomorphized copy already
   knows its `T` concretely — a `tdesc(T)` intrinsic resolves to a
   static descriptor index at instantiation time. Values stay
   untagged; there is no `any` to design, no per-allocation cost, no
   rt.c layout change. The cost is a descriptor table in the binary
   (bounded by instantiated types, dedup'd per type).
2. **Descriptors describe layout, not behavior.** A descriptor
   records: name, kind, size, field list `{name, offset,
   type-desc-idx}` for structs, element desc for slice/chan
   shapes, variant names for enums. No method tables — ifaces already carry vtables; the
   descriptor surface composes with them rather than duplicating.
3. **Reading field values crosses one unsafe seam — with enforced
   lifetime and origin.** `reflect.Value` is `{tdesc, addr, w}` —
   opaque field addressing plus a writability bit. `value_of` /
   `value_of_mut` are compiler-lowered intrinsics (no `addrof`
   builtin exists to abuse) and `Value` is declared a scope-bound
   type. The enforced rule is *provenance*, not the literal `ref`
   signature bans — those would reject this spec's own
   `-> [Value, err]` methods (the self-hosted checker bans `ref`/
   `mut` under `Ret::Pair` as well as `Ret::One`). Instead the
   checker gains a provenance pass for this — a new rule, not a
   reuse of a borrow-provenance pass that doesn't exist: a
   function may return a `Value` only when it derives from one of
   that function's `ref`/`mut`/`Value` parameters; a `Value`
   derived from a local `own` (the actually-dangerous case —
   `c := new(v); return value_of(c)` returns an address whose
   pointee dies at scope end) may not be returned. No `Value` of
   any provenance may be stored into a file-scope global, stored
   in heap shapes, captured into a closure or fn-value that
   outlives the source scope, or sent to `spawn` — param-derived
   Values dangle in those slots identically; return is the only
   escape the rule opens, and the checker's ordinary ref-capture
   argument does not apply to a Value's bare ints, so the capture
   ban is spelled out explicitly. (`value_of(p)` on a `ref` param IS
   safe to return — the pointee lives in the caller's frame, and
   the provenance rule says exactly that.) The flag also marks
   `Value` non-constructible by struct literal outside
   `std/reflect` and makes `Value` **field-opaque** outside
   `std/reflect` — `v.addr`/`v.w` are public ints, so
   `v.addr = evil` would otherwise forge address and writability
   by ordinary assignment; stores to AND reads of `Value`'s
   fields are rejected there (inside `std/reflect` they stay
   ordinary ints for the extern calls). `poke8`/`poke16`/
   `poke32` already write arbitrary memory by design, so the
   guard protects the `td`↔`addr` invariant the kind-checked
   lanes rely on, not the address space. The read path is
   extern helpers (`rt_field_*`, `rt_desc_*`) called inside
   `std/reflect`'s `unsafe` blocks; user code sees typed `Value`
   methods, never raw addresses. The externs are not private —
   any module may redeclare them — so confinement is social; the
   *enforced* guarantees are the provenance rule and the
   no-literal rule, which hold regardless of who calls the externs.
   Field stores close the gap literals don't: `v.addr = x` on a
   `Value` var would fabricate the same arbitrary access without
   ever spelling a literal — so the scope-bound flag makes `Value`
   **field-opaque** outside `std/reflect`: stores to AND reads of
   `Value`'s fields are rejected there. Inside `std/reflect` the
   fields stay ordinary ints the extern calls consume.
4. **`errors.As` gets a typed box, `err` stays int64.** Go's As
   matches a *dynamic* type; int64 codes have none. `box(v)` mints
   a fresh int64 code and stores `{tdesc(T), payload}` in the rt
   err registry — the same out-of-band side table wrapped-err
   payloads already use, so a box *is* an `err` end to end and
   chains through `wrap`/`unwrap`/`is` untouched. `errors.as[T](e,
   out)` reads the registry entry's tag and payload back. `ErrBox`
   is the typed lane; the code/payload split stays in rt, not an
   oxl struct (an oxl struct can't be an int64 `err`). `as[T]`
   walks the unwrap chain like Go's As; a box whose payload was
   already consumed contributes no match — the walk continues past
   it (the move-once rule lives in plan.md R3).
5. **gob is the first hard consumer, not %v.** %v proves the table
   emits; gob proves the walk machinery is complete enough to trust
   (arbitrary nested struct → bytes → equal struct). Stages ordered
   so each consumer retires a real risk before the next is spent.
6. **Two drivers, one contract.** Descriptor emission lands in
   `codegen.rs` AND `codegen.oxl`; parity is asserted by
   `tests/desc_parity.oxl` — it compiles a fixture under each driver
   and compares descriptor contents (name, fields, offsets). The
   C-text fixpoint only guards the self emitter across generations
   and cannot witness cross-driver table drift.

## The decision

**A compiler-emitted `TypeDesc` table + a `tdesc(T)` intrinsic,
resolved per monomorphized instantiation.**

```oxl
// std/reflect — public surface (v1)
// Type and Field are descriptor-table HANDLES, not materialized
// records — reads go through rt_desc_* externs lazily, so no slice
// or str backing has to be fabricated in-callee.
struct Type  { td: int }                       // descriptor idx
struct Field { td: int, i: int }               // descriptor + field idx
struct Variant { td: int, i: int }             // descriptor + variant idx
struct Value { td: int, addr: int, w: int }    // w: write bit — the name is
                                             //  `w`, not `mut` (a keyword);
                                             //  fields are OPAQUE outside
                                             //  std/reflect (see below)
fn type_of(t) -> Type                        // builtin special form —
                                             // takes a TYPE operand
                                             // (mkslice precedent):
                                             // type_of(Point), or
                                             // type_of(T) inside a
                                             // generic body; folds at
                                             // mono time, not a
                                             // callable fn
fn value_of[T any](v: ref T) -> Value        // intrinsic → {tdesc(base(T)),
                                             //  pointee addr — qualified T
                                             //  derefs the handle once}
fn value_of_mut[T any](v: mut T) -> Value    // same, sets v.w — the write
                                             //  lane's provenance (see below)
fn (v Value) field(i: int) -> [Value, err]   // STRUCT only; addr + f_off(i);
                                             //  td ← f_td(i); err_oob past
                                             //  nfields — always bind the
                                             //  pair ([f, e] = v.field(i))
fn (v Value) len() -> [int, err]             // SLICE only (RtSlice.len)
fn (v Value) index(i: int) -> [Value, err]   // SLICE only, scope-bound;
                                             //  err_oob before address math;
                                             //  elem_ptr slots deref once
fn (v Value) int() -> [int, err]             // kind-checked read (i64 lane —
                                             //  INT and ERR kinds; ERR yields
                                             //  the code)
fn (v Value) f64() -> [float, err]           // kind-checked read
fn (v Value) bool() -> [int, err]            // kind-checked read (i32 lane —
                                             //  C `int`, 4B — NOT an i64 load)
fn (v Value) byte() -> [int, err]            // kind-checked read (u8 lane)
fn (v Value) str() -> [str, err]             // kind-checked read (STR + PTR
                                             //  kinds — PTR is cstr, read via
                                             //  rt_field_cstr)
fn (v Value) set_int(x: int) -> err          // kind-checked write; err_kind
fn (v Value) set_bool(x: int) -> err         //  unless v.w (mut-derived)
fn (v Value) set_byte(x: int) -> err         //
fn (v Value) set_f64(x: float) -> err        //
fn (v Value) set_str(x: str) -> err          //
fn (v Value) alloc_field(i: int) -> [Value, err]
                                             // STRUCT only, FieldDesc.ptr
                                             //  fields — the decode lane's
                                             //  object mint: stores a fresh
                                             //  zeroed pointee
                                             //  (rt_desc_alloc +
                                             //  rt_field_set_ptr) and yields
                                             //  it mut-set; err_oob past
                                             //  nfields; err_kind unless
                                             //  ptr field + v.w
fn (t Type) name() -> str                    // rt_desc_name
fn (t Type) kind() -> int                    // rt_desc_kind
fn (t Type) size() -> int                    // rt_desc_size
fn (t Type) nfields() -> int                 // rt_desc_nfields
fn (t Type) field(i: int) -> [Field, err]    // {td, i}; err_oob — an OOB
                                             //  desc read is UB, so index
                                             //  accessors are pair-shaped
                                             //  like v.index
fn (t Type) elem() -> [Type, err]            // rt_desc_elem — PAIR-shaped:
                                             //  -1 (absent elem: scalars,
                                             //  structs) would fabricate
                                             //  Type{td:-1}; err_kind instead
fn (t Type) nvars() -> int                   // rt_desc_nvars
fn (t Type) varname(i: int) -> [str, err]    // rt_desc_var
fn (t Type) variant(i: int) -> [Variant, err]// {td, i}; err_oob
fn (x Variant) name() -> str                 // rt_desc_var
                                             //  (name asymmetry is
                                             //  deliberate: Variant.name /
                                             //  Field.name for decl names,
                                             //  Field.tag / Value.tag for
                                             //  metadata/discriminants —
                                             //  same word, different axis)
fn (x Variant) nfields() -> int              // rt_desc_v_nfields —
                                             //  positional payload slots
fn (x Variant) ftyp(i: int) -> [Type, err]   // {rt_desc_v_f_td}; err_oob
fn (x Variant) foff(i: int) -> [int, err]    // rt_desc_v_f_off — relative
                                             //  to the union blob base;
                                             //  err_oob
fn (x Variant) fname(i: int) -> [str, err]   // rt_desc_v_f_name — declared
                                             //  name for named payloads,
                                             //  synthesized `fN` for
                                             //  positional; err_oob
fn (v Value) tag() -> [int, err]             // ENUM only — reads the tag
                                             //  slot via the i32 lane (the
                                             //  tag is a C `int`, 4B in both
                                             //  drivers). The union blob
                                             //  base is rt_desc_v_base(td)
                                             //  — codegen-pinned offsetof,
                                             //  NOT a fixed constant: with
                                             //  `int` tags it is alignment-
                                             //  dependent (4 for unit-only
                                             //  or low-align payloads).
                                             //  The tag value IS the variant
                                             //  index: t.variant(v.tag())
                                             //  selects the live variant's
                                             //  metadata — the emitter emits
                                             //  variants in decl order and
                                             //  tags count the same order.
fn (v Value) set_tag(i: int) -> err          // ENUM only — writes the i32
                                             //  tag slot; err_kind unless
                                             //  v.w (decode lane)
fn (v Value) vfield(vi: int, fi: int) -> [Value, err]
                                             // ENUM payload access — the
                                             //  only way a payload SLOT
                                             //  becomes a Value. addr =
                                             //  v.addr + rt_desc_v_base(td)
                                             //  + rt_desc_v_f_off(td, vi, fi);
                                             //  td ← rt_desc_v_f_td. Callers
                                             //  MUST pass vi = v.tag() (any
                                             //  other variant's offsets
                                             //  describe the wrong shape) —
                                             //  the method still bounds-
                                             //  checks vi/fi with err_oob,
                                             //  and err_kind on non-ENUM.
                                             //  An `own`-typed payload slot
                                             //  holds a POINTER: when
                                             //  rt_desc_v_f_ptr reports the
                                             //  slot indirect, vfield derefs
                                             //  once (like FieldDesc.ptr on
                                             //  struct fields) and yields the
                                             //  pointee layout — never the
                                             //  handle slot itself.
fn (f Field) name() -> str                   // rt_desc_f_name
fn (f Field) off() -> int                    // rt_desc_f_off
fn (f Field) typ() -> Type                   // {rt_desc_f_td}
fn (f Field) tag() -> str                    // rt_desc_f_tag; "" absent
fn (v Value) typ() -> Type                   // {v.td}
```

`type_of` is NOT a generic fn — type parameters bind only from call
arguments (`check.rs`), so `type_of[T any]()` could never be
invoked; it takes a type operand as a builtin special form, the
same parsing precedent `mkslice(byte, n)` set — the operand
grammar is mkslice's exactly: an Ident type name or a type
literal, so `type_of([]byte)`, `type_of(own Point)`, and
`type_of(chan own T)` (inside a generic body) all parse. All five
intrinsics (`tdesc`, `tqual`, `type_of`, `value_of`,
`value_of_mut`) are GLOBAL builtins — `type_of(Point)`, never
`reflect.type_of(...)` — matching `new`/`mkslice`/`len` residence;
`std/reflect` re-exports nothing for them. Because the return
types `Type`/`Value`/`Variant`/`Field` name std/reflect structs,
the checker folds the intrinsic's result to the descriptor index /
{td,addr,w} shape without resolving a package — the structs are
ordinary decls the checker names when the import is present, and
the intrinsic type is spelled internally as the reflect struct
shape (no import required to type-check the call). A
`tdesc(T)`/`tqual(T)`/`type_of(T)` naming a type parameter is
legal only inside a body where `T` is a bound generic param —
elsewhere `T` is just an unknown name and the checker's ordinary
"unknown type" diagnostic applies (no special intrinsic-side rule
needed, recorded here so nobody adds one). Inside a monomorphized body `type_of(T)` folds with `tdesc(T)`; elsewhere it
takes any concrete type operand. `type_of`, `value_of`, and
`value_of_mut` — and `box` over in `std/errors`' lane — are
global builtins in the `mkslice`/`push` family: the checker
resolves them with no import; they sit in this block because
they are the surface users meet, not because `std/reflect` owns
the names (a package could never declare them — type operands
and ref→int lowering are not expressible in signatures). One
nuance: `type_of(T)` resolves without the import, but the
`Type`/`Field`/`Variant`/`Value` methods live in `std/reflect` —
`t.name()` DOES require importing it. Kind mismatches return the
`reflect.err_kind` err code through the `[v, err]` lanes — the
read contract's err channel is deliverable because the surface is
shaped as pairs from the start.

`fmt` grows `sprintv[T any](v: T) -> str` / `printv[T any]` +
`vfmt[T](f: str, v: T)` covering `%v`/`%+v`/`%T`/`%#v` for a single
typed value — the Go variadic-multi-arg form stays impossible (no
variadics) and the doc says so. The `&{…}` ptr form is delivered
by a sibling intrinsic `tqual(T) -> int` (0 unqualified, 1 `own`,
2 `ref`, 3 `mut`) folded at mono time next to `tdesc(T)` — the
generic binding of `T` carries the qualifier, so a
`sprintv[own Point]` instantiation statically knows to print
`&` — and so do `ref`/`mut` (`tqual` ≠ 0 → `&{…}`, matching Go's
`*T` print for all pointer-lane qualifiers). (Caveat worth one line: a `v: T` param of `sprintv` itself receives the value — `own` args are *moved* into the callee by the
usual rules.) `%v` on opaque kinds (IFACE/FN/CHAN/ERR) prints a
placeholder form — `iface{…}`/`fn`/`chan`/`err <code>` — pinned
here so R2 doesn't improvise; PTR-kind (cstr) values print the
C string's contents via the same `rt_field_cstr` lane `v.str()`
uses. By-value `v: T` can't coerce to
`ref T` (`assignable` admits refs only from own/mut/ref args), so
the bridge inside these wrappers is pinned: `c := new(v)` yields
`own T`, which coerces to `ref T` for `value_of` — then `c` drops
with the wrapper's scope, inside the `Value`'s scope-bound lifetime.

Consumers walk: `gob.encode[T]` → field-wise binary per descriptor;
`xml` → tag-named fields; `template` → `{{.Field}}` lookup by
descriptor name; `sql` row `scan[T]` → column order onto fields.
Each is generic over T; no value is ever boxed.

Qualified-`T` handling is pinned at `value_of`: for `own`/`ref`/
`mut`-qualified `T` the reference lands on the *handle slot*, not
the layout — `value_of` loads the handle once at construction so
`v.addr` always addresses the described layout (`tdesc` resolves
qualified `T` to the wrapped desc per the contract). Decode paths
(`gob` decode, `xml` unmarshal, `sql.scan[T]`'s `out`) write
through `field(i).set_*` on `mut`-derived `Value`s — minting
`own`-field pointees through `v.alloc_field(i)` (a nil `own`
slot reads `err_nil`; the alloc is the mint) and enum payloads
through `set_tag` + `vfield` (tag write on the i32 lane, then
payload-slot writes) — the same
scope-bound rule applies, so a writable `Value` provably cannot
outlive the buffer it mutates. Writability is *enforced*, not
conventional: `mut T` args coerce to `ref T`, which would erase
the bit, so the lane takes `value_of_mut` — a parallel intrinsic
that sets `Value.w`; `field`/`index`/`vfield`/`alloc_field`
propagate it, and `set_*`/`set_tag` return `err_kind` on a Value
lacking it.