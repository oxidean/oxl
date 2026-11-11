# items/x509-trust.md — the x509 trust contract

X5's deliverable and the reason the trigger exists: the roadmap says
the spec "must cover the x509 trust story, not just a wrapping API."
This file is that story, pinned end to end — parse, path build,
verify, roots, hostname, expiry, and the revocation stance.

## Package surface

```oxl
package x509    // std/crypto/x509

struct Cert {                       // a parsed certificate; fields
    raw: own []byte,                //  are populated lazily at parse —
    version: int, serial: own []byte,
    issuer: str, subject: str,      //  RDN → printable form — display
    //  only; path linking compares DER, never these strings
    issuer_der: own []byte, subject_der: own []byte,
    //  the raw Name encodings — OWNED copies (not slices into
    //  `raw`; the cert may outlive its parse buffer)
    not_before: int, not_after: int,//  epoch seconds (UTCTime/GenTime)
    dns_names: own []str,           //  SAN dNSName entries, lowercased
    ip_addrs: own []str,            //  SAN iPAddress entries —
                                   //  v4 dotted quad, v6 RFC 5952
                                   //  canonical (lowercase, ::)
    is_ca: int,                     //  BasicConstraints cA
    max_path: int,                  //  pathLenConstraint, -1 = unset
    ku: int,                        //  KeyUsage bitmask, -1 = absent
    eku: own []str,                 //  EKU OID strings, empty = absent
    sig_alg: int,                   //  signatureAlgorithm (enum below)
    spki_alg: int,                  //  subjectPublicKeyInfo alg
    spki: own []byte,               //  the raw SPKI (verify input)
    skid: own []byte, akid: own []byte,
    sig: own []byte, tbs: own []byte,
}
struct Roots { cas: own []Cert }

fn parse_cert(der: []byte) -> [Cert, err]
fn parse_pem(text: str) -> [own []Cert, err]     // every CERTIFICATE block
fn (r mut Roots) load_pem(text: str) -> [int, err] // count appended
fn (r mut Roots) append(c: Cert)
fn load_system_roots() -> [Roots, err]
fn verify(leaf: Cert, untrusted: []Cert, roots: Roots,
          name: str, at: int) -> [own []Cert, err]   // returns the path
          // name non-empty ⇒ match_hostname runs inside verify
          // after the path verifies; name "" skips it (the
          // Config.verify escape hatch decides its own policy)
fn match_hostname(c: Cert, name: str) -> err
          // exported separately so a custom Verifier can reuse
          // exactly this rule
```

`SIG_*` consts: `rsa_pkcs1_sha256|384|512`, `rsa_pss_sha256|384|512`,
`ecdsa_p256_sha256`, `ecdsa_p384_sha384`, `ed25519` — the acceptance
set, and it's a *set*: anything else (sha1, md5, sha224, unknown
OID) yields `err_alg` at verify. `SPKI_*`: `rsa`, `ec_p256`,
`ec_p384`, `ed25519`.

## DER / PEM

- Reader is definite-length only (DER and the cert form of BER both
  are), TLV-walking; indefinite form is `err_der`. Tags consumed:
  SEQUENCE, SET, INTEGER (positive only — leading-zero stripped),
  BIT STRING (unused-bits byte must be 0), OCTET STRING, NULL, OID,
  PrintableString, UTF8String, IA5String, BMPString (decoded for
  display only — never matched), UTCTime, GeneralizedTime, explicit
  context tags `[0]`/`[3]` per RFC 5280. String tags outside that
  set (T61String/TeletexString and friends — live in older real-world
  certs) are skipped, not `err_der`: issuer/subject strings are
  display-only, DER bytes are what's matched. UTCTime's 2-digit
  year follows RFC 5280: YY < 50 ⇒ 20YY, else 19YY.
- Rejects, all `err_der`: length over remaining bytes, 64-bit
  overflow lengths, negative INTEGERs, non-minimal length encodings
  (long form where short suffices), trailing garbage after the top
  SEQUENCE.
