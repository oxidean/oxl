# FFI boundary contract — retention, consumers, and the trigger

What an address-stable value buys a foreign consumer, what the
existing `extern` boundary actually does today, and the concrete
test that fires the parked implementation.

## The boundary today: borrow-for-duration, universally

The extern ABI passes oxl values as their C shapes (`own`/`ref`/
`mut` → pointers, `[]T` → `RtSlice` header, `str`/`cstr` →
`OxlStr`/`char*`, `fn` → `RtFnv` pair, `chan`/`shared`/`scope` →
opaque words — checker whitelist check.rs:2472 / check.oxl:3873).
Every pointer that crosses today is governed by one implicit rule:
**the callee may use it for the duration of the call and must not
keep it.** Retention has never been legal — it has also never been
checked.

That rule is load-bearing and today it holds by accident of usage:

| surface | what crosses | retention? |
|---|---|---|
| `extra/gui/gtk` shim | int handles in; `str` text in (copied at boundary); `cstr` out (borrowed toolkit buffer → `str` copy); `RtFnv` via the pilot's `gui_connect` (shim **heap-copies** it, frees on destroy-notify) | none — C owns the copy |
| `std/net` | fds (ints); `RtSlice` into `rt_sock_read`/`rt_sock_write` — synchronous syscalls | none — duration borrow |
| `std/os` `rt_fd_read`/`rt_fd_write`, `rt_proc_output` | `[]byte`/`mut []byte` buffers — synchronous; `rt_proc_output` drains into C-owned memory and copies back | none — duration borrow |
| `rt_lookup_start` | `str` host | none — shim `memcpy`s it (rt.c) |
| sqlite builtins | `str` paths/queries, `OxlStr` results — synchronous | none |
| JS lane `__oxl_ffi` | `[]byte` → shared `Uint8Array` view; `own`/`ref`/`mut` → raw refs | GC makes it moot — a JS shim's "retention" is reachability, which is automatic and safe |

Two existing rules make the duration-borrow safe end to end:
synchronous externs can't outlive their caller's scope, and
`spawn`/`goin` args can't carry `[]T`/`ref`/`mut` into a task
(check.rs:2530 — "the backing dies with the scope"). The checker
already keeps arena memory from outliving its arena in task
machinery; `pin` is the piece that does the same for foreign
machinery.

## What `pin` buys a consumer — the contract line

```oxl
extern fn rt_aio_submit(fd: int, buf: pin own void, off: int) -> int
```

Reading `pin` on a param: **"this callee retains `buf` past return;
the caller must pin it first."** That single word converts today's
implicit rule into a checked one:

- With `pin` (the primitive, post-trigger): retention is a declared,
  checked property. An unpinned argument to a `pin` param is a
  compile error; an undeclared retention is a contract violation
  exactly like an undocumented `rt_free` — on the shim author.
- Without `pin` (today): a shim that retains is indistinguishable
  from one that borrows. The hole is real but vacant — the survey
  found no retainer.

Every non-`pin` extern param remains borrow-for-duration; the
qualifier adds the only legal second shape.

## The guarantee an FFI consumer can rely on

Once `pin(b)` has run and `b` crossed a `pin` param:

- the address the callee received — `b` as a `void*` — stays valid and
  points at the same initialized object until the pin count reaches
  zero. The callee may stash it, hand it to an OS facility
  (io_uring, OVERLAPPED, POSIX aio, a driver ring), or write through
  it from another thread, subject to the ordinary aliasing rules of
  the consumer's domain.
- The callee's obligation is the release protocol: exactly one
  `rt_unpin`/`unpin` per pin, from whichever side the decl's
  contract names (items/pin-semantics.md §Release protocol).
- The callee may NOT free a pinned object (`rt_free` traps 11),
  assume anything about addresses *inside* the object beyond the
  pointer it was given, or keep using the pointer after its release
  lands.

## Worked shape: async write (the expected first consumer)

