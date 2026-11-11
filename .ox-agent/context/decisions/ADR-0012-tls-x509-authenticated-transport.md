# ADR-0012: TLS/x509 — pure-.oxl TLS 1.3 client, trust story in std, verify-only crypto

Status: accepted (WI-0009) — 2026-11-11

## Decision

Milestone X un-parks `crypto/tls` + `x509` for the driving consumer
(`std/net/http` `https://`): a client-side **TLS 1.3-only** stack
written fresh in `.oxl` from RFC 8446 + companion RFCs, over one new
rt.c veneer (`rt_csrand`), with the x509 trust story as a real
package (`std/crypto/x509`: DER parse, chain build/verify, platform
root loading, SAN-only hostname matching) rather than a delegated
one.

Spec-level forks resolved (detail in
`docs/specs/2026-11-11-tls-x509/`):

1. **Fresh-from-RFC .oxl over platform-TLS veneers or a vendored C
   lib.** The S4 crypto ethos ("written fresh in oxl from the public
   specs — no C port") scales: one behavior across all three CI legs,
   every line reviewable, no new link surface (the `rt_sqlite_`-style
   `-D`/`-l` pattern stays untouched). The alternatives — OpenSSL/
   Schannel/SecureTransport per-platform veneers (divergent verify
   semantics, deprecated-or-async macOS APIs, the trust story
   delegated exactly where the trigger demands it be owned) or a
   vendored mbedtls (~100k lines of un-auditable-in-repo C) — lose
   on the same axis. Cost stated honestly: the largest .oxl surface
   yet, gated on external vectors + live interop, never
   self-consistency.
2. **TLS 1.3 only.** No 1.2 negotiation, downgrade sentinels hard-
   alert, no renegotiation. Suites: `TLS_AES_128_GCM_SHA256`,
   `TLS_CHACHA20_POLY1305_SHA256`, `TLS_AES_256_GCM_SHA384`; groups
   `x25519`/`secp256r1` shares (+`secp384r1` via HRR).
3. **Verify-only asymmetric crypto.** `rsa` (v1.5+PSS verify),
   `nistec` (P-256/P-384 ECDH+ECDSA verify), `ed25519` (verify), `x25519`
   — no sign/encrypt/decrypt surface until a consumer asks.
4. **Roots resolve env → platform → fail-loud.** `OXL_SSL_CERT_FILE`/
   `OXL_SSL_CERT_DIR` (then `SSL_CERT_*` fallbacks) → POSIX bundle
   paths / macOS `security` exec / Windows `Cert:` via PowerShell →
   `err_roots` naming the override. No bundled Mozilla list.
5. **Hostname: SAN-only, wildcard single-label, iPAddress for IP
   literals, no CN fallback; SHA-1/MD5 signatures hard-fail.**
6. **Expiry hard-checked; revocation parked** (no CRL/OCSP) with a
   documented trigger — stated, not half-implemented.
7. **No `insecure_skip_verify`.** `Config.verify` is the override
   hook; `Config.roots` is the pinning path.
8. **Constant-time is documented, not claimed.** `.oxl` gives no
   constant-time discipline; client-handshake posture is recorded
   in docs/tls.md; the pass re-opens with the first server-side or
   signing consumer.

## Consequences

- Seven implementation stages (X1–X7): entropy+hashes → AEAD →
  bignum+rsa → curves → x509 → tls wire → https seam; each a PR
  through the review loop with suite-green gates.
- rt.c grows exactly one always-needed extern (`rt_csrand`,
  `-DOXL_CRYPTO`-gated, `-lbcrypt` on Windows); root loading uses
  `os/exec` against OS tools instead of new C.
- `std/crypto` roughly triples; `bignum` is public-but-documented
  as crypto-internal (the language has no internal-package rule).
- `http` gains `Url.secure` + `Client.tlscfg`; `serve` untouched.
- js lane: tls packages compile (pure .oxl) and their socket use
  inherits net's documented trap path.
