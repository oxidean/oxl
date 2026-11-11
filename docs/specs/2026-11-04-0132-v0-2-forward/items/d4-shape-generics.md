# D4 — Shape-based generics (shape stenciling)

## Problem

Today every concrete call site gets a full monomorphized copy —
`Max[int]` and `Max[int64]` are separate functions. Works, but:
binary bloat + compile time grow linearly with instantiations. The
design doc's preferred implementation is shape stenciling:
share code per *memory shape*, not per type.

## Design sketch

- Classify each concrete type argument by shape:
  pointer-shaped, word-sized int, f64, or aggregate-specific
- Instantiate one function per distinct *shape signature*, not per
  type signature — `Max[int]`/`Max[int64]`/`Max[own X]` can share the
  same emitted body when their shapes coincide
- Runtime type identity: generic fns get a hidden shape descriptor
  (upstream designs pass iface-table/dictionary params; our C backend
  can pass a `void*`-sized
  descriptor or specialize only the ops that differ)
- Fallback: full monomorphization stays for types whose ops differ
  semantically (the constraint ops are the shape-breaking part)

## Acceptance

- `Max[int]` and `Max[int64]` emit ONE function; `Max[str]` a separate
  one (different ops)
- Binary size of a generic-heavy file measurably smaller
- All generic tests still pass (semantics unchanged — pure codegen
  optimization)

## Depends on

- Nothing — pure backend optimization. Low priority; can slip a
  milestone without blocking anything.

## Risks

- The dictionary-passing machinery is the fiddly part;
  the win is real but the complexity-per-benefit is low at v0 scale —
  spec honestly says: do it when generic usage is heavy enough to
  measure, not before.

## Deferred (measured 2026-11-05 — baseline for the re-measure below)

Per the risk note's own bar, generic usage was measured before
building: the entire corpus defines **3** generic fns
(`first[T any]` in tests/slices.oxl, `use[T Writer]` in
tests/methods.oxl, `id[T any]` in a run.sh fixture) and emitted C
contains **zero** shared-shape instantiation groups worth stenciling —
`first` isn't even instantiated with a concrete arg. Monomorphization
cost at this volume is nil; dictionaries + shape descriptors would be
pure complexity. Revisit when generic definitions or emitted
instantiations reach an order of magnitude more (rough threshold:
hundreds of mono'd bodies sharing a shape in one compile).

## Re-measured 2026-11-11 (grown corpus)

22 generic fn defs (19 in `std/` — sort 6, slices 9, cmp 3, rand 1 —
plus 3 in `tests/`: `first` in slices.oxl, `use` in methods.oxl
(generic with a `Writer` bound, not a method), and `f` in the
diag/generic_constraint reject fixture — the `fn id[T]` inside
run.sh's `gen)` printf is a string fixture, not a def). ~35 unique (fn,T) instantiations
corpus-wide (decl sites grepped via `fn \w+\[`; instantiation
counts from `ginst_name`'s `(fn,tyargs)` dedup in the driver's own
emit queue — `bootstrap/codegen/codegen.oxl` — plus per-file call-site
inspection); the heaviest single compile (`tests/util_test.oxl`)
emits ~26 mono'd bodies — `cmp_{compare,min,max}`,
`sort_{sort,sifto,is_sorted,sortfn,sift,reverse}`, `slices_*`
over `int`. The driver build itself emits only
the `sort_*__str` set, which is what the earlier enumeration
counted. One shareable pair: `first__{int,float}` (word shapes);
`use__{Lower,Upper}` shares layout but its `Writer` bound breaks
the shape signature. Still ~2 orders under the bar; stays parked.
