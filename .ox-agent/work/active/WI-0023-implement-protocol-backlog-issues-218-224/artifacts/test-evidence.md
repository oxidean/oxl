# Test evidence — current HTTP/2/CONNECT increment

- `./target/oxl fmt --check std/net/http2/conn.oxl tests/http2_conn_test.oxl tests/http2_interop_test.oxl`: passed.
- `./target/oxl test tests/http2_conn_test.oxl`: passed, including the new
  SETTINGS_ENABLE_PUSH=0 accept / =1 reject regression.
- Node-backed `tests/http2_interop_test.oxl`: passed, including h2c, TLS ALPN,
  custom ALPN retention, caller server-name preservation, HTTP/1.1 fallback,
  TLS verification failure, and client-level HTTP/2 behavior.
- `bash -n tests/run.sh` and `git diff --check`: passed.
- Full `tests/run.sh` attempt did not complete: `tests/run.sh` was edited while
  it was executing, and the shell exited with a syntax error after the CONNECT
  fixtures. That run is invalid evidence for the final tree; rerun the full
  suite after all source edits settle.
- Red-first outcome was not captured for the pre-existing H2/CONNECT
  implementation. Report this limitation rather than claiming a red-to-green
  sequence. New regression tests pass on the current implementation.
