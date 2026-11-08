# Monorepo + oxl-extra — Shaping Notes

## Scope

Migrate the repository to a monorepo: packages that do not belong in
`std` live in-tree under an `extra/` module, publishable and
consumable through the module system. This spec covers the machinery
— layout, workspace resolution, subdir-module fetch, the git-backed
index, the extras release lane, and the polish issues folded in
(#26–#30). The GUI layer (`extra/gui`) is milestone G's spec, not
this one.

## The decision

Owner direction (2026-11-08, WI-0004): monorepo with `oxl-extra`
packages outside the standard library. Planned together with all
remaining Phase-2 work as two milestones — **E** (this spec) then
**G** (GUI, spec'd at its own start).

Why a monorepo rather than a second repository:

- `extra/` packages dogfood the module system with zero publishing
  infrastructure on day one — `oxl.work` resolves them locally.
- CI, review, and the diag corpus stay in one place; the extras are
  release-gated alongside the toolchain they version against.
- The index protocol (E4) can be proven against real packages in
  this repo before any hosted registry exists.

## Key decisions (ADR-0008)

- **One extras module**: `module github.com/oxidean/oxl/extra`
  rooted at `extra/` — a subdirectory module. Single `extra/v*`
  version series (golang.org/x/* convention) until a package needs
  its own cadence.
- **`oxl.work` workspace file** (go.work analog): `use` directive
  lists module dirs; imports under a used module's path resolve to
  the local tree. Pays the deferred `work workspaces` item from the
  package-system plan.
- **Tag-prefix subdir-module fetch**: module path suffix ↔ tag
  prefix (`extra/v1.2.3` → `extra/` tree). `oxl.sum` hashes the
  module subtree.
- **Git-backed index**: registry = git repo of
  `index/<host>/<org>/<name>.json` files
  (`{version, commit, h1}` entries). `oxl publish` appends + tags;
  `oxl get` consults `OXLMODINDEX` then falls back to direct git.
  Hosted service stays parked.
- **`extra/v*` release lane**: same subject-derived bump rule,
  separate tag series, does not retrigger the toolchain release.

## Non-goals

- Hosted registry service / publish auth / web UI — parked.
- The GUI layer itself (milestone G spec).
- Per-package modules under `extra/` (single module — recorded).
- Language changes — `oxl.work` is manifest surface.

## Sequencing

```
E0 docs ─ E1 workspace ─ E2 layout+testutil ─ E4 index ─ E5 release
                     └── E3 subdir-fetch ────┘    (E6 polish, parallel)

G0 spec ─ G1 extra/gui core ─ G2 gtk ─ G3 chan events ─ G4 widgets
                                            └─ G5 apps ─ G6 2nd backend
```
