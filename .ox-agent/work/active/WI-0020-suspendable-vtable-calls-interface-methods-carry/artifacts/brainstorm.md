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
