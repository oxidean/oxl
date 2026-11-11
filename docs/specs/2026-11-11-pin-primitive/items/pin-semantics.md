# `pin`/`unpin` semantics contract

What `pin` and `unpin` mean in the `own`/`ref`/`mut` ownership model
(`docs/semantics/ownership.md`), what guarantee a pinned value gives
an FFI consumer, and how pinning interacts with scope/task
machinery. This is the contract both checkers and both runtimes
implement when the trigger fires (plan.md P2/P3/P4).

## The guarantee, stated exactly

A pinned object has two properties for as long as its pin count is
non-zero:

1. **Its address does not change.** (Already true of every
   `rt_alloc_own` block — pin adds nothing here; it exists so the
   claim is contractual, not incidental.)
2. **It is not reclaimed.** `rt_free` on a pinned object traps
   (code 11); the `chan own T` `drop_elem` path reaches the same
   `rt_free` and traps identically. Scope close does not reclaim it
   — `own` storage is never scope-tracked.

Pin says nothing else: not immutability (writes stay legal), not
exclusivity (`ref`/`mut` borrows of a pinned object are ordinary
borrows), not thread placement (the other `pin` — see shape.md's
disambiguation), and nothing at all about the *handle*. **Pin binds
the object, not the binding**: the oxl variable may die, go out of
scope, or sit idle — the guarantee is to the address the foreign
consumer recorded.

## What can kill an `own` object, and what pin does about it

