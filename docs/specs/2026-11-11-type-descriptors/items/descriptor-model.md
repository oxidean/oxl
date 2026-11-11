# Descriptor model contract

## What codegen emits

Each driver's codegen emits one `TypeDesc` record per type that is
*reachable through a `tdesc` reference* — the named type plus,
transitively, every type its descriptor points at (`elem`,
`fields[].td`). Emission is demand-driven, not per instantiation:
`hello.oxl` names no `tdesc` and stays table-free, matching the
repo's dead-code/size discipline. Records are deduplicated by type
identity; indices are assigned in first-mention order — the
sequence each driver meets `tdesc` references in its existing
decl/instantiation emission traversal — so the fixpoint's
byte-level C diff sees identical tables:

```
TypeDesc {
  name:   cstr          // "Point", "io.File", "int", "[]byte"
  kind:   u8            // kind enum below
  size:   int           // sizeof in the C layout the emitter produced
  align:  int           // recorded for the table's ABI consumers
                       // (cross-driver parity checks, external tools);
                       // rt helpers do no align math — offsets are
                       // already absolute
  nfields:int
  fields: FieldDesc*    // structs only; NULL elsewhere
  elem:   int           // desc idx of element type: slice/chan/ptr
  elem_ptr: int         // 1 when the element SLOT is a pointer to
                       // elem's layout (`[]own T`) — index(i) then
                       // derefs the slot like FieldDesc.ptr; 0 for
                       // inline elements. CHAN payloads are in-flight
                       // values, never addressable — CHAN reads stay
                       // opaque regardless.
  nvars:  int           // enum variant count (0 elsewhere)
  vars:   VariantDesc*  // enums only; NULL elsewhere
}
VariantDesc { name: cstr, nfields: int, fields: FieldDesc* }
FieldDesc { name: cstr, off: int, td: int, tag: cstr, ptr: int }
```

`VariantDesc.fields` describes a variant's payload slots as
`FieldDesc` entries (`off` is relative to the union blob's base).
Named payloads (`E.V{ a: t }`) keep their declared names — gob/xml
need them for named-payload variants — and positional payloads get
`name: ""`. Payload-carrying enums are
walkable end to end: `%v` prints `circle(3.0)`, gob/XML round-trip
them (decode writes the tag through the `rt_field_set_i32` lane on
`v.addr` — `v.set_tag(i)` — then payload slots through
`v.vfield(vi, fi)` Values), and `reflect` exposes them — a
name-only variant table would make every payload invisible to all
three consumers.

`FieldDesc.ptr` is `1` when the declared field type carries `own`
(the only qualifier legal in field position — `ref`/`mut` can't be
heap-stored): the slot then holds a pointer to `td`'s layout, so
`field(i)` dereferences the slot once and yields the pointee
`Value`. A nil `own` slot yields `err_nil` — never a read of a
zeroed address. `ptr` is `0` everywhere else.

Table initializers spell `sizeof(struct o_s_*)` /
`offsetof(struct o_s_*, f)` / `offsetof(struct o_en_*, u.v*)` —
never precomputed integers. Two effects are pinned: emitted
layout stays C-truth on each driver, and because the unit pass
decides dead-decl reachability on the emitted text itself — any
`o_*` name a live unit spells is a use edge (`codegen.rs`) — the
sizeof/offsetof spellings double as the edges that pull every
desc-referenced decl live. A descriptor naming a type keeps that
type emitted.

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

`tqual(T)` is the sibling intrinsic at the same fold site: it
yields `0`/`1`/`2`/`3` for an unqualified/`own`/`ref`/`mut`
binding of `T` — the generic binding carries the qualifier, so a
`sprintv[own Point]` instantiation statically knows to print the
`&{…}` form and `value_of` knows the handle needs one deref.
Qualified-`T` normalization is pinned the same way for both:
`tdesc(own T)`/`tdesc(ref T)`/`tdesc(mut T)` resolve to the
wrapped `T`'s descriptor (the value described is a `T` — the
qualifier lives on the slot, not the layout) while `tqual`
returns which slot shape was bound.

`type_of` on the public surface is a **builtin special form**, not a
callable fn — generic type parameters bind only from call
arguments, so `type_of[T any]()` would be uncallable; the
`mkslice(byte, n)` parsing precedent applies: `type_of(Point)` takes
a type operand and folds to `Type{tdesc(Point)}`. The operand
grammar is mkslice's exactly — an Ident type name or a type
literal, so `type_of([]byte)`, `type_of(own Point)`, and
`type_of(chan own T)` (inside a generic body) all parse;
`type_of`/`value_of`/`value_of_mut`/`box` are global builtins in
the `mkslice`/`push` family, resolved by the checker with no
import — a package signature could never express a type operand
or the ref→int/`own`→slot lowering. Inside a generic
body `type_of(T)` resolves per instantiation identically. `Type`
and `Field` are table handles — `std/reflect` wraps `rt_desc_*`
accessors in methods rather than materializing `[]Field`/`str`
backing that could never be returned from a callee.

## Value reads — the one unsafe seam

