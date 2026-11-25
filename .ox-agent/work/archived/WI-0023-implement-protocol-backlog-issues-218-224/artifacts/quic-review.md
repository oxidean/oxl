# Independent review — QUIC/HTTP/3 architecture spike

## Initial findings and amendments

The review confirmed the lack of UDP/datagram APIs, stream-coupled TLS, and
QUIC peer/vector harness. It found omitted key updates; Retry, CID lifecycle,
stateless-reset and Initial-padding behavior; IPv4/IPv6 scope; constant-time
posture; H3 ALPN/transport extension; test-lane policy; licensing/runtime
tradeoffs; PMTU/ECN; compatible version negotiation/greasing; and raw-fd
rationale. The spike was amended to cover each item.

A follow-up review approved the amended design with two minor corrections. The
spike now cites RFC 9368/9287 for compatible version negotiation and greasing,
and states that RFC 9000's 1200-byte Initial padding floor is mandatory rather
than a configurable bound. It also clarifies that the Node lane is hard-required
in CI but skips locally when Node is absent.

## Verdict

The document is approved as an architecture/security-gate artifact, not as
approval to implement #219. The pure-Oxl versus external runtime library,
address-family support, resource caps, and crypto timing posture remain explicit
unresolved decisions. Keep #219 open until those decisions, vectors, and an
independent peer CI harness are accepted.