```oxl
extern fn rt_aio_submit(fd: int, buf: pin own void, off: int) -> int  // 0 = queued
extern fn rt_aio_poll(fd: int) -> int      // -errno / 0 pending / n done
extern fn rt_unpin(b: own void)            // rt export — C-callable either way

// shape 1 — pinning task waits, oxl-side release:
fn write_awaited(fd: int, b: own void) -> err {
    pin(b)
    if rt_aio_submit(fd, b, 0) != 0 { unpin(b); return aio_err() }
    for rt_aio_poll(fd) == 0 { time.sleep_ms(1) }   // parks; poll is nonblocking
    unpin(b)                                        // same binding releases
    return nil
}

// shape 2 — submit-and-continue, C-side release:
fn write_detached(fd: int) -> err {
    b := mkbuf(4096)
    pin(b)
    if rt_aio_submit(fd, b, 0) != 0 { unpin(b); return aio_err() }
    return nil          // b's binding dies pinned — the object stays put;
}                       // the shim's completion callback calls rt_unpin(ptr)
```

A pinned handle cannot be `goin`'d into a worker — spawn args are
move sites — so oxl-side release means the pinning task itself
waits; submit-and-continue flows release from C. The alternative
without `pin` — `mkbuf` + "don't free" comments — is exactly what
pin replaces: same capability, no check, and no signal in the decl
that the shim retains.

## Self-referential `own` graphs (the second named trigger)

A node holding the address of its own parent/sibling — the shape
OS handle tables and intrusive C lists want — needs two things:
stable addresses (pin provides) and a way to *store* an address
inside another object. oxl has no addressable-pointer type: `ref`/
`mut` can't be stored in heap objects (v0 ban, check.rs:521),
`own` fields hold whole objects, `shared` cells hold words. So the
honest statement: pin is **necessary but not sufficient**. A
self-referential graph today is built of `poke*`'d raw words inside
`mkbuf` storage — pin makes those words valid; it does not make
them typed. A typed self-reference surface (an address-of or
intrusive-link type) is its own parked item; this spec does not
pretend to deliver it.

## The trigger test

`pin` implements when the first extern decl lands in-tree whose
contract retains a caller pointer past return. The acceptance test
for the whole feature — written now, run then — is
`tests/ffi_pin.oxl` plus a ~60-line `tests/ffi_pin_shim.c`:

```oxl
extern fn pt_hold(b: pin own void)         // stashes the pointer — retention
extern fn pt_poke(off: int, v: int)        // writes through it AFTER return
extern fn pt_read(off: int) -> int         // reads it back
extern fn pt_release()                     // shim calls rt_unpin on the stash

fn main() {
    b := mkbuf(64)
    pin(b)
    pt_hold(b)
    pt_poke(3, 77)                          // post-return write — the shape
    if pt_read(3) != 77 { println("pin retention broken"); exit(1) }
    pt_release()                            // C-side release — b's binding
}                                           //    dies still pinned; a second
                                            // case keeps pt_release out and
                                            // unpin(b)s itself instead —
                                            // exactly one release per pin
```

Companion assertions in the same file: `rt_free` on a pinned
object traps 11 inside a child scope (observed as `ErrTrap` at
`sjoin`), double-`unpin` traps 11, `pin` on an arena-backed value
isn't reachable (`pin` requires `own` — covered by diag tests).

Compile-fail diagnostics (`tests/diag/`):
`pin_move_send.oxl` (send of pinned), `pin_move_return.oxl`,
`pin_move_field.oxl`, `pin_nonown.oxl` (`pin` on `[]byte`/`ref`),
`pin_expr.oxl` (`pin(mkbuf(n))` — non-binding), `pin_twice.oxl`,
`unpin_unpinned.oxl`, `pin_arg_unpinned.oxl` (unpinned arg to a
`pin` param), `pin_param_nonextern.oxl` (`pin` on an ordinary fn
param), `pin_push.oxl` (`push` on pinned `own []T`).

The trigger firing also requires the *consuming* PR to land its
decl first or in the same PR — `pin` ships behind a real caller,
never alone.

## Honest status

No existing surface needs `pin`. The GTK backend — the heaviest FFI
consumer in the tree — went out of its way to need none of it
(handles + heap-copies + destroy-notify). The correct response to
that fact is what this spec does: document the guarantee that
already exists (plan P1), park the checked-retention surface behind
a concrete trigger, and refuse to ship a primitive whose only user
is its own test.
