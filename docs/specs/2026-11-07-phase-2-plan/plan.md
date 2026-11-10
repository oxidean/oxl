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

## E — monorepo: `extra/` + workspace + git-index + polish — SHIPPED

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

**Shipped as:** E0–E6 merged (WI-0004); `oxl.work` workspaces,
subdir-module fetch, the git-backed index, the `extra/v*` lane,
and `extra/testutil` are on main (PRs #50–#53).

## G — portable GUI layer — SHIPPED

Widget layer in the language on top of the GTK4 FFI pilot
(`examples/gui-todo`).

**Scope sketch:** widget-tree abstraction with retained state,
layout model, event dispatch into `scope`/`select` concurrency,
platform backend interface with GTK4 as the first backend. The
widget tree must stay DOM-mappable — it is the agreed guardrail that
keeps the web target open (`docs/specs/2026-11-04-0132-v0-2-forward/items/parked-web.md` in the v0.2 spec).
Lands as `extra/gui` + `extra/gui/gtk` — the first real consumer of
E's monorepo machinery.

**Entry:** G0 spec after E0 lands; G1 (core) needs E2 (extra layout
+ workspace).

**Exit:** a reference app with real widgets (beyond the pilot's
raw FFI calls); a second backend sketched or an honest written case
for why the abstraction doesn't foreclose one.

**Shipped as:** G0–G6 merged (WI-0005); `extra/gui` core + mock +
GTK4 backends, the widget kinds, and `examples/gui-todo` are on
main (PRs #56, #59).

## W — web compilation target

*Added 2026-11-10 — the web target's parked-trigger fired when G
shipped. WI-0007; spec proposed at
`docs/specs/2026-11-10-web-target/` (lands with its own spec PR).*

**Scope sketch:** a JavaScript emit target — `runtime/rt.mjs`
semantic runtime; a `bootstrap/codegen/js` emitter (the value
surface first, then `susp` fns as poll state-machines); the full
concurrency surface (chans/select/named scopes over a microtask
run queue); a `--target js` emit lane with a node-gated suite
section; `rt-node`/`rt-browser` env shims; and `extra/gui/dom` —
the DOM backend the G widget-tree abstraction was shaped to keep
open — plus `examples/web-todo`.

**Entry:** G shipped (done — its DOM-mappable tree was the
guardrail); stages W0→W6 run sequentially, each a PR.

**Exit:** the conformance claim — `conc_*` + `gui_*` (mock) suite
files emit to JS and run under `node` with identical output; the
web-todo reference app runs on `extra/gui/dom`; a jsdom-class
smoke covers the DOM backend paths the mock's ledger cannot.

## R — package registry — FOLDED INTO E

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

See `parked.md` — LLVM backend, D4 shape-generics, parked-stdlib
list. Each has an explicit reopen trigger; none is scheduled. (The
web target's trigger fired when G shipped — it is milestone W now,
WI-0007, spec proposed at `docs/specs/2026-11-10-web-target/`.)

## Sequence

```
T, E, G (shipped) ──► W  (R, P absorbed into E)
└── LLVM, D4, stdlib-list: parked on triggers
```
