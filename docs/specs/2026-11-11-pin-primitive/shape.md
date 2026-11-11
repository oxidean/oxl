# `pin` primitive — address-stable values — Shaping Notes

## Scope

The parked `pin` work item, scoped by its trigger: "FFI or IO needs
address-stable values (OS async handles, self-referential own
graphs)." This spec resolves the fork that scope line leaves open —
is `pin` a language-level primitive or a guarantee the runtime
already gives — and pre-decides the design so a fired trigger lands
implementation, not redesign.

Not this spec: task-to-thread pinning (`spawnPinned`, the `is_root`
machinery — a different axis, already resolved), async IO itself,
typed self-referential structures, a moving allocator of any kind.

## Two different `pin`s — disambiguation first

`pin` names two orthogonal guarantees in this design space, and the
repo already settled one:

- **Task-to-thread** — "this task never leaves its OS thread." The
  GUI milestone parked it as a primitive and resolved it as a
  mechanism: `rt_run_root` drives the root task on the entry thread
  with its own park loop, so "root-task-only IS the pin"
  (`docs/specs/2026-11-09-gui-layer/items/backend-protocol.md`,
  `docs/gui-backends.md` §"The `pin` question, revisited" — verdict:
  stay parked; no shipped backend needs a dedicated non-main
  thread). `spawnPinned` remains a reserved word
  (`docs/semantics/concurrency.md`).
- **Value-to-address** — "this object never relocates and is never
  reclaimed while a foreign consumer holds its address." That is
  this spec. The two share nothing but the metaphor: a pinned task
  stays on a thread; a pinned value stays at an address.

## Evidence

The allocation model (`runtime/rt.c`, `docs/semantics/ownership.md`)
already decides most of the question:

- **Nothing user-visible relocates.** `rt_alloc` bump-allocates into
  a scope arena (`alloc_in`, rt.c:70); `rt_alloc_own` always
  `malloc`s (rt.c:106). There is no compactor, no moving GC — the
  language principles forbid one ("No tracing GC",
  `docs/standards/global/language-principles.md`). Susp-fn locals
  live in a single `[RtTask][frame]` block (`rt_task_new`,
  rt.c:987) that never moves for the task's life. `xrealloc`
  touches only rt-internal buffers (env-merge, rt.c:3799), never
  oxl-visible storage.
- **Address stability and liveness are different questions.** Every
  `own` object is address-stable for its whole life *by
  construction*. What can end that life: `rt_free` (reachable from
  C — `rt_str_free` precedent in `extra/gui/gtk`), `drop_elem` on a
  `chan own T` (teardown, close-drain, retracted `try_send` —
  rt.c:1507-1666, codegen `o_drop_*`), and process exit. Arena
  objects die wholesale at scope close, but nothing `own`-typed is
  arena-backed.
- **One real relocation exists:** `rt_slice_push` growth allocates a
  new backing and `memcpy`s (rt.c:2515) — a pointer into the old
  backing dangles. `rt_slice_own` gives an `own []T` a boxed header
  + private heap backing (rt.c:2532) — two pinnable blocks.
- **The FFI boundary retains nothing today.** Full survey:
  `extra/gui/gtk` passes opaque int handles and heap-copies closures
  (the pilot's `gui_connect` pattern — C copies the `RtFnv`, frees
  it on destroy-notify); `std/net` passes fds and `RtSlice`s
  synchronously (`rt_sock_read`, rt.c:3661); `std/os/exec` drains
  child output into C-owned buffers and copies back
  (`rt_proc_output`); `rt_lookup_start` `memcpy`s the host string;
  sqlite builtins are synchronous. Every pointer that crosses is
  borrow-for-duration — legal only because the call is synchronous
  and the caller's scope outlives it (spawn-arg rules already bar
  `[]T`/`ref`/`mut` from escaping into tasks, check.rs:2530).
- **JS lane** (`docs/specs/2026-11-10-web-target/js-semantics.md`,
  on `feat/milestone-w`): `own`/`ref`/`mut` map to raw refs,
  `[]byte` to a shared `Uint8Array` view, externs to
  `__oxl_ffi.<name>`. Objects have no addresses; GC retention makes
  pinning trivially true. `pin` is a ledger entry there, not a
  guarantee.

## The fork, resolved: rt-level guarantee + parked language surface

**Address stability is already an rt-level guarantee — the language
primitive is only about *checked retention*, and it stays parked on
the consumer trigger.**

Decomposed, `pin` would deliver three things:

1. **Non-moving placement.** Exists. `rt_alloc_own` never relocates;
   `mkbuf` already hands FFI a stable, own-heap buffer (rt.c:2622).
   What is missing is only that the guarantee is *unwritten* —
   `ownership.md` never promises non-moving placement, so a consumer
   cannot tell stability is contractual rather than incidental.
   Plan stage P1 writes it down; that is documentation, not a
   primitive.
2. **Reclaim protection while a foreign consumer holds the
   address.** Partially exists — an `own` object outlives any scope
   and is freed only by `rt_free`/`drop_elem`. But nothing stops a
   `rt_free` from C bookkeeping, or a `chan own T` teardown drop,
   while a retained pointer is still live. The honest check is a
   per-object pin count `rt_free` refuses to run against — runtime
   machinery, small and parked.
3. **Checked retention.** The actual hole: today *any* pointer arg
   to *any* extern may be retained by C — nothing in the decl or the
   checker distinguishes "borrow for the call" from "keep this."
   Closing it needs language surface: a `pin` param qualifier that
   declares retention at the boundary, and `pin`/`unpin` builtins
   the checker tracks so a pinned `own` cannot move into a death
   path. This is the primitive the roadmap means — and it is pure
   contract enforcement: oxl's convention is that escaping data is
   explicit, and foreign retention is exactly the class of escape
   the checkers exist to police.

