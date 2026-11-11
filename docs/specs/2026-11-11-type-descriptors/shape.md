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
reflection (iface-typed `T` describes as IFACE and stops — no path
to the concrete payload), `unsafe` pointer arithmetic as a language
feature (existing `unsafe` is an ownership opt-out block, kept that
way), `runtime/pprof`-class introspection, and the `--target js`
emit lane: `addr:int` arithmetic and C `rt_field_*` loads don't
port to JS, so R is native-lane only — js-lane descriptors/`%v`
defer to their own trigger.

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
   type-desc-idx}` for structs, element desc for slice/chan/ptr
   shapes, variant names for enums. No method tables — ifaces already carry vtables; the
   descriptor surface composes with them rather than duplicating.
3. **Reading field values crosses one unsafe seam — with enforced
   lifetime.** `reflect.Value` is `{tdesc, addr}` — an opaque field
   address. `value_of` is a compiler-lowered intrinsic (no `addrof`
   builtin exists to abuse) and `Value` is declared a scope-bound
   type: the checker applies the same escape rules as borrowed
   `ref`s (no return, no heap store, no spawn escape), so a `Value`
   provably cannot outlive its source. The read path is a small set
   of extern helpers (`rt_field_*`) confined to `std/reflect`
   internals behind `unsafe`; user code sees typed `Value` methods
   (`v.int()`, `v.str()`, `v.field(i)`, `v.len()`/`v.index(i)`),
   never raw addresses.
4. **`errors.As` gets a typed box, `err` stays int64.** Go's As
   matches a *dynamic* type; int64 codes have none. `box(v)` mints
   a fresh int64 code and stores `{tdesc(T), payload}` in the rt
   err registry — the same out-of-band side table wrapped-err
   payloads already use, so a box *is* an `err` end to end and
   chains through `wrap`/`unwrap`/`is` untouched. `errors.as[T](e,
   out)` reads the registry entry's tag and payload back. `ErrBox`
   is the typed lane; the code/payload split stays in rt, not an
   oxl struct (an oxl struct can't be an int64 `err`).
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
struct Field { name: str, off: int, td: int, tag: str } // tag = "" when absent
struct Type  { name: str, kind: int, size: int,
               fields: []Field, elem: int }        // elem: slice/ptr/chan
struct Value { td: int, addr: int }               // opaque; scope-bound

fn type_of[T any]() -> Type                 // tdesc(T) resolved at mono time
fn value_of[T any](v: ref T) -> Value        // intrinsic → {tdesc, addr-of-v}
fn (v Value) field(i: int) -> Value          // addr + fields[i].off
fn (v Value) len() -> int                    // SLICE only (RtSlice.len)
fn (v Value) index(i: int) -> Value          // SLICE only, scope-bound
fn (v Value) int() -> int                    // kind-checked read
fn (v Value) str() -> str                    // kind-checked read
```

`fmt` grows `sprintv[T any](v: T) -> str` / `printv[T any]` +
`vfmt[T](f: str, v: T)` covering `%v`/`%+v`/`%T`/`%#v` for a single
typed value — the Go variadic-multi-arg form stays impossible (no
variadics) and the doc says so. By-value `v: T` can't coerce to
`ref T` (`assignable` admits refs only from own/mut/ref args), so
the bridge inside these wrappers is pinned: `c := new(v)` yields
`own T`, which coerces to `ref T` for `value_of` — then `c` drops
with the wrapper's scope, inside the `Value`'s scope-bound lifetime.

Consumers walk: `gob.encode[T]` → field-wise binary per descriptor;
`xml` → tag-named fields; `template` → `{{.Field}}` lookup by
descriptor name; `sql` row `scan[T]` → column order onto fields.
Each is generic over T; no value is ever boxed.
