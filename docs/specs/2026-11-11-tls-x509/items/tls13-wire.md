# items/tls13-wire.md — TLS 1.3 record, handshake, and key schedule contract

X6's deliverable. Everything on the wire is RFC 8446; this file pins
the subset offered, the message flow implemented, the key schedule
derivation, and the alert/error semantics — the parts a from-spec
implementation must not improvise.

## Offered parameters (ClientHello)

| field | value |
|---|---|
| `legacy_version` | 0x0303 (TLS 1.2 encoding position; 1.3 rides `supported_versions`) |
| `legacy_session_id` | 32 bytes of fresh `rt_csrand` — compat mode §4.1.2; the ServerHello must echo it verbatim (`legacy_session_id_echo` check, `unexpected_message` else) |
| `legacy_compression_methods` | single `0x00` (null) — required field, always this value |
| `supported_versions` | 0x0304 only |
| `cipher_suites` | `TLS_AES_128_GCM_SHA256` (0x1301), `TLS_CHACHA20_POLY1305_SHA256` (0x1303), `TLS_AES_256_GCM_SHA384` (0x1302) — in that order |
| `supported_groups` | `x25519` (0x001d), `secp256r1` (0x0017), `secp384r1` (0x0018) — all three advertised; a server may only pick an advertised group |
| `key_share` | shares for x25519 and secp256r1 (two shares dodge the common HRR) |
| `signature_algorithms` | `ecdsa_secp256r1_sha256` (0x0403), `ecdsa_secp384r1_sha384` (0x0503), `ed25519` (0x0807), `rsa_pss_rsae_sha256/384/512` (0x0804/0x0805/0x0806), `rsa_pkcs1_sha256/384/512` (0x0401/0x0501/0x0601) |
| `server_name` | the DNS name being dialed; omitted for IP literals |
| `alpn` | from `Config.alpn`; absent when empty |
| `psk_key_exchange_modes` | `psk_dhe_ke` — sent for form (we offer no PSKs); keeps the CH shape boringly standard |

Compatibility mode: a dummy ChangeCipherSpec is sent and CCS
records from the server are tolerated mid-flight (RFC 8446 §D.4
middlebox accommodation).

**Downgrade sentinels:** the last 8 bytes of ServerHello.random
equal to either RFC 8446 §4.1.3 sentinel is a hard `illegal_parameter`
alert — we offer 1.3 only, so their presence is an attack, not a
negotiation.

RSA-PSS in CertificateVerify: `salt_len` pins to the hash length
(the generic "salt-len recover" verify path accepts anything — we
send and accept only hashlen).

## Handshake state machine

```
ClientHello
  → [HelloRetryRequest — at most once; echo any `cookie`
     extension verbatim (§4.2.2), rebuild CH with a key_share for
     the demanded group if it's x25519/secp256r1/secp384r1
     (`illegal_parameter` alert else); transcript carries the HRR
     message_hash. A second HRR → `unexpected_message` alert]
  → ServerHello        — must carry `supported_versions`=0x0304
                          (its mandatory pin; a 0x0303-only ServerHello
                          is a 1.2 answer → `protocol_version` alert).
                          Suite/group echoes must ∈ offered, any
                          extension we didn't offer →
                          illegal_parameter; else alert.
                          The peer's key_share validates BEFORE use:
                          x25519 → RFC 7748 all-zero output check
                          (`illegal_parameter` alert — the RFC's
                          "MUST abort"); P-256/P-384 →
                          point-on-curve check (invalid-curve defense)
  → EncryptedExtensions — ALPN echo must ∈ offered list when sent;
                          any unoffered extension →
                          illegal_parameter
  → [CertificateRequest mid-flight — answered with an empty
     Certificate message (certificate_list len 0, §4.4.2.4 —
     the RFC-mandated answer; a server requiring client auth
     then alerts `certificate_required`). mTLS itself stays
     out of scope.]
  → Certificate         — each cert_parse'd; leaf + untrusted chain;
                          per-entry extensions (OCSP staples, SCTs)
                          parsed over, ignored
  → CertificateVerify   — signature over the running transcript;
                          signed content is 0x20×64 +
                          "TLS 1.3, server CertificateVerify" + 0x00
                          + transcript (§4.4.3); alg must ∈
                          signature_algorithms and be a CV-legal
                          alg (see below) — else alert. A local
                          verify/chain failure answers with an
                          alert — bad_certificate for sig/parse,
                          certificate_expired for validity — not a
                          bare close
  → Finished            — verify_data == HMAC(finished_key, transcript)
  → [client Finished]   — handshake complete; app traffic keys live
```

