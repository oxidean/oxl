# js-semantics.md — oxl→JS representation + runtime contract

The load-bearing contract for milestone W. It pins what emitted
JavaScript *means*: every representation choice a reader can
observe, every runtime obligation `rt.js` owes, and every place
the JS target deliberately diverges from native. Divergences are
named so a program that hits one fails loudly, not silently.

## 1. Type representation

| oxl type | JS representation | notes |
|---|---|---|
| `int` | `BigInt` | literals emit `123n`; all arithmetic routes `rt_i*` helpers applying `BigInt.asIntN(64, x)` — wrap-on-overflow preserved |
| `err` | `BigInt` | `0n` = nil; interned codes from the same `RT_ERR_BASE = 1<<20` FNV registry as rt.c, ported verbatim |
| `float` | `Number` | IEEE-754 double — identical to native |
| `byte` | `Number` masked `& 0xff` | cheap; only appears in byte slices + byte ops |
| `bool` | `boolean` | |
| `str` | `{u8: Uint8Array, off: Number, len: Number}` | UTF-8 byte view — §3 |
| `cstr` | JS `string` | extern-boundary only — §7 |
| `[]T` | `{a: Array, off: Number, len: Number, cap: Number}` | view semantics — §4 |
| `own T` / `ref T` / `mut T` | plain JS reference | GC owns lifetime; move rules compile-time — §9 |
| `struct` | plain object `{f0…}` or named fields | field access identical |
| `enum` | `{tag: Number, p0…}` | payload slots unrolled like rt.c's union |
| `chan` / `chan own T` | `RtChan`-analog object | §5 |
| `shared` | `{v: BigInt}` cell | single-threaded — `scas`/`sadd` trivially atomic |
| `scope` (handle) | scope object ref | §6 |
| fn value | JS closure `{env, fp}` or plain function | direct call |
| iface | `{obj, methods: {name: fn}}` | vtable → method-table object |
| `[v, err]` ret | `{val, err}` | destructured at callsites |
| extern fn | `__oxl_ffi.<name>` | §7 |
| nil | `null` (handles) / `{a:null,off:0,len:0,cap:0}` (slices) | |

`main` returns `int` → process exit code conversion happens in
`rt.js`'s entry (`node: process.exitCode`, browser: ignored).

### The `int`/`Number` firewall

Emission rule: **an oxl `int` is always a `BigInt` in emitted
positions** — locals, fields, args, returns, slice `len`/`cap`
surface reads via `rt_len` (returns BigInt). `Number` is legal
only *inside* runtime internals where JS demands it: array
indices, `length`, `setTimeout` ms, `off` fields, loop counters
that never cross an oxl-visible boundary. `rt_i*` helpers:

- `rt_iadd/sub/mul/div/mod/neg(a,b)` → `BigInt.asIntN(64, …)`
- `rt_ishl/shr(a,b)` → asIntN-64 shifts (b masked `&63n`)
- `rt_icmp*` → boolean
- `rt_itoa(i)` / `rt_i_from_str(s)` — strconv shims
- `rt_to_int(n)` / `rt_to_num(i)` — boundary casts (externs, §7)

Slice indices emitted as `rt_to_num(idx)` at the access — arrays
are Number-indexed; the check is `rt_trap(10)` on the BigInt
domain *before* narrowing.

## 2. Emit shape

`emit(r, testm) -> str` returns one ES-module text:

```js
import * as rt from './rt.js'
// … emitted declarations …
export function oxl_main() { … }
rt.__oxl_boot(oxl_main)   // entry: installs run queue, runs root
```

- `out.mjs` so `node out.mjs` works unconditionally; browsers
  load it via `<script type="module">`.
- `oxl run --target js` → `node <scratch>/out.mjs`; the sibling
  copies `rt.js` + `rt-node.js`/`rt-browser.js` come from the
  `runtime/` dir via the existing `runtime_dir()` probe.
- `rt.js` self-selects env: `typeof process !== "undefined"` →
  dynamic `import('./rt-node.js')` wiring before `oxl_main`;
  else `rt-browser.js` stubs. Selection happens inside
  `__oxl_boot` — `import` of the env file is the only
  conditional import in the system.
- testm=1 emits the same `test_*` wrapper pattern as C emit
  (each test in its own scope + `rt_scope_try`-equivalent).

## 3. `str` — byte substrate

`OxlStr { u8: Uint8Array, off: Number, len: Number }`.

- Literals: emitted as base64/`TextEncoder` init — `rt_str_lit`
  decodes once at module init into a shared backing buffer;
  views reference `(u8, off, len)`.
