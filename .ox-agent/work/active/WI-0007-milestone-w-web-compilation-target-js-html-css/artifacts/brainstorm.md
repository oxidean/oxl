# WI-0007 brainstorm — milestone W: web compilation target (JS/HTML/CSS)

Context: the trigger fired when G landed — the widget tree proved
DOM-mappable (`docs/gui-backends.md`). Recon
(`context/references/web-target-recon.md`) mapped the seams: a JS
backend is a sibling emitter over the same `check.CkRes`, plus a
`rt.js` runtime shim, a driver `--target` flag, and a node-gated
test lane. These are the forks inside that shape.

## Fork W-a — `int` representation: BigInt vs Number

oxl `int` is i64, wrap-on-overflow; `err` is int64 interned codes.

| option | shape | tradeoff |
|---|---|---|
| **A. BigInt** | codegen emits `rt_iadd`/`rt_imul`/… helpers applying `BigInt.asIntN(64, …)`; literals emit `123n`; `Number` only at extern boundaries | exact i64 semantics incl. overflow/shift/div; slower arithmetic; awkward Number mixing (every interop cast explicit); `itoa`/`scas`/err codes port cleanly |
| B. `Number` | ints are plain doubles | fast, idiomatic; **silent precision loss past 2^53**; wrong wrap/shift semantics — a language-visible lie |
| C. `Number` + range check | trap on |x|>2^53 | no wrap bug but still a reduced range; check cost on every op |

Recommendation: **A** — a compiler target that changes integer
semantics isn't the same language. BigInt helpers are mechanical;
the perf concern is parked behind a later `--int-mode number` flag
if a real consumer measures it.

## Fork W-b — `str` representation: byte substrate vs JS string

oxl `str` = `{p,n}` UTF-8 bytes; `len()`/`byteat`/`substr`/`str as
[]byte` are byte ops; `std/unicode/utf8` decodes manually. JS
`string` is UTF-16 — `len` and indexing diverge observably.

| option | shape | tradeoff |
|---|---|---|
| **A. `OxlStr{u8,off,len}` view** | Uint8Array backing + offset; literals TextEncoder-encoded at init; `substr` = O(1) view; `as []byte` = same buffer | byte-faithful — every std byte op ports literally; boundary (DOM/console/extern) pays a decode per crossing; two artifacts (view vs JS string) need care at extern edges |
| B. JS `string` | str → string | idiomatic, free DOM interop; `len`/`byteat`/`substr` all wrong; `str as []byte` forces re-encode anyway — the byte ops can't be faked |
| C. Array-of-codepoints | str → uint32 array | correct indexing but `len()` becomes codepoints not bytes — still a semantic lie, and every literal pays explode |

Recommendation: **A** — the byte ops in std make B a fiction; A is
the same `{buf,off,len}` shape slices already need, so one view
type serves both. Decode happens once at system edges
(`rt_print_str`, DOM `set_prop`, `__oxl_ffi` args).

## Fork W-c — executor: blocking surface on a single thread

Frame tasks (poll state-machines) map onto a microtask run queue
directly. The blocking surface (`rt_send`/`rt_recv` blocking,
`rt_scope_join_named`, `spawnBlocking`, `usleep`) exists only for
thread-task trampolines — JS has no threads to block.

| option | shape | tradeoff |
|---|---|---|
| **A. All-frame model + trap-on-blocking** | JS codegen emits only poll frames; every spawn builtin-call becomes a poll-able trampoline; `spawnBlocking`/blocking-extern/`usleep` emit `rt_trap` | zero dead machinery; honest failure mode; `spawnBlocking` programs (http server, DNS) are Node-anyway and could later get Worker |
| B. Worker threads | spawnBlocking → `Worker` + SharedArrayBuffer + `Atomics.wait` | real blocking, but SAB requires COOP/COEP headers — dead on arrival for plain file:// and most static hosts; huge runtime surface for a v1 |
| C. Emulated blocking via asyncify-style transform | suspend whole call stack as continuations | re-implements the frame transform for *every* call — the compiler already does this only for `susp` fns; doubling it is a second codegen |

