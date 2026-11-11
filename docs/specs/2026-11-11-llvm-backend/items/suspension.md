# items/suspension.md — suspension lowering: shared poll machines

The spec-level fork: does the LLVM lane lower susp fns to the same
`o_frm_*` frame struct + `o_poll_*` poll-driver state machines the C
lane emits, or does it use LLVM's native coroutine intrinsics
(`llvm.coro.*`) and let the optimizer split the frame?

**Decided: share the lowering.** The lane emits the same frame/poll
architecture in IR. `llvm.coro.*` is parked with a stated trigger.
This document is the contract for the shared lowering and the record
of the rejected fork.

## Why sharing is right for v1

- **The poll protocol is the semantic contract, not an
  implementation detail.** `docs/semantics/concurrency.md` pins it:
  `RtFrame { cur_scope, state }` header, `int poll(RtFrame*,
  RtTask*)` returning `RT_READY`/`RT_PENDING`/`RT_CANCEL`,
  `fr->child` inline child-poll, `tls_scope` save/restore around the
  driver, suspend points at statement boundaries only, `rt_task_new`
  one-alloc task+frame, `rt_run_root` driving the root. Every
  guarantee the concurrency suite exercises — scope join semantics,
  trap propagation into parked chains, orphan teardown, defer drain
  on cancel — is expressed in terms of this protocol. Sharing it
  means the L2 gate can claim *identical observable behavior* with a
  straight face: the executor, the scope tree, the chan/select
  machinery are the same bytes of rt.c for both lanes.
- **A coro lane needs a second executor protocol.** `llvm.coro`
  produces a compiler-managed frame + `coro.resume` handle; the
  suspend boundary is an intrinsic, the frame shape is
  optimizer-chosen, and resume is a different entry convention than
  `poll(RtFrame*, RtTask*)`. rt.c's executor would need a parallel
  dispatch path (or every coro frame wrapped in a poll shim — which
  reintroduces the poll machine on top of the coro frame, paying
  both costs). That is a runtime change for a codegen choice — the
  wrong direction of coupling for this lane, and a doubled
  conformance surface to prove.
- **The optimization case for coro is weaker than it looks.** The
  win LLVM coroutines advertise is automatic frame splitting and
  elision when a suspend never actually suspends. Our suspend
  points are already statement-level with a hand-known live set —
  the emitted `o_frm_*` field list IS the split, computed at emit
  time with checker knowledge (the `susp` set + live-local analysis)
  rather than recovered by a pass. The C lane's residual overhead is
  the `switch` resume dispatch and frame-slot memory traffic; IR
  already improves both (a real `switch` lowers to a jump table or
  bit-test tree the C compiler produced anyway; and everything
  *outside* the frame — the non-susp fn surface, temporaries, calls —
  is where the lane's optimization gain actually lives).
- **Determinism for the fixpoint.** Hand-lowered frames keep the
  emitted `.ll` a pure function of `CkRes` — required for L4's
  byte-identical IR fixpoint. Coro lowering output would still be
  deterministic, but the *frame layout* would move inside the
  compiler, making diff review of emitted text meaningless.

## The shared-lowering contract

For each susp fn `<qn>` the lane emits:

```llvm
%o_frm_<qn> = type {
    ptr,        ; cur_scope   ─┐ RtFrame header: field-for-field
    i32,        ; state       ─┘ boundary (rt.c reads via RtFrame*)
    ptr,        ; child       (RtFrame*)
    ptr,        ; _dmark      (RtDefer*)
    <valT|%o_ret_<qn>>, ; result — <valT> for single rets,
                ;            %o_ret_<qn> for pairs, absent for void
    <p_* params…>,
    <v* frame slots…>,
    <embedded aggregates…>,   ; o_s_/o_en_ values live at frame type
    [0 x i8]    ; scope tail  — dynamic stride, §5 of llvm-semantics
}

define i32 @o_poll_<qn>(ptr %_f, ptr %task) {
  ; prologue: cast _f, save tls_scope, restore fr->cur_scope
  ; dispatch: switch i32 %state, label %s0 [ i32 1, label %s1 … ]
  ; bodies: straight IR per segment; suspend points store the next
  ;         state, save fr->cur_scope, ret i32 1 (RT_PENDING)
  ; fallthrough: restore tls_scope, ret i32 0 (RT_READY)
  ; cancel observed at a suspend point: ret i32 2 (RT_CANCEL)
}
```

- State numbering, suspend-point placement (statement boundaries,
  hoisted expr-position susp calls into fresh slots), `cur_scope`/
  `tls_scope` save-restore choreography, scope-enter/leave/
  join_poll/finish call order, defer mark/drain windows, and the
  `fr->child` inline-poll idiom mirror `codegen.oxl`'s fsusp_*/fstmt
  emission — a reader must be able to line the two emissions up
  structurally.
- Resume dispatch is a `switch` on the `i32` state field (never
  `indirectbr` + `blockaddress` — the switch is simpler, optimizes
  equivalently at this state count, and keeps the `.ll` diff-stable).
- `result` embeds *by value* — `<valT>` for a single return,
  `%o_ret_<qn>` for a pair, absent for `void` — matching the C
  lane's three `res` spellings; child-completion reads it back
  through `fr->child`.
- Poll fns take the `(ptr, ptr)` `RtPoll` signature; `rt_task_new`'s
  `poll` argument is `@o_poll_<qn>` directly — no trampolines.
- Non-susp spawned fns keep the C lane's other path: `ptr(ptr)`
  args-struct thunks in the trampoline band, `rt_spawn`/`rt_spawnb`
  thread tasks — unchanged semantics (blocking pools are rt.c's).
- Suspendable generic instantiations emit only frames (no `o_f_`
  proto) — same as the C lane's `ginst_head` rule.

## The rejected fork, kept warm

`llvm.coro.*` (switch/returned-style splitting, `coro.id`/
`coro.suspend`/`coro.resume`/`coro.destroy`) would let LLVM own the
frame transform. The honest cost/benefit to reopen later:

- Would need: a coro-handle↔RtTask adapter in rt.c (or poll-shim
  wrappers), a second resume convention, liveness/escape re-audit
  for scope-arena allocations crossing suspend (coro elision must
  not break `rt_alloc`'s scope-lifetime contract), and a separate
  conformance argument — it is a second executor, not a faster
  frame.
- Trigger to reopen: a measured profile showing poll-dispatch or
  frame-slot traffic dominating a real workload beyond what
  mem2reg/regalloc recover on the shared lowering, OR an
  async-ABI consumer (C-interop await, wasm component model)
  that needs the standard coro shape. File it as a new spec;
  this one's contract stays the poll machine.
