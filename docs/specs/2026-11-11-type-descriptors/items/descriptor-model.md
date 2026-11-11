# Descriptor model contract

## What codegen emits

Each driver's codegen emits one `TypeDesc` record per type that is
*reachable through a `tdesc` reference* — the named type plus,
transitively, every type its descriptor points at (`elem`,
`fields[].td`). Emission is demand-driven, not per instantiation:
`hello.oxl` names no `tdesc` and stays table-free, matching the
repo's dead-code/size discipline. Records are deduplicated by type
identity:

```
TypeDesc {
  name:   cstr          // "Point", "io.File", "int", "[]byte"
  kind:   u8            // kind enum below
  size:   int           // sizeof in the C layout the emitter produced
  align:  int           // field-address arithmetic needs it for ptr reads
  nfields:int
  fields: FieldDesc*    // structs only; NULL elsewhere
  elem:   int           // desc idx of element type: slice/chan/ptr
  nvars:  int           // enum variant count (0 elsewhere)
  vars:   VariantDesc*  // enums only; NULL elsewhere
}
VariantDesc { name: cstr, nfields: int, fields: FieldDesc* }
FieldDesc { name: cstr, off: int, td: int, tag: cstr, ptr: int }
```

`VariantDesc.fields` describes a variant's positional payload
slots as anonymous `FieldDesc` entries (`name` is `""`, `off` is
relative to the union blob's base). Payload-carrying enums are
walkable end to end: `%v` prints `circle(3.0)`, gob/XML round-trip
them, and `reflect` exposes them — a name-only variant table would
make every payload invisible to all three consumers.

`FieldDesc.ptr` is `1` when the declared field type carries `own`
(the only qualifier legal in field position — `ref`/`mut` can't be
heap-stored): the slot then holds a pointer to `td`'s layout, so
`field(i)` dereferences the slot once and yields the pointee
`Value`. A nil `own` slot yields `err_nil` — never a read of a
zeroed address. `ptr` is `0` everywhere else.

`kind` values: `INT, FLOAT, BOOL, STR, BYTE, SLICE, MAP, STRUCT,
PTR, CHAN, IFACE, FN, ERR, ENUM, VOID` — order frozen once R1 lands
(the table is a stable ABI surface for tools that read the binary).
`MAP` stays in the frozen order but R1 emits no MAP descriptors:
the language's map is the concrete `collections.Map` struct, which
describes as STRUCT over its own internals. `elem` doubles as the
element-desc slot for ptr and chan shapes.

`Ty` → `kind` mapping (anything not listed can't be named by
`tdesc` — the checker rejects it at fold time):

| `Ty`                                    | `kind`  | notes                          |
|-----------------------------------------|---------|--------------------------------|
| int/float/bool/str/byte                 | INT/FLOAT/BOOL/STR/BYTE | one `float` (C `double`) — no f32/f64 split |
| struct                                  | STRUCT  | fields per decl order          |
| `[]T`                                   | SLICE   | `elem` → T's desc              |
| `own T` / `ref T` / `mut T` qualifiers  | (wrapped) | `tdesc(own T)` resolves to the wrapped T's desc — the VALUE is a T. Struct fields declared `own T` keep the wrapped desc too, but set `FieldDesc.ptr` so the walk dereferences the pointer slot once |
| `chan T`                                | CHAN    | `elem` → T's desc; reads opaque |
| iface                                   | IFACE   | reads opaque — no path to the concrete payload (RtIface carries no td); `sprintv`/`gob` on an iface-typed T see only IFACE |
| `fn`                                    | FN      | reads opaque                   |
| `err`                                   | ERR     | int64 code                     |
| enum                                    | ENUM    | `{tag:int, union blob}` layout; `vars` names variants for `%v` |
| `cstr`                                  | PTR     | raw `char*` — the only PTR row v1 produces |
| `Scope`, bare `shared`                  | VOID    | emitted as opaque rows so `tdesc` stays total; reads rejected (`shared` is a non-generic atomic cell, not a `Shared[T]` parametric) |

`tag` holds the field-tag string (`xml:"name"`, `gob:"-"`) — NULL
when absent; needed by R5's xml and R4's gob name overrides. R1 emits
the slot (parser already carries tags if it does — checked at R1;
if tag syntax doesn't exist yet, R1 adds `tag "..."` on fields and
threads it through both parsers/checkers/emitters).

## Resolution: `tdesc(T)` at monomorph time

Inside a monomorphized generic body the parameter `T` is concrete.
`tdesc(T)` is a compile-time intrinsic: codegen folds it to the
descriptor-table index for the bound type at instantiation (`check`
only type-checks the operand — the substitution lives in
`bind_generic`/`func_inst` where `T` is already concrete). It is
*not* a runtime call — the generated code is `mov $idx, ...`. Outside a generic
context `tdesc` takes a concrete type operand identically.

Non-generic code can also name it: `tdesc(int)` is legal anywhere a
constant int is.

`type_of` on the public surface is a **builtin special form**, not a
callable fn — generic type parameters bind only from call
arguments, so `type_of[T any]()` would be uncallable; the
`mkslice(byte, n)` parsing precedent applies: `type_of(Point)` takes
a type operand and folds to `Type{tdesc(Point)}`. Inside a generic
body `type_of(T)` resolves per instantiation identically. `Type`
and `Field` are table handles — `std/reflect` wraps `rt_desc_*`
accessors in methods rather than materializing `[]Field`/`str`
backing that could never be returned from a callee.

## Value reads — the one unsafe seam

`reflect.Value{td, addr}` is constructed only by `value_of`, which
is itself a compiler-lowered intrinsic: `value_of[T](v: ref T)`
emits `Value{tdesc(T), (int64_t)v}` — there is no other way to turn
a reference into an address (no `addrof` builtin; `as` casts stay
str/byte/int/enum-only, and generic externs are not a surface R
opens). Field walks add `off` to `addr`; reads go through externs
that interpret `addr` per the desc's kind:

Field reads — trivial C loads interpreting `addr` per the desc's kind:

```
extern fn rt_field_i64(addr: int) -> int
extern fn rt_field_f64(addr: int) -> float
extern fn rt_field_str(addr: int) -> str       // borrow — same lifetime as v
extern fn rt_field_ptr(addr: int) -> int       // raw field address
```

Field writes — the decode lane (`gob`/`xml`/`sql.scan` all assign
through `mut`-derived `Value`s):

```
extern fn rt_field_set_i64(addr: int, v: int)
extern fn rt_field_set_f64(addr: int, v: float)
extern fn rt_field_set_str(addr: int, v: str)
extern fn rt_field_set_ptr(addr: int, v: int)
```

Descriptor reads — what `Type`/`Field` methods wrap; each is a
table index + read + (for strs) an rt-str build over the stored
cstr:

```
extern fn rt_desc_name(td: int) -> str
extern fn rt_desc_kind(td: int) -> int
extern fn rt_desc_size(td: int) -> int
extern fn rt_desc_nfields(td: int) -> int
extern fn rt_desc_elem(td: int) -> int          // -1 when absent
extern fn rt_desc_nvars(td: int) -> int
extern fn rt_desc_var(td: int, i: int) -> str
extern fn rt_desc_f_name(td: int, i: int) -> str
extern fn rt_desc_f_off(td: int, i: int) -> int
extern fn rt_desc_f_td(td: int, i: int) -> int
extern fn rt_desc_f_tag(td: int, i: int) -> str // "" when absent
extern fn rt_desc_f_ptr(td: int, i: int) -> int // 1: slot is a ptr
extern fn rt_desc_v_nfields(td: int, vi: int) -> int   // enum payload
extern fn rt_desc_v_f_td(td: int, vi: int, fi: int) -> int
extern fn rt_desc_v_f_off(td: int, vi: int, fi: int) -> int
```

All are trivial C; the ONLY unsafe surface is inside `std/reflect`
(`unsafe` blocks around the addr arithmetic). The emitted `align`
field is consumed only by the C helpers' own address math — no
oxl-side accessor is needed.

**`Value` lifetime is enforced, not conventional.** Two ints carry
no borrow marker, so the checker can't rely on the `ref` rules
alone — `fn leak(p: ref Point) -> Value { return value_of(p) }`
would otherwise compile and return a dangling `addr`. The rule:
`reflect.Value` is a **scope-bound type** — the same escape checks
borrowed `ref`s already get (no `return`, no store in `own`/heap
shapes, no spawn escape; the `check.rs` code paths for `ref` escape
are reused via a type flag on `Value`). `v.field(i)`/`v.index(i)`
yield scope-bound `Value`s deriving from `v`. Inside `std/reflect`
this is enough machinery to write the whole walk; outside, a
`Value` can live only as long as its source's scope. Kind
mismatches return a `reflect.err_kind` err code, never garbage.

## What is NOT emitted

- Method tables — ifaces carry vtables; descriptors stay layout-only.
- Type identity beyond the table — two structurally identical named
  types get ONE descriptor each by *name* (nominal, matching the
  checker's own identity rule).
- Payload values — descriptors describe shape; values live behind
  `reflect.Value`.

## Container walks + opaque kinds

`SLICE` values are walkable: `v.len()` reads the slice header's
`len`, `v.index(i)` yields a scope-bound `Value` at
`data + i*elem.size`. `index` rejects `i < 0 || i >= v.len()` with
`err_oob` BEFORE the address math — the emitted address must never
leave the slice's data window. The contract pins the emitted header layout
— `RtSlice{ptr:int, len:int, cap:int, heap:int}` (`rt.h`) — as the
read surface; both drivers already agree since they share the C
layout. `CHAN`, `FN`, and `IFACE` kind values are read-opaque:
`v.len()`/`v.index(i)`/typed reads on them return `err_kind`.

## Fixpoint parity

`tests/desc_parity.oxl` asserts for a fixture struct: identical
`name`, `kind`, `size`, `nfields`, `off` list under both drivers.
The suite's existing fixpoint already proves the emitted programs
behave identically; this asserts the *tables* do.
