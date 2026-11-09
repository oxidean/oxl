# ADR-0009: portable GUI layer — retained tree over Backend iface, chan events, convention-first UI thread

Status: accepted (WI-0005) — 2026-11-09

## Decision

Milestone G builds the charter's path (b): a portable widget layer in
`.oxl` under `extra/gui`, over a `gui.Backend` iface (new/set_prop/
attach/detach/destroy/pump/stop/wake). Spec-level forks resolved:

1. **UI-thread convention, not a language primitive** — the **root
   task** (the one executing `main`'s call chain) must call
   `gui.run`; it alone owns the toolkit. This is a mechanism, not a
   documented convention: the runtime pins the root task to the main
   OS thread and never pool-schedules it, while spawned tasks CAN
   migrate onto workers — so "the calling task" would be wrong, and
   a `go`/`spawn`ed `gui.run` is a contract violation `gui.run`
   itself rejects unconditionally; backends additionally check
   affinity via the dev gate. The check rides a G1 `is_root` flag
   marking only the task `rt_run_root` was ENTERED for — the
   process or test-binary root task, which is always the entry
   thread. A spawned frame that fell back to running inline through
   `rt_run_root` (thread creation failed, no pool workers) is NOT
   marked: it can sit on a non-entry thread, and GTK on the wrong
   thread is the exact hazard the check exists for — a fallback
   task gets `err_not_root`, not a pass. Test binaries still pass
   legitimately since their main IS their root task, so the mock
   suite keeps its `pump`-driving path without admitting
   fallbacks. A `pin`
   primitive stays parked and is revisited at G6 with two
   backends' evidence. Reversible either way.
2. **Single buffered `chan own Event`, app-side dispatch** — events
   are ordinary channel values `select`ed next to app channels;
   overflow
   policy is drop-oldest + an `overflow` marker event (input events
   never vanish silently).
3. **Typed public setters over a narrow `Prop{id,val}` protocol** —
   `button.set_label(...)` desugars to `set_prop`; `Prop` serializes
   to DOM attributes, serving the DOM-mappable guardrail.
4. **Pilot-parity first widget tranche** (window, vbox/hbox, label,
   button, entry, list, scrolled) — the protocol is the milestone,
   not widget count.
5. **`Backend` iface with a pure-oxl mock** — headless CI exercises
   the full protocol without a display; `extra/gui/gtk` wraps the
   pilot's generalized shim; a DOM-protocol sketch is the
   second-backend evidence.
6. **Copy at the boundary** — `str` getters return owned copies; no
   borrowed `cstr` aliases cross the public API (the pilot's named
   bug-breeding place).
7. **Commands are channel values too** (added at review) — events
   flow out on `events`; mutations flow back on `cmds`, a second
   mailbox (`CmdBuf`, not a chan) the `pump` drains on the root
   task. Widget mutators only enqueue; reads are `Cmd`s carrying a
   reply chan. This resolves
   the review-caught gap where the thread rule left event handlers
   no legal way to mutate widgets. Related fixes: `detach` never
   destroys (`destroy` is the single release op, idempotent on dead
   handles); `stop` is invoked by a `gui.run`-internal watcher task
   since a defer can't fire while `gui.run` still blocks; overflow
   drops oldest *drop-eligible* events, appending past `cap` —
   bounded by the live-window protected surplus — when only
   protected (`close_requested`) events remain.

## Rationale

- Paradigm-level forks were already owner-decided (WI-0004,
  2026-11-08): retained widget tree over backend iface; own-tree
  scope-bound ownership with `gui.Widget` for kinds; `chan own Event`
  events; retained-widget backend protocol; `extra/` packaging.
- The pilot (`docs/gui-pilot.md`) measured the seam: ~15 C functions
  per macro-heavy toolkit, `{env,fp}` closures as the event
  interface, thread affinity, and the two lifetime traps
  (borrow-alias, scope-arena capture) — each maps to a decision above.
- Convention-first on the UI thread avoids designing a language
  feature against one backend's constraints; G6 re-opens it with
  evidence.

## Consequences

- `gui.run` + `backend.stop()` is the documented enter/exit pair for
  the root task; scope cancellation reaches `pump` through
  `gui.run`'s internal watcher task — a `defer` on the pump-blocked
  task cannot run while it blocks (see
  `docs/specs/2026-11-09-gui-layer/items/event-model.md`).
- The language's suspend rules shape two surface details: `pump` is
  an iface method, so it must stay non-susp-capable — replies go out
  on `try_send` (widened to `chan own T` in G1 for exactly this
  reason), never blocking `send`; and `app` is a non-susp trampoline
  `fn(chan own Event)` — susp fns can't be fn values — whose body
  `go`s the real worker into `run`'s inner scope. `gui.Widget`
  likewise declares only non-susp methods; susp operations live on
  the concrete typed wrappers.
- Headless CI never blocks on a display: mock drives the protocol,
  gtk selftests are pkg-config-gated as today.
- Parked with triggers: `pin` primitive (G6 revisit), dialogs/a11y/
  HiDPI/menus/canvas (consumer demand), cocoa/win32 backends
  (platform coverage milestone, if ever).
