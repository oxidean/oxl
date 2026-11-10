# Product Roadmap

## Phase 1: MVP (v0.0.1)

- Language semantics annex: ownership rules, coroutine semantics,
  compiler interface contracts
- De-risking prototype: state-machine transform + ownership-check spike
- Compiler skeleton: lexer/parser → AST → typechecker → native codegen
- Minimal runtime: scope arenas, ownership metadata + checks,
  scope-contained traps
- `[v, err]` error returns with must-use checking; C FFI
- Integrated toolchain binary: build, run, test, fmt, doc, LSP
- Concurrency runtime: single-thread executor, scopes, channels,
  multithread work-stealing pool
- Service-shaped stdlib subset; generics (type parameters with
  constraint interfaces)
- Pilot apps under `examples/`: CLI; HTTP CRUD server + SQLite
- Open-source plumbing: MIT license, CI, release builds, docs

## Phase 1.5: v0.2 Forward Work (spec'd — `docs/specs/2026-11-04-0132-v0-2-forward/`)

- **Track A (critical path):** state-machine coroutine transform,
  `select`, buffered channels
- **Track B (self-host features):** `enum`, `match`, slices `[]T`,
  function values, `defer`, `std/collections` maps/sets
- **Track C (self-host compiler):** `bootstrap/check.oxl`,
  `bootstrap/codegen.oxl` — the full bootstrap chain
- **Track D (type depth):** `float`, `own` move tracking, methods +
  interface dispatch, shape-based generics, module qualification
- **Track E (tooling):** LSP hover/goto, AST-printer fmt, platform
  matrix CI (aarch64/macOS/Windows)
- **Track F (pilot):** GUI app — GTK4 FFI bridge first, portable layer
  remains the charter

## Phase 2: Post-v0.2

Milestone map: [docs/specs/2026-11-07-phase-2-plan/](../specs/2026-11-07-phase-2-plan/shape.md)

- **T — toolchain-in-oxl**: shipped — `cmd/oxl` is `.oxl` end to
  end; cargo is out of the build path
- **E — monorepo / oxl-extra**: `extra/` module for packages outside
  `std`, `oxl.work` workspaces, git-backed index + `oxl publish`
  (absorbs registry), polish issues
- **G — portable GUI layer** in the language (charter path) as
  `extra/gui` + `extra/gui/gtk` — shipped; spec:
  `docs/specs/2026-11-09-gui-layer/`
- **W — web compilation target**: shipped — `--target js` emit
  (node + browser flavors), `extra/gui/dom` backend, `web-todo`
  reference app; spec: `docs/specs/2026-11-10-web-target/`
- Parked on triggers (each unparks when its trigger fires, then
  takes the normal spec → work-item → PR loop):
  - LLVM backend — trigger: the C emit lane hits a wall the
    `interfaces.md` codegen seam can't route around (optimization
    ceiling, platform reach) or a second backend consumer arrives
    to prove the seam.
  - D4 shape-generics — spec item exists
    (`docs/specs/2026-11-04-0132-v0-2-forward/items/d4-shape-generics.md`);
    trigger: generic-heavy builds show measurable bloat or compile-
    time pain — pure backend optimization, semantics unchanged.
  - reflection-class stdlib (runtime type descriptors) — trigger:
    a stdlib surface needs runtime type introspection (generic
    fmt, serialization, plugin dispatch).
  - TLS/x509 — trigger: first consumer needing authenticated or
    encrypted transport beyond cleartext `net`; spec must cover
    the x509 trust story, not just a wrapping API.
  - `pin` primitive — trigger: FFI or IO needs address-stable
    values (OS async handles, self-referential own graphs).
  - parked-stdlib list — per module, trigger: a real consumer
    demands it; files one work item each.

(The compiler already compiles itself — see `docs/self-hosting.md`;
"T" retires the Rust seed driver, not the compiler.)
