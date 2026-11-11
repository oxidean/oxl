# Phase 2 — Milestone Map

Milestones as scheduled. Each active entry gives a scope sketch,
entry criteria (what must be true to start), and exit criteria (what
"done" means). Implementation specs are written when a milestone
starts; this map is the schedule, not the design.

*Amended 2026-11-08 (WI-0004, ADR-0008): T shipped. The remaining
work regroups into **E** (monorepo + `extra/` + git-index + polish —
absorbs R and P) then **G** (GUI as an `extra/` citizen). Spec:
`../2026-11-08-monorepo-oxl-extra/`.*

## T — toolchain-in-oxl — SHIPPED

*Renamed from "Full self-hosting" — see `shape.md` and ADR-0003.*

Port the seed driver — today the Rust code under `oxl/src/` — to
`.oxl`.

**In scope:**
- `oxl` CLI: arg parsing, subcommand dispatch (`build`/`run`/`test`/
  `fmt`/`doc`/`get`/`mod`/`list`/`lsp`)
- Module machinery in the driver: `oxl.mod` manifest parse, MVS
  build-list, `~/.oxl/mod` cache layout, git fetch, `oxl.sum`
  `h1:` verify (sha256 dirhash already ported for the checker)
- `fmt` (AST printer exists in the seed; port or wrap)
- `doc` extraction
- `lsp` server (hover/goto — LSP plumbing is driver-side)
- `oxl test` runner orchestration
- A driver-side pipeline: invoke the self-hosted lexlib/parser/check/
  codegen components as libraries (they already self-compile; the
  driver becomes a `cmd/` over them)

**Out of scope (explicit):** compiler passes, runtime (`rt.c` stays C
— it's the platform runtime, not the toolchain), stdlib growth.

**Entry:** none — can start now.

**Exit:** `oxl` binary is built from `.oxl` sources; `cargo` is gone
from the build path (retained only as historical seed, if at all);
full `tests/run.sh` green under the self-built driver including the
bootstrap/diag gates.

**Shipped as:** T0–T6 merged (WI-0003); `cmd/oxl` is `.oxl` end to
end, cargo is out of the build path.

**Detailed spec + staged plan:**
[`docs/specs/2026-11-07-toolchain-in-oxl/`](../2026-11-07-toolchain-in-oxl/spec.md)
(WI-0003).

## E — monorepo: `extra/` + workspace + git-index + polish

*Added 2026-11-08 — absorbs R (rescoped to a git-backed index) and P
(issues placed in a stage). Spec: `../2026-11-08-monorepo-oxl-extra/`.*

**Scope sketch:** `extra/` subdirectory module
(`github.com/oxidean/oxl/extra`) for packages outside `std`;
`oxl.work` workspace resolution; tag-prefix subdir-module fetch;
git-backed index + `oxl publish`/`get`; `extra/v*` release lane;
P-track issues #26–#30 (#28 parks); `extra/testutil` first citizen.

**Entry:** none — starts now.

**Exit:** workspace + fetch + index verified end-to-end in the
suite; `extra/testutil` published and consumed on workspace and
cache paths; #26/#27/#29/#30 closed, #28 parked; first `extra/v*`
release.

## G — portable GUI layer

Widget layer in the language on top of the GTK4 FFI pilot
(`examples/gui-todo`).

**Scope sketch:** widget-tree abstraction with retained state,
layout model, event dispatch into `scope`/`select` concurrency,
platform backend interface with GTK4 as the first backend. The
widget tree must stay DOM-mappable — it is the agreed guardrail that
kept the web target open — later un-parked as milestone W
(`--target js`).
Lands as `extra/gui` + `extra/gui/gtk` — the first real consumer of
E's monorepo machinery.

**Entry:** G0 spec after E0 lands; G1 (core) needs E2 (extra layout
+ workspace).

**Exit:** a reference app with real widgets (beyond the pilot's
raw FFI calls); a second backend sketched or an honest written case
for why the abstraction doesn't foreclose one.

**Shipped as:** milestone G merged — `extra/gui` + GTK4 backend,
`examples/gui-todo`.

## W — web compilation target (`--target js`)

*Un-parked 2026-11-09* — its reopen trigger fired on G's merge:
the G spec shipped the widget tree DOM-mappable, which was the
guardrail keeping web parked. Spec and implementation are in
flight together on `feat/milestone-w` (PR open); work item WI-0007.

**Scope sketch:** a second emit lane beside native C —
`runtime/rt.js` semantic runtime (run queue, frame-task
scheduler, scope trees + cancel, err registry), `js` emitter for
the full surface incl. `susp` poll state-machines and
chans/select/named scopes, driver `--target js` on
build/run/test, node lane env shims (`rt-node.js`) with
`rt-browser.js` err-stubs, `extra/gui/dom` backend +
`examples/web-todo`. Blocking forms trap (`rt_trap(21)`), no
Worker/SAB lane.

**Entry:** G shipped (done — the DOM-mappable tree was the
gate); stages W1–W6 sequential per the spec plan.

**Exit:** JS lane green in the suite on CI (node-gated);
conformance — `conc_*` + `gui_*` (mock) files emit identical
output under `node out.mjs`; `examples/web-todo` live; the
guarded differences (repr, blocking traps) documented in
`docs/web-target.md`; WI-0007 shipped.

## R — package registry — FOLDED INTO E

*(letter later reclaimed by the type-descriptors milestone — spec
merged `docs/specs/2026-11-11-type-descriptors/`; implementation
WI-0008 in flight)*

*2026-11-08:* rescoped to a **git-backed index** and folded into
milestone E (stages E3–E5). `oxl get` consults the index via
`OXLMODINDEX` with direct-git fallback; `oxl publish` appends index
entries + pushes `<prefix>/v*` tags. Namespace = index-repo write
access. A hosted service stays parked in `parked.md` — adopting one
later is an `OXLMODINDEX` URL scheme, not a redesign.

## P — polish — FOLDED INTO E

*2026-11-08:* no longer opportunistic — all five issues are placed
in E's stage E6. Filed items:

- `std/encoding/json`: `\uXXXX` surrogate-pair decode edge cases —
  [#26](https://github.com/oxidean/oxl/issues/26)
- `std/errors`: `Is`/`As` (needs error-tree + typed-target design) —
  [#27](https://github.com/oxidean/oxl/issues/27)
- `std/fmt`: `%v` (needs reflection — may park, decide in issue) —
  [#28](https://github.com/oxidean/oxl/issues/28)
- `std/net`: DNS/`getaddrinfo` (needs a resolution API design) —
  [#29](https://github.com/oxidean/oxl/issues/29)
- `std/time`: revisit blocking-worker API stopgap —
  [#30](https://github.com/oxidean/oxl/issues/30)

## Parked

See `parked.md` — LLVM backend, D4 shape-generics, pin primitive,
parked-stdlib list. Each has an explicit reopen trigger; none is
scheduled.

## Sequence

```
T (shipped) ──► E ──► G ──► W  (registry-R, P absorbed into E;
                               W un-parked — G shipped the
                               DOM-mappable widget tree; R letter
                               reused by type descriptors)
└── LLVM, D4, pin, stdlib-list: parked on triggers
```
