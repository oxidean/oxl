# Architecture/security spike — HTTP/3 over QUIC (#219)

## Decision boundary

This is a design gate, not an implementation proposal ready to merge. The
current tree has no UDP datagram API, the TLS 1.3 handshake is coupled to a
stream record layer, and no independent QUIC peer or vector harness is wired to
CI. A client-only QUIC/H3 implementation must not begin until the architecture,
interoperability harness, resource limits, and security review below are
accepted. No stub or partial API is proposed here.

## Current baseline

- `std/net/net.oxl` exposes TCP open/connect/listen/accept/read/write/close.
  Runtime code has no `sendto`/`recvfrom` or portable datagram readiness API.
- `std/net/tls` performs TLS 1.3 over `net.Conn`; record framing and the
  handshake are stream-coupled. QUIC needs CRYPTO data across Initial,
  Handshake, and 1-RTT levels plus QUIC transport parameters and different
  packet protection.
- The repository already has AES, ChaCha20-Poly1305, HKDF, SHA-2, X25519,
  certificate verification, and time primitives. They are useful building
  blocks but do not implement QUIC packet processing or loss recovery.
- The Node HTTP/2 interop lane is required in CI and hard-fails if Node is absent;
  it skips locally when Node is missing. The OpenSSL TLS interop lane skips if
  OpenSSL is absent. No QUIC peer exists in
  the current test harness.

## Proposed decomposition (not yet approved)

### 1. Datagram transport prerequisite

Add a bounded datagram abstraction in `std/net` before QUIC. The API needs
addressed and connected UDP operation, `sendto`/`recvfrom`, local/remote
addresses, close, and receive deadlines/readiness that integrate with the
runtime scheduler without a busy loop. Runtime shims need POSIX and Winsock
implementations and explicit behavior for truncation, unreachable peers,
interrupts, and timeout. JS targets must either get a documented supported
transport or a clear compile-time unsupported result; they must not silently
emulate UDP over TCP. The current resolver/runtime are IPv4-only
(`sockaddr_in`/`AF_INET`); the API decision must explicitly choose IPv4-only
first release versus dual-stack IPv4/IPv6 and whether Happy Eyeballs is needed.

The existing TCP API has `rawfd()` escape hatches, but that is not a portable
UDP send/receive contract; do not make raw descriptors the public datagram API.
The design must choose whether a single `PacketConn` API covers connected and
addressed sockets or whether it composes `PacketConn` and `UDPConn`, and define
buffer ownership and maximum datagram size.

### 2. Transport-independent TLS 1.3 core

Refactor the handshake into a core that consumes and emits handshake/CRYPTO
bytes and receives explicit encryption-level keys, while retaining the current
TCP TLS client as a thin record-transport adapter. QUIC owns Initial/Handshake/
1-RTT packet protection and feeds reassembled CRYPTO bytes to this core. The
core must expose TLS extension `quic_transport_parameters` (0x0039), honor H3
ALPN `h3`, and preserve ADR-0012 certificate-chain, hostname, and trust
verification behavior. Do not duplicate
certificate verification or private-key logic in the QUIC layer.

The change is security-critical and should land/test as a separately reviewable
prerequisite before packet recovery and HTTP/3 consume it.

### 3. QUIC connection and stream layers

Implement RFC 9000/9001/9002 in explicit layers, plus compatible version
negotiation (RFC 9368) and reserved-bit greasing (RFC 9287): connection IDs (`NEW_CONNECTION_ID`,
`RETIRE_CONNECTION_ID`), `NEW_TOKEN`, and stateless-reset detection; Retry
token handling; Initial datagram padding to at least 1200 bytes; packet number
spaces, key phase, traffic-key update/rotation, header protection, Initial key
derivation, AEAD packet protection, CRYPTO reassembly, ACK ranges, loss
recovery/PTO and congestion control, connection/stream flow control, stream
limits, transport parameters, connection close, and migration policy. Start
with one origin and no client migration, 0-RTT, or DATAGRAM frames. Every packet
parse, CRYPTO reassembly buffer, ACK range set, stream queue, and retransmission
queue must have a reviewed bound and overflow behavior.

### 4. HTTP/3 and QPACK

