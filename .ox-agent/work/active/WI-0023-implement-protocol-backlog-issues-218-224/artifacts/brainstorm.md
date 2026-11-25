# Brainstorm — delivery shape for protocol issues #218–#224

## Option A — one branch, one final PR, issue-scoped commits

Keep the seven issue streams on one branch, order dependencies (#218 before
#223), and use separate commits/tests/reviews per issue. Open a single PR after
all included issues pass their gates.

- Benefits: matches the user's explicit one-PR request; dependent H2/gRPC
  changes are reviewed together; one cross-platform matrix validates the final
  tree.
- Costs: large review surface; unrelated protocol stacks share CI; conflicts
  and security findings may delay the whole PR.
- Guard: an issue with unmet architecture/security gates is not represented by
  a stub and is not claimed complete. #219 and #221 may remain open with
  evidence if gates cannot be met.

## Option B — separate PRs by protocol capability

Ship HTTP/2+gRPC, WebSocket, TLS 1.2, and CONNECT as separate PRs.

- Benefits: smaller diffs, independent review/rollback, faster shipping of
  completed capabilities.
- Costs: contradicts the explicit one-PR request and requires more branch/CI
  coordination; gRPC still depends on H2.

## Option C — one design PR followed by implementation PRs

Submit the shared architecture and issue specifications first, then implement
features in dependency order.

- Benefits: resolves QUIC and mTLS security decisions before implementation.
- Costs: does not deliver the requested implementations in one PR; adds a
  planning-only merge cycle.

## Convergence

Select Option A because the user explicitly requested one PR. Keep commits and
reviews issue-scoped, and retain the #219 QUIC architecture and #221 mTLS crypto
security gates. If either cannot safely pass, deliver only fully accepted
features and state plainly that the all-issues request is not complete; do not
close or reference blocked issues as implemented. Existing PR #215 is unrelated
and excluded.
