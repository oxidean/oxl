# TLS in oxl

Status by milestone: X1 shipped `crypto/rand` + hashing, X2 AEAD
primitives, X3 bignum + RSA verify, X4 P-256/P-384 + Ed25519 +
X25519, and **X5 ships `std/crypto/x509`** — certificate parsing,
path building, trust anchors, hostname verification, and platform
root discovery. The TLS record/handshake layer and `https://` in
`net/http` are later milestones; this document grows with them.

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