Layer H3 request/control streams over QUIC streams, with bounded frame parsing,
settings validation, critical-stream handling, and HTTP semantics consistent
with the existing client. QPACK static/literal decoding can be the initial
profile; dynamic table capacity and blocked streams must have explicit caps and
must reject malformed references. This is not HTTP/2-over-UDP and must not
reuse HPACK as QPACK.

### 5. Interoperability and vectors

Before feature implementation, add deterministic tests for RFC 9000 varints,
version negotiation, Retry, Initial padding, connection-ID/stateless-reset
handling and packet parsing; RFC 9001 Initial secrets, header protection,
key-phase/key-update, and AEAD; RFC 9002 loss-recovery transitions; and RFC 9204
QPACK. The CI fixture must be an independently implemented QUIC/H3 peer
(candidate: Python `aioquic` or a maintained `ngtcp2`/`quiche` binary); pin its
version, dependency/license, setup, and failure policy. The QUIC peer must
hard-fail if absent, matching the required Node HTTP/2 lane rather than the
optional OpenSSL TLS lane. The required test must exercise certificate/name
validation, request/response headers and DATA, stream flow control, peer close,
malformed packets, and resource bounds. No success-only smoke test is
sufficient.

## Licensing and dependency assessment

The repository is MIT-licensed. Candidate test-only peers report permissive
licenses: `aioquic` BSD-3-Clause, `quiche` BSD-2-Clause, and `ngtcp2` MIT.
These are plausible CI fixtures subject to pinning and notice preservation, but
test-only use does not decide a runtime dependency. An external runtime library
adds ABI, packaging, toolchain, cross-platform, release, and target-support
burden; a quiche path also implies a Rust build toolchain. Compare that burden
against the project's self-hosting targets and ADR-0012's preference for a
reviewable TLS surface. Licensing permissiveness alone is not approval. Sources checked: the
repository `LICENSE`, and the official `aiortc/aioquic`, `cloudflare/quiche`,
and `ngtcp2/ngtcp2` repositories. Recheck pinned versions before CI adoption.

## Bounds requiring design approval

These values are proposals for discussion, not accepted constants:

- Maximum UDP payload and whether to reject truncated datagrams. RFC 9000
  requires client Initial datagrams to be padded to at least 1200 bytes; that
  floor is mandatory, not a tunable bound.
- PMTU/DPLPMTUD policy and whether probing is disabled; whether to process ECN
  (an initial profile may explicitly disable ECN).
- Maximum concurrent connections and bidirectional/unidirectional streams.
- Maximum packet/CRYPTO reassembly bytes per connection and per stream.
- Maximum ACK ranges, outstanding packets, retransmission bytes, and blocked
  QPACK streams.
- QPACK dynamic-table capacity and header-list size.
- Connection idle timeout and PTO/backoff ceilings.

Every cap must be configurable only if configuration cannot disable the safety
bound; otherwise use conservative fixed library limits with documented errors.

## Unresolved decisions

1. Pure Oxl implementation versus a foreign QUIC library behind a runtime shim;
   compare portability, build/release burden, licensing, security reviewability,
   and JS/WASM compatibility. A runtime dependency needs a separate decision
   from a test-only permissively licensed peer.
2. Public datagram API shape and supported target matrix, including IPv4-only
   versus dual-stack IPv4/IPv6 and whether Happy Eyeballs is required.
3. Whether the TLS refactor is a prerequisite PR or part of the QUIC feature
   series; it must remain independently testable either way.
4. Exact resource caps and whether QPACK dynamic table support is required for
   the first interoperable client profile.
5. Whether QUIC inherits ADR-0012's documented non-constant-time caveat or
   reopens it, given per-packet AEAD/header-protection operations.
6. Independent peer choice, pinned version, reproducible CI installation, and
   a hard-fail policy if the peer is unavailable.
7. PMTU/ECN defaults and the precise version-negotiation/greasing profile.

## Gate and safe next action

Obtain an independent QUIC/TLS security review of this decomposition, resolve
the API/library/limit decisions through a durable Ox-Agent input, and prove the
vectors plus independent peer can run in CI. Until then, keep #219 open and do
not add QUIC source files or claim implementation completion.
