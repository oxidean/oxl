# TLS in oxl

Status by milestone: X1 shipped `crypto/rand` + hashing, X2 AEAD
primitives, X3 bignum + RSA verify, X4 P-256/P-384 + Ed25519 +
X25519, **X5 ships `std/crypto/x509`** — certificate parsing, path
building, trust anchors, hostname verification, and platform root
discovery — **X6 ships `std/net/tls`** — a client-only TLS 1.3
stack: record layer, the CH→(single) HRR→server-flight→CV→Finished
state machine, the full HKDF key schedule, X.509 chain + hostname
verification, NST consume-ignore, KeyUpdate consume+reply+rotate,
and `dial`/`dial_timeout`/`client` over `net.Conn` — and **X7 ships
`https://` in `std/net/http`** — the `Url.secure` / `Client.tlscfg`
seam that closes the milestone.

## `crypto/x509` surface

```oxl
struct Cert { raw, version, serial, issuer, subject, issuer_der,
              subject_der, not_before, not_after, dns_names,
              ip_addrs, is_ca, max_path, ku, eku, sig_alg,
              spki_alg, spki, skid, akid, sig, tbs }
struct Roots { cas: own []Cert }

parse_cert(der) -> [Cert, err]
parse_pem(text) -> [own []Cert, err]          // every CERTIFICATE block
(r mut Roots).load_pem(text) -> [int, err]    // count appended
(r mut Roots).append(c)
load_system_roots() -> [Roots, err]
verify(leaf, untrusted, roots, name, at) -> [own []Cert, err]
match_hostname(c, name) -> err
```

`SIG_*` is the signature-algorithm acceptance set
(`rsa_pkcs1_sha256|384|512`, `rsa_pss_sha256|384|512`,
`ecdsa_p256_sha256`, `ecdsa_p384_sha384`, `ed25519`); `SPKI_*` the
key families (`rsa`, `ec_p256`, `ec_p384`, `ed25519`). Errors are
sentinels — `err_der err_alg err_sig err_expired err_notyet err_ca
err_eku err_path err_root err_name err_roots` — returned wrapped in
detail text, so callers branch with `errors.is(e, x509.err_alg())`
and never match message strings.

## Trust roots: resolution order

`load_system_roots()` walks, first non-empty wins:

1. `OXL_SSL_CERT_FILE` (PEM bundle), then `OXL_SSL_CERT_DIR`
   (directory of `*.pem`/`*.crt`/`*.cer` files).
2. `SSL_CERT_FILE`, then `SSL_CERT_DIR`.
3. The POSIX bundle paths (`/etc/ssl/certs/ca-certificates.crt`,
   `/etc/pki/tls/certs/ca-bundle.crt`, `/etc/ssl/ca-bundle.pem`,
   `/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem`,
   `/etc/ssl/cert.pem`, `/etc/ssl/certs/ca-bundle.crt`,
   `/etc/ssl/certs/ca-bundle.trust.crt`,
   `/var/lib/ca-certificates/ca-bundle.pem`,
   `/etc/ssl/certs/ca-certificates.pem`).
4. macOS: `security find-certificate -a -p` against the System Root
   Certificates keychain (never the user's default chain).
5. Windows: `powershell.exe -NoProfile -Command` dumping
   `Cert:\LocalMachine\Root` and `Cert:\CurrentUser\Root` as PEM.

A set-but-broken env override fails `err_roots` naming the variable
— overrides are loud, never silently ignored, and every file an
override names must strict-parse. Platform candidates parse
leniently instead: a malformed block inside a shared system bundle
is skipped rather than sinking the whole store. Exec-based discovery
spawns once per process (memoized in a `shared` cell); the returned
`Roots` is a per-call value. Everything empty → `err_roots` naming
`OXL_SSL_CERT_FILE` as the override.

## Verification model

- Path building is depth-first from the leaf over `untrusted`
  intermediates then pool members, linked by DER-equal
  issuer/subject names (printable strings are display-only),
  tightened by AKID==SKID when both exist. Loops cap at 8 links.
- Every non-anchor link enforces: DER issuer match, signature over
  `tbs` under the issuer's SPKI (real RSA v1.5/PSS, ECDSA
  P-256/P-384, Ed25519 verification through X3/X4), `is_ca`,
  `keyCertSign` when KU is present, `max_path` against the
  subordinate-CA count, the validity window at `at`, and EKU
  containing serverAuth or anyEKU when present.
