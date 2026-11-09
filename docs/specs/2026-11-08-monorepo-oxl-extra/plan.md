# Monorepo + oxl-extra — Stage Plan

Spec: `shape.md`. ADR: `.ox-agent/context/decisions/ADR-0008-*.md`.
Every stage is a PR through the review loop (approval + green CI);
every stage lands with the suite green.

- [done] **E0 — planning docs** — PR #50 — this directory, ADR-0008, phase-2 map
      + roadmap update, parked-stdlib cross-referenced for `fmt %v` (#28 — already listed). *(this PR)*
- [done] **E1 — `oxl.work` + workspace resolution** — `use` directive
      in the manifest grammar; workspace resolution ahead of
      requires/cache; diag corpus rows (malformed work file, missing
      dir, module-path conflict); file mode untouched.
      Gate: corpus byte-parity both drivers; suite green.
- [done] **E2 — `extra/` layout + first citizen** — the e2-e6 PR — `extra/oxl.mod`
      (`module github.com/oxidean/oxl/extra`), `extra/testutil`
      (assert/tempdir helpers factored from `tests/*.oxl`), root
      `oxl.mod` gains `require` + root `oxl.work` gains `use ./extra`;
      suite extras section; `docs/site/language.mdx` + README updates.
      Gate: suite consumes the workspace path on all platforms.
- [done] **E3 — subdir-module fetch** — the e2-e6 PR — path suffix ↔ tag prefix
      (`extra/vX.Y.Z`) → archive slice at module root; cache slot
      `…/extra@vX`; `oxl.sum` on the module subtree; local-git-remote
      fixture. Parallel-ok with E2. Gate: fetch round-trip fixture,
      byte-parity diagnostics.
- [done] **E4 — git-backed index** — the e2-e6 PR — `index/<host>/<org>/<name>.json`
      `{version,commit,h1}` entries; `OXLMODINDEX` (path or git URL);
      `oxl publish` (validate + append + tag); `get` index-first →
      git fallback; a tampered index entry is caught at fetch
      (`oxl get` compares the entry `h1` to the fetched tree);
      `oxl mod verify` re-hashes cache slots.
      Gate: scratch-index publish→get round-trip in the suite.
- [done] **E5 — extras release lane** — the e2-e6 PR — `extra/v*` tag series; bump
      rule extended per-module without retriggering the toolchain
      lane; CI gates `extra/` build+test; release docs.
      Gate: dry-run derivation + workflow lint; first `extra/v0.1.0`.
- [done] **E6 — polish issues** — the e2-e6 PR — #26 json surrogates (impl), #27
      errors.Is/As (bounded design + impl), #29 net DNS (bounded
      design + impl), #30 time stopgap (impl); #28 → parked
      (needs runtime type descriptors — recorded, issue closed,
      parked-stdlib updated). Parallel-ok throughout.

**Milestone E exit:** workspace + fetch + index verified end-to-end
by suite fixtures; `extra/testutil` published and consumed on both
paths (workspace + cache); #26/#27/#29/#30 closed, #28 parked;
first `extra/v*` release cut.

## Milestone G — pointer

GUI lands under this layout as `extra/gui` + `extra/gui/gtk`
(spec'd at G0): G1 core + mock backend ← E2; G2 GTK4 backend;
G3 chan event model; G4 widget tranche; G5 reference apps; G6
second-backend sketch + docs. G0 may start once E0 lands.
