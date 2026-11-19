# WI-0020 spec — suspendable vtable calls via descriptor slots (issue #135)

Route: **A — descriptor-slot suspendable vtable ABI** (IN-0003, answered by
jesse: "include this ABI inside this run"). Sub-decisions as recommended:
descriptor-in-slot, ready-shim frames for sync impls, `susp` marker syntax,
`spawn w.m()` excluded for v1.

## 1. Problem

Suspending fns emit **no callable symbol**: the C lane emits only
`struct o_frm_<n>` + `int o_poll_<n>(RtFrame*, RtTask*)` (the `o_f_<n>`
prototype is skipped, codegen.oxl:1441). Vtable dispatch is a bare fn
pointer `((ret (*)(void*, args…))_iv.vtab[i])(_iv.data, args)` — it can
neither allocate the impl's frame nor name its poll driver. Checker's
D3 guard (check.oxl:10253) rejects every susp method on an
iface-satisfying receiver. This WI gives indirect calls the same
suspend plumbing direct calls have — the oxl analog of Rust's
`Pin<Box<dyn Future>>` (`async_trait`), per the prior-art analysis in
brainstorm.md.

## 2. Surface syntax

`susp` marks an interface method as suspendable:

```oxl
interface Transport {
    susp send(b: bytes) -> (int, err),
    recv() -> bytes,
}
```

- `susp` is a **contextual marker inside `interface {}` bodies only** —
  NOT a new keyword. `susp` cannot join `is_kw` (parser.oxl:58): the
  checker field `ck.susp` is used hundreds of times and keyword-ifying
  would break every `.susp` field access. The interface-body parser
  (parser.oxl:1283–1304) accepts an optional leading `susp` ident
  before a method name: `susp` followed by an ident is the marker;
  `susp(` directly is a method literally named `susp`.
- `Node.Method` gains `susp: int` (0/1); `IMethod` gains `susp: int`
  (check.oxl:333); the `Node.Method` → `IMethod` conversion
  (check.oxl:4369) copies it.
- This is the first `susp` surface syntax — precedent for fn-value
  types later (`fn susp(…)`) using the same contextual-marker approach.

## 3. Semantics

- **`susp` is part of the method signature** — the *declaration* fixes
  the calling convention (Rust precedent: `async` is part of the fn
  type), not the impl. Satisfaction matrix:

  | iface method | impl method | result |
  |---|---|---|
  | `susp` | susp (inferred) | OK — real susp dispatch via descriptor |
  | `susp` | sync | OK — ready-shim frame (async_trait analog) |
  | non-`susp` | sync | OK — today's thunk |
  | non-`susp` | susp | **reject** — signature mismatch |

