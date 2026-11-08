# ADR-0008: monorepo layout — oxl-extra module, oxl.work, git index

Status: accepted (WI-0004) — 2026-11-08

## Decision
The repo becomes a monorepo. Packages outside `std` live under a
single subdirectory module `module github.com/oxidean/oxl/extra`
rooted at `extra/`, versioned on the `extra/v*` tag series. A new
`oxl.work` workspace file (`use` directive) resolves used modules to
local trees during in-repo development. Publishing goes through a
git-backed index repository (`index/…/<name>.json` metadata files);
`oxl get` consults the index via `OXLMODINDEX` and falls back to
direct git. Fetch supports subdirectory modules via tag prefixes
(`extra/v1.2.3` → the `extra/` subtree).

## Rationale
- Owner directive: packages outside std should live in-repo — one
  CI, one review surface, extras dogfood the module system before
  any hosted registry exists.
- Single extras module over per-package modules: one version series
  is enough until a package needs its own cadence (golang.org/x/*
  precedent); per-package tags multiply fetch surface for no gain.
- `oxl.work` over `replace`-per-consumer: the deferred `work
  workspaces` item in the package-system plan is the honest
  mechanism; `replace` stays for ad-hoc overrides.
- Git-backed index over a hosted service: zero infrastructure —
  namespace and publish auth are index-repo write access. The
  service option stays parked rather than rejected.
- Tag-prefix subdir modules over whole-repo fetches: proven
  convention; `oxl.sum` integrity stays at module granularity.

## Consequences
- Module path is URL-shaped (`github.com/oxidean/oxl/extra`) even
  though the root module `oxl` is bare — imports of extras are
  uniform whether resolved via workspace or cache.
- `extra/v*` tags must not retrigger the toolchain release lane —
  the release workflow keys lanes by tag prefix.
- A future package needing its own cadence splits into its own
  module; the index protocol does not change.
- Hosted registry adoption later = implement an `OXLMODINDEX` URL
  scheme; no protocol redesign.