- `len(s)` → `s.len` (BigInt at surface). `byteat`/`s[i]` →
  `u8[off+i]` + `rt_trap(10)` bounds. `substr`/`s[i:j]` → new
  view on the same `u8` — O(1), aliasing like rt.c.
- `str as []byte` → `{a: s.u8-as-array-or-same-buffer, off,
  len, cap: len}` — byte-level identity preserved; `[]byte as
  str` → `{u8, off, len}` view. Mutation through the slice is
  visible through the str (same as native).
- `strcat`/`+` → concat into fresh `Uint8Array`.
- `streq` → `rt_streq` byte-compare (`u8` range compare, not
  `===` — views may differ in `off`).
- **`cstr`/edge decode**: `rt_str_cstr(s)` → `TextDecoder`
  utf-8 → JS string (used by `rt_print_str`, `rt_eprint_str`,
  `__oxl_ffi` str args, DOM set_prop). Encode back:
  `TextEncoder`. These two fns are the *only* legal UTF-16
  crossings — std code never sees a JS string.
- `println`/`print`/`eprintln` use `rt_print_str` → Node:
  `process.stdout.write(decoded)`; browser: `console.log`.

## 4. Slices — `{a, off, len, cap}`

- `a` is a JS `Array` (any elem) — or `Uint8Array` when the
  slice shares `str` storage (`[]byte` only).
- `mkslice`/`[]T{…}` literals: fresh array, `off=0`, `cap=len`
  (literal) or `cap≥len` (`mkslice`).
- `s[i]`: `rt_trap(10)` if `i<0 || i>=s.len`, else
  `a[off+rt_to_num(i)]`.
- `s[i:j]`: bounds-trap on i,j; `{a, off+i, len:j-i, cap:cap-i}`
  — **aliasing**: writes through the sub-view hit the parent.
- `push(s, v)`: if `len<cap` → `a[off+len]=v`, `len++` in place;
  else allocate `new Array(2*cap)` (or `max(4,2*cap)`),
  copy, `cap=2*cap`. Slice value is a *struct copy* — push
  returns/assigns like native (callers already treat `push`
  as a builtin that may re-seat).
- `own []T`: a boxed view — `{v: slice}` where `v` re-seats on
  grow; `*p` derefs to the view.
- `mkbuf`/`poke8`/`bufstr`/`mkshared`-adjacent byte-buffer
  builtins → `Uint8Array` + `{u8,off,len}` views.

## 5. Channels + select — `RtChan` analog

```js
chan = {
  buf: Array|null, head: 0, count: 0, cap: 0,   // ring
  has: false, val: null,                        // rendezvous slot
  sendq: [], recvq: [], selq: [],               // parked waiters
  closed: false,
  scope: Scope|null,                            // mkchan_scoped
}
```

- `drop_elem` thunks exist on `chan own T` but are **no-ops**
  (GC owns payloads). The field stays so codegen shape parity
  is mechanical.
- `send(ch,v)`/`recv(ch)` exist **only as poll forms** —
  `rt_send_poll`/`rt_recv_poll` port rt.c's state machines
  verbatim minus mutexes: READY delivers (buffered, parked
  receiver, or rendezvous slot), PENDING parks the task's
  continuation on sendq/recvq and returns `RT_PENDING`.
- Delivery order + claim/unlink invariants from rt.c are
  preserved: a parked waiter owns its node until claimed; a
  resumed loser unlinks. Single-threaded ⇒ no atomic ops, but
  **ordering is still the contract** — a parked send claimed
  by select must not double-deliver.
