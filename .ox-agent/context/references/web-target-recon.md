# Recon — JS compilation target (WI-0007 discovery)

Codebase survey for milestone W. All anchors verified against the
tree; deeper detail lives in the session recon log.

## Where a JS backend plugs in

Pipeline is `source → parse → check → codegen → C → cc → native`
(`docs/semantics/interfaces.md`). Everything up to `check` is
target-agnostic; `codegen.emit(r, testm) -> str` consumes
`check.CkRes` and returns one C string (`bootstrap/codegen/codegen.oxl:5787`).
A JS backend is a **sibling emitter package** consuming the same
`CkRes` + `susp` set, plus three seams:

- **Driver flag** — no flag parser exists; `out_arg()` is a raw
  `argv` scan for `-o` (`cmd/oxl/main.oxl:483-495`). `--target js`
  slots into `cmd_build`/`cmd_run`/`cmd_test`, forking
  `compile_res` (`codegen.emit` at `:138`) and `emit_and_cc` (`:505`).
- **Runtime sidecar** — `emit_and_cc` copies `rt.h`/`rt.c` into a
  scratch dir (`:351-371`); `runtime_dir()`'s ancestor probe
  (`:208-252`) already locates `runtime/` — a `runtime/rt.js` probe
  reuses it verbatim.
- **Test lane** — `tests/run.sh` has no manifest; per-test
  `grep -q` asserts. A `command -v node`-gated JS section reuses
  the same output greps; `tests/diag/`+`tests/mod/` are check-side
  (dual-driver, no target dimension) and need nothing.

No Rust mirror required: the seed only bootstraps gen1
(`tests/run.sh:95`); `bootstrap/codegen/js.oxl` compiles through
`codegen.rs` like any source. `--target js` being OXL-only breaks
no dual-driver parity check.

## The semantic payload

`rt.c` (~4.4k lines) splits ~35% platform machinery a JS GC erases
(arena/ObjHdr/borrow bookkeeping, mutex/CV/thread veneer) and ~65%
semantics `rt.js` must re-express: scope trees + cancellation +
trap propagation, defer stacks, channel rendezvous/buffering/
select, named scopes, err registry, slice/str/bounds traps.

Executor: frame tasks (`rt_spawn_task`/`rt_run_root`,
`docs/semantics/concurrency.md:32-62`) are poll-driven
state-machines — they map onto a microtask run queue cleanly.
The *blocking* surface (`rt_send`/`rt_recv`/`rt_scope_join_named`)
exists only for thread-task trampolines (`spawn send(ch,v)`,
`spawnBlocking`) and has no single-thread-JS equivalent.

## Data representation pressure points

- `int` = `int64_t` wrap-on-overflow; `err` = int64 interned codes
  (`RT_ERR_BASE=1<<20`). JS `Number` breaks past 2^53 → spec
  decides BigInt-vs-Number.
- `str` = `OxlStr{p,n}` UTF-8 **bytes** — `len`/`byteat`/`substr`/
  `str as []byte` are byte ops; `std/unicode/utf8` decodes
  manually. JS `string` (UTF-16) cannot carry these semantics →
  a byte substrate (`Uint8Array` + offset views) is nearly forced.
- `[]T` = `{ptr,len,cap,heap}` — JS `{a,off,len,cap}` keeps
  `push`-into-cap and aliasing-slice semantics.
- `own`/`ref`/`mut` = pointers → plain JS refs (move-tracking is
  compile-time; no dangling checks emitted today).
- `chan` = `RtChan*` — JS object `{buf,head,count,cap,has,val,
  sendq[],recvq[],selq[],closed,dropElem,scope}`; mutexes/atomics
  evaporate single-threaded but claim/unlink ordering invariants
  must be preserved.
- `[v,err]` = `struct o_ret_*` → `{val,err}` pair.

## Extern/FFI — the invented seam

No shim table exists: emitted C references extern symbols by bare
name, resolved at cc link (`LANG_LDFLAGS` injects shim objects,
`cmd/oxl/main.oxl:443-452`). JS has no link step → the spec must
invent a binding convention (registry/module). Checker's extern
arg whitelist: `check.oxl:3873-3882`.

## std/extra portability

Pure-oxl (ports once rt.js builtins land): `bufio cmp collections
crypto/{aes,chacha20,sha256} encoding/{base64,binary,csv,hex} fmt
hash io maps math/rand regexp slices sort sync testing bytes
strings unicode/utf8 encoding/json errors strconv log math time
extra/gui extra/gui/mock`.

Node-only via shims: `os os/exec net net/http flag path/filepath
extra/testutil`. Native-only: `extra/gui/gtk`, sqlite surface.

`extra/gui` core is the flagship consumer of typed chans + named
scopes — `gui_*`/`conc_*` tests become the JS conformance suite.
`extra/gui/dom`: `Prop`→attrs, `WidgetKind`→elements,
`Event`→listeners, `pump`→event-loop drain — "the protocol ports;
nothing GTK-shaped beyond the thread rule" (`docs/gui-backends.md`).

## Undecided at discovery (brainstorm forks)

1. `int` representation: BigInt vs Number-with-caveat.
2. `str` byte-substrate shape + literal/boundary conversion.
3. Blocking surface (`spawnBlocking`/blocking recv/`usleep`) on a
   single-threaded target: runtime trap vs Worker vs reject.
4. Extern binding convention + env flavors (node vs browser).
5. Emit form: single-file `out.js` vs sidecar rt.js; module type.
6. HTML/CSS story scope: `gui/dom` backend + host-page scaffold
   vs a broader static emit.
7. Blocking-FFI compile-time vs runtime enforcement.
