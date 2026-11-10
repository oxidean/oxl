# ADR-0010: web target — sibling JS emitter, BigInt ints, byte-view strings, frame-only executor, __oxl_ffi externs

Status: accepted (WI-0007) — 2026-11-10

## Decision

Milestone W adds a JavaScript compilation target: a sibling
`.oxl` emitter (`bootstrap/codegen/js/`) over the same
`check.CkRes`, a `runtime/rt.mjs` semantic runtime, env-flavor
extern shims (`rt-node.mjs`/`rt-browser.mjs`), a `oxl --target js`
driver lane, a node-gated test section, and `extra/gui/dom` as
the DOM backend that justified un-parking.

Forks resolved (brainstorm detail in WI-0007 artifacts):

1. **`int` is `BigInt`** — `rt_i*` helpers apply
   `BigInt.asIntN(64)` so i64 wrap/shift/div semantics survive;
   `Number` exists only inside runtime internals (array indices,
   timers) behind a documented firewall. `Number`-as-int would
   silently lie past 2^53 — a compiler target that changes
   integer semantics isn't the same language.
2. **`str` is a byte view** — `OxlStr{u8, off, len}` over
   `Uint8Array`. oxl's `len`/`byteat`/`substr`/`str as []byte`
   are byte operations; JS `string` (UTF-16) cannot carry them.
   The only legal UTF-16 crossings are `rt_str_cstr`/encode at
   edges (print, DOM, `__oxl_ffi` args).
3. **Executor is frame-task-only** — every spawned call lowers
   to a poll-able micro-frame on a microtask/setImmediate run
   queue. The blocking surface (`spawnBlocking`, blocking
   `send`/`recv` in non-susp positions, `usleep`, raw blocking
   externs) emits `rt_trap(21)` — loud failure, not a hung loop.
   Worker/SAB emulation is parked (needs COOP/COEP headers).
4. **Externs bind via `globalThis.__oxl_ffi`** — emitted calls
   `__oxl_ffi.<name>(mapped…)`; `[T,err]` externs take
   `{val,err}` returns. `rt-node.mjs` wires std shims to Node
   builtins when `typeof process !== "undefined"`;
   `rt-browser.mjs` fills the same names with `err`-stubs. A
   missing name is a contract violation, not a `TypeError`.
5. **Emit `out.mjs` + runtime siblings** — module output
   importing `./rt.mjs`; the driver copies the rt files beside
   it (the `rt.c`-copy model verbatim). `.mjs` sidecars keep
   the files ESM under any ambient `package.json` `type`
   setting. `oxl run --target js` execs node; `--html` writes
   a module-script host page.
6. **own/borrow heap machinery erases under GC** — `rt_alloc`
   →`new`, `rt_free`→no-op, arenas absent. Dynamic borrow
   *checks* do not erase: overlapping same-task `mut`/`ref`
   borrows are observable (`TrapAliasing`), so `rt_borrow_*`
   port as a per-task ledger keyed on object identity in
   rt.mjs. Move rules remain compile-time.
7. **Slices `{a,off,len,cap}`** — one view type preserving
   `push`-into-cap growth and aliasing sub-slice semantics;
   `[]byte` is always `Uint8Array`-backed so extern writes
   land in caller storage, and `str`↔`[]byte` follows the
   native copy/view directions.
8. **No Rust-seed JS emitter** — `--target js` is OXL-driver
   only; the seed's role is bootstrap. Dual-driver parity
   covers shared commands; the js flag is not shared.
9. **HTML/CSS = the GUI layer** — `extra/gui/dom` inside the
   shipped `Backend` iface; CSS is user assets beside
   `index.html`. Static-site/templating emit is parked as
   framework-layer work.
10. **Check stays target-agnostic** — blocking-surface misuse
    is a runtime trap, not a diag; plumbing the target into
    `check` buys one warning for a new cross-stage input.

## Consequences

- `rt.mjs` re-expresses ~65% of `rt.c` (scopes/traps/defers,
  chans/select, named scopes, err registry, slice/str traps)
  while ~35% (arenas, ObjHdr, mutex/CV/thread veneer) evaporates
  under GC — the contract doc pins which claims carry over.
- `extra/gui` + mock become the conformance suite: they
  exercise typed chans + named scopes + cancel + select
  end-to-end, so `gui_*`/`conc_*` green under node is the
  semantic-parity gate.
- The `chan own T` drop-thunk field survives in `rt.mjs` as a
  no-op so emitter shape stays mechanical — documented, not a
  leak.
- Select keeps uniform-random arm pick (semantic, via
  `Math.random`) and cancel-until-deadline timer refs.
