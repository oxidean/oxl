# Implementation record — current increment

## Completed commits on the combined branch

- `22ea1ea` — HTTPS proxy CONNECT request/tunnel integration and local tests.
- `dbe919b` — harden CONNECT response parsing and reject invalid tunnel framing.
- `6609778` — add HTTP/2 framing, HPACK, stream/flow-control state, ALPN/h2c
  client integration, and independent Node interoperability tests.
- `1a61cb6` — preserve caller TLS server-name/custom ALPN settings, accept only
  RFC-valid server `SETTINGS_ENABLE_PUSH=0`, and add regressions/name assertions.

## Current verification

Focused connection and interop tests pass; exact command output is recorded in
`test-evidence.md`. The full suite attempt is not final evidence because
`tests/run.sh` changed during that run. Re-run after all sources stabilize.

## Remaining implementation

WebSocket (#220), gRPC (#223), and TLS 1.2 (#224) are in isolated worktrees and
must be independently audited before integration. QUIC (#219) and client mTLS
(#221) remain gated by the spec. No issue is complete merely because code has
been drafted; each needs its tests, review, and platform CI.