`reflect.Value{td, addr, mut}` is constructed only by
`value_of`/`value_of_mut`, which are compiler-lowered intrinsics:
`value_of[T](v: ref T)` emits `Value{tdesc(T), (int64_t)v, 0}` —
there is no other way to turn a reference into an address (no
`addrof` builtin; `as` casts stay str/byte/int/enum-only, and
generic externs are not a surface R opens). "Only the intrinsics"
is enforced: the language has no private fields, so the
scope-bound flag additionally rejects `reflect.Value{...}`
struct literals AND field writes on a `Value` outside
`std/reflect` — `v.addr`/`v.mut` are public ints, so either
lane would otherwise mint an address/writability the intrinsics
never blessed (field reads stay open). The `poke8`/`poke16`/
`poke32` builtins already write arbitrary memory by design, so
the guard protects the `td`↔`addr` invariant the kind-checked
lanes rely on, not the address space. Field walks add `off` to
`addr` and propagate `mut`; reads go through externs that
interpret `addr` per the desc's kind:

Field reads — trivial C loads interpreting `addr` per the desc's kind:

```
extern fn rt_field_i64(addr: int) -> int     // INT + ERR lane (8B —
                                             //  ERR yields the code)
extern fn rt_field_i32(addr: int) -> int     // BOOL + enum tag lane
                                             // (C `int`, 4B — an i64
                                             // load would pull adjacent
                                             // memory)
extern fn rt_field_u8(addr: int) -> int      // BYTE lane (1B)
extern fn rt_field_f64(addr: int) -> float
extern fn rt_field_str(addr: int) -> str       // borrow — same lifetime as v
extern fn rt_field_cstr(addr: int) -> str      // PTR lane — rt-str build
                                               //  over the stored char*
                                               //  (strlen — NOT an RtStr
                                               //  header load)
extern fn rt_field_ptr(addr: int) -> int       // raw field address
```

Field writes — the decode lane (`gob`/`xml`/`sql.scan` all assign
through `mut`-derived `Value`s):

```
extern fn rt_field_set_i64(addr: int, v: int)
extern fn rt_field_set_i32(addr: int, v: int)
extern fn rt_field_set_u8(addr: int, v: int)
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
extern fn rt_desc_v_f_name(td: int, vi: int, fi: int) -> str
                                             // "" for positional slots
extern fn rt_desc_v_base(td: int) -> int     // union blob base offset —
                                             // codegen-pinned offsetof(u);
                                             // NOT a fixed constant (tag is
                                             // C `int` 4B; alignment varies)
extern fn rt_desc_alloc(td: int) -> int      // decode lane's object mint —
                                             // zeroed rt_alloc_own of the
                                             // desc's `size`, returned as
                                             // the raw address; store into
                                             // an own field slot via
                                             // rt_field_set_ptr, then walk
                                             // it as {td, addr, mut:1}
```

All are trivial C; the ONLY unsafe surface is inside `std/reflect`
(`unsafe` blocks around the addr arithmetic). The emitted `align`
field is for the parity test and external ABI readers — rt
helpers do no align math (offsets are already absolute) and no
oxl-side accessor is needed.

**`Value` lifetime is enforced, not conventional — via
provenance, not the `ref` signature bans.** Three ints carry no
borrow marker, so the checker can't rely on the `ref` rules
alone — and a literal reuse of those rules would also reject this
surface's own `-> [Value, err]` methods (check.oxl bans `ref`/
`mut` under `Ret::Pair` too; `[]T` returns are banned under both).
The pinned rule: `reflect.Value` is a **scope-bound type** — the
flag attaches at the decl (the checker marks `std/reflect`'s
`Value` struct by decl site; no marker syntax ships in v1) — a
`Value` may be returned only when it derives from one of the
function's `ref`/`mut`/`Value` parameters (the checker tracks
Value provenance through assignments and `field`/`index`/`vfield`
walks — new, Value-only machinery; today's borrow rules are
type-position bans, not a provenance pass). A `Value`
derived from a *local* `own` — `c := new(v); return value_of(c)`
is the real dangling case, since `p`-derived Values address
caller-owned storage — may not be returned, and no `Value` of
any provenance may be stored into a file-scope global, stored in
`own`/heap shapes, or sent to `spawn` (param-derived Values
dangle in those slots identically — return is the only escape
the rule opens). `v.field(i)`/`v.index(i)`/`v.vfield(vi, fi)`
yield scope-bound `Value`s deriving from `v`. Inside `std/reflect` this
is enough machinery to write the whole walk; outside, a `Value`
can live only as long as its source's scope. Kind mismatches
return a `reflect.err_kind` err code, never garbage. (`err_kind`,
`err_oob`, `err_nil` are fns returning interned sentinels, the
`io.eof()` convention.)

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
`data + i*stride`, where `stride` is pointer size when `elem_ptr`
is set (the slot holds a pointer to `elem`'s layout and derefs
once, like `FieldDesc.ptr`) or `elem.size` for inline elements.
`index` rejects `i < 0 || i >= v.len()` with
`err_oob` BEFORE the address math — the emitted address must never
leave the slice's data window. The contract pins the emitted header layout
— `RtSlice{ptr:int, len:int, cap:int, heap:int}` (`rt.h`) — as the
read surface; both drivers already agree since they share the C
layout. `CHAN`, `FN`, and `IFACE` kind values are read-opaque:
`v.len()`/`v.index(i)`/typed reads on them return `err_kind`.
`PTR` is not opaque — `v.str()` reads it through `rt_field_cstr`;
`ERR` reads its code through `v.int()` (the i64 lane).

## Fixpoint parity

`tests/desc_parity.oxl` asserts for a fixture struct: identical
`name`, `kind`, `size`, `nfields`, `off` list under both drivers.
The suite's existing fixpoint already proves the emitted programs
behave identically; this asserts the *tables* do.
