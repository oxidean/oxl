# `pin` primitive — Stage Plan

Spec: `shape.md`. Contracts: `items/pin-semantics.md`,
`items/ffi-boundary.md`. Working artifacts: WI-0011 under
`.ox-agent/work/`. Only P0 and P1 are scheduled: P2–P4 are one
implementation unit gated on the trigger test in
`items/ffi-boundary.md` — the first in-tree extern decl that
retains a caller pointer past return. Every stage is a PR through
the review loop (approval + green CI); every stage lands with the
suite green.

- [done] **P0 — spec** — this directory, WI-0011 artifacts.
      *(this PR)*
- [ ] **P1 — contract documentation (trigger-free, may land any
      time)** — write down the guarantee that already holds:
      `docs/semantics/ownership.md` gains an "Address stability"
      section (`rt_alloc_own` placement never relocates; the
      death-path table — `rt_free`, `drop_elem`, scope arena
      close, process exit — and the "not a promise" exclusions:
      borrowed `[]T` backings relocate on `push`, views die with
      their scope); `docs/site/language.mdx` FFI bullet gains the
      retention rule ("extern pointer params are
      borrow-for-duration; retention is a contract violation until
      `pin` lands"); `runtime/rt.h` gains the ObjHdr comment
      pinning the non-moving-placement invariant next to the
      header it describes. Zero code changes.
      Gate: docs only; the new text names no unimplemented surface
      as available (pin is named as parked design, pointer to this
      spec).
- [ ] **P2 — runtime pin machinery (trigger-fired)** — `ObjHdr.pinned`
      rides the `_pad` byte (header stays 24B); `rt_pin`/`rt_unpin`/
      `rt_pin_slice`/`rt_unpin_slice` exported (C-callable like
      `rt_free`); `rt_free` on `pinned>0` → `rt_trap(11)`; arena-
      pin, double-unpin, count-overflow → `rt_trap(11)`; `drop_elem`
      inherits the trap through `rt_free`. `tests/ffi_pin.oxl` +
      `tests/ffi_pin_shim.c` (the trigger test —
      `items/ffi-boundary.md`) exercises hold/poke/release; a scope-
      joined child task asserts trap-11 on `rt_free`-while-pinned
      and on double-`unpin` (`ErrTrap` at `sjoin`).
      Gate: rt suite green; trigger test green on Linux + macOS CI
      legs; no perf regression on `conc_ping` (pin adds a header
      read on the `rt_free` path only).
- [ ] **P3 — checkers + parsers (trigger-fired, needs P2)** — both
      drivers, same shape: `pin`/`unpin` builtins (`BUILTINS` +
      call dispatch in `oxl/src/check.rs`; the builtin-name table +
      `expr` dispatch in `bootstrap/check/check.oxl`); a `pinned`
      set riding `env` beside `moved`/`ck.moved` with branch-
      **intersection** merge (pin-semantics.md — pinned iff pinned
      on every non-diverging incoming path); move-site bans
      (own-arg/send/try_send/return/field-store/spawn-arg +
      `push` on pinned `own []T` + assign-over);
      `pin` stays a contextual qualifier — `TyKind::Pin` in the
      seed (parser `ty()` matches the `pin` *ident* — no
      `Kw::Pin`/keyword-table entry: `getmod.oxl` binds `pin`
      as an identifier) + `k_pin()` and the same text-matched
      qualifier arm in bootstrap's `p_ty`/`ty_parse` — never
      `is_kw`;
      `pin own T` legal on extern params only; `pin` param arg
      must be a pinned `own` binding. `tests/diag/` gains:
      `pin_move_send.oxl`, `pin_move_return.oxl`,
      `pin_move_field.oxl`, `pin_nonown.oxl`, `pin_expr.oxl`,
      `pin_twice.oxl`, `unpin_unpinned.oxl`,
      `pin_arg_unpinned.oxl`, `pin_param_nonextern.oxl`,
      `pin_push.oxl`, `pin_if_arm.oxl`, `unpin_if_arm.oxl`,
      `pin_for_body.oxl`.
      Gate: byte-identical diagnostics from both checkers on the
      new diag files (the existing parity mechanism); `oxl test`
      green on both drivers.
- [ ] **P4 — codegen + lanes + docs (trigger-fired, needs P3)** —
      `pin`/`unpin` emit `rt_pin`/`rt_unpin` (or the `_slice`
      forms for `own []T`) in `oxl/src/codegen.rs` and
      `bootstrap/codegen/codegen.oxl`; `pin` qualifier erases in
      ABI output; rt.mjs gains the identity-ledger pin count +
      `__oxl_ffi` arg-table row ("`pin own` → raw ref");
      `docs/semantics/ownership.md` grows the real `pin` section
      (the P1 text points at it), `concurrency.md` gains the
      task-migration note, `language.mdx` swaps the retention rule
      for the checked contract.
      Gate: `tests/ffi_pin.oxl` green native + js lane (ledger
      semantics); self-hosted driver compiles the new surface
      byte-identically (bootstrap chain green); docs land.

## Dependencies

P1 is independent — documents existing behavior, land whenever.
P2→P3→P4 are strictly sequential and all gated on the trigger: the
consumer's extern decl rides in P2's PR (or earlier — the decl may
land first as an undocumented-retention shim whose retention the
P2 PR then declares via `pin`, but `pin` itself never merges
without the consumer).

## Watch items

- **`shared` word stashing** — a pinned object's address stored in
  a shared cell is outside the checked surface (words are untyped
  by design). The contract rule stands ("legal, unchecked"); if a
  consumer pattern emerges, a `Shared<pinned>`-ish surface is a
  follow-up spec, not silent growth here.
- **`push` on `own []T`** — the only relocation that survives pin
  is slice growth, banned at P3 by checker rule. If a consumer
  needs growable pinned buffers the design has to grow a
  pre-sized-capacity story — flagged, not designed.
- **Abandoned pins** — a pin whose releaser dies (cancel,
  forgotten completion path) leaks `own`-style. A pin-leak report
  (e.g., scope-close audit) is a plausible follow-up once a real
  consumer shows which direction mistakes flow.
- **`pin` qualifier spread** — returns and non-extern params are
  v0 rejects; if a consumer wants foreign-to-oxl ownership with
  pinning, that shape gets its own spec round rather than a quiet
  extension here.
