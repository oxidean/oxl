# Reflection — type descriptors and `std/reflect`

oxl is statically typed with generics and no runtime type information
by default. Milestone R added an opt-in lane: the compiler emits a
`TypeDesc` record for every type *reachable through a `tdesc`
reference*, and `std/reflect` wraps that table in handles user code
can walk. Demand-driven means `hello.oxl` — which names no `tdesc` —
ships no populated table: reflection costs nothing until you ask for
it.

The whole lane is **native-target only**. Under `--target js` every
descriptor intrinsic and `rt_desc_*`/`rt_field_*` extern is a compile
diagnostic.

## The intrinsics

Five builtins mint handles — no import needed; they fold at
instantiation like `mkslice`/`push`:

| Form | Yields | Meaning |
|---|---|---|
| `tdesc(T)` | `int` | the descriptor-table index for `T` |
| `tqual(T)` | `int` | qualifier of the binding: `0`/`1`/`2`/`3` = plain/`own`/`ref`/`mut` |
| `type_of(T)` | `reflect.Type` | the descriptor handle for `T` |
| `value_of(v)` | `reflect.Value` | read-only walk over `ref`-derived `v` |
| `value_of_mut(v)` | `reflect.Value` | writable walk over `mut`/`own`-derived `v` |

`tdesc`/`tqual`/`type_of` take a *type operand* — `type_of(Point)`,
`type_of([]byte)`, `type_of(T)` inside a generic body all work.
`value_of`/`value_of_mut` take a value of `ref`/`mut`/`own`-qualified
type (`own` handles slot-convert; `value_of_mut` rejects `ref`).
`tdesc(own T)`/`tdesc(ref T)`/`tdesc(mut T)` resolve to the wrapped
`T`'s descriptor — the qualifier lives on the slot, not the layout —
while `tqual` says which slot shape was bound.

## Kinds

Every descriptor carries a frozen kind code; `std/reflect` exposes
one fn per code since v1 has no const surface:

```
KindInt() KindFloat() KindBool() KindStr() KindByte() KindSlice()
KindMap()  KindStruct() KindPtr() KindChan() KindIface() KindFn()
KindErr()  KindEnum()  KindVoid()
```

`int`/`float`/`bool`/`str`/`byte`/`err` map to their scalar lanes;
`cstr` is the only PTR kind; `chan`, iface, and `fn` describe as
opaque kinds (no readable interior); `MAP` is reserved in the frozen
order — the language's map type is the `collections.Map` struct,
which describes as STRUCT. `VOID` covers shapes that exist only so
`tdesc` stays total.

## `std/reflect` — handles

```oxl
import "std/reflect"
```

Three handle types address metadata; one addresses live memory:

- **`Type`** — a descriptor-table index: `name()`, `kind()`,
  `size()`, `nfields()`, `field(i) -> [Field, err]`,
  `elem() -> [Type, err]`, `elemptr()`, `nvars()`, `varname(i)`,
  `variant(i) -> [Variant, err]`.
- **`Field`** — one struct field's metadata: `name()`, `off()`,
  `typ() -> [Type, err]`, `tag()`, `ptr()`.
- **`Variant`** — one enum variant's shape: `name()`, `nfields()`,
  `ftyp(i)`, `foff(i)`, `fname(i)`, `fptr(i)` — payload slots get
  the synthesized names `f0`, `f1`, … when the payload is
  positional.
- **`Value`** — `{descriptor, address, write-bit}` over a live
  layout: `typ()`, the kind-checked readers `int()`, `f64()`,
  `bool()`, `byte()`, `str()` (PTR reads through the cstr lane), and
  — on `value_of_mut`-derived Values only — the writers `set_int`,
  `set_bool`, `set_byte`, `set_f64`, `set_str` (`set_str` heap-copies
  the argument so it can't dangle at scope leave).

Walks: `field(i)` selects struct field `i` (an `own` field's pointer
slot derefs once; a nil slot reports `err_nil`), `len()` reads a
SLICE header's length, `index(i)` selects slice element `i` —
`[]own T` element slots deref once per `elemptr()`. Enum reads:
`tag()` is the live discriminant — its value *is* the variant index,
so `t.variant(v.tag())` names the live variant — `vfield(vi, fi)`
selects variant `vi`'s payload slot `fi` (only when `vi` equals the
live tag; a stale variant reports `err_kind`), `set_tag(i)` retags.

Decode mints — the write lane's object constructors, all requiring a
`mut`-derived `Value`: `alloc_field(i)` mints a zeroed pointee for an
`own` struct field and yields it writable; `alloc_slice(i, n)` mints
a live header + `n`-element heap backing for a SLICE field;
`alloc_elem(i)` mints a nil `[]own T` element slot;
`set_slice(src)` copies a whole slice header (`{ptr,len,cap,heap}`)
into the slot `v` addresses — this is how a `mut []T` out-param
takes a callee-grown slice: mint `new(mkslice(T, n))` (an own-lane
boxed header whose heap backing escapes), fill it through
`index`/`set_*`, then land the header through the `mut` Value.

Every walk is kind-checked: reading an INT field as `str`, writing
through a read-only `Value`, indexing past a bound, or walking an
opaque kind reports an `err` — `reflect.err_kind()`,
`reflect.err_oob()`, `reflect.err_nil()` are the interned sentinels
`errors.is` matches against.

## The `Value` scope rules

`Value` carries a raw address, so the checker keeps it honest rather
than conventional:

- Only `value_of`/`value_of_mut` mint one. Struct literals of
  `Type`/`Field`/`Variant`/`Value` and any field access on them are
  rejected outside `std/reflect` — a spelled `{td, addr}` would be
  arbitrary-memory access.
- A `Value` may be *returned* only when derived from a `ref`/`mut`/
  `Value` parameter — a `Value` over local storage dies with the
  scope.
- No `Value` of any provenance may be stored into a file-scope
  global, a heap shape (struct field, slice element), or a `spawn`.
- Read-only (`value_of`-derived) Values refuse every `set_*` and
  mint — the `w` bit propagates through `field`/`index`/`vfield`
  walks, so a borrowed subtree can't be written either.

## Field tags

Struct fields carry an optional tag string for wire formats:

```oxl
struct Point { x: int, y: int tag "unit:mm" }
```

`Field.tag()` returns it ("" when absent). The tag is metadata only
— codecs decide what it means (`xml:"name"`, `gob:"-"`, …).

## Consumers

- **`std/fmt`** — `%v` prints Go's default forms (`{v1 v2}` structs,
  `&{…}` pointers, variant names for enums), `%+v` adds field names,
  `%T` the type name, `%#v` the source-literal form.
- **`std/database/sql`** — `scan(rows, out)` maps each row's columns
  in declared order onto a struct's fields through the walk above —
  the descriptor table is the only per-row type information it
  consults.

A consumer that walks `Value`s needs only `import "std/reflect"` and
the intrinsics — the emitted binary pays for exactly the descriptors
its `tdesc` references reach.

## Errors are sentinels, not traps

Reflection never traps on shape mismatches — `rt_desc_*` bounds-check
every index and `std/reflect` reports `err` for every mismatched kind
or bound. A descriptor-referencing program that emits no table (a
module redeclaring the externs without a `tdesc` in sight) links
against the weak stub: `rt_desc_count()` is `0` and every accessor
returns its sentinel.
