# WI-0019 brainstorm — iface-boxed borrow escape (issue #138)

## Reproduction (confirmed on main @ a9cc5df)

```oxl
fn helper() -> io.Reader {
    buf := bytes.newbuffer()
    [wn, we] = buf.write("hello world" as []byte)
    return buf.asreader()   // boxes &buf — buf dies at helper return
}
// main: r.read(b) → n=64 of NUL/garbage, not "hello world"
```

No diagnostic anywhere: `return` position, struct-field store
(`Box{r: buf.asreader()}` then `return bx.r`), all escape silently.

## Why the existing check misses it

`ret_sig` (check.oxl ~2401) rejects declared `-> ref`/`mut` returns
("borrowed refs may not be returned (v0)"), and `spawn` args of
`[]T`/`ref`/`mut` are rejected via `ck.in_spawn`. But a `mut Buffer`
coerced to `io.Reader` erases the borrow into an iface fat pointer —
the declared return type is `io.Reader`, not `mut`, so neither gate
fires. Same hole B3 scoped out for arena-backed `[]T` stored in
outer structs (`docs/specs/2026-11-04-0132-v0-2-forward/items/b3-slices.md`):
"the general check … remains open work."

## Runtime angle

`rt.c` keeps a per-task `BorrowEnt` ledger (`rt_borrow_read/mut`,
`rt_unborrow`) enforcing mutable aliasing dynamically. But the ledger
entry for `buf.asreader()`'s receiver borrow is popped when the call
returns — the iface box stores a raw pointer with no live borrow, so
scope close can't trap. Making the box hold a borrow requires knowing
when the iface value dies — iface values have no drop hook, and a
borrow pushed in helper's scope dies with it while the returned iface
lives in the caller's. Borrow transfer across return = the hard part.

## Forks

| option | shape | tradeoff |
|---|---|---|
| **A. own/copy box** | asreader heap-copies the receiver | breaks the documented contract — aswriter writes must land in the caller's Buffer; per-type semantics diverge (reader-copy "works", writer-copy loses writes). Rejected |
| **B. static escape analysis** | track borrow provenance through iface boxes/structs/slices; reject escapes at scope exit | the correct fix; this IS the B3 open work generalized. Needs per-fn return summaries ("iface ret borrows param N") + flow tracking + scope-exit checks. Largest surface: check.oxl + stage0 regen |
| **C. runtime borrow-on-iface** | iface_wrap of a borrow registers a BorrowEnt transferred to the box's owner scope | traps instead of silently corrupting, but needs iface-lifetime/drop machinery that doesn't exist; partial coverage at best |
| **D. accept + document + owned variants** | add `into_reader()`/`into_readwriter()` (own receiver → heap box, safe escape) alongside as*; document the hazard + `new()` workaround | ships no soundness fix; every existing as* call site stays a footgun. oxttp already workaround'd this way |

## Recommendation

**B** as the milestone-shaped fix (it subsumes the B3 slice gap too —
one provenance lattice covers `[]T`, `ref`, `mut`, and iface boxes).
Sequencing: D's `into_*` owned variants are a cheap interim that gives
oxttp a first-class safe API without waiting on B — worth folding in
as stage 1 so the issue's consumer unblocks immediately.

## Open questions for spec

- Does provenance need to be per-value (SSA-ish) or per-type? Per-value
  is precise; per-type over-approximates and may reject the blessed
  heap `h.asheap()` transient-call pattern.
- Struct-field stores (`Box{r: buf.asreader()}`) escape through the
  same hole — B must cover composite escapes, not just `return`.
- Interaction with `spawn` (already rejects borrow args) and closures
  (captures are copied by value — already safe per check_closures).