Recommendation: **A** — frame-only is the clean semantic subset;
the blocking surface traps with a named code (`rt_trap(21)` —
"blocking surface unsupported on this target") so misuse fails
loud at the call, not as a hung loop.

## Fork W-d — extern binding: the invented seam

C emit references externs by bare name → cc link. JS has no link;
emitted calls need a binding convention.

| option | shape | tradeoff |
|---|---|---|
| **A. `globalThis.__oxl_ffi` registry** | emitted calls `__oxl_ffi.name(args…)`; user/runtime assigns the object before `oxl_main`; runtime env file (rt-node/rt-browser) pre-fills std shims | zero module machinery; works from script tag, ESM, or node REPL; user shims are one file; collision-safe name |
| B. ESM `import` from `./ffi.js` | emitted code imports a sibling the user writes | real module graph but *requires* a bundler/module-loader context — breaks `node out.js` single-file runs; missing file = parse error not runtime err |
| C. Generated registration table | emit `register_ffi({…})` call user fills | same as A with extra emit surface |

Recommendation: **A** — registry with env pre-fill. `rt.js`
detects Node (`typeof process`) and wires `rt-node.js` shims;
browser gets stub-fns returning `err`/`rt_trap` per call contract.
Extern *pair-return* fns keep the `o_ret_*` shape: `__oxl_ffi.f`
returns `{val, err}`.

## Fork W-e — emit form: file layout + module type

| option | shape | tradeoff |
|---|---|---|
| **A. `out.js` + `rt.js` siblings** | emit writes program JS; driver copies `runtime/rt.js` (+ `rt-node.js`, `rt-browser.js`) beside it; `out.js` does `import './rt.js'` then calls `rt_run_root` | mirrors the `rt.c`-copy model verbatim; runtime diffable/versionable separately; `node out.js` needs ESM (`import` → `.mjs`/package.json or ESM syntax in `.js` under `--experimental` — actually node ≥20 runs `.js` ESM only inside a `"type":"module"` package) |
| B. Single concatenated `out.js` | `emit` returns `rt.js_text + program_text` like the `#include "rt.h"` prepend | one artifact, `node out.js` works CJS-style; runtime not separately inspectable; embeds a *copy* of rt.js text in the binary (self-hosted driver reads `runtime/rt.js` at build time — needs it shipped beside the driver like rt.c already is) |
| **C. A, with `.mjs` + host flag** | as A but emit `out.mjs` (ESM) + optional `--html` emitting a bare `index.html` host | ESM is the DOM story's native form (script type=module); node runs `.mjs` unconditionally; the html scaffold is a template, not codegen |

Recommendation: **C** — `out.mjs` + copied `rt.js`/`rt-node.js`/
`rt-browser.js` siblings under a scratch or `-o` dir; `oxl run
--target js` execs `node out.mjs`; `--html` (opt-in) also writes a
module-script `index.html`. Program text references `rt.js` via a
static `import` — real module resolution, no bundler needed.

## Fork W-f — HTML/CSS scope

The milestone title says JS/HTML/CSS — the honest core is the JS
target + the DOM story it unlocks.

| option | shape | tradeoff |
|---|---|---|
| **A. `extra/gui/dom` backend + host page** | gui DOM backend (WidgetKind→elements, Prop→attrs, Event→listeners, pump→microtask drain) + `examples/web-todo` + `--html` scaffold | HTML/CSS = the GUI layer's rendering, not a second emit mode; scope stays compiler-shaped |
| B. Static-site emit mode | oxl emits HTML/CSS from declarative widgets | a *second* frontend (templates, layout, styling model) — a separate milestone disguised as a flag |

Recommendation: **A** — DOM backend inside the existing Backend
iface; CSS ships as user assets next to `index.html`. No
stylesheet emit, no HTML templating — those belong to a web-app
framework layer above the language, parked with a stated trigger.

## Fork W-g — blocking-surface enforcement level

