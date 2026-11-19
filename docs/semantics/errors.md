# Errors

`err` stays an int64 code — the `[v, err]` ABI is unchanged. What a
code *means* lives in the runtime's append-only error registry,
which `std/errors` (`std/errors/errors.oxl`) fronts.

## Message codes

```oxl
e := errors.new("EOF")          // interned — same text, same code
s := errors.msg(e)              // "EOF"; "" for nil/foreign codes
c := errors.code(e)             // the raw int64
```

`errors.new` interns by message text, which is what makes sentinels
comparable: `errors.new("EOF")` called anywhere returns the same
code and `e == io.eof()` is a plain int compare.

## Chains

```oxl
w := errors.wrap("open config", e)   // new entry, cause = e
u := errors.unwrap(w)                // e, or nil at chain end
ok := errors.is(w, e)                // code compare at each link
```

Unlike `new`, `wrap` is never interned — two wraps of the same text
stay distinct so each keeps its own chain. `is` walks `rt_err_cause`
links comparing codes, so interned sentinels and boxed values both
match by identity.

## Typed payloads — `box` and `errors.as`

An int64 code carries no type identity, so `std/errors` gains a
typed lane built on R1 runtime type descriptors:

```oxl
e := box(req)                    // global builtin, like value_of/mkslice
out := new(Request)
if errors.as(e, out) {           // declared generic — folds at the
    handle(out)                  // call site to rt_err_as
}
```

`box[T any](v: T)` is a compiler-lowered global builtin — no extern
signature can carry a generic `T`/`own` payload into an int slot, so
the compiler binds `T` from `v` and emits `rt_err_box(tdesc(T),
pdata)` directly. The result is an ordinary `err` code: a box **is**
an error end to end and chains through `wrap`/`unwrap`/`is`
untouched. `errors.msg` on a box yields the boxed type's descriptor
name.

Each `box` call mints a fresh registry entry — boxes never intern,
even for identical payloads.

### The registry entry

A box entry extends the message record with `{td, pdata}`:

- `td` — the payload type's descriptor index, folded at the box site.
- `pdata` — **always a pointer**; the registry adopts it.
- `msg` — the boxed type's descriptor name.
- `next`, `cause` — NULL; a box ends a chain.

### Payload storage

How `pdata` is produced depends on the argument shape:

- A bare `own T` **binding moves its handle** into `pdata` — no
  copy; the checker marks the binding moved.
- `own T` **rvalues** (`box(new(P))`, `box(mk())`) move the same
  way — the temp is unaliased.
- `own` **fields and other non-Name own exprs heap-copy the pointee**
  — a field can't be move-marked, so copying keeps the owner sound.
- Value, `ref`, and `mut` args **heap-copy** `sizeof(T)` bytes into
  an `rt_alloc_own` block.
- `str` payloads additionally get an `rt_str_own` upgrade: the copied
  `OxlStr` header would otherwise name the boxer's scope-arena
  backing, which dies with that scope.

`box` consumes `v` per ownership semantics — a moved `own` binding
can't be used afterward.

> Heap-adjacent payloads are shallow: `str` fields inside a boxed
> struct, or slice backings, still name scope-arena memory. Box own
> data or plain values on error paths — don't box arena-backed shapes
> that must outlive their scope.

### Matching with `errors.as`

`as[T any](e, out: mut T)` is a declared generic — `mut T` binds `T`
from `out` — but the call site folds to `rt_err_as(code, tdesc(T),
out_addr, mv)` exactly like `box`: a `mut T` param's C pointer *is*
the writable `*out` address the extern needs.

Matching walks the cause chain from `e` inward:

- The **first box whose stored `td` equals `T`'s descriptor index
  exactly** wins — descriptor identity, no assignability or
  method-set walk.
- An **interface-typed `out` matches only a box storing that same
  interface descriptor** — boxing `impl` won't match `as[iface]` and
  vice versa.
- On a match the payload copies into `*out`; for `own`-bound outs
  (`mut own T` slots) the entry's handle is **moved** in instead.
- The matched slot **clears** (`pdata = NULL`, `td = -1`): a box
  answers `as` **exactly once**. A consumed box contributes no match
  and the walk continues past it.
- Non-box entries (`pdata == 0`) are skipped; `nil`, foreign codes,
  and chain end answer `false`.

Since `wrap` interleaves message entries and a box's own `cause` is
NULL, a chain holds at most one box — but the same rules apply to
any chain shape the runtime can represent.

## Lifetime and bounds

Registry entries — and the payload blocks they adopt — are **never
freed**. The registry caps at `RT_ERR_MAX` (65536) entries; overflow
returns the shared `"error registry full"` sentinel. All registry
access is mutex-guarded, so `box`/`as` are safe across `spawn`ed
tasks.

That makes `box` a tool for **error paths, not hot loops**: every
call permanently allocates an entry plus a payload block. Prefer
message codes and `is` on hot paths; reserve `box`/`as` for failures
worth reporting with structure.

## `--target js`

The typed lane is native-only — `box`, `errors.as` call sites, and
the `rt_err_box`/`rt_err_as` externs are checker diagnostics under
`--target js`, alongside the R1 descriptor surface. Message codes,
`wrap`/`unwrap`/`is` work in both lanes.