- Leaf checks: validity at `at`, `sig_alg` in the acceptance set
  (SHA-1/MD5/SHA-224/unknown OIDs all die `err_alg` here), EKU
  absent/anyEKU/serverAuth, and KU `digitalSignature` when present.
- **Anchors are trusted by store membership.** A `roots` member
  terminates the path on its DER alone: its self-signature is never
  verified and its own validity/CA/KU/EKU fields are exempt — a
  SHA-1-signed root already in the store still anchors, matching
  real trust-store behavior.
- `Roots{cas: nil}` is "no pool given" — the TLS layer (X6) treats
  that as "load system roots"; a non-nil-but-empty `cas` is a
  deliberate pin to zero anchors and fails every chain `err_root`.
- `verify` returns the owned path `[leaf, intermediates..., anchor]`
  on success; `name == ""` skips hostname verification, otherwise it
  runs after the chain verifies.

## Hostname matching

- IP literals (dotted-quad v4 or `[v6]` bracketed) match `ip_addrs`
  only, canonicalized (v6 → lowercase RFC 5952), never `dns_names`.
- DNS names lowercase-compare against `dns_names`. `*.example.com`
  spans exactly one left-most label; `*` anywhere else is literal.
- **No CN fallback.** A certificate with zero SANs fails every name
  check — subject CN is display-only.

## Documented divergences (X5)

These are deliberate, spec-owned positions; reversing them needs an
explicit ask, not a bug report.

- **No revocation checking.** No CRL, no OCSP, no stapling. The
  trigger for revisiting is a revocation requirement in a consumer
  milestone.
- **`nameConstraints` is not processed.** A *critical*
  nameConstraints fails `err_der` at parse (the processed critical
  set is exactly {basicConstraints, keyUsage, extKeyUsage, SAN,
  SKID, AKID}); a non-critical one is ignored per RFC 5280.
- **`_DIR` is not the OpenSSL `capath` layout.** Directories are
  scanned flat for `*.pem`/`*.crt`/`*.cer` — no hashed symlinks —
  and under an env override every matched file must parse.
- **Strict DER.** Indefinite lengths, non-minimal encodings,
  negative INTEGERs, trailing garbage, and BIT STRINGs with nonzero
  unused bits (where the field requires none) are `err_der`, not
  tolerated-BER.
- **Anchor exemption.** Store membership alone vouches for an
  anchor — its own signature, expiry, and constraints are not
  re-evaluated.
- **Display names are lossy.** issuer/subject strings skip
  T61String/TeletexString and other unmapped tags; DER bytes are
  the comparison key, so path building is unaffected.

## `net/tls` surface (X6)

```oxl
struct Config { server_name: str, roots: x509.Roots,
                alpn: []str, verify: Verifier }
iface Verifier { check(leaf: x509.Cert, untrusted: []x509.Cert) -> err }
struct Conn { ... }   // net.Conn parity: read/write/close/rawfd +
                      // asreader/aswriter/ascloser/asreadwriter, peer()

default_cfg() -> Config
dial(host, port, cfg) -> [Conn, err]             // server_name <- host
dial_timeout(host, port, tmo_ms, cfg) -> [Conn, err]
client(inner: net.Conn, cfg) -> [Conn, err]
```

