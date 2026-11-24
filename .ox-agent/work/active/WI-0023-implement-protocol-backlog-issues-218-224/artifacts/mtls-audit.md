# Independent audit — client mTLS (#221)

## Branch state

The `language-tls-server` (`feat/tls-server`) and `language-x509-extras`
(`feat/x509-extras`) worktrees are uncommitted drafts based on `a2602a44`, while
`origin/main` is `b463ebe`. Their changes are not on main and are not safe to
cherry-pick wholesale. The X.509 extras draft is unrelated to #221 and conflicts
with ADR-0012's parked revocation scope.

## Current client behavior

- `std/net/tls/tls.oxl` documents no mTLS and `Config` has no client identity
  fields.
- `std/net/tls/handshake.oxl` answers a CertificateRequest with an empty
  Certificate and Finished; there is no client CertificateVerify path.
- `std/crypto/x509` parses certificates, not private-key PEM. HTTPS already
  carries `tls.Config`, so adding validated identity fields can be plumbed
  without a new HTTP transport API.

## Reusable draft substrate (not yet reviewed or tested)

The TLS-server worktree contains PKCS#8/PKCS#1/SEC1 key parsing and key/cert
matching, RSA v1.5/PSS signing, deterministic ECDSA signing, Ed25519 signing,
and a server-side CertificateVerify routine. These may be reusable after
extracting and rebasing, but the server itself must not be included in #221.

## Blocking gaps

1. No configured client Certificate/CertificateVerify flight exists on main.
2. CertificateRequest `signature_algorithms` is ignored; client selection must
   be constrained to the server's offered schemes.
3. Post-handshake client authentication requires advertising
   `post_handshake_auth`; the current ClientHello does not.
4. No key parsing, signing, mismatch, flight, or client-auth interoperability
   tests exist in the drafts.
5. The signing draft uses variable-time private operations (`nistec` scalar
   multiplication and unblinded big-number exponentiation). ADR-0012's
   constant-time review trigger is now active because mTLS introduces signing.
   The posture needs explicit crypto-focused review/acceptance before ship.
6. Drafts are based on stale main and include server-side TLS or CRL/revocation
   code outside #221. Extract only reviewed primitives; do not merge wholesale.

## Required gate before inclusion

Rebase reviewed key/signing primitives onto the combined branch; add Config and
client-flight wiring; preserve mandatory server chain/name verification; test
valid and invalid/mismatched keys, all supported signature schemes, no-cert and
server-no-request paths, and TLS 1.3 interop with client auth enabled/disabled.
Obtain a crypto-focused review of key validation and private-key timing. Keep
#221 open and exclude it from the combined PR until these criteria pass.
