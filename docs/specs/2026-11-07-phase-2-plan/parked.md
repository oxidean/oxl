# Parked work — reopen only on trigger

Nothing here is scheduled. Each item has a stated trigger; a trigger
firing moves the item into the milestone map via a new work item.

## LLVM backend

- **Status: shipped** — milestone L landed the lane:
  `bootstrap/codegen/llvm.oxl` behind the `CkRes` seam,
  `oxl build/run/test --target llvm` with `--triple`/`--emit-llvm`,
  rt.c under clang (>=15), the IR fixpoint + cross-lane parity
  gate. Docs `docs/llvm-target.md`; spec
  `docs/specs/2026-11-11-llvm-backend/`. What the milestone
  deliberately left parked (full text: the spec's `plan.md`
  §Parking rules):
  - `llvm.coro.*` native splitting — trigger: measured poll-
    dispatch overhead mem2reg/regalloc can't recover, or an
    async-ABI consumer
  - wasm32/wasi rt port — trigger: a wasm product target + an rt
    port design (rt.c's pthread/POSIX surface has no wasi spelling)
  - DWARF/`DIBuilder` debug info — trigger: native-debugger
    workflows on lane-compiled binaries
  - opt-metadata pass (`noalias`/`nonnull`/TBAA/`inbounds`) —
    trigger: a measured win, each attribute audited against
    borrow-check semantics first
  - `--emit-bc`/LTO/lld plumbing — trigger: a size/link-time
    consumer

## D4 shape-based generics

- **Why parked:** deferred with a real measurement in the v0.2 spec —
  3 generic fns in the entire corpus, zero shared-shape groups; type-
  dictionary passing is pure complexity at that scale. Re-measured
  2026-11-11 on the grown corpus (item doc): 22 generic fn defs,
  ~35 unique (fn,T) instantiations, one shareable pair — still
  ~2 orders under the bar.
- **Reopen trigger:** shared-shape groups grow enough that mono dedup
  is a *measured* win (the 11-11 count found one pair — existence
  alone isn't the bar; hundreds of mono'd bodies sharing a shape in
  one compile is).

## Pin primitive (address-stable values)

- **Why parked:** no consumer needed address-stable values; the
  runtime does not move objects, so pinning is a contract surface
  rather than a mechanism. (Distinct from the G spec's deferred
  thread-pin idea — same name, different ask; that one stayed
  parked inside the GUI spec.)
- **Reopen trigger:** fired — spec merged
  (`docs/specs/2026-11-11-pin-primitive/`); retire this section when
  the primitive ships.

## Parked stdlib list (`docs/specs/2026-11-06-0111-package-system/items/parked-stdlib.md`)

- reflection-class packages (`fmt %v`, `gob`, `xml`, `database/sql`,
  templates): need runtime type descriptors — type-descriptor
  milestone spec merged (`docs/specs/2026-11-11-type-descriptors/`);
  implementation tracked as WI-0008 (un-parks on impl)
- `crypto/tls`, `x509`, asymmetric crypto: **shipped** — milestone X
  (`docs/specs/2026-11-11-tls-x509/`): TLS 1.3 client `std/net/tls`,
  `std/crypto/x509`, `https://` in `std/net/http`, and the crypto
  beneath (`crypto/rand`, `sha512`, `hkdf`, AEAD, `bignum`, `rsa`,
  curves). Parked under live triggers: TLS server (`tls.listen`/
  `accept` — first serving consumer needing inbound TLS), TLS 1.2
  fallback (first 1.2-only endpoint), session resumption/PSK
  (measured reconnect cost), client certs/mTLS (first mutual-auth
  consumer), revocation OCSP/CRL (first consumer needing proof), a
  bundled root list (platform image with no store and no env
  override), and a constant-time pass (first server-side or signing
  consumer).
- `compress`/`archive` landed (`compress/{flate,zlib,gzip}`,
  `archive/{tar,zip}`); `net/url`, `container/{heap,list,ring}`
  implementations in flight on their own PRs — drop from this list
  on merge
- `image`: deferred until a real consumer exists
- `context`: deliberate non-goal — `scope` carries cancellation and
  deadlines
- **Reopen trigger:** the language machinery exists (type descriptors
  / reflection) or a concrete consumer demands the package.