Client-only TLS 1.3. Cipher suites `TLS_AES_128_GCM_SHA256`,
`TLS_CHACHA20_POLY1305_SHA256`, `TLS_AES_256_GCM_SHA384` in that
order; groups x25519 + secp256r1/secp384r1 key shares; one
HelloRetryRequest honoured (cookie echoed, demanded group must be
offered). Verification defaults to `x509.verify` + `match_hostname`
against `cfg.roots` (nil roots = lazy system store); a non-nil
`verify` replaces both — there is no `insecure_skip_verify`.
Reads deliver application data only: post-handshake
NewSessionTickets are consumed and ignored, KeyUpdate is consumed,
answered when `update_requested`, and both epochs rotate; an
orderly `close_notify` reads as `io.eof()` while a bare TCP close
surfaces `err_eof` — truncation is never silent. `close()` emits a
best-effort `close_notify` then closes the inner socket and is
idempotent.

Explicitly out of scope: TLS <= 1.2, server side, resumption/PSK/
0-RTT, client certificates (a CertificateRequest is answered with
an empty Certificate per RFC 8446), and OCSP/CRL.

## `net/http` seam (X7)

```oxl
struct Url { host: str, port: int, path: str, secure: int }
// parse_url: "https://" → secure=1, port 443; "http://" or bare →
// secure=0, port 80; other schemes stay an err.

struct Client { tmo: int, tlscfg: tls.Config }
new_client(tmo) -> Client        // tlscfg = tls.default_cfg()
```

A secure URL dials `tls.dial_timeout(host, port, cl.tmo, cl.tlscfg)`;
the client's budget bounds the TCP connect and doubles as the
handshake-flight receive timeout. Two defaults are applied per
request, never to the caller's Config: `server_name` fills from the
URL host when empty (IP literals included — the iPAddress SAN check
needs them) and `alpn` fills to `["http/1.1"]` when empty. The
`host:` header appends `:port` only when the port differs from the
scheme default — no spurious `:443`. Redirect resolution
(`resolve_location`) is scheme-aware end to end: `https://`
Locations, scheme-relative `//h/p` on a secure base, and relative
merges all keep the scheme, and `same_origin` includes `secure` so
credentials never cross an http→https hop. HTTPS through an HTTP
proxy needs CONNECT tunneling — parked — so a configured proxy on a
secure URL errors rather than silently going direct or cleartext.
`serve` is untouched; a TLS listener is not part of this surface.

## Error taxonomy

`request`/`do` surface failures in three layers, all `err`:

| layer | examples | caller meaning |
|---|---|---|
| transport | net dial errors verbatim | host unreachable, refused |
| protocol | `err_proto`, `err_alert` (alert name in text), `err_eof` | peer not TLS, mid-handshake cut |
| trust | `err_sig` `err_expired` `err_notyet` `err_ca` `err_eku` `err_path` `err_root` `err_name` `err_alg` `err_der` `err_roots` | the x509 verdict |

Trust errors are never flattened into "handshake failed" — the
verdict rides in the error text, so a failed `https.get` says
*which* check lost and `errors.is(e, x509.err_root())` stays
actionable ("add the CA to `OXL_SSL_CERT_FILE`", "clock is wrong").

## Divergences, posture, non-goals

- **Truncation fails loud.** A TLS peer that closes TCP without
  `close_notify` surfaces `err_eof` — where permissive HTTP/1.1
  stacks would deliver the partial body, this client returns the
  error. Orderly `close_notify` is the only clean end.
- **Side-channel posture is documented, not claimed.** `.oxl`
  arithmetic compiles through C with no constant-time discipline —
  branches on secret material are written, not eliminated. The
  exposure is narrow for a client (session keys, not long-term
  identity keys) and the verify-only design ships no signing
  oracle. A constant-time pass is parked; trigger: first
  server-side or signing consumer.
- **Non-goals with their reopen triggers** (each becomes a work
  item when its trigger fires):
  - TLS server (`tls.listen`/`accept`) — first serving consumer
    needing inbound TLS.
  - TLS 1.2 fallback — first consumer hitting a 1.2-only endpoint.
  - Session resumption / PSK — measured reconnect cost on a real
    workload.
  - Client certs (mTLS) — first consumer needing mutual auth;
    brings the signing surface back into scope.
  - Revocation (OCSP/CRL) — first consumer needing revocation
    proof.
  - Bundled root list — first consumer on a platform image with
    no store and no way to set the env override.
