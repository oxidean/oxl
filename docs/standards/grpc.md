# gRPC client boundary

`std/net/grpc` implements the transport adapter: target scheme/dial policy,
HTTP/2 request headers, metadata validation, gRPC's five-byte message envelope,
status/trailer decoding, deadline and cancellation signaling, and bounded
message handling. It does **not** own protobuf descriptors or generated code.
Applications serialize request messages to bytes and parse response bytes with
their own protobuf implementation; protojson belongs to the application layer.

The `Client.begin` / `Call.send_message` / `Call.close_send` /
`Call.receive_message` sequence supports client-, server-, and bidirectional
streaming. `Client.unary` is a convenience for unary calls. Metadata is a
list of lowercase ASCII name/value pairs. Binary metadata values (`*-bin`) are
passed as encoded wire values; applications own base64 handling.

Targets `grpc://` and `http://` use plaintext HTTP/2; `grpcs://` and `https://`
use TLS with ALPN `h2`. Bare loopback targets, including `localhost:PORT`, use
plaintext and other bare targets use TLS. `dial_config` supplies trust
configuration. The current
`std/net` transport resolves numeric IPv4 addresses only.

Limits are explicit: messages are at most 4 MiB; metadata is capped at 64
fields and 8 KiB; one call's request body is capped at 60,000 framed bytes or
the peer's smaller current HTTP/2 send window;
and H2 pending events are bounded by its 64 KiB queue. The adapter caps active
calls at 16 process-wide and each call owns one HTTP/2 connection with one
active stream (there is no shared connection pool). Call `close` releases the
active-call slot. Compressed messages are rejected
as unsupported (`UNIMPLEMENTED`); there is no compression or reflection. The
connection timeout is the total RPC budget; `cancel` resets the active stream.

The outbound cap is a transport integration constraint, not a protocol limit:
the current H2 API exposes `send_data` but no public flow-control pump for
advancing a stream beyond the initial window while continuing a multi-message
send. A message that does not fit the current window is rejected before any
part of its gRPC envelope is written. Removing this cap requires a separately
reviewed H2 flow-control pump.

Received status values outside the defined 0–16 range map to `UNKNOWN`; the
wire value remains available as `Status.raw_code`. Non-200 HTTP responses map
to the corresponding gRPC status, and responses must use an
`application/grpc` content type.
