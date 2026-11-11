# Parked work — reopen only on trigger

Nothing here is scheduled. Each item has a stated trigger; a trigger
firing moves the item into the milestone map via a new work item.

## LLVM backend

- **Why parked:** the C backend works, is portable, and keeps emitted
  code inspectable. The codegen seam (`docs/semantics/interfaces.md`)
  exists precisely so LLVM can slot in later.
- **Reopen trigger:** C codegen is a *measured* bottleneck (compile-
  time or runtime) or a platform target requires it (e.g. wasm via
  LLVM).

## D4 shape-based generics

- **Why parked:** deferred with a real measurement in the v0.2 spec —
  3 generic fns in the entire corpus, zero shared-shape groups; type-
  dictionary passing is pure complexity at that scale. Re-measured
  2026-11-11 on the grown corpus (item doc): 22 generic fn defs,
  ~35 unique (fn,T) instantiations, one shareable pair — still
  ~2 orders under the bar.
- **Reopen trigger:** shared-shape groups grow enough that mono dedup
  is a *measured* win (the 11-11 count found one pair — existence
  alone isn't the bar; hundreds of mono'd bodies sharing a shape in
  one compile is).

## Pin primitive (address-stable values)

- **Why parked:** no consumer needed address-stable values; the
  runtime does not move objects, so pinning is a contract surface
  rather than a mechanism. (Distinct from the G spec's deferred
  thread-pin idea — same name, different ask; that one stayed
  parked inside the GUI spec.)
- **Reopen trigger:** fired — spec in flight as its own work item;
  retire this section when the pin spec merges.

## Parked stdlib list (`docs/specs/2026-11-06-0111-package-system/items/parked-stdlib.md`)

- reflection-class packages (`fmt %v`, `gob`, `xml`, `database/sql`,
  templates): need runtime type descriptors — type-descriptor
  milestone spec in flight (`docs/specs/2026-11-11-type-descriptors/`,
  PR open), implementation tracked as WI-0008 (un-parks on
  spec merge + impl)
- `crypto/tls`, `x509`, asymmetric crypto: a TLS stack is a project,
  not a package — spec in flight (`docs/specs/2026-11-11-tls-x509/`)
- `compress`, `archive`, `net/url`, `container/heap` (grew to
  `container/{heap,list,ring}` and friends): implementations in
  flight on their own PRs — drop from this list on merge
- `image`: deferred until a real consumer exists
- `context`: deliberate non-goal — `scope` carries cancellation and
  deadlines
- **Reopen trigger:** the language machinery exists (type descriptors
  / reflection) or a concrete consumer demands the package.
