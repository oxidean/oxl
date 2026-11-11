# items/tls-api.md — `std/net/tls` + `http` seam contract

The public surface the milestone ships, field by field. The
deliberate absences are part of the contract — they're decisions,
not gaps.

## `std/net/tls`

```oxl
import "std/net"
import "std/crypto/x509"

struct Config {
    server_name: str,      // verification name — dial() fills it
                           // from host verbatim. The SNI extension
                           // is sent only for DNS names, but the
                           // hostname check still runs for IP
                           // literals (against iPAddress SANs).
                           // Empty ⇒ SNI omitted AND match_hostname
                           // skipped — only legal alongside a
                           // non-nil verify, enforced at client().
    roots: x509.Roots,     // empty Roots{} ⇒ load_system_roots()
    alpn: []str,           // empty ⇒ no ALPN extension
    verify: Verifier,      // nil ⇒ x509.verify + match_hostname.
                           // Non-nil ⇒ replaces BOTH (chain AND
                           // hostname) — the full-override hook for
                           // tests/private PKI/self-signed pinning.
}

interface Verifier {
    check(leaf: x509.Cert, untrusted: []x509.Cert) -> err
    // an IFACE, not a `fn` field: `nil` is `Ty::Err` in oxl —
    // assignable to ifaces, never to `fn` — so "no override" spells
    // `verify: nil`. Callers implement `check` on a small struct,
    // the same idiom as http.Handler and hash.Hash.
}

fn dial(host: str, port: int) -> [Conn, err]
fn dial_timeout(host: str, port: int, tmo_ms: int) -> [Conn, err]
    // = net.dial_timeout + client(); on handshake failure the inner
    // socket is closed before returning the err — no half-open leak.

fn client(c: net.Conn, cfg: Config) -> [Conn, err]
    // handshake over an existing conn (the wrap API — proxy CONNECT
    // and tests ride this). cfg.server_name empty + cfg.verify nil
    // is err_name — a caller who means "no name check" must say so
    // with a Verifier, never by accident.

struct Conn { inner: net.Conn, st: shared, g: int }
    // st/g is the same close-latch discipline as net.Conn: copies
    // (struct value, iface box) share the cell; close wins once.

fn (c mut Conn) read(b: []byte) -> [int, err]
    // yields decrypted app-data; close_notify → io.eof();
    // post-handshake msgs (NST/KeyUpdate) are consumed inside read —
    // callers see only app-data semantics per io.Reader.
fn (c mut Conn) write(b: []byte) -> [int, err]
    // slices b into ≤16KiB records; may write short per io.Writer.
fn (c mut Conn) close() -> err
    // close_notify best-effort → inner.close(); double-close safe
    // via the latch.
fn (c ref Conn) rawfd() -> int     // inner.rawfd() — set_*timo works
fn (c ref Conn) peer() -> x509.Cert
    // the verified leaf — callers needing the presented identity
    // (audit logs, key pinning checks on top of verify) read it
    // here, never from a parallel parse.
fn (c mut Conn) asreader/aswriter/ascloser/asreadwriter  // net.Conn parity
```

**No `insecure_skip_verify`.** The flag exists in every TLS lib
and is the single most-abused TLS setting ever shipped; this
surface's answer is `verify` — a hook that says *what* trust means,
not a boolean that says "don't." Tests and private PKI pin a CA
through `roots` instead.

**Dial-time defaults:** `dial*` sets `server_name = host` when host
is a DNS name; ALPN comes only from `cfg.alpn` (tls doesn't guess —
`http` supplies `["http/1.1"]`).

## `std/net/http` — the seam

```oxl
struct Url { host: str, port: int, path: str, secure: int }
// parse_url: "https://" → secure=1, port 443; "http://" or bare →
// secure=0, port 80; "x://…" unsupported stays an err (unchanged).
// userinfo/query handling is untouched — this spec adds a scheme.

struct Client { tmo: int, tlscfg: tls.Config }
// request(): u.secure ⇒ tls.dial_timeout(u.host, u.port, cl.tmo)
// with cfg = cl.tlscfg, cfg.server_name defaulted to u.host when
// empty, cfg.alpn defaulted to ["http/1.1"] when empty;
// else ⇒ net.dial_timeout (unchanged path).
```

`serve` is untouched — TLS server is a parked trigger, not a stage.
The `host:` header, `connection: close`, read-until-EOF body loop,
and `Resp` shape all carry over byte-for-byte: from `request`'s
view a `tls.Conn` is just the `io` plumbing `net.Conn` already was.

## Error taxonomy (what callers see)

`dial`/`client` surface failures in three layers, all `err`:

| layer | examples | caller meaning |
|---|---|---|
| transport | net dial errors verbatim | host unreachable, refused |
| protocol | `err_proto`, `err_alert` (alert name in text), `err_eof` | peer not TLS, mid-handshake cut |
| trust | `err_sig` `err_expired` `err_notyet` `err_ca` `err_eku` `err_path` `err_root` `err_name` `err_alg` `err_der` `err_roots` | the x509 verdict — `errors.is` categories, actionable ("add the CA to OXL_SSL_CERT_FILE", "clock is wrong") |

Trust errors are never flattened into "handshake failed" — the
name/dates/verdict belong in the error text so a failed `https.get`
tells the user *which* check lost.
