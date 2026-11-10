# Runtime type descriptors + reflection surface — Shaping Notes

## Scope

Milestone R from the parked list
(`docs/specs/2026-11-06-0111-package-system/items/parked-stdlib.md`,
`docs/specs/2026-11-07-phase-2-plan/parked.md`): compiler-emitted
runtime type descriptors + the reflection-class stdlib they unlock —
`fmt` `%v`/`%+v`/`%T` (issue #28), `errors.As` typed binding (issue
#27 partial), then `encoding/gob`, `encoding/xml`, `text/template`,
`database/sql`, and a `std/reflect` lite as the public machinery.

Not this spec: an `any` type or boxed values, variadic call forms,
runtime type-id tags on every allocation, interface-dispatch
reflection, `unsafe` pointer arithmetic as a language feature
(existing `unsafe` is an ownership opt-out block, kept that way),
`runtime/pprof`-class introspection.

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
   type-desc-idx}` for structs, element desc for slice/chan/ptr/map
   shapes. No method tables — ifaces already carry vtables; the
   descriptor surface composes with them rather than duplicating.
3. **Reading field values crosses one unsafe seam.** `reflect.Value`
   is `{tdesc, addr}` — an opaque field address. The read path is a
   small set of extern helpers (`rt_field_*`) confined to `std/reflect`
   internals behind `unsafe`; user code sees typed `Value` methods
   (`v.int()`, `v.str()`, `v.field(i)`), never raw addresses.
4. **`errors.As` gets a typed box, `err` stays int64.** Go's As
   matches a *dynamic* type; int64 codes have none. Additive
   `ErrBox{code, tdesc, payload}` — `errors.box(v)`, `errors.as[T](e,
   out)` walks the box's tag. The `err` chain (`wrap`/`unwrap`/`is`)
   is untouched; `ErrBox` is the typed lane.
5. **gob is the first hard consumer, not %v.** %v proves the table
   emits; gob proves the walk machinery is complete enough to trust
   (arbitrary nested struct → bytes → equal struct). Stages ordered
   so each consumer retires a real risk before the next is spent.
6. **Two drivers, one contract.** Descriptor emission lands in
   `codegen.rs` AND `codegen.oxl`; the fixpoint suite is the parity
   check — a test asserts descriptor contents (name, fields, offsets)
   for a fixture type compiled by each driver.

## The decision

**A compiler-emitted `TypeDesc` table + a `tdesc(T)` intrinsic,
resolved per monomorphized instantiation.**

```oxl
// std/reflect — public surface (v1)
struct Field { name: str, off: int, td: int }     // td = desc idx
struct Type  { name: str, kind: int, size: int,
               fields: []Field, elem: int }        // elem: slice/ptr/chan/map
struct Value { td: int, addr: int }               // opaque; unsafe internals

fn type_of[T any]() -> Type                 // tdesc(T) resolved at mono time
fn value_of[T any](v: ref T) -> Value        // {tdesc, addr-of-v}
fn (v Value) field(i: int) -> Value          // addr + fields[i].off
fn (v Value) int() -> int                    // kind-checked read
fn (v Value) str() -> str                    // kind-checked read
```

`fmt` grows `sprintv[T any](v: T) -> str` / `printv[T any]` +
`vfmt[T](f: str, v: T)` covering `%v`/`%+v`/`%T`/`%#v` for a single
typed value — the Go variadic-multi-arg form stays impossible (no
variadics) and the doc says so.

Consumers walk: `gob.encode[T]` → field-wise binary per descriptor;
`xml` → tag-named fields; `template` → `{{.Field}}` lookup by
descriptor name; `sql` row `scan[T]` → column order onto fields.
Each is generic over T; no value is ever boxed.