- `close(ch)`: delivers at most one deposited value to a
  parked receiver, marks closed, wakes all waiters; send on
  closed completes silently (payload GC'd — no drop needed);
  recv on closed+drained → `closed` result.
- `try_send(ch,v)`: `true` iff delivered (buffered slot, parked
  receiver, or empty rendezvous); `false` on full **or closed**
  — payload drops (GC; drop-on-false rule, see
  `docs/specs/2026-11-09-gui-layer/items/event-model.md`).
- select: per-arm waiter nodes on `selq`; readiness per rt.c
  (buffered / parked sends / rendezvous / closed); winner pick
  is **uniform random** among ready arms; losers unlink via
  `rt_select_arm` analog; `timeout` → `setTimeout` one-shot
  park; `else` → READY-immediate. Cancel of a timed select
  keeps refs alive until deadline (rt.c parity).

## 6. Scopes, tasks, defers, traps

- **Run queue**: `rq = []` drained by `queueMicrotask` (browser)
  or `setImmediate` (node) — each drained task polls once.
  `rt_run_root` drives the root frame until READY; when the
  queue empties with live parked tasks, the loop waits on
  timer/wake sources (node: natural event loop; it exits when
  nothing is pending — same termination rule as native).
- **Task**: `{poll, state, scope, wakes, defer_top}`; `go f()` /
  `spawn f()` / `goin(sc, f())` all emit frame tasks — *every*
  spawned call is a poll frame (there are no thread tasks).
- **Scope tree**: `{parent, children, tasks, chans, cancelled,
  err, name}`; `mkscope`/`curscope`/`sjoin`/`scancel` port the
  named-scope machinery; `smkchan` registers for teardown.
  `sjoin` is poll-form: joins parked children then completes.
- **Cancel**: `scancel` → subtree cancel wake — parked waiters
  claim-cancel (same order invariants as `scope_cancel_wake` in
  rt.c), defer stacks drain, `err` propagates to joiner.
- **defers**: per-scope LIFO thunk list, drained at scope leave
  and on cancel — same semantics, minus env-struct capture cost
  (closures capture directly).
- **`is_root()`** → always `true` on this target (every task is
  the main thread) — emitted as `rt_is_root` returning true.
- **Traps**: `rt_trap(code)` → `throw {__oxl_trap: code}`;
  caught at the task's spawn-scope boundary → cancels siblings,
  propagates `err` to joiner — the rt.c propagation, minus
  arena unwinding. `rt_scope_try` → try/catch wrapper. Codes
  are the rt.c set plus `21` = blocking surface unsupported.
- **No arenas, no ObjHdr, no borrow flags** (§9).

## 7. Externs — `__oxl_ffi`

Emitted: `extern fn name(args) -> [ret, err]` calls
`__oxl_ffi.name(mapped_args…)` and expects:

- plain return → the mapped ret value
- `[T, err]` → `{val, err}` (err: BigInt code or `0n`)

`__oxl_ffi` is `globalThis.__oxl_ffi` — `rt-node.js`/`rt-browser.js`
pre-fill the std set before `oxl_main` runs; user shims assign or
extend the same object.

Arg mapping (mirrors the checker FFI whitelist
`check.oxl:3873-3882`):

| oxl | JS at the boundary |
|---|---|
| `int`/`err`/`byte` | `BigInt`/`BigInt`/`Number` |
| `float` | `Number` |
| `bool` | `boolean` |
| `str` | JS `string` (decoded via `rt_str_cstr`) |
| `cstr` | JS `string` |
| `[]byte` | `Uint8Array` view |
| `[]T` other | `{a,off,len,cap}` (shims must respect views) |
| `own/ref/mut` | raw ref |
| `chan`/`shared`/scope/fn/iface | raw object |
| `own void` | raw ref — opaque handle convention |

Return mapping inverts the table; `{val, err}` for pair fns.

- **Node flavor** (`rt-node.js`): `rt_open_write`→`fs.openSync`,
  `rt_readfile`→`fs.readFileSync`, `rt_proc_*`→`child_process`,
  `rt_sock_*`→`net`+`dns` (lookup → shared cell callback),
  `rt_getenv`/`rt_argv`/`rt_exepath`/`rt_exit`→`process.*`,
  `rt_now*`→`Date.now`/`performance.now`, `rt_errstr`→string.
- **Browser flavor** (`rt-browser.js`): every name present as
  a stub — `err` returns where the contract allows, else
  `rt_trap(21)`. No unbound names: a missing shim is a contract
  violation, not a `TypeError`.

## 8. The blocking list (traps, not silence)

These emit `rt_trap(21)` on this target:

- `spawnBlocking f()` — any callee
- blocking `send`/`recv` positions that only thread tasks reach
  on native (non-susp fn bodies, trampolines) — the JS emitter
  emits poll forms everywhere, so this only fires where a
  poll form can't exist (raw extern call sites)
- `usleep` (deliberate blocking)
- `rt_sleep_poll`/`rt_msleep_poll` DO have equivalents —
  `setTimeout` + park; `msleep` in a susp context works

## 9. What erases

- `rt_alloc`/`rt_alloc_own` → `new`/`{}` (GC)
- `rt_free` → no-op
- `rt_borrow_read`/`rt_borrow_mut`/`rt_unborrow` → no-ops —
  borrow checks gate *call-arg aliasing*; under GC there is no
  scope-arena lifetime to protect. Move/consume rules stay
  compile-time (check unchanged).
- `ObjHdr`/per-task borrow lists → absent
- `rt_alloc` failure traps → absent (GC throws OOM → uncaught,
  same as native abort)

## 10. Test entry

`testm=1` emit wraps `test_*` fns in scope+try like the C path;
`oxl test --target js` execs `node out.mjs` and asserts the
same `test_x … ok` lines.
