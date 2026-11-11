# Spec — milestone L: TLS/x509 — authenticated transport

Status: draft for review (L0)

## Problem

`std/net/http`'s client is the first consumer needing authenticated
transport beyond cleartext `net` — the parked `crypto/tls`/`x509`
row's trigger fired. The trigger requires the spec to cover the x509
trust story, not just a wrapping API.

## Direction (WI-0009 brainstorm — all forks resolved)

- **Fresh-from-RFC `.oxl` stack.** All primitives, the x509 path, and
  the TLS 1.3 record/handshake in packages; rt.c contributes only
  `rt_csrand` (`-DOXL_CRYPTO`-gated, `-lbcrypt` on Windows). Platform-TLS
  veneers and vendored C TLS weighed and rejected — one behavior
  across CI legs and the trust story owned in-repo outweigh audited-C
  delegation.
- **TLS 1.3 only.** Suites `TLS_AES_128_GCM_SHA256`,
  `TLS_CHACHA20_POLY1305_SHA256`, `TLS_AES_256_GCM_SHA384`; groups
  x25519/secp256r1 (+secp384r1 via HRR); downgrade sentinels alert.
- **Verify-only asymmetric crypto** — rsa v1.5/PSS, ECDSA P-256/P-384,
  Ed25519 verifies; x25519/P-256/P-384 ECDH. No signing/encryption
  surface.
- **Trust story**: DER parse → issuer/AKID path build → signature +
  validity + BC/KU/EKU checks → SAN-only hostname (no CN fallback;
  SHA-1/MD5 hard-fail). Roots: `OXL_SSL_CERT_FILE/DIR` → `SSL_CERT_*`
  → platform store (POSIX files / `security` exec / PowerShell
  `Cert:`) → `err_roots`. No bundled list; expiry hard-checked;
  revocation parked with trigger.
- **API**: `tls.dial`/`tls.client(net.Conn, Config)`; `Conn` is
  `io.R/W/Closer` + `rawfd` + `peer`; `Config{server_name, roots,
  alpn, verify}` — no `insecure_skip_verify`. `http` gains `Url.secure`
  + `Client.tlscfg`; `https://` at one seam.
- **Gates**: RFC/NIST vectors per primitive, RFC 8448 trace for the
  key schedule, checked-in x509 fixtures, `openssl s_server` interop
  behind `command -v openssl`.

## Non-goals

TLS server, TLS≤1.2, DTLS/QUIC, HTTP/2+, mTLS/client certs,
resumption/PSK/0-RTT, OCSP/CRL, issuance ops, bundled roots, name
constraints, `insecure_skip_verify`, js-lane transport, constant-time
guarantee (documented posture instead).

## Stage map

L0 spec → L1 entropy+sha512+hkdf → L2 AES-GCM+ChaCha20-Poly1305 →
L3 bignum+rsa → L4 curves → L5 x509 → L6 std/net/tls → L7 https +
closeout. Detail in `docs/specs/2026-11-11-tls-x509/plan.md`.
