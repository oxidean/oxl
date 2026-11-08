# WI-0004 plan: monorepo + oxl-extra + git-index + GUI — staged

Two milestones, E then G. Every stage is its own PR through the
CodeRabbit loop (approval + green CI); every stage lands with the
suite green — nothing strands. Deps are hard requirements;
"parallel-ok" marks stages with no shared-file contention.

## Stage map

| stage | milestone | contents | deps | gate |
|---|---|---|---|---|
| **E0** | E | This planning increment as a docs PR: `docs/specs/<date>-monorepo-oxl-extra/` (shape.md, plan.md, items/), ADR (monorepo layout + subdir module + git-index), phase-2 map + roadmap update, parked-stdlib += `fmt %v` | — | review loop + green CI |
| **E1** | E | `oxl.work` in manifest grammar (`use` dirs); workspace resolution ahead of manifest/requires; diag corpus rows (malformed, missing dir, conflicting module paths); file-mode untouched | — | corpus byte-parity both drivers; suite green |
| **E2** | E | `extra/` module skeleton (`module github.com/oxidean/oxl/extra`); `extra/testutil` first citizen; `tests/` + `examples/` consume via `oxl.work`; suite extras section; README/monorepo docs | E1 | suite exercises the workspace path end-to-end on all platforms |
| **E3** | E | Subdir-module fetch: module-path suffix → tag prefix (`extra/vX.Y.Z`) → archive slice at module root; cache layout `…/extra@vX`; `oxl.sum` hashes module tree; local-git-remote fixture | E1 (shares resolution) — parallel-ok with E2 | new corpus rows + fixture fetch round-trip, byte-parity |
| **E4** | E | Git-backed index: `index/…/<name>.json` entries `{version,commit,h1}`; `OXLMODINDEX` env (local path or git URL); `oxl publish` (validate + append + tag); `get` index-first → git fallback; index-entry tamper caught at fetch (`get` compares entry `h1` to the fetched tree); `mod verify` covers cache slots | E2, E3 | scratch-index publish→get round-trip in suite |
| **E5** | E | Release lane: `extra/v*` tag series; auto-release bump rule extended per-module; CI gates `extra/` build+test; release docs | E4 | dry-run tag derivation + workflow lint; first extras release cut |
| **E6** | E | P-track issues: #26 json surrogates (impl), #27 errors.Is/As (bounded design + impl), #29 net DNS (bounded design + impl), #30 time stopgap (impl); #28 → parked, issue closed, parked-stdlib updated | — (parallel-ok throughout) | per-issue PRs; suite additions per fix |

**E entry**: none — starts immediately.
**E exit (milestone E done)**: workspace + fetch + index verified
end-to-end by suite fixtures; `extra/testutil` published+consumed on
both paths; #26/#27/#29/#30 closed, #28 parked; release lane cut.

| stage | milestone | contents | deps | gate |
|---|---|---|---|---|
| **G0** | G | G spec PR (`docs/specs/<date>-gui-layer/`): backend protocol iface def, Event/Prop model, ownership rules, widget scope tranche | E0 (planning docs landed) | review loop |
| **G1** | G | `extra/gui` core: `own` widget tree, `gui.Widget` iface, Event/Prop types, backend protocol iface; headless mock backend; tree/event/prop-diff suite | E2 (extra layout + workspace path) | mock-backend tests headless on all platforms |
| **G2** | G | `extra/gui/gtk` backend over `gui_shim.c` (extended): window/box/entry/button/label parity with pilot | G1 | GTK4 CI leg builds+smoke-runs |
| **G3** | G | Chan event model: buffered `chan gui.Event`, main-pinned pump, select integration; pilot's `gui_connect` internal to backend | G2 | select-driven event test green |
| **G4** | G | Widget tranche 2: text, list/scroll, checkbox | G1 | per-widget tests + demo wiring |
| **G5** | G | Reference apps: `gui-todo` ported to the layer; second app mixing UI events + worker channels in one select | G3 (+G4 widgets as needed) | apps build+run; suite smoke coverage |
| **G6** | G | Second-backend sketch (DOM or platform-native written case) + docs + `OXL_GUI` dogfood gate | G2 | doc lands; gate asserted in CI |

**G entry**: G0 may start in parallel once E0 lands (spec needs only
the planning frame). G1 waits on E2 — the `extra/` layout and
workspace resolution must exist to host `extra/gui`.
**G exit**: the spec's acceptance criteria — ported gui-todo on
GTK4, mock+gtk backend substitutability, select-driven events,
written second-backend case, no-import → zero GUI in emitted C.

## Risks / assumptions

- **Subdir-module fetch (E3)** is the deepest machinery: tag-prefix
  ↔ module-path-suffix mapping must handle multi-segment suffixes
  and cache-path layout. Mitigation: local-git-remote fixture from
  T4 is the testbed; corpus rows pin byte-parity.
- **`oxl.work` grammar** must not drift from the manifest parser —
  implement in the same parse path, not a second grammar.
- **E4's index protocol** is the only new external contract —
  keep the file format trivially line-oriented JSON to stay
  debuggable; ADR records it.
- **G's G2 (GTK4 backend)** is the largest single stage; G1's
  protocol design is the risk that gates it — the mock backend
  suite is the forcing function for getting the iface right.
- **P-track parallelism**: #27/#29 carry bounded design — if either
  blows its bound it becomes its own spec'd item (recorded call),
  not silent scope creep.
- **Auto-release interplay**: E5 adds a second tag series — the
  lane must not let `extra/v*` pushes retrigger the toolchain
  release (existing in-run release pattern extends cleanly).
