---
covers:
  - std/net/http/**
  - std/net/http2/**
  - std/net/websocket/**
  - std/net/grpc/**
  - std/net/tls/**
  - tests/http2_*
  - tests/websocket_*
  - tests/grpc_*
  - tests/tls/**
---

# Protocol backlog #218–#224

## Delivery contract

Use one implementation branch and one pull request for issues #218–#224, as
requested. Keep implementation commits and tests issue-scoped. Do not merge
this pull request. Reference or close an issue only after its acceptance
criteria pass; security-gated issues remain open rather than receiving
placeholders.

## Acceptance criteria

### #218 — HTTP/2 client

Negotiate `h2` with TLS ALPN and support cleartext prior-knowledge h2c. Correctly
implement preface, SETTINGS, frame validation, stream lifecycle,
request/response headers, DATA, trailers, multiplexing, and client-side flow
control. Bound streams, frames, header blocks, HPACK tables, queued events, and
response bodies. Test vectors and malformed input, concurrency, trailers,
flow-control boundaries, GOAWAY/RST, ALPN, h2c, HTTP/1.1 ALPN fallback, TLS
verification failure, deadlines, and independent interoperability.

### #219 — HTTP/3 over QUIC

Client-only QUIC/TLS 1.3/HTTP/3; server, 0-RTT, and datagrams are out of scope.
First pass an architecture/security spike covering UDP runtime APIs, packet
protection, key updates, loss recovery, congestion and flow control, stream
limits, QPACK, bounds, licensing, deterministic vectors, and independent
interoperability. Do not implement or close the issue until the design and test
harness pass independent review; otherwise keep it open with evidence.

### #220 — WebSocket client

Support `ws`/`wss` handshake and client duplex framing: text/binary messages,
fragmentation, control frames, masking, close codes, ping/pong, subprotocols,
and deadlines. No server, HTTP/2, or compression. Test handshake accept/reject,
frame bounds/validation, fragmentation, control interleaving, UTF-8/close
validation, deadlines, TLS identity verification, and an independent peer.

### #221 — TLS 1.3 client certificates

Load and validate PEM certificate chains/private keys, answer CertificateRequest,
and send a correct CertificateVerify/Finished flight through HTTPS. Preserve
mandatory server certificate and hostname verification; passworded private keys
are out of scope. Require crypto-focused review of key validation/timing plus
vectors, mismatch/invalid-key negatives, and server interop both with and
without client authentication. Do not ship until the security posture is
explicitly accepted.

### #222 — HTTPS through an HTTP proxy

Establish TCP to the proxy, send bounded CONNECT, accept only a valid 200, then
perform origin TLS over that socket with origin SNI and hostname verification.
Preserve bypass behavior; never fall back to direct/plaintext HTTPS after proxy,
CONNECT, or TLS failure. Test success, non-200/malformed/oversized/interim
responses, proxy close, NO_PROXY/explicit/direct selection, origin identity
failures, and local end-to-end proxying.

### #223 — gRPC client

Depends on independently reviewed #218 APIs in this branch. The standard
library owns framing/metadata/status only; applications own protobuf and
protojson. Support unary, client-streaming, server-streaming, and bidi RPCs;
metadata, headers/trailers, grpc-status/message, deadlines/cancellation, and
bounded 5-byte message framing. Reject unsupported compression. No reflection
or compression implementation. Test each stream direction, metadata/status,
cancellation/deadlines, malformed/oversized frames, and independent H2 gRPC
interop.

### #224 — TLS 1.2 fallback

TLS 1.3 remains the default secure floor. Support the issue's explicit TLS 1.2
selection/fallback semantics with mandatory verification; TLS 1.0/1.1 fail
clearly and no silent downgrade is permitted. Fix downgrade-sentinel gating and
consume TLS 1.2 NewSessionTicket correctly. Test TLS 1.3 default, pinned/auto
TLS 1.2, version intolerance, downgrade alerts, certificate verification,
malformed handshakes, vectors, and independent TLS 1.2 interop.

## Cross-cutting gates

Add tests proving acceptance, not just compilation. Run focused tests,
formatting, `bash scripts/stage0.sh`, and `tests/run.sh ./target/oxl`; regenerate
and verify `bootstrap/stage0/oxl.c` if compiler sources change. Require
issue-specific independent reviews with no unresolved actionable findings and
green Ubuntu/macOS/Windows CI before opening the final PR. Preserve bounded
parser, TLS verification, release, and no-fallback security contracts. Exclude
unrelated PR #215.
