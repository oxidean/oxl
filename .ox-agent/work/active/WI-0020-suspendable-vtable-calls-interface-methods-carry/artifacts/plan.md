# WI-0020 plan — suspendable vtable ABI, staged

Contract: artifacts/spec.md (descriptor-slot ABI, `susp` iface marker).
Issue: oxidean/oxl#135. Route: A-now (IN-0003).

## Stage 1 — syntax + check (`bootstrap/parser`, `bootstrap/check`)

- parser.oxl: `Node.Method` gains `susp: int`; interface-body parse
  accepts optional `susp` ident before method names (contextual —
  `susp` is not added to `is_kw`; `ck.susp` field stays valid).
- check.oxl: `IMethod.susp`; conversion copies the flag (~4369).
- Seed `ck.susp` with `Iface.m` for susp-declared methods at iface
  registration.
- `add_edge(ck, mt.q)` for `mt.k == 2` calls (propagates susp to
  callers through the existing fixpoint).
- goin/spawn gate: `mt.k == 2` + susp method → v1 reject diag (§8).
- D3 post-pass reframed: fire only when a susp impl matches a
  non-`susp` iface method; new message text (§8).
- Verify: `oxl` rebuild via stage0; new diag fixtures pass check-only;
  existing iface/borrow tests still pass (check leg only — no codegen
  for susp pairs yet).

## Stage 2 — C codegen (`runtime/rt.h`, `bootstrap/codegen/codegen.oxl`)

- rt.h: `RtSuspDesc` typedef + `#include <stddef.h>`.
- `gemvtab_one`: susp method slots emit `o_vsd_*` descriptors —
  susp-impl `make`, sync-impl ready-shim (`o_shf_`/`o_shp_`/`o_shm_`),
  iface→iface rewrap wrapper (`o_wf_`/`o_wmk_`/`o_wp_`).
- Call-site: `gfsusp_call`-shaped emit for `mt.k == 2` + susp method —
  `vsd<N>` frame fields via `g.fdecls`, `res_off` result readback,
  `o_vret_<w>_<m>` for retk==2, borrow pre/post marks.
- Generic impls: mangled names via `ginst_name`.
- Regen `bootstrap/stage0/oxl.c` (`scripts/stage0.sh`).
- Verify: positive fixtures compile+run on the native lane; old
  susp-impl-in-non-susp-slot programs still rejected at check.

## Stage 3 — JS lane (`bootstrap/codegen/js.oxl`)

- `jfsusp_call`-shaped emit for susp iface calls; descriptor objects
  `{m, p}`; shim + rewrap wrappers; no `res_off` (uniform `.result`).
- Verify: codegen-lane fixtures (tests/run.sh js sections) green.

## Stage 4 — tests + docs + ship

- tests/: §9 matrix fixtures + run.sh entries (native + codegen lists).
- docs/semantics/: `susp` iface methods documented; fnvals.md note
  (`susp` still banned on fn values); spawn+handle workaround noted
  for `spawn`-position calls.
- Full `tests/run.sh` green both lanes; `oxl fmt --check` clean;
  stage0 snapshot committed.
- PR → self-review (CodeRabbit quota-substitute per standing rule)
  → squash-merge → closes #135 → archive WI-0020.

## Dependencies / risks

- c2-iface-codegen spec (`docs/specs/2026-11-05-c2-iface-codegen`):
  vtab layout is `void*[]` — descriptors ride it unchanged; the spec
  doc gets a slot-content note in stage 4.
- `RtFrame` header stays pinned (LLVM spec contract) — the descriptor
  avoids extending it; `vsd<N>` fields live in the generated
  `o_frm_<n>` (not RtFrame).
- Risk: `gav_decl` arg-fill against iface sigs (no impl decl) — arg
  conversions/borrows must plan off `mt.ps`; mitigate by reusing the
  `gcall_plan` machinery's iface arm rather than a parallel path.
- Risk: stage0 regen churn on check.oxl — the parse/check changes
  land in the snapshot with the codegen stage (single regen at stage 2
  end, then re-verify).
