# WI-0009 brainstorm — TLS/x509 spec: authenticated transport

Context: the parked row (`parked.md`, `parked-stdlib.md`) reads
"a TLS stack is a project, not a package" with trigger "first
consumer needing authenticated or encrypted transport beyond
cleartext `net`; spec must cover the x509 trust story, not just a
wrapping API." The consumer is `std/net/http` `https://`. Forks
covered: the spec-level design space for the stack itself.

## Fork X-a — implementation strategy

| option | shape | tradeoff |
|---|---|---|
| **A. Fresh-from-RFC .oxl** | all primitives + x509 + record/handshake in packages; rt.c adds only `rt_csrand` | repo's S4 ethos verbatim ("written fresh in oxl — no C port"); identical behavior on all 3 CI legs; zero new link surface; every byte reviewable. Cost: largest .oxl surface yet; correctness gated on vectors + interop, no audit |
| B. Platform TLS in rt.c | OpenSSL / SecureTransport / Schannel behind `rt_tls_*` | audited crypto, free roots — but 3 divergent backends, macOS API deprecated-or-async, verify semantics the suite can't pin, trust story delegated (what the trigger forbids) |
| C. Vendored C TLS | BearSSL (1.2-only — fails floor), mbedtls (full but ~100k LOC) | dependency weight for least ownership; still needs a root-loading story it can't provide |

Recommendation: **A** — with verify-only scoping and external-vector
gates.

## Fork X-b — protocol floor

| option | shape | tradeoff |
|---|---|---|
| **TLS 1.3 only** | RFC 8446 floor+ceiling; sentinels alert | smaller surface (no non-AEAD suites, no RSA key transport, no renegotiation); every endpoint that matters speaks it |
| 1.3 + 1.2 AEAD fallback | +SHA-256 CBC/GCM 1.2 suites, different handshake | doubles handshake machinery for legacy reach nobody has asked for |

Recommendation: **1.3 only**; 1.2 parks with its own trigger.

## Fork X-c — trust-root sourcing

| option | shape | tradeoff |
|---|---|---|
| **env → platform store → err** | `OXL_SSL_CERT_FILE/DIR` → `SSL_CERT_*` → POSIX paths / `security` / `Cert:` via exec | zero new C; live stores; honest failure mode naming the override |
| bundled Mozilla list | roots compiled in | works on bare containers — but a security-maintenance treadmill the release process doesn't have |
| rt.c store veneer | CryptoAPI/SecTrust C | live stores without exec — ~150 lines platform C for what `os/exec` already reaches |

Recommendation: **env → platform → err**; bundling parks with a
trigger.

## Fork X-d — caller override shape

| option | shape | tradeoff |
|---|---|---|
| **`verify` hook + `roots` pool** | fn replaces chain+hostname; Roots pins CAs | every misuse requires a stated trust policy, not a shrug |
| `insecure_skip_verify: int` | the industry-standard footgun | one-line "disable authentication" flag — the most-abused TLS setting ever shipped |

Recommendation: **hook, no flag.**

## Fork X-e — hostname policy

| option | shape | tradeoff |
|---|---|---|
| **SAN-only** | dNSName/iPAddress, single-label wildcard | current browser practice; CN absence fails loudly |
| SAN → CN fallback | older libcurl-style | hides misissuance; blesses pre-2010 certs nobody should mint |

Recommendation: **SAN-only**, no fallback.
