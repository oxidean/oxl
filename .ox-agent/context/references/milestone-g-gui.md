# Milestone G — portable GUI layer: discovery evidence (WI-0005)

Spec target: `extra/gui` + `extra/gui/gtk` — first real consumer of the
monorepo `extra/` machinery. Stage sketch: G0 spec → G1 core+mock → G2
GTK4 → G3 chan events → G4 widgets → G5 reference apps → G6
second-backend sketch + docs.

## Charter and guardrails (docs/specs/2026-11-03-language-design.md)

- GUI charter keeps three paths; milestone G is path (b): portable
  retained-widget layer written in the language.
- "main-pinned task owns UI" is a first-class concurrency concept.
- DOM-mappable widget tree is the agreed guardrail keeping the parked
  web target open — the spec must not foreclose a DOM backend.

## Owner-decided design forks (WI-0004 brainstorm, adopted)

- Paradigm: retained widget tree over a backend iface (A).
- Ownership: own-tree, scope-bound; `gui.Widget` iface for user-visible
  widget kinds, tree stays own-typed.
- Events: buffered `chan gui.Event` consumed by `select`; pilot-style
  `gui_connect` stays backend-internal.
- Backend: retained-widget protocol iface — new/set_prop/on_event/
  attach-detach/run; GTK4 first, DOM is the natural second backend.
- Packaging: `extra/` monorepo packages (owner direction 2026-11-08).

## Pilot evidence (docs/gui-pilot.md, examples/gui-todo/)

- GTK4 via C FFI works: opaque int handles, `extern fn`, `gui_connect`
  passes {env,fp} fn-values to a ~15-fn C shim (macro APIs can't be
  declared extern — every macro-heavy toolkit needs a shim).
- Selftest drives real GTK signals; churn to 100k cycles shows no
  constant-slope leak.
- Friction that becomes spec requirements:
  - `str(cstr)` borrow aliases the toolkit's buffer — boundary needs
    explicit ownership rules (copy-at-boundary or documented borrow).
  - GTK is thread-bound: every call on the `gtk_init` thread; the
    blocking pool is wrong for it. UI = pinned main task + channels.
  - Closure envs escape scopes already (own heap); captured *borrowed*
    scope data dangles — layer must document the rule.
- Per-backend surface is ~15 functions (window/box/entry/button/label/
  list/scrolled/connect/run) — a small honest contract.

## Dependencies — all landed

- `extra/` module + `oxl.work` workspace (E1–E6 merged, v0.8.0).
- scope/select/chan/go/spawn, ifaces+generics, own/borrow, defer,
  fn-values — all shipped.
- `extra/testutil` exists as the test-support pattern to reuse.

## Open questions the spec must answer

- UI-thread model surface: convention ("the task calling gui.run owns
  the toolkit") vs a language primitive — pilot doc says primitive
  would be needed "if the language grows native GUI support"; the
  layer can start with the convention.
- Event model detail: Event shape (kind/target/payload), delivery
  ordering vs `scope` cancellation, backpressure on the buffered chan.
- Backend protocol contract: exact iface methods + prop typing
  (stringly-typed props vs typed unions).
- Platform coverage honesty: GTK4 is Linux-first; Windows/macOS backend
  story belongs in G6's second-backend evidence, not G1.
- CI: gtk4-gated build+selftest pattern already exists in tests/run.sh;
  headless runs compile-only.