| option | shape | tradeoff |
|---|---|---|
| **A. Runtime trap only** | `spawnBlocking`/blocking-extern/`usleep` emit trap calls on JS target | minimal checker surface; misuse found at run |
| B. Checker warning + runtime trap | check emits `target_blocking` warning diag when the target is js | early signal; needs target plumbed into `check` — a new cross-stage input for one warning |

Recommendation: **A** — runtime trap; the unsupported set is small
and documented in `docs/web-target.md`. Check stays
target-agnostic (its contract).

## Fork W-h — own/borrow machinery under GC

Arenas/ObjHdr/borrow flags exist for manual memory + aliasing
traps. JS GC removes the memory need entirely.

| option | shape | tradeoff |
|---|---|---|
| **A. Erase** | `rt_alloc`→`new`/GC; borrow calls → no-ops; `rt_free`→no-op; move rules stay compile-time | smallest rt.js; no runtime aliasing traps — but native doesn't trap on shared-state races either (borrow checks gate *call args*, not heap lifetime) |
| B. Dev-mode borrow flags | keep rt_borrow_* as debug instrumentation | behavioral parity nobody's testing; double the flag surface |

Recommendation: **A** — erase. `chan own T`'s `drop_elem` thunks
become no-ops (nothing to free); documented in the target doc.

## Fork W-i — codegen placement

| option | shape | tradeoff |
|---|---|---|
| **A. `bootstrap/codegen/js` package, .oxl** | sibling emitter over `CkRes`; `emit(r,testm) -> str` mirrors codegen's signature | follows T philosophy — the .oxl toolchain is the real surface; compiles through the seed like all oxl; no Rust mirror needed |
| B. Also port to `oxl/src/codegen.rs` | Rust seed gains `--target js` | doubles emitter surface for a bootstrap-only binary; dual-driver parity covers shared commands only — no requirement exists |

Recommendation: **A** — `.oxl` only, named
`bootstrap/codegen/js/` to sit beside `codegen/`. Seed untouched.

## Fork W-j — test lane

| option | shape | tradeoff |
|---|---|---|
| **A. node-gated section in run.sh** | `command -v node` → for each whitelisted test: `oxl build --target js` → `node out.mjs` → same `grep -q` asserts | reuses the suite's assert style verbatim; whitelist = the pure-std + `conc_*` + `gui_*`-mock set — the JS conformance suite |
| B. Separate `tests/run-js.sh` | new script | duplicates the suite's scaffolding for a conditional section |

Recommendation: **A** — one suite, a `RUN_JS` gate like the GTK
gate (`pkg-config gtk4`) and DISPLAY gate already used.

## Fork W-k — slice representation detail

| option | shape | tradeoff |
|---|---|---|
| **A. `{a:Array,off,len,cap}` uniform** | all `[]T` one view type; `push` mutates `a` in place within `cap`, allocs beyond; index → `a[off+i]` + bounds trap | aliasing slices work (`s[1:3]` shares `a`); cap amortization preserved; one runtime shape for every elem kind |
| B. TypedArrays for `[]byte`/`[]int` etc | Uint8Array/Float64Array per elem kind | faster raw math; but generics + `own []T` erase the per-kind win; two slice shapes to keep consistent |

Recommendation: **A** — one view type; `[]byte` gets a Uint8Array
*a* only where `str`-interop already needs bytes (same substrate
as W-b's backing).

## Resolved without fork

- `bool`→`boolean`, `float`→`Number`, `nil`→`null`, `byte`→masked
  `Number`, `cstr`→JS `string` at extern edges, `fn val`→closure,
  iface→`{obj,methods}` vtable object, `shared`→`{v}` cell,
  `[v,err]`→`{val,err}`.
- `rt_select_poll`'s uniform-random pick is preserved (seeded
  Math.random — semantic, not crypto).
- `pump`/`stop`/`wake` for `gui/dom`: microtask drain, flag, and
  `queueMicrotask` nudge — the root-task rule is trivially true.
