# WI-0016 brainstorm

Issue #122 is already a detailed spec (package layout, workflow steps,
consumption contract, test plan) — convergent analysis collapsed to
confirming its forks:

- Registry: GitHub Packages (org-native, GITHUB_TOKEN publish) AND
  release-tarball asset (auth-free path) — both, per issue.
- Version source: release tag via the same VER="${TAG#v}" stamp the
  vsix step uses; repo copy stays "0.0.0".
- Fixed-name asset `shiki-oxl.tgz` added alongside the versioned tgz so
  releases/latest/download/<name> stays stable (existing convention).
- .npmrc committed with `${NODE_AUTH_TOKEN}` reference — documents auth
  for manual publishes; excluded from tarball by the files whitelist.
- Publish step is a hard fail (GITHUB_TOKEN + packages:write always
  present), unlike the credential-gated OVSX/mirror legs.
- Docs fences normalized upstream per issue §4 — cosmetic; oxidean.dev
  normalizes old fences for already-published bundles anyway.