- PEM is `-----BEGIN CERTIFICATE-----` blocks → block framing
  strips the 64-col line wrapping, then `encoding/base64.decode`
  (strict alphabet + %4 padding — decode never sees the newlines);
  non-certificate blocks are skipped, so a mixed bundle file parses
  clean.
- `Cert` keeps `tbs` verbatim — signature verification covers the
  raw TBSCertificate bytes exactly as transmitted, never a re-encode.

## Path building and verification

`verify` builds a path leaf→root and checks it:

1. **Build.** Candidate issuers: `untrusted` intermediates (the
   server's Certificate flight) then `roots`. Link rule:
   `child.issuer_der` byte-equals `candidate.subject_der`
   (DER byte-equal — the printable forms are display-only), tightened to
   `akid`==`skid` when both present. Loops cap at 8 links —
   `err_path` beyond. First path that verifies wins; alternatives
   are tried (cross-signed roots).
2. **Per-cert checks, every link.** `at` inside
   `[not_before, not_after]` → `err_expired` / `err_notyet`.
   `sig_alg` ∈ acceptance set → else `err_alg` (SHA-1/MD5 are
   rejected *here*, not by omission — a chain containing one dies
   the same way whether it's leaf, intermediate, or a root that
   signed anything). Signature over `tbs` verifies under the
   issuer's SPKI → else `err_sig`. Verification is *real* — RSA
   v1.5/PSS, ECDSA P-256/P-384, Ed25519 — through X3/X4.
3. **CA checks on every issuer link.** `is_ca` → else
   `err_ca`. `ku` present → must carry keyCertSign. `max_path` ≥
   subordinate-CA count below it → else `err_path`. An
   intermediate carrying EKU that contains neither serverAuth
   nor anyEKU fails `err_eku` — an EKU-restricted CA can't
   vouch usages it isn't authorized for.
4. **Leaf checks.** EKU absent, anyEKU, or containing
   serverAuth → pass; otherwise `err_eku`. `ku` present → must
   carry digitalSignature (TLS 1.3 auth is always a signature).
5. **Trust anchor.** The terminal issuer must be a `roots` member
   (`raw`-equal) → else `err_root`. Anchors are trusted by store
   membership, so the anchor's own self-signature is never verified
   and the sig-alg check (step 2's SHA-1/MD5 hard-fail) does not
   reach it — a SHA-1 self-signed anchor in the store validates,
   matching real trust stores. The returned path includes the
   anchor.

NameConstraints is not processed — parked with the
revocation/name-constraint trigger. One floor rule: the
processed critical set is {basicConstraints, keyUsage,
extKeyUsage, SAN, SKID, AKID} — any *critical* extension outside
it fails `err_der` (a critical nameConstraints we can't honor
must not validate as an ordinary root); a non-critical
nameConstraints is ignored per RFC 5280. Deliberate divergence
from a full PKIX stack, documented in docs/tls.md.

`untrusted` is treated as attacker-controlled throughout: it may
omit intermediates (chain fails `err_root`), reorder (harmless —
the build is by name), or append junk (skipped). A path built only
from untrusted certs with no roots link fails — the store is the
only source of trust.

## Trust roots: resolution order

`load_system_roots()` walks this list, first non-empty wins:

1. **`OXL_SSL_CERT_FILE`** — a PEM bundle file (any `*.pem`-
   readable concatenation). `OXL_SSL_CERT_DIR` — a directory
   scanned for `*.pem`/`*.crt`/`*.cer` files, each loaded
   wholesale (this is *not* openssl's hashed-capath layout —
   documented in docs/tls.md). Either set to a bad path →
   `err_roots` naming the var — an override that doesn't work
   must not fall through silently to the store it meant to
   replace.
2. **`SSL_CERT_FILE` / `SSL_CERT_DIR`** — same semantics;
   honored so tools configured for the OpenSSL convention work
   unmodified.
3. **Platform store:**
   - Linux/Unix: first existing of
     `/etc/ssl/certs/ca-certificates.crt` (Debian/Ubuntu),
     `/etc/pki/tls/certs/ca-bundle.crt` (Fedora/RHEL),
     `/etc/ssl/ca-bundle.pem` (openSUSE),
     `/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem`,
     `/etc/ssl/cert.pem` (Alpine, macOS, *BSD).
   - macOS: if no file matched, exec
     `security find-certificate -a -p
     /System/Library/Keychains/SystemRootCertificates.keychain`
     (explicit keychain path — the bare invocation reads the
     user's keychains, not the System Roots store) via `os/exec` and parse the PEM output — live
     store, no framework link needed.
   - Windows: exec `powershell.exe -NoProfile -Command`
     emitting each `Cert:\LocalMachine\Root` and
     `Cert:\CurrentUser\Root` cert's `RawData` base64'd — parse
     the PEM-shaped output. One exec at first use per process,
     cached in the returned `Roots`.
4. **Fail:** no source yields ≥1 root → `err_roots` naming
   `OXL_SSL_CERT_FILE` as the override — never a silent empty
   pool (an empty pool would make every chain `err_root` with a
   misleading smell).

`cas` nil (vs a non-nil-but-empty `cas`, which is a deliberate
pin to *zero* anchors — everything verifies `err_root`) ⇒
`Config.roots` empty ⇒ `client` calls `load_system_roots()` once
per handshake (cheap on POSIX; the exec paths amortize to one
spawn — callers that care hold a `Roots` and reuse it). A
non-empty `roots` short-circuits all of the above — that's the
pinning path: `roots.load_pem(myca)` + empty env gives exactly
one trust anchor.

## Hostname verification (`match_hostname`)

- `name` empty → `err_name` — a caller that means "don't check"
  uses `Config.verify`, never an empty name (the check on empty
  is what makes the skip legible rather than accidental).
- IP literal (v4 dotted quad or `[v6]`) → matches `ip_addrs`
  exactly; never dns_names.
- DNS name → lowercase-compare against `dns_names`. Wildcard
  `*.example.com` matches exactly one left-most label
  (`a.example.com` yes; `example.com`, `a.b.example.com`,
  `xample.com` no). `*` elsewhere or mid-label is literal, not
  wild.
- **No CN fallback.** A cert with zero `dns_names`+`ip_addrs`
  fails `err_name` for any name — subject CN is read for
  display only. This matches current browser practice and is the
  decision the spec owns, stated so a later "compatibility" ask
  has to argue *for* CN, not discover its absence.

## Expiry and time

`at` is an explicit epoch parameter — `verify` takes it (tests
pin it; `tls` passes `time.unix()`). Not-before and not-after are
inclusive bounds; both fail closed. There is no skew tolerance —
a validation library can't negotiate the user's clock, and a
fudged window hides real expiry.

## Revocation stance

v1 performs **no** revocation checking: no CRL fetch, no OCSP,
no stapled-status evaluation, no must-staple enforcement. That is
a documented limitation (`docs/tls.md` names it), not an
oversight — the trigger text asks for the trust story to be
specified, and honesty here is part of it. Reopen trigger:
first consumer needing revocation proof; the `verify` hook means
a caller can layer its own check today without a std change.

## Errors

`err_der`, `err_alg`, `err_sig`, `err_expired`, `err_notyet`,
`err_ca`, `err_eku`, `err_path`, `err_root`, `err_name`,
`err_roots` — package-level sentinel `err` values. Detail text
(cert subject, offending name) is the message and the sentinel
rides as the cause — `errors.wrap(detail, sentinel)`.
`errors.new` interns by message text, so wrapping is
what keeps `errors.is(e, err_expired)` matching when the message
carries the cert's name. Callers branch on category, never on
message text.
