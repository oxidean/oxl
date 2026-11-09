# WI-0004 brainstorm: remaining Phase-2 work post-T

Discovery summary: milestone T (toolchain-in-oxl) is fully shipped —
T0–T6 merged, WI-0003 archived, cargo out of the build path, dogfood
CI green. The phase-2 map's G entry criterion ("after T") is now met.
Remaining documented work: milestone G (spec needed — map is schedule,
not design), milestone R (map-level scope check only), P-track issues
#26–#30 (sequencing), parked set (unchanged, triggers intact).

## Fork 1 — milestone G paradigm

The design-doc GUI charter keeps three paths open (FFI-to-native,
portable in-language layer, FFI bridge). The map committed to the
portable layer; this fork decides whether that still holds now that T
is done and the real surface is visible.

| option | shape | tradeoff |
|---|---|---|
| **A. Retained widget tree over a backend iface** (map's pick) | `std/gui`-adjacent packages: widget tree in `.oxl`, backend protocol iface (create/props/events per widget kind), GTK4 shim becomes first backend | Delivers the charter item; DOM-mappable guardrail preserved (a DOM backend is a plausible second backend); dogfoods interfaces/generics/own heavily. Cost: largest scope; needs the backend protocol designed, not implied |
| B. Thin managed bindings over the pilot shim | polish `gui_shim.c` externs into a typed `std`-adjacent package, stop there | Ships fast, honest, small — but it is path (a), not the charter item; "portable layer" stays unbuilt and the milestone renames into a smaller thing |
| C. Immediate-mode over a draw surface | backend = canvas+input primitives; widgets are per-frame calls | Most portable conceptually (GPU/DOM trivial) but reinvents layout/hit-testing/a11y; wrong fit for a retained-tree guardrail |

Recommendation: **A**. The map already chose it and nothing in T's
completion weakened the case — the language machinery it exercises
(ifaces, generics, own, scope/select) is exactly what G is for.

## Fork 2 — widget ownership & lifecycle

| option | shape | tradeoff |
|---|---|---|
| **A. own-tree, scope-bound** (recommended) | widget nodes are `own` values; the tree lives in an app scope; children attach/detach; teardown follows scope cancellation | one ownership story language-wide; `defer` + scope cancel = free cleanup; matches "structured" everything |
| B. opaque int handles (pilot model) | integers into a backend table | simple but manual lifetime, leak-by-neglect, wrong feel for the language |
| C. iface-polymorphic widgets, arena teardown | widgets behind `gui.Widget` iface; whole-tree arena free | flexible but hides ownership; harder to prove DOM-mappable diffs |

Recommendation: **A** — with `gui.Widget` as an iface for *user-visible
widget kinds* (button, entry) while the tree itself stays own-typed.

## Fork 3 — event model / main-thread

Design doc: "main-pinned task owns UI" is a first-class concurrency
concept.

| option | shape | tradeoff |
|---|---|---|
| **A. events as channel values** (recommended) | UI runs on the pinned main task; events delivered on a buffered `chan gui.Event`; app code `select`s them next to other channels | composes with `scope`/`select` natively — event handling IS the concurrency model; no reentrancy |
| B. callback registration (pilot's `gui_connect`) | fns invoked by backend loop | reentrant by construction; callbacks run where the backend wants, not where scope rules say |
| C. polled event queue | `gui.poll()` drained manually | honest but fights the language's own model |

Recommendation: **A** — the pilot keeps `gui_connect` internally (the
backend shim still needs it) but the public API speaks `chan`.

## Fork 4 — backend protocol shape

Exit criterion: a second backend sketched or an honest written case.

| option | shape | tradeoff |
|---|---|---|
| **A. retained-widget protocol** (recommended) | iface: `new(kind, props)`, `set_prop`, `on_event`, `attach/detach`, `run/pump`; GTK4 first; DOM second is natural | maps 1:1 to widget tree; second-backend case writes itself |
| B. platform-native trio | gtk4 linux, cocoa macos, win32 windows | best native feel; triples the backend work; DOM doesn't fit cleanly |
| C. draw+input surface | backend = pixels + events | portable floor; rebuilds everything above it |

Recommendation: **A**.

## Fork 5 — where GUI lives — DECIDED (owner, 2026-11-08)

Owner direction: migrate to a monorepo — packages outside std live in
the same repo under an `oxl-extra` tree. Fork 5's option A is adopted
and concretized: the GUI layer lands as `oxl-extra` packages, not
`std/gui`. This makes the monorepo migration the new critical-path
item — everything downstream (G's packaging, R's first real
publishable units, extras versioning) depends on it.

## Fork 6 — monorepo shape (new, owner-directed)

The monorepo migration is the umbrella decision. Design questions the
spec must answer:

| question | options | lean |
|---|---|---|
| module layout | (a) one module `oxidean/oxl-extra` rooted at `extra/` with package subtrees; (b) one module per publishable package (`extra/gui`, `extra/flagx`, ...) | (a) — matches golang.org/x/* convention; one version series for "the extras", simplest fetch/tag story; per-package modules explode tag count for no gain until a package needs its own cadence |
| in-repo resolution | (a) `oxl.work` workspace file (go.work analog) listing module dirs; (b) `replace` in every consumer; (c) toolchain special-case for repo layout | (a) — workspace is the honest mechanism, replace stays for overrides; dogfoods module machinery in the new .oxl driver |
| subdir-module fetch | repo root != module root requires either tag-prefix publishing (`extra/v0.1.0`) or full-module fetch + subdir slice | Go's tag-prefix convention — proven model, and V1's MVS machinery already handles versioned tags |
| versioning | (a) extras version independently of toolchain (`extra/v*`); (b) extras version-locked to toolchain | (a) — extras move at their own cadence; toolchain tag series stays clean |

## R — pulled into scope (owner: "plan out the entire remaining work")

With `oxl-extra` producing publishable packages immediately, R's
"spec at milestone start" trigger fires now. The infrastructure worry
dissolves under a git-backed index:

| option | shape | tradeoff |
|---|---|---|
| **A. git-backed index** (recommended) | index = a git repo of per-package metadata files (name -> {repo, versions, sums}); `oxl publish` = metadata commit + tag; `get` consults index, falls back to direct git | zero hosted infrastructure — Homebrew-tap/Go-direct shape; namespace + auth = repo write access; defers all service decisions |
| B. minimal HTTP index service | small read API + publish endpoint | real service to host/auth/maintain — premature |
| C. skip index, git-only | `require` always takes git URLs | works today but no namespace/discovery story; "registry" stays aspirational |

Recommendation: **A** — the index protocol spec lands in the same
milestone as the monorepo machinery (they share the fetch path).

## P — milestone placement (was: opportunistic)

Owner wants issues planned, not floating. Fold #26-#30 into the
monorepo milestone as a stage — the module/CI surfaces are already
open, and four of five are small. Dispositions for the spec to bake:

- #26 json surrogate pairs — pure implementation, do
- #27 errors.Is/As — needs error-tree design; bounded design + impl
- #28 fmt %v — needs reflection; **park candidate**, record decision
- #29 net DNS — needs resolution API design; bounded design + impl
- #30 time stopgap — pure implementation, do

## Revised milestone grouping — TWO milestones, all remaining work

### Milestone E — "monorepo: oxl-extra + git-index + polish"

- E1 repo layout: `extra/` module tree, root `oxl.work`, doc/README
  restructure, CI paths
- E2 toolchain: workspace resolution + subdir-module fetch +
  tag-prefix versions (all in the .oxl driver — dogfoods T)
- E3 git-backed index: protocol spec + `oxl publish`/`get` path
- E4 release/CI: `extra/v*` tag series, auto-release extension,
  per-module gating
- E5 P-track: issues #26-#30 (with #28's park decision recorded)
- E6 first citizen: migrate an existing non-std package to `extra/`
  (proves the loop end-to-end before G)

### Milestone G — portable GUI layer (unchanged stage sketch below)

G0-G6 as sketched previously; lands as `extra/gui` + `extra/gui/gtk`
under the new layout — first real external consumer of E's machinery.

### Parked — unchanged

LLVM backend, web target (G's DOM-map guardrail keeps it open), D4
shape-generics, parked-stdlib, hosted index service (A's deferral).