| death path | source | pin's answer |
|---|---|---|
| `rt_free` from C/externs | `rt_str_free` precedent (`extra/gui/gtk/gtk.oxl`) | trap 11 while pinned |
| `drop_elem` on `chan own T` | scope teardown, `close` drain, retracted `try_send` (rt.c:1507-1970) | same `rt_free` → trap 11; the send itself is a compile error while pinned, so the trap is a second line, not the primary check |
| scope close | arena bulk-free | N/A — `pin` requires `own`; `own` is never arena-backed (`alloc_in`'s `!own` guard, rt.c:77) |
| future own-handle reclamation | ownership.md:29 reserves it ("does not emit ... today") | pinned objects are exactly the set that must be exempt — writing the pin contract now keeps a later reclamation pass honest |
| process exit | OS teardown | out of scope — no guarantee can survive it |

## Surface

```oxl
b := mkbuf(4096)              // or new(T), own []T — any `own T` binding
pin(b)                          // statement builtin — mark pinned
unpin(b)                        // statement builtin — release
```

`pin`/`unpin` join the builtin family (`mkbuf`, `mkshared`,
`close`) — not keywords, not statement forms in the grammar. On the
seed driver that means `BUILTINS` (check.rs:270) plus handling in
the call-name dispatch; on the bootstrap driver the builtin-name
table (check.oxl:2638) plus its `expr` dispatch. Codegen emits
`rt_pin(x)` / `rt_unpin(x)`; for `own []T` operands it emits
`rt_pin_slice(x)` / `rt_unpin_slice(x)` (header box + backing —
both are `rt_alloc_own` blocks, both pinnable).

## Checker rules

A `pinned` set rides `env` next to `moved` (same `Vec<HashMap>`
shape in the seed checker — check.rs:139 — and the same `SList`
shape in the bootstrap checker — check.oxl:395). Entries:

- `pin(x)`: `x` must be an Ident whose binding is `own T` for any T
  (`own`, `own void`, `own []T`, `own Struct`, ...). Diagnostics:
  "`x` is not an `own` binding — pin requires owned storage" for
  non-`own` args; "`pin` takes a binding, not an expression" for
  non-Ident args (a pinned rvalue can never be tracked or
  released). `pin` on an already-pinned binding: "`x` already
  pinned" — keeps the object count binary per binding so
  `unpin`'s release is unambiguous.
- `unpin(x)`: same Ident/`own` requirements; "`x` is not pinned"
  when the binding's mark is clear. `unpin` clears the mark.
- Rebinding a pinned binding (`b = ...`, `b := ...` in a shadowing
  scope is fine — that is a new binding) clears nothing silently:
  assignment to a pinned binding is a move-adjacent act on the live
  handle, so it is rejected like a move site ("`b` assigned while
  pinned — unpin first"). Re-*binding* by shadowing is a new name
  and does not touch the mark.
- **Move sites on a pinned binding are compile errors** —
  "`b` moved while pinned — unpin it first": an `own` argument to an
  `own`/`iface` param, `send`/`try_send`, `return`, struct/enum
  field stores (`s.f = b`, `E.V{ f: b }`), and `spawn`/`goin` args
  (already a move). This is the checker's move-site set
  (`move_for`, check.rs) — a superset of the four ownership.md
  enumerates — plus the pinned check layered on it.
  The pin-set merges by **intersection** at joins: a binding
  counts as pinned at a point iff it is pinned on *every*
  non-diverging path reaching it (inside a pinning branch the
  mark holds and move-site bans apply there). Union would be
  unsound in both directions — `if c { pin(b) }` joining as
  pinned would compile a `pin`-param arg whose else path never
  pinned, and `pin(b); if c { unpin(b) }` joining as pinned
  would compile an `unpin` that traps on the taken path. The
  same balance rule `moved` applies to `for` bodies
  (ownership.md) applies here: pins introduced inside a loop
  body must be released inside it.
- Legal while pinned: field/index reads and writes through the
  handle, `ref`/`mut` borrows (a borrow is not a move; the object
  stays put and borrowed access is unaffected), passing `b` to an
  extern `pin` param (the point), and — deliberately — scope exit.
- **Derived bindings carry the mark.** `b2 := b` on an `own`
  binding is not a move site (the `cur := head` aliasing idiom),
  so the checker propagates `pinned` to same-object aliases
  created while the mark holds — otherwise `send(ch, b2)` would
  push a still-pinned object into `drop_elem` (trap 11 — the rt
  backstop is the second line, not the contract).
  Noted, not solved: the mark rides per-binding-name and the
  checker tracks no alias classes — an alias created *before*
  `pin(b)` runs, and a per-alias `unpin` after the object is
  released, both escape the compile-time surface; the rt pin
  count remains the enforcement (the former frees under a pin →
  trap 11, the latter traps on count 0).
- **`pin` and `push`:** `s = push(s, v)` where `s` is a pinned
  `own []T` binding is a compile error — "push may relocate the
  pinned backing; unpin first" (`rt_slice_push` allocates a new
  backing on growth, rt.c:2516). Element writes `s[i] = v` are
  fine — they go through the same backing.

## Runtime rules

`ObjHdr` gains `pinned` in the existing `_pad` byte — the header
stays 24 bytes, no ABI change (ownership.md:71-81).

- `rt_pin(obj)`: `hdr->arena` or `hdr->hscope` set → trap 11
  (any scope-lived block bulk-frees under a pin — arena memory
  frees wholesale, the checker should already have rejected
  non-`own` args — this is the second line). `pinned == 255` →
  trap 11 (overflow). Otherwise `pinned++`.
- `rt_unpin(obj)`: `pinned == 0` → trap 11 (double release — the
  release-protocol invariant is exactly-one). Otherwise `pinned--`.
- `rt_free(obj)`: `pinned > 0` → trap 11 before unlink/free. The
  `drop_elem` path flows through `rt_free` (codegen `o_drop_*`
  frees own fields then the object) so a buffered pinned payload
  traps at teardown — though the checker already bans the `send`.
- `rt_pin_slice(hdr*)`/`rt_unpin_slice(hdr*)`: pin/unpin the
  `RtSlice` box, then its `->ptr` backing (a second `ObjHdr`).
  Order matters on release: backing first, then header — freeing a
  pinned header while the backing is still counted keeps the trap
  ordering deterministic.

Trap code 11 is an unused native code (11) (2 = borrow moved-from/
aliasing, 3 = assert, 9 = unreachable/enum-unwrap, 10 = slice
bounds, 21 = JS blocking surface). Pin traps name the violation
"pin contract."

## Release protocol

Exactly one release per pin, from either side:

- **oxl-side release:** `unpin(b)` after observing completion —
  the completion itself arrives by the ordinary machinery
  (chan/shared/`select`), there is no special pin-aware
  delivery.
- **C-side release:** the shim calls `rt_unpin(ptr)` inside its
  completion/destroy callback — the `rt_free`/`rt_str_free`
  precedent: rt exports are already C-callable.

Both paths on one pin is a contract violation — the second
`rt_unpin`/`unpin` traps on the zero count. Which side releases is
part of the extern's contract, documented per decl like GTK's
destroy-notify rule.

## Scope and task interaction

- **Pin outlives the pinning scope by design.** `own` storage is
  not scope-tracked, so a pinned binding going out of scope (block
  exit, `scope{}` close, task settle) leaves a live pinned object —
  that is the async pattern, not a bug. No diagnostic. The handle
  being gone means release must come from `rt_unpin` on the C side;
  a pin no one releases leaks exactly like any `own` today.
- **Task migration cannot move a value.** A suspended task resumes
  on whichever pool worker dequeues it; its frame block (one
  `rt_task_new` allocation) and every `own` object stay at fixed
  addresses. Pin is therefore *not* about scope/task movement —
  there is none to prevent. What task machinery *can* do is move
  ownership (`send`, spawn args) into a path that frees — the
  checker's move-site ban is what covers that.
- **Cancellation**: a task cancelled while holding a pinned
  binding unwinds normally; the object survives pinned. If the
  cancelled task was the intended releaser, the pin leaks — same
  class as a leaked `own`, and the reason C-side release is the
  recommended protocol for completion-driven flows.
- **`spawn`/`goin` args** are move sites — a pinned binding cannot
  be sent into a task while pinned. Borrow args are already banned
  across spawn (check.rs:2530) and an `own` arg is a move, so a
  pinned object does not cross a spawn boundary in any direction —
  it is effectively owner-task-confined for oxl access while
  pinned, which is correct: the retainer is on the foreign side.
  A spawned task that needs the buffer gets the handle *after*
  `unpin` restored the move.
- **`Shared<T>`/shared words**: shared cells hold raw words —
  stashing a pinned object's address in one is outside the checked
  surface today (as is any word-stashed pointer). Contract rule:
  legal (the object stays alive), unchecked (no `unpin` tracking
  follows the word). Noted, not solved — same honesty level as
  `poke*`.

## `pin` type qualifier

`pin` joins the qualifier family (`own`/`ref`/`mut`) at type
position, with a v0 restriction: legal **only wrapping `own` and
only on `extern fn` parameters.**

- Grammar: `pin` wraps only `own`; `pin T` is sugar for
  `pin own T`. Bare `pin`, `pin ref`, `pin mut` → compile error.
- `pin` stays a contextual qualifier, never a keyword: the corpus
  binds `pin` as an identifier (`cmd/oxl/getmod.oxl`'s
  `[pin, pe] = pin_require(...)` — a `Kw::Pin`/`is_kw` entry would
  break the toolchain itself). Both drivers match the *text*
  `pin` in qualifier position inside `ty()`/`p_ty` only — the
  same positional matching `own`/`ref`/`mut` already use — and
  `pin`/`unpin` builtins are ident-dispatched calls like
  `send`/`close`, so no call-site grammar change is needed.
- Seed driver: `TyKind::Pin(Box<TyRef>)` in ast.rs:160, parser.rs
  `ty()` qualifier branch on the `pin` ident, `ty_text` →
  `"pin own T"`.
- Bootstrap driver: `p_ty`'s qualifier arm (parser.oxl:1105) +
  `ty_parse`'s qualifier arm (check.oxl:1980) + a `k_pin()` kind.
- Checker: `pin` qualifier anywhere but an extern param →
  "`pin` is only legal on `extern fn` params (v0)". `pin` on a
  return type is a separate question (foreign-to-oxl ownership
  transfer — returns stay `own`; a received `own` can be `pin`ned
  after arrival) and is rejected in v0.
- ABI: `pin own T` erases to the same pointer `own T` emits — the
  qualifier is a contract annotation, not a calling-convention
  change. JS lane: erases to raw ref like `own` (js-semantics §7
  arg mapping gains one row: "`pin own` → raw ref").

Arg rule at call sites: an argument to a `pin` param must be an
Ident bound to a pinned `own T`. Anything else — rvalue, unpinned
binding, non-`own` — is a compile error: "retained argument must
be a pinned `own` binding."

## JS lane mapping (rt.mjs)

`pin`/`unpin` enter the identity ledger next to the borrow ledger:
a `Map` on object identity counts pins; `unpin` on a zero count
traps (conformance with native), `pin` on arena/scope-shaped
storage is unreachable on JS (no arenas — the checker rule does
the work). `rt_free` is a no-op on JS so trap 11 cannot fire
there; the *checkable* behavior (move-freeze, pin-param arg rules,
double-unpin) is compile-time or ledger-time and ports exactly.
`pin` params on `__oxl_ffi` externs impose nothing at runtime —
the GC retains what the shim holds; the qualifier's job on JS is
documentation and checker parity.
