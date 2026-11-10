# GUI backends — the contract and the second-backend case

`extra/gui` ships two backends and leaves room for more. This is the
G6 evidence doc: what a backend must implement, what the GTK port
proved, and where a third backend (a DOM-protocol target) stands.

## The Backend contract

    interface Backend {
        new(kind: WidgetKind, props: own []Prop) -> [int, err],
        set_prop(h: int, p: Prop),
        attach(parent: int, child: int),
        detach(parent: int, child: int),
        destroy(h: int),
        pump(events: mut EventBuf, cmds: mut CmdBuf),
        stop(),
        wake(),
    }

Obligations, all enforced or exercised by the suite:

- **Handles are monotonic ints** — never reused within a `gui.run`
  session. The backend tracks a live set for dead-handle checks and
  the exit sweep; it must not return from `pump` with live handles.
- **`pump` is the loop.** It runs inline on the root task, drains
  `CmdBuf` into toolkit calls, and posts toolkit events into
  `EventBuf` via `eb.post` (non-blocking, eviction policy inside).
  It blocks until `stop()` — `wake()` is the cross-thread nudge.
- **Dead-handle split.** Reads (`read`, `new_kind` parents) on dead
  handles reply `gui.err_gone()`; fire-and-forget `Cmd`s to dead
  handles are accepted-and-dropped. The mock records the drop so the
  rule is testable.
- **Post-stop.** `pump` must notice `stop` on its own — the watcher
  calls it from another task, so `stop`/`wake` are the only methods
  allowed off the root task and must be signal-safe. Everything else
  runs inside `pump`'s drain.

## What two backends proved

**mock** (`extra/gui/mock`) is pure oxl — no toolkit, a scriptable
`inject`, a call ledger tests assert on (`count("new")`). It
exercises the whole contract headless: dispatch end-to-end, the
`close_pending` dedup path, cancel-through-scope, overflow eviction.

**gtk** (`extra/gui/gtk`) is the real port: a ~490-line `gtk_shim.c`
generalizing the pilot's trampolines (signals → a lock-free C ring;
`pump` marshals triples into `Event`s between `Cmd` drains — toolkit
signals never enter oxl directly). It proved:

- the mailbox direction survives a real toolkit — GTK's
  thread-affinity requirement is exactly why `run` is root-task-only;
- `Prop`/`PropVal` covers every kind/prop the pilot needed — the
  union didn't need widening (a spec watch item, resolved);
- copy-at-boundary holds at a real FFI edge (`gx_read_str` copies);
- the selftest drives real signals (`gx_emit`/`gx_emit_row`) and
  asserts through the read path — the same `List.rows()` count the
  mock computes from child edges.

## The DOM case (honest sketch)

A third backend over a DOM protocol (websocket/CDP-style, or the
parked web target) maps without schema changes: `Prop` serializes
to attribute/property pairs, `WidgetKind` to element roles, the
`Event` kinds to DOM event names. Two real deltas: a remote pump is
latency-bound (the mailbox absorbs it unchanged), and row widgets
want a virtual-list extension — an `extra/gui/dom` sketch stays a
spec-shaped possibility, not committed surface. The honest verdict:
the protocol ports; nothing in the contract is GTK-shaped beyond
the thread rule, and even that (a main-loop thread) holds in the
DOM world.

## The `pin` question, revisited

G0 parked a `pin`-to-thread primitive pending second-backend
evidence. Two backends in: **stay parked.** The GTK backend — the
strictest case — is satisfied by the root-task rule alone, because
`rt_run_root` pins the root task to the process's main thread with
its own external park loop and no pool migration. A `pin` primitive
would only serve a backend needing a *dedicated non-main* thread;
no shipped backend does, and adding it now would be surface without
a consumer. Revisit when a backend's threading model demands it.

## Publishing

`extra/gui` rides the `extra/` module (`extra/oxl.mod`); backends
are ordinary packages inside it — consumers `oxl get
github.com/oxidean/oxl/extra` and import `.../extra/gui/gtk`.
`extra/gui/mock` is index-importable too, which is deliberate: app
test suites can drive the headless backend exactly like the repo's
own `tests/gui_*.oxl`.
