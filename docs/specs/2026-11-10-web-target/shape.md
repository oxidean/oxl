# Web compilation target (JS/HTML/CSS) — Shaping Notes

## Scope

Milestone W from the phase-2 map, un-parked when G landed: a
JavaScript backend for the whole language — emitter, runtime shim,
driver flag, std/env surface, and the DOM GUI backend the
guardrail was kept for. Lands as `bootstrap/codegen/js/` +
`runtime/{rt.mjs,rt-node.mjs,rt-browser.mjs}` + `extra/gui/dom` +
a `oxl --target js` driver lane and a node-gated test section.

Not this spec: Worker/SharedArrayBuffer blocked threads,
`--int-mode number` fast path, static-site/template/CSS emit,
a wasm target (LLVM backend owns that story), a Rust-seed JS
emitter, checker-level blocking rejection, a web framework layer.

## Evidence

- `docs/semantics/interfaces.md`: the codegen seam was designed
  swappable — "`codegen/` is the only cc-aware module". A JS
  emitter is a sibling consumer of `check.CkRes` + `susp`.
- Recon (`context/references/web-target-recon.md`): `rt.c` is
  ~35% platform machinery a JS GC erases (arenas, ObjHdr,
  mutex/CV/thread veneer; borrow *checks* port as a ledger) and ~65% semantics rt.mjs
  re-expresses (scopes+traps+defers, chans/select, named scopes,
  err registry, slice/str traps).
- `docs/gui-backends.md` DOM sketch: the Backend iface "ports;
  nothing in the contract is GTK-shaped beyond the thread rule,
  and even that holds in the DOM world". `Prop`→attrs,
  `WidgetKind`→elements, `Event`→listeners, `pump`→susp event-loop
  drain.
- Executor reality: frame tasks are already poll-driven state
  machines (`docs/semantics/concurrency.md`) — they map onto a
  microtask run queue cleanly. The blocking surface exists only
  for thread-task trampolines and has no single-thread
  equivalent.

## The decision

**A sibling `.oxl` emitter + a `rt.mjs` semantic runtime + env-flavor
extern shims.**

- `bootstrap/codegen/js/` — `emit(r, testm) -> str` over the same
  `CkRes`. Emits `out.mjs` text importing `./rt.mjs`.
- `runtime/rt.mjs` — scopes/traps/defers, frame-task run queue,
  chans/select/named scopes, shared cells, err registry,
  slice/str ops, borrow-ledger checks. No arenas, no threads.
- `runtime/rt-node.mjs` / `rt-browser.mjs` — `__oxl_ffi` pre-fill:
  Node wires `os`/`exec`/`net`/`filepath`/`log` to node builtins;
  browser fills the same names with `err`-stubs.
- Driver: `build|run|test --target js`; run/test exec `node`;
  `--html` writes a module-script host page.
- `extra/gui`/`extra/gui/mock` port unchanged — they are the JS
  conformance suite. `extra/gui/dom` is the new backend;
  `examples/web-todo` is the reference app.

Representation contract (details in `js-semantics.md`):

| oxl | JS | | oxl | JS |
|---|---|---|---|---|
| `int`/`err` | `BigInt` (asIntN-64 helpers) | | `[]T` | `{a,off,len,cap}` view |
| `float` | `Number` | | `str` | `{u8,off,len}` byte view |
| `byte` | masked `Number` | | `bool`/`nil` | `boolean`/`null` |
| `own`/`ref`/`mut` | plain ref | | `chan` | object per rt.mjs §chan |
| `shared` | `{v}` cell | | fn val | closure |
| `cstr` | JS string (edges) | | iface | `{obj,methods}` |
| `[v,err]` | `{val,err}` | | extern | `__oxl_ffi.<name>` |

## Stage map

`plan.md` carries the stage contracts. W1 rt.mjs core; W2 emitter
non-concurrency surface; W3 concurrency surface; W4 driver +
test lane; W5 std/env shims; W6 `extra/gui/dom` + example + docs.
Each stage's gate is observable suite green, not review-shaped
artifacts.

## Risk

- **BigInt ergonomics** — every arithmetic op routes through a
  helper; emitted code must never let a raw `Number` leak into
  int positions (extern args, slice indices internal-use only).
- **Blocking-surface honesty** — `spawnBlocking`/blocking
  recv/`usleep` trap loudly (`rt_trap(21)`); std docs must name
  the limitation or users will hit silent divergence.
- **str boundary correctness** — decode/encode crossings are the
  bug farm; `js-semantics.md` pins exactly where conversion is
  legal.
- **Single-thread truth** — no mutexes in rt.mjs, but claim/
  unlink ordering from rt.c's chan/select paths must be
  preserved verbatim or races become invisible misordering.