- A call through an iface value to a `susp`-declared method **makes the
  caller susp** — it suspends whenever the impl does (or never, for
  shim'd sync impls). Propagation is by declaration, not impl: the
  caller is susp even if the dynamic impl turns out sync.
- The D3 post-pass (check.oxl:10230–10255) is reframed: instead of
  banning every susp method on an iface-satisfying receiver, it bans
  susp impls matched to **non-`susp`** iface methods. The diagnostic
  points at the fix: `` suspendable method `T.m` — `T` satisfies
  interface `I` whose method `m` is not declared `susp` — add `susp`
  to `I.m` or make `T.m` non-suspending ``.
- `impl_satisfies` (check.oxl:2911) stays susp-oblivious — `ck.susp` is
  only final after the susp-analysis fixpoint, which runs post-check;
  the post-pass guard keeps the unsafe pair out of codegen.
- Structural satisfaction is preserved: a sync impl still satisfies a
  `susp` iface method (via shim), so existing code that boxes sync
  impls into a newly-`susp` iface keeps compiling.

## 4. Checker changes

- `IMethod.susp` parsed + stored (see §2).
- **Susp propagation**: `ck.susp` is seeded with `Iface.m` for each
  `susp`-declared method at iface registration (qualified names,
  disjoint from real fns — `ck.fns` never contains them). The
  call-check path adds `add_edge(ck, mt.q)` for `mt.k == 2`
  (check.oxl:3359ff, currently skipped) so the fixpoint marks the
  caller susp when `mt.q` is a seeded susp iface method. Seeding
  `ck.susp` directly is safe for the D3 scan: `Iface.m`'s "receiver"
  is the iface itself, which fails `impl_satisfies` early (no
  `Iface.m` in `ck.fns`), so no false diagnostic.
- **`goin`/`spawn` gate** (check.oxl:6685 `goin_stmt` + the 6696 susp
  gate): a spawned call whose method target is `mt.k == 2` AND the
  iface method is `susp`-declared is rejected for v1 —
  `` `goin`/`spawn` on a vtable susp call isn't supported yet — wrap
  the call in a susp fn and spawn that ``. (The descriptor machinery
  would make this nearly free later — `rt_task_new(sd->poll, …)` —
  but v1 excludes it per IN-0003.)
- `call_seeds`/`expr_susp` (6836+): unchanged for v1 — the syntactic
  scan can't see receiver types; semantic propagation via edges covers
  caller-susp marking, and the goin gate is handled above.

## 5. Runtime (runtime/rt.h)

New public type beside `RtPoll` (rt.h:135):

```c
typedef struct {
    RtPoll poll;      /* drive the child frame */
    void  *make;      /* RtFrame *(*)(void *data, <sig args…>) — cast per sig */
    size_t res_off;   /* offsetof(<impl frame>, result); 0 when retk==0 */
} RtSuspDesc;
```

- `res_off` uses `offsetof` → rt.h gains `#include <stddef.h>` (the
  emitted TU includes only `"rt.h"`, codegen.oxl:5941).
- `make` is type-erased like today's `vtab[i]` slots; the call site
  casts it to `RtFrame *(*)(void*, <params…>)`.

## 6. C codegen

### 6.1 vtab slot content

For a `susp`-declared iface method, the vtab slot for every
(impl, iface) pair stores `&o_vsd_<w>_<impl>_<i>` (a `static const
RtSuspDesc`) instead of an `o_vtt_*` thunk fn pointer. `void **vtab`
is unchanged — the slot is just `void*`.

### 6.2 Descriptors per pair (gemvtab_one, codegen.oxl:5460+)

**Susp impl** (impl's `m` ∈ ck.susp):

```c
static RtFrame *o_vsm_<w>_<impl>_<i>(void *_d<, sig params>) {
    struct o_frm_<impl.m> *_c =
        (struct o_frm_<impl.m> *)malloc(sizeof(struct o_frm_<impl.m>));
    ((RtFrame *)_c)->cur_scope = tls_scope;
    ((RtFrame *)_c)->state = 0;
    _c->p_<recv> = (<recv ty>)_d;   /* same erased-recv normalization as o_vtt_ */
    _c->p_<a0> = a0; …
    return (RtFrame *)_c;
}
static const RtSuspDesc o_vsd_<w>_<impl>_<i> = {
    o_poll_<impl.m>, (void *)o_vsm_<w>_<impl>_<i>,
    offsetof(struct o_frm_<impl.m>, result)   /* 0 when retk==0 */
};
```

Generic impls: same shape with `ginst_name`-mangled frame/poll names
(the `gvtab_bind`/`ginst_queue` path already produces them).

**Sync impl in a `susp` slot — ready-shim**:

```c
struct o_shf_<impl>_<m> {          /* minimal shim frame */
    RtFrame _h;                    /* must be first (RtFrame header) */
    <ResTy> result;                /* omitted when retk==0 */
    <recv ty> p_<recv>; <pty> p_<a0>; …
};
static int o_shp_<impl>_<m>(RtFrame *_f, RtTask *task) {
    struct o_shf_<impl>_<m> *f = (struct o_shf_<impl>_<m> *)_f;
    f->result = o_f_<impl.m>((<recv ty>)f->p_<recv>, f->p_<a0>, …); /* retk==1 */
    /* retk==2: struct o_ret_<impl.m> _r = o_f_<impl.m>(…);
       f->result = (<o_vret ty>){ _r.val, _r.err }; — same {val;err} layout */
    /* retk==0: just the call */
    return RT_READY;
}
static RtFrame *o_shm_<impl>_<m>(void *_d<, sig params>) { alloc + fill; }
static const RtSuspDesc o_vsd_<w>_<impl>_<i> = {
    o_shp_<impl>_<m>, (void *)o_shm_<impl>_<m>,
    offsetof(struct o_shf_<impl>_<m>, result)
};
```

**iface→iface rewrap** (`impl == "iface:<w2>"`): the inner desc is only
known from the inner iface *value*, so the outer desc is a forwarder
pair over a wrapper frame:

```c
struct o_wf_<w>_<i> {
    RtFrame _h;
    RtFrame *inner;
    const RtSuspDesc *isd;
    <ResTy> result;
};
static RtFrame *o_wmk_<w>_<i>(void *_d<, sig params>) {
    RtIface *_iv = (RtIface *)_d;
    struct o_wf_<w>_<i> *w = malloc(sizeof *w);
    w->isd = (const RtSuspDesc *)_iv->vtab[j];      /* j = inner midx */
    w->inner = ((RtFrame *(*)(void*<,sig>))w->isd->make)(_iv->data, args);
    ((RtFrame *)w)->cur_scope = tls_scope; ((RtFrame *)w)->state = 0;
    return (RtFrame *)w;
}
static int o_wp_<w>_<i>(RtFrame *_f, RtTask *t) {
    struct o_wf_<w>_<i> *w = (struct o_wf_<w>_<i> *)_f;
    int p = w->isd->poll(w->inner, t);
    if (p == RT_READY) {
        w->result = *(<ResTy>*)((char *)w->inner + w->isd->res_off);
        free(w->inner);
    }
    return p;
}
```

### 6.3 Call site (susp iface method)

Inside a susp fn, `w.m(args)` where `w: Iface` and `m` is `susp`
emits the `gfsusp_call` shape (codegen.oxl:4206) with two deltas —
the descriptor comes from the vtab and the poll/result access go
through it:

```c
{ RtIface _iv = <recv expr>;
  fr->vsd<N> = (const RtSuspDesc *)_iv.vtab[<midx>];
  { RtFrame *_c = ((RtFrame *(*)(void*<, argtys>))fr->vsd<N>->make)(_iv.data<, args>);
    fr->child = _c; fr->state = <k>;
  }
s<k>: ;
  _p = fr->vsd<N>->poll(fr->child, task);
  if (_p != RT_READY) { fr->cur_scope = tls_scope; tls_scope = saved; return _p; }
  <borrow-post / result bind — see below>
  free(fr->child);
}
```

- `fr->vsd<N>`: per-call-site frame field `const RtSuspDesc *vsd<N>;`
  appended to `g.fdecls`/`g.sdecls`-style field lists of the enclosing
  `o_frm_<cur>` (fields join the struct decl at codegen.oxl:5113;
  `N` = per-fn counter `g.vsdn`). Assigning `vsd` before `fr->state`
  persists the descriptor across suspensions.
- Result readback (`res_off`):
  - retk==0: nothing (res_off is 0).
  - retk==1: `<ty> _r = *(<ty> *)((char *)fr->child + fr->vsd<N>->res_off);`
    then bind per `dk` (`fr->da` / local).
  - retk==2: `struct o_vret_<w>_<m> _r = *(struct o_vret_<w>_<m> *)
    ((char *)fr->child + fr->vsd<N>->res_off);` — `o_vret_<w>_<m>`
    ({val; int64_t err}) is already emitted per (iface, method) at
    codegen.oxl:5639 and matches the impl frame's `o_ret_<impl.m>`
    layout; destructure `_r.val` / `_r.err` per `dk`.
- Borrow marks (`gav_borrows` pre/post) apply exactly as in
  `gfsusp_call` — the same single-eval and borrow-tracking rules.
- Arg fills use `gav_decl` resolved against the *iface signature*
  (`mt.ps`), not an impl decl — receiver is the iface value itself
  (evaluated once into `_iv`).

### 6.4 Ordering requirement

The `susp` iface call may only appear where the existing susp-call
emit is legal (inside susp fns / susp blocks); a sync fn calling one
becomes susp by propagation (§4) so the emit path always runs in a
frame context.

## 7. JS lane (bootstrap/codegen/js.oxl)

Mirror at `jfsusp_call` (js.oxl:2245) and the vtab emit:

- Susp vtab slots become `{m: makeFn, p: pollFn}`-shaped entries (JS
  frames are duck-typed; `result` is a fixed property name so no
  `res_off` is needed).
- Call site emits the same child/poll/resume state sequence as
  `jfsusp_call`, with `fr.sd<N>` holding the descriptor object.
- Ready-shim + rewrap wrappers follow the C shapes with plain objects.

## 8. Diagnostics

| condition | diagnostic |
|---|---|
| susp impl satisfies non-`susp` iface method | `` suspendable method `T.m` — `T` satisfies interface `I` whose method `m` is not declared `susp` — add `susp` to `I.m` or make `T.m` non-suspending `` (reframes today's D3 text) |
| `spawn`/`goin` on susp vtable call | `` `spawn`/`goin` on a vtable susp call isn't supported yet — wrap the call in a susp fn and spawn that `` |
| `susp` marker before an op name | parse error (marker only valid before method names) |

## 9. Test matrix

Positive (`tests/`, both lanes via tests/run.sh grep lists):

- `iface_susp.oxl` — `susp`-declared method on a susp impl; suspend +
  resume observed end-to-end (chan/msleep-backed impl through `w.m()`).
- `iface_susp_shim.oxl` — sync impl boxed into `susp` iface method;
  call completes, result correct.
- `iface_susp_pair.oxl` — `susp` method returning `(val, err)`;
  both lanes bind `o_vret` correctly.
- `iface_susp_nested.oxl` — susp iface method whose body calls another
  susp iface method (nested indirect suspension — free via child
  chaining).
- `iface_susp_rewrap.oxl` — iface→iface conversion where the method
  is `susp` (wrapper frame forwards).
- Caller-susp propagation: a fn calling `w.m()` (susp method) is
  itself susp — verified by a second fn spawning it.

Diagnostics (`tests/diag/`):

- `iface_susp_nonsusp` — susp impl + non-`susp` iface method → §8 diag.
- `iface_susp_spawn` — `spawn`/`goin` on susp vtable call → §8 diag.

Stage0: regenerate `bootstrap/stage0/oxl.c` via `scripts/stage0.sh`;
full `tests/run.sh` green on both lanes.

## 10. Out of scope (v1)

- `spawn w.m()` / `goin` on susp iface methods (rejected, §4).
- `susp` on fn-value types (`fn susp(…)`) — the fnval susp ban
  (check.oxl:8086, "suspendable fn can't be a value (v0.2)") stays.
- Per-method susp bits on non-declared methods; ops (`eq`, `ordered`)
  can't be `susp`.
- Anything beyond the iface→iface rewrap wrapper in §6.2.

## 11. Rollout stages (plan.md)

1. **Syntax+check**: parser flag, `IMethod.susp`, satisfaction matrix,
   seeding + edge propagation, goin reject, D3 reframe + diagnostics.
   Diag fixtures green; codegen still rejects the (now-impossible)
   unsafe pair via the post-pass.
2. **C lane**: `RtSuspDesc` in rt.h, descriptor/make/shim/rewrap emit
   in `gemvtab_one`, call-site machinery + `vsd<N>` frame fields,
   stage0 regen.
3. **JS lane**: §7 parity.
4. **Docs + tests**: semantics docs (`docs/semantics/` iface + fnvals
   note), the spawn+handle workaround doc line, test matrix §9.
