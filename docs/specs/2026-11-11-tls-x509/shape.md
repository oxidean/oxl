# TLS/x509 — authenticated transport — Shaping Notes

## Scope

Milestone X (x509’s letter — fresh; R was reclaimed by the descriptor
spec, T/G/E/W are taken, and L went to the LLVM lane spec, `docs/specs/2026-11-11-llvm-backend/` — spec in flight) un-parks the `crypto/tls` + `x509` row from
`docs/specs/2026-11-07-phase-2-plan/parked.md` and
`docs/specs/2026-11-06-0111-package-system/items/parked-stdlib.md`.
The trigger fired: `std/net/http`'s client is the first consumer
needing authenticated, encrypted transport beyond cleartext `net`
(`http.oxl`'s own header still reads "HTTPS stays parked (no TLS)").
The deliverable is a client-side TLS 1.3 stack plus the x509 trust
story the trigger demands — `std/net/tls`, `std/crypto/x509`, and the
crypto packages beneath them — ending in `http.get("https://…")`.

Not this spec: TLS server (`tls.listen`/`accept`), TLS 1.2 or older,
DTLS/QUIC, HTTP/2+, client certificates (mTLS), session resumption /
PSK / 0-RTT, OCSP/CRL revocation checking, certificate *issuance*
(sign/encrypt/decrypt RSA ops), a bundled root list, name-constraint
processing, an `insecure_skip_verify` flag, and any `--target js`
lane (sockets already trap under node; `tls` inherits net's path).

## Evidence

- The repo's crypto ethos is set in S4: `sha256`/`md5`/`hmac` were
  "written fresh in oxl from the public specs — no C port" and the
  item closes with "the language is sufficient." u32-in-int64
  arithmetic (`x/2**n`, `(x*2**n)&M32`) is the established pattern —
  correct first; the perf gate (X5 interop budget) is what makes it
  acceptable, not any compiler strength-reduction (there is none).
- The driver's link pattern is demand-driven off emitted text:
  `rt_sqlite_*` → `-DOXL_SQLITE` + `-lsqlite3` (or `LANG_SQLITE_SRC`
  amalgamation on Windows); `rt_sock_*` → `-DOXL_NET` + `ws2_32`;
  `rt_m_*` → `-DOXL_MATH` + `-lm`. A TLS stack that needs zero new
  link surface keeps this pattern untouched.
- `runtime/rt.c` has **no entropy source** — `rand()` seeds chan
  select, and `std/math/rand` is a documented drand48 LCG. Every
  other crypto input exists in `.oxl`; a CSPRNG cannot (it is a
  syscall), so one rt.c veneer is the minimum.
- `std/net`: `Conn{fd, st, g}` implements `io.Reader/Writer/Closer`
  with a shared close-latch — `tls.Conn` wraps it field-for-field.
  `dial_timeout` bounds connect; `rawfd()` exposes the socket for
  `set_rcvtimo`-class calls.
- `std/net/http`: `parse_url` accepts only `http://` (port 80),
  `Client{tmo}` dials `net.dial_timeout` directly — one seam to
  branch on `secure`.
- Encoding/decoding inventory already shipped: `encoding/base64`
  (PEM bodies), `encoding/hex`, `encoding/binary` (be_u16/u32 reads
  the record layer), `bytes`, `io` ifaces, `os.getenv`, `os/exec`,
  `time.unix` (CLOCK_REALTIME — cert validity checks can use it).
- CI runs ubuntu + macOS + windows (git-bash, `LANG_CC=gcc`), and
  `tests/run.sh` already gates lanes on `command -v` probes
  (gtk's `pkg-config`, amalgamation env vars; W's js lane adds `node`
  in flight) — the TLS interop lane rides the
  same probe pattern on `openssl`.
- Windows and macOS have no filesystem root bundle a stock program
  can assume; POSIX distros disagree on the path. The platform
  *does* offer stores — Windows `Cert:\LocalMachine\Root` via
  PowerShell, macOS `security find-certificate` — both reachable
  through `std/os/exec` with zero new C.

## The forks, decided

1. **Pure-.oxl crypto and protocol; rt.c contributes only entropy.**
   Options weighed:

   | option | shape | verdict |
   |---|---|---|
   | A. Fresh-from-RFC .oxl stack | all primitives + record/handshake + x509 in packages; one `rt_csrand` veneer | repo ethos; one behavior across all three CI legs; every byte reviewable; suite gates are RFC vectors + interop — but the largest .oxl surface yet and no third-party audit |
   | B. Platform TLS veneer in rt.c | OpenSSL (unix), SecureTransport or Network.framework (macOS), Schannel (Windows) behind `rt_tls_*` | audited crypto + free system roots — but ~3 divergent C backends (>1.5k lines), a deprecated-or-async-mismatched macOS API, per-platform verify semantics the suite can't pin, and the trust story *delegated*, which is what the trigger says the spec must cover |
   | C. Vendored C TLS lib | BearSSL: TLS 1.2 only — fails the floor. mbed TLS: full 1.3 but ~100k lines vendored or `LANG_TLS_SRC`-fetched | biggest dependency weight for least ownership of the answer; sqlite's system-or-amalgamation pattern exists but pulls a security-critical dep the project then can't audit |

   Option A, with the honest cost stated: the primitives are
   verify-only where possible, the wire surface is TLS 1.3 only, and
   the gates are published test vectors plus live `openssl s_server`
   interop — not self-consistency. Side-channel posture is written
   down, not waved (§Risk).

2. **TLS 1.3 only.** RFC 8446, floor and ceiling. No 1.2 negotiation,
   no downgrade path (the sentinel in ServerRandom is a hard alert),
   no renegotiation (does not exist in 1.3). Rationale: every public
   web-PKI endpoint that matters speaks 1.3; the 1.2 handshake,
   non-AEAD ciphersuites, RSA key transport, and renegotiation are
   exactly where a from-spec stack bleeds. A 1.2 fallback re-opens
   with the trigger "a consumer hits a 1.2-only endpoint."
3. **Cipher floor: two suites + one free rider.** Offer
   `TLS_AES_128_GCM_SHA256` and `TLS_CHACHA20_POLY1305_SHA256`, plus
   `TLS_AES_256_GCM_SHA384` since SHA-384 exists anyway for the
   signature set. Key shares: `x25519` and `secp256r1`; `secp384r1` is
   advertised in `supported_groups` (no share sent up front) so
   an HRR demanding it is honored (the field code exists for ECDSA
   regardless). No FFDHE, no 0-RTT, no early data.
4. **Verify-only asymmetric crypto.** Certificates need signature
   *verification* — never signing, encryption, or decryption — so the
   packages expose exactly that: `rsa` (PKCS#1 v1.5 + PSS verify),
   `nistec` (P-256/P-384 ECDH+ECDSA verify), `ed25519` (verify), `x25519`.
   A `sign`/`encrypt`/`decrypt` surface lands only with its own
   consumer (trigger: JWT/mTLS issuance or TLS server).
5. **The trust story is ours, loaded three ways.** The x509 contract
   (`items/x509-trust.md`): DER parse, chain build leaf→root by
   issuer/AKID, signature verify per the floor set, validity vs
   `time.unix`, BasicConstraints/KeyUsage/EKU checks, SAN hostname
   match. Roots resolve in order: `OXL_SSL_CERT_FILE` /
   `OXL_SSL_CERT_DIR` env (then `SSL_CERT_FILE`/`SSL_CERT_DIR` as
   fallback spellings), else the platform store — POSIX bundle paths,
   macOS `security find-certificate` exec, Windows PowerShell `Cert:`
   provider — else a named error, never silent-cleartext. No bundled
   Mozilla list: a vendored root set is a maintenance treadmill the
   release process doesn't have; the env override is the documented
   answer on stripped containers.
6. **Hostname verification: SAN-only.** dNSName SANs (wildcard on
   exactly one left-most label), iPAddress for IP literals, *no CN
   fallback* — a SAN-less cert fails `err_name` even when its CN
   matches (public CAs have issued SANs for a decade; CN matching is
   deprecated practice that hides misissuance). SHA-1/MD5 signatures
   hard-fail at parse-and-verify at every link — the one exception is
   the trust anchor's own self-signature, which is never verified
   (store membership is the trust decision), matching x509-trust.md.
7. **Expiry is hard-checked; revocation is parked.** notBefore/
   notAfter validated against wall clock — no tolerance window.
   CRL/OCSP (incl. stapling) is a documented non-goal with the same
   trigger shape as every parked row: first consumer that needs
   revocation proof. Until then `x509` says so plainly rather than
   pretending half-checks.
8. **`tls` wraps `net.Conn`; `http` gains `https` at one seam.**
   `tls.dial` = `net.dial_timeout` + `tls.client`. `tls.Conn` is
   `io.Reader/Writer/Closer` with `rawfd()` passthrough so the
   existing timeout builtins keep working. `http.Url` grows
   `secure`; `Client` grows `tlscfg: tls.Config`. No
   `insecure_skip_verify` — the `Config.verify` hook is the
   deliberate escape hatch (test fixtures and private PKI inject a
   `Roots` or a `Verifier`; a boolean that disables authentication is
   a footgun, not a feature). The hook is an iface, not a `fn` field:
   oxl's `nil` is `Ty::Err` — assignable to ifaces and slices, not to
   `fn` — so `verify: nil` must mean an empty iface, the same shape
   `http.Handler`/`hash.Hash` already set for policy injection.
9. **Hermetic gates first, interop second.** Published vectors
   (FIPS/NIST/RFC 7748/8032/5869/8439/8448) gate every primitive;
   RFC 8448's published handshake trace gates the key schedule;
   checked-in x509 fixtures (generator script in `scripts/`) gate
   the trust story; `openssl s_server` end-to-end interop runs in a
   `command -v openssl`–gated lane, never the sole gate.
10. **js-lane inherits net's answer.** Under milestone W (in
    flight): `runtime/rt-node.mjs`/`rt-browser.mjs` sockets trap21; TLS
    needs sockets, so `--target js` gains nothing here — the
    packages compile (pure .oxl) and their socket use fails the same
    documented way. A fetch-backed transport is its own trigger.

## What exists vs what's missing

| have | missing → package |
|---|---|
| `crypto/sha256`, `md5`, `hmac` over `hash.Hash` | `crypto/sha512` (SHA-512 + SHA-384), `crypto/hkdf` (extract/expand/expand-label) |
| — | `crypto/rand` over one new extern `rt_csrand` (getrandom / `arc4random_buf` / `BCryptGenRandom`) |
| — | `crypto/aes` (encrypt-only block) + `crypto/aesgcm` (AEAD, GHASH in i64 pairs), `crypto/chacha20poly1305` (RFC 8439, Poly1305 5×26 limbs) |
| — | `crypto/bignum` (i64-limb mod arithmetic — RSA + prime-field ECDSA), `crypto/x25519` + `crypto/ed25519` (ref10-style 10×25.5-limb field), `crypto/nistec` (P-256 + P-384: ECDH + ECDSA verify), `crypto/rsa` (v1.5 + PSS verify) |
| `encoding/base64`/`hex`/`binary` | `crypto/x509` (DER/PEM parse, chain verify, `Roots` + system loaders, hostname match) |
| `net.Conn`, `io` ifaces | `std/net/tls` (`Config`, `Conn`, `dial`, `client`) |
| `http` client | `https://` scheme + `Client.tlscfg` |

`math/rand` is named deliberately absent above — it is an LCG; its
doc comment already says so. Nothing cryptographic may consume it.

## Risk

- **From-spec correctness** is the dominant risk, not performance:
  gates are external vectors at every layer, and X6 gates on a real
  `openssl s_server` handshake where available — self-consistency
  alone is never the exit.
- **Side channels**: `.oxl` arithmetic compiles through C but offers
  no constant-time discipline (branches on secret material are
  written, not eliminated). The stack's posture is "correctness-
  verified, no constant-time claim" — recorded in `docs/tls.md` at
  closeout. A client handshake's exposure is narrow (session keys,
  not long-term identity keys), and the verify-only design means no
  signing oracle exists. A constant-time pass is parked with the
  trigger "first server-side or signing consumer."
- **Perf floor**: RSA-4096 verify < 250 ms, x25519 < 50 ms,
  handshake crypto < 1 s total on a CI leg (the dial budget is 30 s;
  crypto must not dominate it), AEAD ≥ 5 MiB/s. Gates, not
  aspirations — measured in the suite.
- **Root-store drift**: exec-based loaders depend on `security` /
  `powershell` being present (true on stock images; Nano Server-class
  minimal Windows is the exception → the env override is the
  documented answer there, and the error names it).

## The decision

**A TLS 1.3 client stack written fresh in `.oxl` from RFC 8446 +
companion RFCs, over one new rt.c entropy veneer, with the x509
trust story in `std/crypto/x509` and `https://` delivered through a
single seam in `std/net/http`.**

```oxl
// std/net/tls — public surface (v1)
struct Config {
    server_name: str,                     // verify name; dial() fills it (SNI is DNS-only)
    roots: x509.Roots,                    // empty ⇒ load_system_roots()
    alpn: []str,                          // empty ⇒ no ALPN ext
    verify: Verifier,                     // nil ⇒ default chain + hostname
}
interface Verifier {                    // override hook — an iface,
    check(leaf: x509.Cert, untrusted: []x509.Cert) -> err
}                                       // not a fn field: oxl's nil
                                        // is Ty::Err — assignable to
                                        // ifaces, never to fn
fn dial(host: str, port: int, cfg: Config) -> [Conn, err]
fn dial_timeout(host: str, port: int, tmo_ms: int, cfg: Config) -> [Conn, err]
fn client(c: net.Conn, cfg: Config) -> [Conn, err]   // wrap any net.Conn
struct Conn { inner: net.Conn, st: shared, g: int }  // io.R/W/Closer
fn (c mut Conn) read/write/close — record layer; close sends
                                   // close_notify then closes inner
fn (c ref Conn) rawfd() -> int           // passthrough for set_*timo
fn (c ref Conn) peer() -> x509.Cert      // the verified leaf
```

```oxl
// std/net/http — the seam (additions only)
struct Url { host: str, port: int, path: str, secure: int }
struct Client { tmo: int, tlscfg: tls.Config }
// parse_url: "https://" → secure=1, port 443; Client.request picks
// tls.dial_timeout vs net.dial_timeout on u.secure
```

Stage map: `plan.md` (X0 spec → X7 https + closeout). Contracts:
`items/x509-trust.md` (the trust story), `items/tls13-wire.md`
(record/handshake/key-schedule), `items/tls-api.md` (package
surfaces + err taxonomy).