So the fork resolves asymmetrically: the *capability* (a stable,
long-lived address) is already an rt-level guarantee — it lands as
written contract, not new machinery. The *enforcement* (compiler-
checked retention) is a small language surface, correctly parked
until a consumer needs it, because without one the qualifier is
surface with no user. Both halves are designed below so that a
fired trigger is implementation work, not a design debate.

## The design (pre-decided for the trigger)

```oxl
b := mkbuf(4096)            // any `own T` binding
pin(b)                      // stmt builtin — mark pinned
rt_aio_write(fd, b)         // extern fn rt_aio_write(fd: int, b: pin own void)
//   ...completion arrives via chan/select — the normal oxl way...
unpin(b)                    // stmt builtin — release
```

- **`pin(x)` / `unpin(x)`** — statement builtins in the
  `mkshared`/`mkbuf` family. `x` must be an `own T` binding (the
  object, not a view — `pin` requires `own` precisely because only
  `own` can outlive its scope; arena/`ref`/`mut`/borrowed `[]T` are
  compile-time rejects). Checker keeps a `pinned` set riding `env`
  next to `moved`; while a binding is pinned, every `own` move site
  (`send`/`try_send`, `own` arg, `return`, field store,
  `spawn`/`goin` arg) is a compile error — the lexical owner must
  not hand the handle to machinery that could drop or free the
  object. A pinned binding going out of scope is legal: the object
  stays pinned and allocated; release then belongs to `rt_unpin`
  from C or is a contract-level leak (v0 leak tolerance).
- **rt** — `ObjHdr.pinned` count (the `_pad` byte, ownership.md:78);
  `rt_pin`/`rt_unpin` exports (C-callable, like `rt_free`);
  `rt_free` and the `drop_elem` path on a pinned object trap — new
  trap code 11. `own []T` pins header *and* backing
  (`rt_pin_slice`); `push` on a pinned slice binding is a compile
  error (growth would relocate the pinned backing).
- **`pin` qualifier** — `pin own T` legal on `extern fn` params
  only (v0): the decl declares "this callee retains." Arg must be a
  pinned `own` binding — an rvalue or unpinned arg is a compile
  error. ABI-erased like `own` (a `void*` either way); rejected on
  non-extern params, returns, fields, and locals.
- **Semantics detail** in `items/pin-semantics.md`; the FFI
  contract, consumer survey, and the trigger test in
  `items/ffi-boundary.md`.

## Key decisions

- **Builtin pair + lexical pin-set over a `Pin<T>` wrapper type.**
  oxl's ownership checks are deliberately dynamic (borrow flags,
  per-task ledgers, moved-marks); pin rides the same machinery. A
  linear pin-token type would be a new type-system concept with no
  precedent — `ref`/`mut` can't be stored, `own` moves are marks,
  and `pin T` objects would need every one of those rules re-
  derived. Dynamic mark + move-freeze is ~30 lines per checker and
  matches how the language already thinks.
- **`pin` qualifies only `own`.** `pin ref`/`pin mut` ask to pin a
  borrow — meaningless: the lender owns the referent's life. `pin
  own` alone is the honest contract: the pinning site must own.
- **Release may come from either side.** `unpin(b)` from oxl after
  observing completion, or `rt_unpin(ptr)` from the C shim inside
  its completion callback — the pin count reaching zero is the only
  invariant; double-release traps (code 11).
- **Pin does not freeze content.** `s[i] = v`, field writes,
  `ref`/`mut` borrows of a pinned object stay legal — the guarantee
  is location + liveness, not immutability.
- **No consumer, no merge.** The survey found zero retained
  pointers — every boundary is synchronous with copy-or-borrow
  semantics. P2+ in `plan.md` implement only when the trigger test
  fires (first extern decl in-tree that retains a caller pointer
  past return — OS async IO is the expected case).
- **Task migration is a non-issue — say so plainly.** A suspended
  task resumes on whichever worker dequeues it, but frames and
  objects are heap blocks; migration never relocates a value. What
  moves under task machinery is *ownership* (send/spawn-arg moves)
  — exactly what the pin-set forbids while pinned. Thread-affinity
  consumers (GTK) are the other axis entirely — `is_root` already
  covers them.

## Non-goals

- Task-to-thread pinning — resolved/parked above (`spawnPinned`
  stays reserved).
- A moving or compacting allocator — principles forbid; pin assumes
  non-moving placement and would have no meaning otherwise.
- Typed self-referential structures — pin supplies the stability
  half; a `&`/raw-`ptr` surface or `Pin`-style wrapper that makes
  intra-graph pointers typeable is out of scope (see
  `items/ffi-boundary.md` §self-referential graphs).
- Pinning views — `str`, borrowed `[]T`, `ref`/`mut`, arena objects:
  rejected by construction (`pin` requires `own`).
- Reclamation of abandoned pins — a pin with no releaser leaks like
  any `own` today; leak-reporting machinery is its own item.
- `pin` outside extern params (returns, fields, locals, non-extern
  params) — rejected v0; a later spec may extend.
- Async IO, io_uring, OVERLAPPED, a callback-registry FFI — the
  consumers that would fire the trigger, not this spec.

## What stays parked, and the reopen trigger

The `pin`/`unpin` builtins, the `pin` extern qualifier, the ObjHdr
pin count, and trap 11 — all parked behind one trigger, defined in
`items/ffi-boundary.md`: **the first extern decl merged anywhere in
the tree (`std`, `extra`, `examples`, or an `rt_*` shim) whose
contract retains a caller-supplied pointer past the call's
return.** At that PR the whole surface lands at once (it is one
reviewable unit) — not before. P1's contract documentation is free
of the trigger: it writes down a guarantee that already holds, and
may land any time.
