# Web target — `--target js`

`oxl` compiles to JavaScript for node and the browser. The emitted
program is a single ES module plus the runtime files it imports;
there is no bundler step and no toolchain dependency past node (or
any ES-module browser).

## Flags

```
oxl build <pkg|file.oxl> --target js [-o out.mjs] [--html]
oxl run   <pkg|file.oxl> --target js        # execs node out.mjs
oxl test  <pkg|file.oxl> --target js        # test_* fns, same `… ok` lines
```

- `--target js` selects the JS emitter (`bootstrap/codegen/js.oxl`).
  Anything else is the native lane.
- `-o` names the emitted module (default `a.mjs` in the working
  directory — the js lane's `a.out`). The runtime files land next
  to it, not inlined.
- `--html` also writes `out.mjs.html`: a minimal page —
  `<div id="app"></div>` + `<script type="module">` — the DOM
  backend mounts on `#app` when present, `<body>` otherwise.

## Emit layout

```
out.mjs          the program
rt.mjs           semantic runtime — scheduler, chans, scopes,
                 defers, str/slice/int, err registry, ffi table
rt-node.mjs      env shims: fs/env/argv/exit/proc/net → node APIs
rt-browser.mjs   env shims: same names, err-or-trap contract
rt-dom.mjs       DOM extern provider — real document or the
                 headless object tree (tests + node)
```

`__oxl_boot` in rt.mjs picks the env flavor by sniffing
`process.versions.node`, then imports rt-dom which self-selects
real vs headless by `typeof document`. Programs that never touch
`extra/gui/dom` pay one small module load.

## Env flavors

- **node**: `os`/`os/exec`/`filepath`/`log`/`flag` work — files
  via `fs`, argv via `process.argv`, exec via `child_process`.
  `exec` calls block the cooperative VM for the child's duration
  (spawn wakes have no susp-extern bridge yet — a W follow-up;
  inside `gui.run` they freeze the pump). `net` and `sqlite`
  binds are present but trap code 21 — socket i/o and the C-lib
  dep have no cooperative-fiber/js mapping yet.
- **browser**: every env name is bound — file/proc/net calls
  return `err` codes where the contract permits and trap code 21
  where it does not. Nothing is unbound; a missing shim is a
  contract violation, not a `TypeError`.

## Extern convention

`extern fn name(args)` emits `__oxl_ffi.name(args)` verbatim:

- `int`/`err`/`byte` → `BigInt`; `float`/`bool` → JS primitives
- `str` → the oxl `{u8,off,len}` rep **end-to-end** — the emitter
  performs no boundary conversion; providers decode args with
  `rt_str_cstr` and construct `{u8,off,len}` returns themselves
  (`rt_readfile` does exactly this). `cstr` positions alone are
  JS `string` on the wire (e.g. `oxl_dom_tag` → String, consumed
  via the `str()` builtin)
- `[]byte` → `Uint8Array` view (writes land in caller storage);
  other slices → `{a,off,len,cap}`
- `[T, err]` returns → `{val, err}` with `err` a BigInt code

## Blocking traps (code 21)

The cooperative scheduler has no blocking waits inside vtable or
extern calls. These trap rather than silently mis-behave:

- `spawnBlocking f()` (raw blocking extern callees)
- `usleep` — deliberate blocking; `msleep`/`sleep_ms` inside susp
  context work (`setTimeout` + park)
- blocking send/recv positions a poll form cannot reach

## Representation deltas

- `int` is `BigInt` — arithmetic, comparisons, `itoa`/`atoi` all
  word-exact. `float` stays IEEE-754 `Number`.
- Own/ref/mut are GC'd object refs. `rt_free` is a no-op; the
  borrow *checks* remain as a per-task ledger (`Map` on object
  identity) so aliasing traps fire identically.
- `spawn`/`goin`/named scopes/select/`try_send`/`chan own T`
  run on the frame-task scheduler — conformance is asserted by
  the suite's w4 whitelist through `node out.mjs`.

## extra/gui/dom

The DOM backend renders `extra/gui` apps to real elements —
`window`→owned `<div>` under `#app`/`<body>`, containers→`<div>`,
`label`→`<span>`, `button`→`<button>`, `entry`→`<input>`,
`list`→`<ul>` with each attached row kept as its own widget tag;
events map `click`/`input`/Enter-keydown/row-click/`oxl-close`
onto the core `EventKind`s.
See `docs/gui-backends.md` and `examples/web-todo`.
