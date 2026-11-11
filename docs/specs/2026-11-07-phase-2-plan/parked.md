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

## Web compilation target (JS/HTML/CSS) — SHIPPED

- **Trigger fired 2026-11-10:** milestone G merged (PR #59); the
  guardrail held — `docs/gui-backends.md` proves the backend protocol
  ports to a DOM mapping with no GTK-shaped assumptions beyond a
  main-loop thread, which holds in the DOM world.
- Moved into the milestone map as **milestone W** (WI-0007) and
  shipped in this PR: `--target js` emit, `extra/gui/dom`,
  `web-todo` — spec: `docs/specs/2026-11-10-web-target/`.

## D4 shape-based generics

- **Why parked:** deferred with a real measurement in the v0.2 spec —
  3 generic fns in the entire corpus, zero shared-shape groups; type-
  dictionary passing is pure complexity at that scale.
- **Re-measured 2026-11-10:** the corpus grew ~7x (201 `.oxl` files —
  std, extra/, gui, the whole self-hosted chain) and still shows ~zero
  shared-shape monomorphization: 23 generic fn decls, 21 distinct
  instantiation sites, no two instantiations sharing a shape. The mono
  cost remains unmeasurable because there is nothing to measure —
  stays parked.
- **Reopen trigger:** the corpus grows enough generic code that two
  or more instantiations share a shape and the mono cost is measured.

## Parked stdlib list (`docs/specs/2026-11-06-0111-package-system/items/parked-stdlib.md`)

- reflection-class packages (`fmt %v`, `gob`, `xml`, `database/sql`,
  templates): need runtime type descriptors — **trigger fired →
  milestone R** (`docs/specs/2026-11-11-type-descriptors/`)
- `crypto/tls`, `x509`, asymmetric crypto: a TLS stack is a project,
  not a package
- `image`, `compress`, `archive`, `net/url`, `container/heap`:
  deferred until a real consumer exists
- `context`: deliberate non-goal — `scope` carries cancellation and
  deadlines
- **Reopen trigger:** the language machinery exists (type descriptors
  / reflection) or a concrete consumer demands the package.
