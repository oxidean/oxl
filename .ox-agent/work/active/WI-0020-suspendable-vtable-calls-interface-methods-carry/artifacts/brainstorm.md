# WI-0020 brainstorm — suspendable vtable calls (issue #135)

## The guard (deliberate, not a bug)

`check_run_tail` (check.oxl ~7832, "D3"): any method that suspends
(`ck.susp`) AND is vtable-reachable — its receiver type satisfies an
interface declaring that method name — is rejected:

    suspendable method `H1.send` — `H1` satisfies interface
    `Transport`; vtable calls carry no task frame

Direct calls to the same method suspend fine — the restriction is
specifically **indirect/vtable dispatch**, which has no task frame to
suspend into. The guard exists so the unsafe case fails at check time
rather than corrupting at runtime.

## What "task frame" means here

Suspension (`dial_timeout` → `lookup_ipv4` → `msleep`) needs per-task
state: the frame that resume re-enters. Direct calls know the callee
statically → codegen emits the suspend/resume plumbing. Vtable calls
go through a function pointer whose target is unknown at the call
site → today there is no ABI for "this indirect callee may suspend".

## Forks

| option | shape | tradeoff |
|---|---|---|
| **A. suspendable vtable ABI** | every iface method slot carries task-frame metadata; indirect call sites get the same suspend plumbing as direct calls | the real fix; touches iface codegen (c2-iface spec), rt task switching, every call site. Milestone-scale |
| **B. constraint split** | suspending ops move OFF iface methods onto free fns / concrete types; ifaces stay synchronous by contract | documents today's boundary as design; oxttp's workaround (raw rt_* externs + usleep) becomes the sanctioned pattern but stays ugly |
| **C. hybrid: async iface tier** | a second iface flavor whose methods are declared suspendable, dispatched through a task-aware shim | two dispatch ABIs to maintain; probably worse than A |

## Recommendation

A is where the language wants to go (seam interfaces like
`Transport`/`io` SHOULD be able to wrap suspending std calls — that's
their purpose). B is the honest interim: document that iface methods
are synchronous-by-contract and suspending seams take concrete types
or callback-style free fns. oxttp's extern workaround should NOT be
the documented pattern — B needs a std-level answer (e.g. non-suspending
lookup/dial variants, or `Shared`+poll primitives).

## Dependencies

- c2-iface-codegen spec (`docs/specs/2026-11-05-c2-iface-codegen`) —
  vtable layout is specified there; A revises it.
- Task/frame machinery from the concurrency runtime (rt.c BorrowEnt/
  task switching) — the frame side already exists for direct calls.

## Open questions for spec

- Does the vtable slot need a per-method suspend bit, or does every
  indirect call pay the frame cost?
- Can a suspending iface method call ANOTHER suspending iface method
  (nested indirect suspension)?
- Interaction with `spawn` — a suspending method inside a spawned
  task vs the parent frame.

## Deep dive (2026-11-18 analysis) — the actual ABI gap

The gap is deeper than "no frame slot": suspending functions emit **no
callable symbol at all**.

- C lane emits only `struct o_frm_<n>` (heap frame:
  `{RtScope* cur_scope; int state; RtFrame* child; RtDefer* _dmark;
  <ret> result; p_<params>…; v<locals>…}`) + `int o_poll_<n>(RtFrame*,
  RtTask*)` — the `o_f_<n>` prototype is skipped (codegen.oxl:1441).
- Direct susp call emits (gfsusp_call, codegen.oxl:4206–4278): malloc
  the statically-known frame type → fill `p_` slots → `fr->child` →
  `o_poll_<n>` → propagate PENDING/CANCEL → read `result` → free.
- Vtable call emits `((ret (*)(void*, args…))_iv.vtab[i])(_iv.data,
  args)`; thunks `o_vtt_*` forward to `o_f_*` — **which does not exist**
  for a susp impl. A `void**` slot can neither name the poll driver
  nor allocate/fill the impl's frame (size + `p_` layout unknown at
  the call site).

Same boundary as `RtFnv` fn-values ("suspendable fn can't be a value",
check.oxl:8081–8090; docs/semantics/fnvals.md). **Uniform rule: no
indirect call in oxl has a suspend ABI.**

Also verified: the guard fires on **potential** satisfaction, not
materialized dispatch — declaring an iface is enough even if the type
is never boxed into it. And the `mt.k == 2` (`call_iface`) path returns
before `add_edge`, so suspendability could not propagate through
vtable calls even without the guard.

## Prior art (2026-11-18) — how Go and Rust answer this

**Go: hide suspension by owning the stack.** No async functions, no
suspend ABI. Every call — direct or through an interface — is an
ordinary indirect call; suspension is a runtime property invisible at
the call site. A blocking channel op, mutex, or net read calls
`gopark`, switching the M:N (GMP) scheduler to another goroutine; the
callee's state lives on its ordinary growable stack and netpoller wires
fd readiness to resumption. `w.Write(b)` on an `io.Writer` whose impl
blocks Just Works — the vtable has zero suspend awareness because
nothing about the call is special. The cost is enormous and invisible:
segmented/growable stacks, a cooperative+preemptive scheduler,
per-goroutine stack maps for the GC — a multi-year runtime investment
oxl should not replicate. Both emit lanes (C, JS) target environments
without growable stacks; a Go-shaped model would need stackful
coroutines (ucontext/asm) per lane.

