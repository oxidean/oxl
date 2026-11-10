# Milestone W — plan

Stages are sequential unless marked parallel-ok. Each lands as a
PR through the standard loop (suite green → CodeRabbit → merge).
W0 is this spec docset.

## W0 — spec (this docset)

`shape.md`, `plan.md`, `js-semantics.md`, `items/dom-backend.md`,
ADR-0010, WI-0007 artifacts. Gate: merged.

## W1 — `runtime/rt.js` core

The semantic runtime: run queue (microtask drain), frame-task
scheduler (`rt_spawn_task`/`rt_run_root` analogs), scope trees +
cancel + trap propagation + defer stacks, err registry, `OxlStr`
+ slice ops + bounds traps, `shared` cells, `{val,err}` helpers,
`is_root` (always true — every task is the main thread), and the
`__oxl_ffi` registry shell. Excludes chans/select/named scopes
(W3).

Gate: `rt.js` loads under node; a hand-written driver test drives
spawn/poll/scope/trap/defer paths green.

## W2 — `bootstrap/codegen/js` emitter — non-concurrency surface

Expressions/statements, fns + `[v,err]`, generics
(monomorphization, same queue model), structs/enums/match,
own/ref/mut as refs, slices (`{a,off,len,cap}`), strs
(`{u8,off,len}` + literal encoding), ifaces, fn vals, externs →
`__oxl_ffi.<name>`, defer (scope-drain), `assert`/bounds → traps.
GNU-stmt-expr sites lower to IIFEs/temp statements. Poll frames
only for `susp` fns *as needed by W3* — W2 emits direct-call
fns and proves the value surface first.

Gate: a curated pure-stdlib corpus (no chans/spawn) emits +
`node out.mjs` runs — `fmt`/`strconv`/`collections`/`regexp`/
`encoding`/`sort`-level tests green under a manual harness.

## W3 — concurrency surface

Emitter: `susp` fns as poll state-machines, `go`/`spawn`/`goin`
(all-frame), `send`/`recv`/`select`/`try_send`/`close`/`mkchan`/
`smkchan`, named scopes (`mkscope`/`curscope`/`scancel`/`sjoin`),
`is_root`, scope{} blocks. rt.js: chans (rendezvous + ring +
`chan own T`), select (random pick, timeout via `setTimeout`,
else, cancel-unlink), named-scope lifecycle. Blocking forms emit
`rt_trap(21)`: `spawnBlocking`, blocking `send`/`recv` in
non-susp context, `usleep`, `spawn f()` where f is a raw
blocking extern.

Gate: `conc_*` + `gui_*` (mock) suite files run under
`node out.mjs` with identical output — the conformance claim.

## W4 — driver lane + test integration

`cmd/oxl/main.oxl`: `--target js` on `build`/`run`/`test`;
`emit_and_js` (scratch layout, `out.mjs` + rt.js siblings copy,
`runtime_dir` probe reuse); `run`/`test` exec `node out.mjs`;
`--html` scaffold flag. `tests/run.sh`: `command -v node` gate +
the whitelisted section (W3's suite + W2's corpus) through the
self-built driver. `oxl test --target js` for `_test.oxl`.

Gate: suite green incl. JS lane on ubuntu+macos CI legs; lane
skips cleanly where node is absent.

## W5 — std/env shims

`runtime/rt-node.js`: `os` (fs/env/argv/exit), `os/exec`
(child_process), `net` (net/dns → shared cell), `filepath`
(path), `log` (timestr via Date), `testutil` reachable.
`runtime/rt-browser.js`: same names → `err` stubs. `extra/gui`
+ `extra/gui/mock` verified ported (they're pure oxl over the
concurrency surface — expected zero-change; any needed change is
a finding). `flag` under node.

Gate: `os`/`exec`/`net` smoke files green under node; browser
stub contract asserted (calls return `err`, never throw
unchecked).

## W6 — `extra/gui/dom` + reference app + docs

`extra/gui/dom/`: Backend over DOM — `new`→element create,
`set_prop`→attr/property, `attach`/`detach`→DOM ops, `destroy`→
remove, `pump`→microtask drain + DOM listeners → `eb.post`,
`stop`/`wake` flag+nudge. `examples/web-todo` + `--html` page +
user CSS. `docs/web-target.md` (flag surface, emit layout, env
flavors, ffi convention, blocking traps, representation deltas);
`docs/gui-backends.md` DOM sketch → shipped section; plan
markers `[done]`; WI-0007 → shipped.

Gate: `examples/web-todo` emits + a CI smoke asserts the page +
bundle structure; a DOM smoke (jsdom or light DOM stub in
rt-browser for tests) drives the backend contract paths the
mock's ledger can't reach — inject/ledger parity where feasible.

## Parking rules

- Worker/SAB blocking threads — trigger: real consumer needs
  `spawnBlocking` in-browser.
- `--int-mode number` — trigger: measured BigInt hot path.
- Web framework layer (templates/CSS emit) — trigger: product
  ask above the language.
