# WI-0004 spec: remaining Phase-2 work — monorepo, oxl-extra, registry, GUI

Owner direction (2026-11-08): migrate the repo to a monorepo —
packages outside `std` live in-tree under an `oxl-extra` module —
and plan ALL remaining Phase-2 work, including open issues #26-#30,
as a bounded set of milestones. This spec covers that set as **two
milestones**: **E** (monorepo + extras machinery + git-backed
registry + polish) then **G** (portable GUI layer as the first real
`extra/` citizen). Deliverable of this WI is the planning increment:
this spec, a staged `plan.md`, ADRs, and updated `docs/specs/`
entries — shipped as one docs PR (WI-0003 precedent).

## Milestone E — monorepo: `extra/` + workspace + git-index + polish

Makes the repo a two-module monorepo and ships the registry as a
git-backed index. All driver work happens in `cmd/oxl` (`.oxl`) —
this milestone dogfoods T's port.

### In scope

1. **Repo layout**: top-level `extra/` directory holding packages
   outside `std`. One module for the extras (golang.org/x/*
   convention — single version series until a package needs its own
   cadence): `module github.com/oxidean/oxl/extra` rooted at `extra/`
   — a *subdirectory module*: repo root != module root.
   Root `oxl.mod` stays `github.com/oxidean/oxl`.
2. **Workspace resolution — `oxl.work`**: new file at repo root
   (go.work analog): `use` directive listing module dirs
   (`use ./`, `use ./extra`). When present, imports resolving under a
   `use` module's path resolve to that local tree — no `replace`
   plumbing, no publishing needed for in-repo consumers. Parse is
   the existing manifest grammar extended; diagnostics reuse
   `mod_*` codes. File-mode (no manifest) behavior unchanged.
3. **Subdirectory-module fetch + tag-prefix versions**: module
   cache entries for `…/extra@vX.Y.Z` come from tag `extra/vX.Y.Z`
   of the host repo. `modfetch` maps module-path suffix -> tag
   prefix -> subdir slice. `oxl.sum` hashes the *module* tree
   (subdir), not the repo. Requires the fetch veneer to slice the
   archive at the module root.
4. **Git-backed index**: registry = a git repo of metadata files,
   `index/<host>/<org>/<name>.json` per module — entries
   `{version, commit, h1}` appended per publish. `oxl publish`
   validates + appends + tags (`<prefix>/vX.Y.Z`); `oxl get`
   consults the index when configured (`OXLMODINDEX`, local-path or
   git URL), falls back to direct git `require`. Namespace =
   index-repo write access. Hosted service stays parked
   (`parked.md`).
5. **Release/CI for extras**: `extra/v*` tag series; the
   auto-release pipeline gains an extras lane (bump rule identical,
   tag prefix per module). CI builds + tests `extra/` packages on
   every PR; the suite gains an extras section gated the same way
   as examples.
6. **P-track — issues #26-#30** (fold in; surfaces are open):
   - #26 `std/encoding/json` surrogate-pair decode — implement.
   - #27 `std/errors` `Is`/`As` — bounded design (error wrapping
     chain + typed target match) + implementation.
   - #28 `std/fmt` `%v` — **park**: requires runtime type
     descriptors; record the decision and close the issue as
     parked with reopen trigger.
   - #29 `std/net` DNS — bounded design (resolution API shape)
     + implementation over the platform resolver.
   - #30 `std/time` stopgap API — implement.
7. **First citizen**: one real package lands in `extra/` proving
   fetch/workspace/publish end-to-end. Candidate: `extra/testutil`
   (assert/tempdir helpers duplicated across `tests/*.oxl`), with
   `examples/` and the suite consuming it via `oxl.work`.

### Out of scope

- Hosted registry service, publish auth beyond index-repo write
  access, web UI — parked.
- GUI work itself (milestone G).
- Per-package modules under `extra/` — single module until cadence
  demands otherwise (recorded as an ADR).
- New language features — `oxl.work` is manifest surface, not a
  language change; if E uncovers a genuine language gap it files a
  separate spec.

### Acceptance criteria (verifiable)

- `oxl build`/`run`/`test` in a module importing
  `github.com/oxidean/oxl/extra/<pkg>` resolves via `oxl.work`
  locally and via `extra/v*` tag through the cache — byte-parity
  diagnostics on both paths.
- `oxl.work` malformed/missing-dir/conflicting-module diagnostics
  land in `tests/diag/` corpus, both drivers byte-identical.
- `oxl publish` on a scratch index repo produces the tag + index
  entry; `oxl get` on a clean `OXLMODCACHE` resolves it; `oxl mod
  verify` catches a tampered entry (`h1` mismatch).
- Suite green on linux/macos/windows including the extras section;
  `extra/` packages unreachable from `std` unless imported (no
  bloat — the G1 reachability gate applies unchanged).
- Issues #26, #27, #29, #30 closed by their PRs; #28 closed as
  parked with the reason recorded in `docs/specs/.../parked-stdlib.md`.

## Milestone G — portable GUI layer (`extra/gui`)

Retained-widget-tree layer over a backend protocol iface; GTK4 is
the first backend. Forks adopted per brainstorm: retained widget
tree (not thin bindings, not immediate-mode), `own`-typed tree
bound to scope, buffered `chan gui.Event` consumed by user
`select`, retained-widget backend protocol. Lands under `extra/`
as `extra/gui` + `extra/gui/gtk` — first real consumer of E.

### In scope

1. **`extra/gui` core**: widget tree (`own` nodes, `gui.Widget`
   iface for user-visible kinds), `Event`/`Prop` types, backend
   protocol iface (`new`/`set_prop`/`on_event`/`attach`/`detach`/
   `pump`), headless mock backend for tests.
2. **`extra/gui/gtk`**: GTK4 backend over `gui_shim.c` (extended as
   needed) — window/box/entry/button/label parity with the pilot.
3. **Event model**: UI on the pinned main task; events on a
   buffered `chan gui.Event`; app code `select`s beside other
   channels. `gui_connect` stays internal to the backend.
4. **Widget growth** (scope bounded by the spec at G0): text,
   list/scroll, checkbox as the second tranche.
5. **Reference apps**: port `examples/gui-todo` to the layer; a
   second app exercising select-driven events alongside worker
   channels.
6. **Second-backend sketch**: DOM or platform-native written case
   satisfying the exit criterion; docs; dogfood in CI behind
   `OXL_GUI`.

### Acceptance criteria (verifiable)

- `gui-todo` ported to the layer builds+runs on GTK4 leg; the mock
  backend suite (tree ops, event dispatch, prop diffing) runs
  headless on all three platforms.
- The backend protocol is a real iface — mock and gtk backends are
  substitutable with no call-site change (proven by the suite
  driving both).
- Events arrive on `chan gui.Event`; a select-driven app handles a
  UI event and a worker message in one `select`.
- A written second-backend case (DOM sketch or platform-native
  doc) demonstrates the protocol is portable — reviewed doc, not
  code.
- No `extra/gui` import → zero GUI in emitted C (OXL_GUI gate +
  reachability hold).

## Cross-cutting constraints

- No AI attribution anywhere (commits, PRs, code, docs).
- `type(scope):` commit subjects; no `!`/`BREAKING` on docs PRs.
- Every stage boundary is its own PR through the CodeRabbit loop
  (approval + green CI) — matching T's cadence.
- The plan must not strand work: every stage lands mergeable with
  the suite green.

## Parked — unchanged

LLVM backend, web target (G preserves the DOM-map guardrail), D4
shape-generics, parked-stdlib (+`fmt %v` joining it via #28),
hosted registry service, `context`.
