# Discovery — protocol backlog #218–#224

## Existing architecture and constraints

- `std/net/http` is a bounded HTTP client with HTTP/1.1 parsing, TLS
  configuration, proxy selection, and redirects. HTTPS CONNECT is incremental;
  origin TLS starts only after a valid 200 response.
- `std/net/tls` is a pure-Oxl TLS 1.3 stack. TLS record framing is coupled to
  stream transport, and `std/net` has no UDP/datagram API.
- `tests/run.sh` is the repository-wide gate. HTTP/2 interop uses Node's
  independent `http2` server; TLS and CONNECT use local Python/OpenSSL fixtures.
- Existing code uses bounded parsers and explicit errors. The TLS-server/key
  signing draft is not client mTLS and requires a crypto audit before reuse.
- `std/net/http2` contains the frame/HPACK codec and connection state machine;
  `Request.http_version` selects ALPN `h2` or explicit h2c prior knowledge.

## Relevant specifications and decisions

- `context/specs/protocol-backlog-218-224.md` records issue-level contracts.
- ADR-0012 governs TLS 1.3 authenticated transport and mandatory verification.
- ADR-0015 records the user's one-branch/one-PR delivery choice and preserves
  security gates.
- The protocol-backlog worktree's earlier plans are preserved as references;
  this item uses a clean consolidated spec, not its unrelated work-item state.

## Risks found

- #219 cannot be implemented safely as a partial client: UDP and
  transport-independent TLS are missing, and QUIC protection, loss recovery,
  congestion/flow control, and QPACK need deterministic vectors and review.
- #221 must implement actual CertificateRequest/CertificateVerify behavior.
  The existing draft does not, and private-key timing/validation needs review.
- #223 depends on stable event ownership, multiplexing, and flow control in
  #218.
- Two duplicate Ox-Agent event IDs in the current base were assigned unique
  identifiers without changing event payloads so status/transitions work.

## Boundary

Proceed with issue-scoped changes only. Do not claim #219 or #221 complete until
their gates pass. Deliver one PR; no merge is authorized.
