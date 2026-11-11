# items/emit-seam.md — the codegen seam, third-lane registration

The seam `docs/semantics/interfaces.md` reserved — "an LLVM backend
drops in behind the same `TAST → object` seam" — is now a
two-consumer pattern in flight (the W lane is on `feat/milestone-w`,
PR open). This item pins what the shared front-end hands
a lane, how a lane registers, and what stays per-lane. The reference
instance is `bootstrap/codegen/js.oxl` (milestone W, in flight); the LLVM lane
follows it mechanically and diverges only where IR differs from an
ES module.

## What the front-end hands a lane

`check.check_file`/`check_files` → `own check.CkRes`:

```text
CkRes { ck: own Ck, items: []It }

ck:    tyv []T              interned type handles (k_* kinds, tyi/tyk)
       fnsv []FnSig         signatures incl. is_extern, ret kinds
       structsv/enumsv/ifacesv   decl tables (fields, variants, method lists)
       globals              name -> ty handle
       susp                 suspendable fn qnames
       fnvals               named fns used as values
       diags                pipeline stop before emit on any Error
       subst_ty/tp_*        bind-map substitution for monomorphization
       fn_qname/resolve_named   the qualified-name canon the o_* scheme uses

items: []It { node, mod, file }   checked AST nodes + module + file
```

Nothing here is C-shaped. There is no per-lane inst table handed
*down* — instantiation is emitter-side: the lane walks call sites,
builds bind maps, and queues `ginst_queue` instantiations against
`subst_ty`. Each lane owns its `G` state struct (codegen.oxl's `G`
and js.oxl's are siblings, not shared); the *machinery* fns it calls
(`gubegin`/`gudrain`/`gdef`/`gscan`, `cname`, `xty*`, `gav*`,
`ginst_*`, `check.*` helpers) are package-level and shared.

Diags pipeline rule unchanged: any `Error` in `ck.diags` stops the
driver before emit — a lane never sees invalid input, and never
emits target-dependent diags itself (check is target-agnostic; the
R spec's `--target js` intrinsic diagnostic is the checker-side
exception and lives in `check`, not the lane).

## How a lane registers (the W pattern)

1. A sibling file in `package codegen` —
   `bootstrap/codegen/llvm.oxl` exporting
   `emit_llvm(r: own check.CkRes, testm: int) -> str`. One output
   text per compile — the seam is a pure function over `CkRes`.
2. Driver dispatch in `cmd/oxl/main.oxl`'s `compile_res`: the
   `--target` flag value selects `codegen.emit` (native, default),
   `codegen.emit_js` (`js`), or `codegen.emit_llvm` (`llvm`).
   Validation message names the accepted set.
3. A per-lane `emit_and_*` (scratch layout, runtime copy, tool
   invocation) and a lane branch on `build`/`run`/`test`.

Non-negotiables for a third lane:

- `package codegen` membership + `o_*` symbol scheme — the G1
  reachability machinery is language-agnostic *only because* defs
  and use-edges are `o_*`/extern identifier tokens. A lane emitting
  different symbol roots must extend the registry; the LLVM lane
  keeps the same roots (`@o_f_*` spells the `o_f_*` token — the `@`
  sigil is a non-word byte the scanner skips into the token start).
- `testm` semantics: the emitted module contains the `test_*`
  wrapper runner as `oxl_main` — same contract as both lanes.
- Emitted text is the lane's entire product: deterministic, no
  timestamps/paths/randomized ordering (determinism is what makes
  both fixpoints possible — map iteration order must route through
  the same ordered-drain discipline the C lane uses).

## What stays per-lane

- The `G` state and every emitter internal (`w*`/`f*`/`cl*` bands,
  label/slot counters, the expression walker).
- The output medium: C text vs `.mjs` vs `.ll` — scratch file name,
  tool invocation, kept-on-failure intermediate.
- The feature-gate *scan tokens* are shared by convention
  (`rt_sqlite_`/`rt_sock_`/`rt_m_` — any lane whose emitted text
  spells the same rt symbols gets `emit_and_llvm`'s identical scans
  for free).
- Lane flag surface: `--target` value, `--triple` (llvm only),
  `--emit-llvm` (llvm only), `--html` (js only).

## §scope-storage — the rt-internal-size rule

One rule the C lane never needed because `sizeof` was free: emitted
IR may not name an rt-internal layout. Where `RtScope` storage is
required the lane emits dynamically-sized storage (contract in
`llvm-semantics.md` §5):

- non-frame `scope {}` → `alloca i8, i64 %rtsz, align 16`,
  `%rtsz = call i64 @rt_scope_sizeof()`
- frame `sc<i>` slots → `[0 x i8]` tail marker in `%o_frm_*`,
  addressed `gep i8` at `fixed_off + i*%rtsz` with `fixed_off`
  aligned up to 16 (matching the alloca rule); the slot space is
  added to `rt_task_new`'s `bytes` argument at spawn
- named-scope handles were always `rt_scope_new()` heap `ptr`s —
  unaffected
- `RtChan*[]` select arrays, `RtDefer`/`RtFrame`/`RtTask` — `ptr`
  throughout; no size needed

`rt_scope_sizeof()` is the only additive rt.h entry the lane
requires. If a future rt-internal type needs emitted storage it
gets the same treatment — declared layouts for rt types beyond the
`llvm-semantics.md` §1 boundary table are banned (the boundary
table itself is field-for-field `rt.h` and covered by the L1
abi-check gate).
