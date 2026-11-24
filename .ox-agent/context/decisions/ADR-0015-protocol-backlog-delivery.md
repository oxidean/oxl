# ADR-0015: Deliver protocol backlog changes in one reviewed PR

## Status

Accepted

## Context

Issues #218–#224 span HTTP/2, HTTPS proxying, WebSocket, TLS client
certificates, gRPC, TLS 1.2, and QUIC/HTTP/3. They share transport and TLS
dependencies but have distinct security and interoperability requirements. The
requested delivery is one combined branch and one PR.

## Decision

Keep implementation commits, tests, and independent reviews issue-scoped on one
branch, then open one PR only after each included feature passes its acceptance
criteria and required CI. Do not merge it as part of this task.

Do not include placeholders for issues whose architecture or security gate is
not met. QUIC/HTTP/3 requires UDP and transport-independent TLS design and
vectors before implementation. Client mTLS requires crypto-focused review of
private-key validation and timing behavior.

## Consequences

- Review HTTP/2 before freezing the dependent gRPC layer.
- Reference only fully implemented and verified issues in the final PR.
- Keep issues blocked by unmet prerequisites open and report evidence.
