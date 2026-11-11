# Parked work — reopen only on trigger

Nothing here is scheduled. Each item has a stated trigger; a trigger
firing moves the item into the milestone map via a new work item.

## LLVM backend

- **Status: trigger fired.** Milestone W is in flight on
  `feat/milestone-w` (PR #66) with a second emit lane
  (`--target js`); the `interfaces.md` codegen seam has a second
  consumer in flight and a third is pattern work; clang-only
  platform reach (wasm, target SDKs — the trigger's "platform
  target requires it" arm) is the standing justification. Spec:
  `docs/specs/2026-11-11-llvm-backend/` (milestone L, WI-0010).
  This section retires when L merges.

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
- **Reopen trigger:** fired — spec merged
  (`docs/specs/2026-11-11-pin-primitive/`); retire this section when
  the primitive ships.

## Parked stdlib list (`docs/specs/2026-11-06-0111-package-system/items/parked-stdlib.md`)

- reflection-class packages (`fmt %v`, `gob`, `xml`, `database/sql`,
  templates): need runtime type descriptors — type-descriptor
  milestone spec merged (`docs/specs/2026-11-11-type-descriptors/`);
  implementation tracked as WI-0008 (un-parks on impl)
- `crypto/tls`, `x509`, asymmetric crypto: a TLS stack is a project,
  not a package — spec in flight on `docs/tls-x509-spec`
- `compress`/`archive` landed (`compress/{flate,zlib,gzip}`,
  `archive/{tar,zip}`); `net/url`, `container/{heap,list,ring}`
  implementations in flight on their own PRs — drop from this list
  on merge
- `image`: deferred until a real consumer exists
- `context`: deliberate non-goal — `scope` carries cancellation and
  deadlines
- **Reopen trigger:** the language machinery exists (type descriptors
  / reflection) or a concrete consumer demands the package.