CertificateVerify accepts `rsa_pss_rsae_*`, `ecdsa_*`, `ed25519`
only — `rsa_pkcs1_*` values are advertised (cert *signatures* need
them: roots still issue PKCS#1 v1.5) but are illegal in CV per RFC
8446 §4.4.3 and rejected there. The x509 chain itself may carry
PKCS#1 signatures — `x509.verify` accepts them.

Post-handshake, consume quietly:
- **NewSessionTicket** — parsed and dropped (resumption is out of
  scope; erroring on it would break interop with every server that
  sends it).
- **KeyUpdate** — `update_requested` → apply peer keys and answer
  `update_not_requested`; `update_not_requested` → apply only.
  Never initiated by us.
- CertificateRequest post-handshake — protocol-illegal here
  (`post_handshake_auth` is never offered), so the strict read is
  `unexpected_message`. We answer leniently instead — the same
  empty Certificate as mid-flight — because real servers do send
  it and an alert buys nothing: the server's own follow-up
  (usually `certificate_required`) ends the session either way.
  The strict alternative is recorded, not chosen. Any other
  handshake-type post-handshake → `unexpected_message` alert.

## Key schedule

Standard RFC 8446 §7.1 chain, all through `hkdf.expand_label`:

```
early secret   = extract(0, zeros)
handshake sec  = extract(der(early), ecdhe_shared)
  → c_hs_traffic / s_hs_traffic  (keys+iv for handshake flight)
master secret  = extract(der(handshake), zeros)
  → c_ap_traffic / s_ap_traffic  (keys+iv for app data)
```

with `finished_key = expand_label(hs_traffic, "finished", "", hlen)`
and `verify_data = HMAC(finished_key, transcript_hash)`. Transcript
is the running hash over raw handshake-message bytes (incl. the
HRR `message_hash` substitution per §4.4.1). Hash follows the
negotiated suite: SHA-256 for 0x1301/0x1303, SHA-384 for 0x1302.

**Test anchor:** RFC 8448 §3's published trace — the fixture feeds
the published server flight and published ECDHE secret; the
implementation must derive the published `c/s_hs_traffic` and
`c/s_ap_traffic` keys byte-for-byte. This is the gate that proves
the whole HKDF chain against an external answer.

## Record layer

- `TLSCiphertext`: 5-byte header `{type=23, version=0x0303, len}`;
  fragment ≤ 16384 + 256 expansion — larger inbound →
  `record_overflow` alert.
- Handshake messages reassemble across record boundaries and
  coalesce within one record — a Certificate flight routinely
  exceeds one fragment, and several handshake messages may share
  one. The handshake reader buffers until each message's 4-byte
  header length is complete — never assume record == message.
- Nonce: `iv ^ (seq` zero-padded to iv len`)`; seq per direction,
  never reused, reset at each secret epoch; wrap → `err_proto`
  (a seq can never legally wrap in our lifetime anyway).
- AAD: the 5-byte header verbatim.
- Inner plaintext: `content || type || zeros` — strip trailing
  zeros, last nonzero byte is the real type; all-zero content →
  `unexpected_message`.
- Outbound padding: none (we send `content||type` only — padding
  is optional and traffic analysis is documented in the risk
  section).
- Record content types: CCS 20, alert 21, handshake 22,
  application_data 23. Inbound CCS is tolerated *once* per
  direction (middlebox compat per §D.4 — more than one is
  `unexpected_message`); alert records map to `err_alert` with
  the alert name; any other unknown type is `unexpected_message`.

## Errors / alerts

- Orderly close (close_notify received) → `read` yields
  `io.eof()`; `close()` sends close_notify best-effort then
  closes `inner` (a wedged peer can't hold the fd).
- TCP EOF mid-record or without close_notify → `err_eof`
  (distinguished from orderly: truncation is never silent).
- Any alert received → `err_alert` carrying the alert name in
  message text (`bad_record_mac`, `certificate_unknown`, …) —
  debugging a failed handshake demands the server's complaint.
- Local verification failures surface the x509 category (`err_sig`,
  `err_expired`, `err_root`, `err_name`, …) — `tls.dial` callers
  get the *reason*, not a flattened "handshake failed".
- Handshake shape violations → the matching alert sent, then
  `err_proto`.
