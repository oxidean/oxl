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
decl/instantiation emission traversal. Cross-driver table parity
is asserted by `tests/desc_parity.oxl` run under both drivers (the
suite's seed-vs-self output-compare pattern) — NOT by the C-text
fixpoint, which only diffs the self emitter across its own
generations:

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
  elem:   int           // desc idx of element type: slice/chan
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
synthesized names `f0`, `f1`, … so `%+v` and gob have a stable
spelling rather than `""`. Payload-carrying enums are
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
`MAP` is reserved in the frozen order — no `Ty` produces it
(the language's map is the concrete `collections.Map` struct,
which describes as STRUCT over its own internals). `elem` doubles as the
element-desc slot for chan shapes; PTR leaves it unset — the only
v1 PTR row is `cstr`, which has no element type to describe.

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

Enum correspondence is pinned: the emitted tag value IS the
variant's index into `vars[]` — variants emit in decl order and
tags count in the same order, so `v.tag()` selects
`variant(v.tag())` directly.

Table linkage follows the demand rule end to end: codegen emits
the populated table only on `tdesc`-reach — a program naming no
`tdesc` emits no *populated* table. The `rt_desc_*`/`rt_field_*`
helpers live in rt.c unconditionally, and rt.c ships a weak stub
(`o_desc_tab[1]`/`o_desc_tab_n` = 0) so a module that redeclares
and calls an extern still links and gets the sentinel
(`rt_desc_count` → 0 → every accessor `err_oob`s) — "link
identically to today" means no emitted table, not no helper
symbols.

`tag` holds the field-tag string (`xml:"name"`, `gob:"-"`) — NULL
when absent; needed by R5's xml and R4's gob name overrides. R1 emits
the slot — the parser carries no tags today, so R1 adds
`tag "..."` on fields and threads it through both
parsers/checkers/emitters.

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

`reflect.Value{td, addr, w}` (`w` — the write bit; `mut` is a
keyword and can't name a field) is constructed only by
`value_of`/`value_of_mut`, which are compiler-lowered intrinsics:
`value_of[T](v: ref T)` emits `Value{tdesc(T), (int64_t)v, 0}` —
there is no other way to turn a reference into an address (no
`addrof` builtin; `as` casts stay str/byte/int/enum-only, and
generic externs are not a surface R opens). "Only the intrinsics"
is enforced: the language has no private fields, so the
scope-bound flag additionally rejects `reflect.Value{...}`
struct literals outside `std/reflect` — fabrication would
otherwise be arbitrary-memory access. The flag makes `Value`
**field-opaque** there too: `v.addr = x` on a `Value` var bypasses
the literal ban while fabricating the same access, so stores to
AND reads of `Value`'s fields are rejected outside `std/reflect`
(inside it they stay ordinary ints for the extern calls). Field
walks add `off` to `addr` and propagate `w`; reads go through
externs. The same flag marks `Type`,
`Field`, and `Variant` non-constructible by struct literal and
field-opaque outside `std/reflect`: they are the same kind of
forgeable handle — `Type{td: <any int>}` mints a descriptor index
out of thin air, and without the ban every `rt_desc_*` accessor
reached through it is an arbitrary-offset read (`t.name()` →
`rt_desc_name(999999)` → `desc_tab[999999].name` — a pointer
deref then `rt_str` over arbitrary memory). Reads of a forged
handle's fields are equally non-load-bearing — nothing outside
`std/reflect` spells `t.td` at all.

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
extern fn rt_field_set_str(addr: int, v: str) // caller must pass
                                             //  rt_str_own backing — a
                                             //  callee-arena str written
                                             //  into caller-owned storage
                                             //  dangles at scope leave
extern fn rt_field_set_ptr(addr: int, v: int)
```

Descriptor reads — what `Type`/`Field` methods wrap; each is a
table index + read + (for strs) an rt-str build over the stored
cstr:

```
extern fn rt_desc_count() -> int             // emitted table length — the
                                             //  bounds bound for every td
                                             //  arg below
extern fn rt_desc_name(td: int) -> str
extern fn rt_desc_kind(td: int) -> int
extern fn rt_desc_size(td: int) -> int
extern fn rt_desc_nfields(td: int) -> int
extern fn rt_desc_elem(td: int) -> int          // -1 when absent — the
                                              //  public elem() is pair-shaped:
                                              //  -1 → err_kind, never
                                              //  Type{td:-1}
extern fn rt_desc_elem_ptr(td: int) -> int      // 1 when the element SLOT is
                                              //  a pointer to elem's layout
                                              //  ([]own T) — v.index's stride
                                              //  + deref-once contract needs
                                              //  this to be callable
extern fn rt_desc_nvars(td: int) -> int
extern fn rt_desc_v_name(td: int, i: int) -> str
extern fn rt_desc_f_sname(td: int, i: int) -> str
extern fn rt_desc_f_off(td: int, i: int) -> int
extern fn rt_desc_f_td(td: int, i: int) -> int
extern fn rt_desc_f_tag(td: int, i: int) -> str // "" when absent
extern fn rt_desc_f_ptr(td: int, i: int) -> int // 1: slot is a ptr
extern fn rt_desc_v_nfields(td: int, vi: int) -> int   // enum payload
extern fn rt_desc_v_f_name(td: int, vi: int, fi: int) -> str
                                             // decl name; synthesized `fN`
                                             //  (f0, f1, …) when the payload
                                             //  slot is positional — the same
                                             //  spelling the C member gets
extern fn rt_desc_v_f_td(td: int, vi: int, fi: int) -> int
extern fn rt_desc_v_f_off(td: int, vi: int, fi: int) -> int
extern fn rt_desc_v_f_ptr(td: int, vi: int, fi: int) -> int
                                             // 1: payload slot is a ptr
                                             //  (own/mut/ref-typed payload —
                                             //  vfield derefs once, like
                                             //  FieldDesc.ptr)
extern fn rt_desc_v_base(td: int) -> int
                                             // offsetof the union blob —
                                             //  identical for every variant
                                             //  (one arg — codegen-pinned,
                                             //  never a fixed constant)
extern fn rt_desc_alloc(td: int) -> int      // decode lane: zeroed pointee
                                             //  mint for td — allocated via
                                             //  rt_alloc_own (heap): a scope-
                                             //  arena mint would die with the
                                             //  decoder's scope while the
                                             //  target struct lives in the
                                             //  caller
extern fn rt_desc_alloc_slice(td: int, n: int) -> int
                                             // decode lane for SLICE fields:
                                             //  mints an RtSlice{ptr,len,cap,
                                             //  heap} header + n*elem-size
                                             //  backing, own-lane; the header
                                             //  addr writes through the
                                             //  ptr-slot lane
field is emitted for ABI consumers only (parity checks,
external tools) — the C helpers do no align math, but the accessor
itself ships for the same consumers:

```
extern fn rt_desc_align(td: int) -> int          // ABI-consumer surface
```

The `rt_desc_*`/`rt_desc_v_f_*`/
`rt_desc_f_*` externs themselves bounds-check every index arg —
`td`, `i`, `vi`, `fi` against the emitted table dimensions
(`rt_desc_count` is emitted alongside the table) — and return
the sentinel (`err_oob`-equivalent / `-1` / `""`) on violation.
That keeps the flag's guarantee honest even for modules that
redeclare the externs: a forged `td` read is UB the helpers
refuse to perform, not just a shape user code can't spell.
**`Value` lifetime is enforced, not conventional — via
provenance, not the `ref` signature bans.** Three ints carry no
borrow marker, so the checker can't rely on the `ref` rules
alone — and a literal reuse of those rules would also reject this
surface's own `-> [Value, err]` methods (check.oxl bans `ref`/
`mut` under `Ret::Pair` too — under check.oxl `-> []T` itself is
a plain slice return and is NOT banned; only the borrow-typed
slots are. check.rs is stricter: it bans `[]T` returns under both
ret shapes — check.rs:814-817/`825-828` — a real parity gap the
R1 implementation must pick a side on).
The pinned rule: `reflect.Value` is a **scope-bound type** — the
flag attaches at the decl (the checker marks `std/reflect`'s
`Value` struct by decl site; no marker syntax ships in v1) — a
`Value` may be returned only when it derives from one of the
function's `ref`/`mut`/`Value` parameters (the checker gains a
provenance pass for this: it tracks Value derivation through
assignments and `field`/`index`/`vfield` walks — a new rule, not a
reuse of an existing borrow-provenance pass, which does not
exist). A `Value`
derived from a *local* `own` — `c := new(v); return value_of(c)` — or a
*file-scope global* (global storage never dies, but v1 classifies
`value_of(g)` like a local-`own` derivation: usable in-scope, not
returnable — a future marker could exempt it)
is the real dangling case, since `p`-derived Values address
caller-owned storage — may not be returned, and no `Value` of
any provenance may be stored into a file-scope global, stored in
`own`/heap shapes, captured into a closure or fn-value that
outlives the source scope, or sent to `spawn` (param-derived
Values dangle in those slots identically — return is the only
escape the rule opens; the checker's ordinary ref-capture ban
does not reach a Value's bare ints, so the capture vector is
spelled out explicitly). `v.field(i)`/`v.index(i)`/`v.vfield(vi, fi)`
yield scope-bound `Value`s deriving from `v`. Inside `std/reflect`
this is enough machinery to write the whole walk; outside, a `Value`
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
`data + i*stride` where stride is the SLOT width — `elem.size`
normally, pointer width (8) when `elem_ptr` is set, then the slot
is dereferenced once to reach `elem`'s layout. `index` rejects `i < 0 || i >= v.len()` with`err_oob` BEFORE the address math — the emitted address must never
leave the slice's data window. The contract pins the emitted header layout
— `RtSlice{ptr:int, len:int, cap:int, heap:int}` (`rt.h`) — as the
read surface; both drivers already agree since they share the C
layout. `CHAN`, `FN`, and `IFACE` kind values are read-opaque:
`v.len()`/`v.index(i)`/typed reads on them return `err_kind`.
`PTR` is not opaque — `v.str()` reads it through `rt_field_cstr`;
`ERR` reads its code through `v.int()` (the i64 lane).

## Target gating

Under `--target js` the whole lane is a diagnostic, not silent
codegen: `tdesc`/`tqual`/`type_of`/`value_of`/`value_of_mut` fold
sites and `rt_desc_*`/`rt_field_*` extern declarations are rejected
by both checkers/emitters (js-lane descriptors defer to their own
trigger — `addr:int` + C loads don't port).

## Cross-driver parity

`tests/desc_parity.oxl` asserts for a fixture struct: identical
`name`, `kind`, `size`, `nfields`, `off` list under both drivers —
it compiles the fixture through codegen.rs AND codegen.oxl and
compares the descriptor contents the programs print. The suite's
C-text fixpoint only diffs the self emitter across its own
generations, so it cannot witness rs-vs-oxl table drift; this test
is the parity gate.