**Rust: expose suspension as a poll-ABI on a state machine.**
`async fn` desugars to a compiler-generated state machine returning
`impl Future`; the contract is `poll(&mut self, cx) -> Poll<T>`
(`Ready`/`Pending`) driven by an external executor, wakers handle
re-enqueue, futures are cold. Rust hit exactly the #135 wall: `async
fn` in traits was uncallable via `dyn` for years — each impl's future
type differs in size/layout, so a vtable cannot return it. The
ecosystem's answer (`async_trait`) is uniform boxing: the slot returns
`Pin<Box<dyn Future>>` and the suspension plumbing rides through the
*future's own* vtable (its `poll`), not the trait's. Sync impls get a
trivially-Ready wrapper future. Native `async fn` in traits (Rust 1.75)
remains static-dispatch only; `dyn` async is still unstable for exactly
this reason.

**oxl is already Rust-shaped.** The mapping is nearly literal:

| oxl | Rust |
|---|---|
| `o_poll_<fn>(fr, t)` + `RtFrame{cur_scope, state}` | `Future::poll` + generated state machine |
| `RtTask` + worker pool | the executor |
| `RT_PENDING` + wait-queue re-enqueue | `Pending` + waker (`t` is the `cx`; no waker object needed) |
| `fr.child` + `case K:` resume | the parent state machine's *inline* child future — unboxed, statically typed |

The missing piece is exactly `Pin<Box<dyn Future>>`: a vtable slot
carrying a **pollable descriptor instead of a fn pointer**.

Rejected alternative: the JS lane could emit native `async`/`await`
and let the engine own suspension — but the C lane has no equivalent,
and lane parity argues for the manual poll driver everywhere.

## Concrete A design (descriptor slot)

For a `susp`-declared iface method, `vtab[i]` holds
`{RtFrame* (*make)(void* data, args…), RtPoll poll}` instead of a bare
fn pointer:

- `make` — per-impl shim with the signature's real param list.
  Allocates the concrete `o_frm_<n>`, fills `p_` slots, returns it
  erased as `RtFrame*`. Solves "call site doesn't know the frame
  layout" the way `Box<dyn Future>` does.
- Call site — emits the same suspend-point machinery as
  `gfsusp_call`/`jfsusp_call` today, except `fr->child` becomes
  `{RtFrame* f; RtPoll p}` and the poll line goes through `p` instead
  of `o_poll_<cn>`.
- Sync impls — an auto-shim `make` allocates a minimal frame whose
  `poll` runs the body once and returns `RT_READY` — the `async_trait`
  ready-wrapper. Structural satisfaction preserved.
- `susp` — part of the iface method signature: the *declaration* fixes
  the calling convention, not the impl (Rust precedent: `async` is part
  of the fn type). The D3 guard becomes an ordinary signature-mismatch
  check.
- Cost — one heap alloc per susp-iface call + indirect polls —
  identical to `async_trait`'s box. Direct susp calls keep the
  zero-alloc inline child frame.
- Earlier open questions resolve: the slot is descriptor-typed *per
  signature* (no per-method bit — declared susp-ness decides); nested
  indirect suspension is free (child frames chain); `spawn w.m()`
  excluded for v1 (Rust likewise requires materializing the future
  before spawning).

## Refined options (extends the A/B fork)

| # | route | scope | notes |
|---|-------|-------|-------|
| A | **Suspendable vtable ABI — descriptor slots** | medium–large | For `susp`-marked iface methods, `vtab[i]` holds `{RtPoll poll, RtFrame* (*make)(void* data, args…)}` instead of a bare fn ptr — avoids touching the pinned `RtFrame{cur_scope,state}` header the LLVM spec makes contract. Call sites emit the factory→child→poll→result dance. Non-susp impls get trivial shim frames so structural satisfaction is preserved. Needs: new `susp` marker syntax (first susp surface syntax in the language — precedent-setting), check narrowing (guard only unmarked ifaces), `add_edge` on the iface-call path, both emitters, stage0 regen |
| B | **Document + sanctioned pattern** | small | The verified pattern: a sync iface method `spawn`s a susp fn and returns `{scope-handle, chan}`; caller `sjoin`/`recv`s. Async-by-handle, expressible today, strictly better than oxttp's raw `rt_*` externs. Optionally a `std/task` joinable wrapper |
| C | Narrow guard to materialized dispatch | small–medium | Only reject (iface, impl) pairs actually boxed somewhere. Murky contract; diagnostic becomes reachability-dependent |
| D | Blocking-drive shim thunk | medium | Thunk spawns impl frame as child task + blocking-join. Semantic downgrade (suspend→block, worker pinning) — weakest |
| E | Uniform susp ABI (marker-free A) | medium | Every slot a frame factory; per-call malloc on *all* iface dispatch — taxes io.Writer hot paths for zero API gain |

**Recommendation: A — descriptor slot — implemented in one run.**
Prior art confirms the shape: the gap is precisely `Pin<Box<dyn
Future>>`, and descriptor-in-slot is its oxl analog. The descriptor
keeps `RtFrame`'s header and the `poll(RtFrame*, RtTask*)` protocol the
LLVM spec pins — lowest blast radius. B's spawn+handle pattern is still
worth a doc line as today's workaround, but need not gate the
milestone. Avoid D and E.

## Open questions for the maintainer

1. ~~Descriptor-in-slot vs extending `RtFrame` with a `poll` field~~ —
   resolved by the concrete design: descriptor-in-slot (the LLVM spec
   pins `RtFrame`'s header as contract).
2. Marker syntax: new `susp` keyword on iface method decls sets
   precedent for fn-values later (`fn susp …` types?). [rec: `susp`
   keyword — mirrors Rust `async` being part of the fn type]
3. ~~Satisfaction rule~~ — resolved: shim frames for non-susp impls
   (the `async_trait` ready-wrapper analog; structural satisfaction
   preserved).
4. Is the spawn+handle pattern the documented interim for v0.2, and
   does std want a `task`/joiner helper? (Still worth a doc line even
   under A-now.)
5. `spawn w.m()` under A — [rec: excluded for v1; Rust likewise
   requires materializing the future before spawning].
