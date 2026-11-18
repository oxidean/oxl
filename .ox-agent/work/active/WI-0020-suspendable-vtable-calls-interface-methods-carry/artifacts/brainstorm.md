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

## Refined options (extends the A/B fork)

| # | route | scope | notes |
|---|-------|-------|-------|
| A | **Suspendable vtable ABI — descriptor slots** | medium–large | For `susp`-marked iface methods, `vtab[i]` holds `{RtPoll poll, RtFrame* (*make)(void* data, args…)}` instead of a bare fn ptr — avoids touching the pinned `RtFrame{cur_scope,state}` header the LLVM spec makes contract. Call sites emit the factory→child→poll→result dance. Non-susp impls get trivial shim frames so structural satisfaction is preserved. Needs: new `susp` marker syntax (first susp surface syntax in the language — precedent-setting), check narrowing (guard only unmarked ifaces), `add_edge` on the iface-call path, both emitters, stage0 regen |
| B | **Document + sanctioned pattern** | small | The verified pattern: a sync iface method `spawn`s a susp fn and returns `{scope-handle, chan}`; caller `sjoin`/`recv`s. Async-by-handle, expressible today, strictly better than oxttp's raw `rt_*` externs. Optionally a `std/task` joinable wrapper |
| C | Narrow guard to materialized dispatch | small–medium | Only reject (iface, impl) pairs actually boxed somewhere. Murky contract; diagnostic becomes reachability-dependent |
| D | Blocking-drive shim thunk | medium | Thunk spawns impl frame as child task + blocking-join. Semantic downgrade (suspend→block, worker pinning) — weakest |
| E | Uniform susp ABI (marker-free A) | medium | Every slot a frame factory; per-call malloc on *all* iface dispatch — taxes io.Writer hot paths for zero API gain |

**Recommendation: B now, A as the milestone fix** (descriptor variant).
The descriptor keeps `RtFrame`'s header and the `poll(RtFrame*,
RtTask*)` protocol the LLVM spec pins — lowest blast radius. Avoid D
and E.

## Open questions for the maintainer

1. Descriptor-in-slot vs extending `RtFrame` with a `poll` field
   (touches the protocol LLVM pins as contract — descriptor preferred).
2. Marker syntax: new `susp` keyword on iface method decls sets
   precedent for fn-values later (`fn susp …` types?).
3. Satisfaction rule: shim frames for non-susp impls (recommended) or
   exact susp-match only.
4. Is the spawn+handle pattern the documented interim for v0.2, and
   does std want a `task`/joiner helper?
5. `spawn w.m()` under A — supported via factory + `rt_task_new_in`
   (same machinery) or excluded for v1.
