# Descriptor model contract

## What codegen emits

For every type instantiated in a program, each driver's codegen
emits one `TypeDesc` record into the binary's static data,
deduplicated by type identity:

```
TypeDesc {
  name:   cstr          // "main.Point", "std/io.File", "int", "[]byte"
  kind:   u8            // kind enum below
  size:   int           // sizeof in the C layout the emitter produced
  align:  int           // field-address arithmetic needs it for ptr reads
  nfields:int
  fields: FieldDesc*    // structs only; NULL elsewhere
  elem:   int           // desc idx of element type: slice/chan/ptr/map val
  key:    int           // map key desc idx (-1 elsewhere)
}
FieldDesc { name: cstr, off: int, td: int, tag: cstr }
```

`kind` values: `INT, FLOAT, BOOL, STR, BYTE, SLICE, MAP, STRUCT,
PTR, CHAN, IFACE, FN, ERR, VOID` — order frozen once R1 lands
(the table is a stable ABI surface for tools that read the binary).

`tag` holds the field-tag string (`xml:"name"`, `gob:"-"`) — NULL
when absent; needed by R5's xml and R4's gob name overrides. R1 emits
the slot (parser already carries tags if it does — checked at R1;
if tag syntax doesn't exist yet, R1 adds `tag "..."` on fields and
threads it through both parsers/checkers/emitters).

## Resolution: `tdesc(T)` at monomorph time

Inside a monomorphized generic body the parameter `T` is concrete.
`tdesc(T)` is a compile-time intrinsic: check substitutes it with
the descriptor-table index for the bound type. It is *not* a runtime
call — the generated code is `mov $idx, ...`. Outside a generic
context `tdesc` takes a concrete type operand identically.

Non-generic code can also name it: `tdesc(int)` is legal anywhere a
constant int is. This keeps `std/reflect.type_of[T]` a one-liner:

```oxl
fn type_of[T any]() -> Type { return reflect_from_desc(tdesc(T)) }
```

## Value reads — the one unsafe seam

`reflect.Value{td, addr}` is constructed only by `value_of`, which
takes `ref T` — a live reference, never an escaped copy. Field walks
add `off` to `addr`; reads go through externs that interpret
`addr` per the desc's kind:

```
extern fn rt_field_i64(addr: int) -> int
extern fn rt_field_f64(addr: int) -> f64
extern fn rt_field_str(addr: int) -> str       // borrow — same lifetime as v
extern fn rt_field_ptr(addr: int) -> int       // raw field address
```

All four are trivial C loads; the ONLY unsafe surface is inside
`std/reflect` (`unsafe` blocks around the addr arithmetic). The
contract forbids `Value` outliving its source: `value_of` borrows,
`v.field(i)` borrows from `v` — same arena/scope rules as `str(cstr)`
borrows in `extra/gui`. Kind mismatches return a `reflect.err_kind`
err code, never garbage.

## What is NOT emitted

- Method tables — ifaces carry vtables; descriptors stay layout-only.
- Type identity beyond the table — two structurally identical named
  types get ONE descriptor each by *name* (nominal, matching the
  checker's own identity rule).
- Payload values — descriptors describe shape; values live behind
  `reflect.Value`.

## Fixpoint parity

`tests/desc_parity.oxl` asserts for a fixture struct: identical
`name`, `kind`, `size`, `nfields`, `off` list under both drivers.
The suite's existing fixpoint already proves the emitted programs
behave identically; this asserts the *tables* do.
