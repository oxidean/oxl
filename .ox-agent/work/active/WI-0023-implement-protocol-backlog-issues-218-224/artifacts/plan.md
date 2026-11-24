# Staged plan — protocol backlog #218–#224

## Delivery

One implementation branch and one final PR, with issue-scoped commits, tests,
and reviews. Do not merge. Only reference issues whose acceptance criteria
pass. Exclude unrelated PR #215.

## Stage 1 — #218/#222 integration hardening

- Finish the H2 ALPN/h2c client and CONNECT path on the combined branch.
- Keep frame/HPACK/resource bounds, GOAWAY/RST semantics, peer concurrency,
  TLS identity, proxy selection, and no-direct-fallback behavior covered.
- Gate: targeted H2/CONNECT tests, full `bash scripts/stage0.sh &&
  tests/run.sh ./target/oxl`, independent review of the final head.
- Current local source has issue-scoped implementation commits; a first full
  suite attempt was interrupted by editing `tests/run.sh` during execution and
  must be rerun after sources stabilize.

## Stage 2 — #220 WebSocket client

- Complete the existing isolated implementation draft; audit the handshake,
  SHA-1 accept calculation, masking direction, frame bounds, fragmentation,
  control interleaving, close semantics, and deadlines.
- Gate: positive/negative handshake tests, frame edge cases, wss identity
  verification, independent peer interop, formatting, and independent review.

## Stage 3 — #224 TLS 1.2 fallback

- Audit the existing draft; TLS 1.3 stays default, with an explicit TLS 1.2
  profile and no silent downgrade.
- Gate: pinned and auto negotiation, downgrade-sentinel negatives, ticket
  handling, certificate verification, malformed-handshake tests, independent
  TLS 1.2 server interop, and security review.

## Stage 4 — #223 gRPC client (depends on #218)

- Use the stabilized H2 stream API; keep protobuf/protojson app-owned.
- Implement bounded message framing, unary and all streaming directions,
  metadata/trailers/status, deadlines/cancellation, and explicit unsupported
  compression errors.
- Gate: every stream direction, malformed/oversized input, independent H2
  gRPC interop, full tests, and independent review.

## Stage 5 — #221 mTLS security gate

- Verify actual client CertificateRequest/CertificateVerify behavior, supported
  key families, certificate/key matching, and HTTPS integration.
- Do not ship until private-key validation and variable-time signing posture
  receive explicit crypto-focused review. If the gate cannot be met, keep #221
  open; do not label server-TLS code as client mTLS.

## Stage 6 — #219 QUIC/HTTP/3 architecture gate

- No implementation before an independently reviewed design for UDP runtime,
  transport-independent TLS 1.3 handshake, packet protection, loss/congestion
  control, flow control, stream limits, QPACK, bounds, licensing, vectors, and
  independent interoperability.
- If prerequisites remain absent, keep #219 open with evidence; no stub.

## Stage 7 — final integration and delivery

- Reconcile only the qualifying issue commits onto current `origin/main` and
  commit valid Ox-Agent state; do not import corrupted unrelated draft state.
- Run format checks, focused fixtures, `bash scripts/stage0.sh`, and the full
  test suite after all sources stop changing.
- Open one combined PR only after independent review and green Ubuntu, macOS,
  and Windows CI. If #219/#221 remain gated, request the user's decision before
  claiming the all-issues request complete; reference only implemented issues.
