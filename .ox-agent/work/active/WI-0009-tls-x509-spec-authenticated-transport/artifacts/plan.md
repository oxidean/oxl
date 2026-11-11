# WI-0009 plan — TLS/x509 spec

Lifecycle: spec work item — the spec docset *is* the deliverable;
implementation rides `feat/milestone-x` stages per the spec's plan.

1. Survey repo (done): spec format from 2026-11-10-web-target +
   2026-11-11-type-descriptors; S4 crypto ethos; driver `needs_*`
   link pattern; rt.c inventory (no entropy, no TLS); net.Conn/
   http seams; CI legs (ubuntu/macos/windows); WI + ADR numbering.
2. Resolve forks (done — artifacts/brainstorm.md): pure-.oxl;
   TLS 1.3 floor; env→platform→err roots; verify-only crypto;
   hook-not-flag overrides; SAN-only names.
3. Write docset: shape.md, plan.md (X0–X7, exit gates + test
   names), items/{x509-trust,tls13-wire,tls-api}.md.
4. ADR-0012 for the spec-level forks.
5. PR `docs/tls-x509-spec` → main; `@coderabbitai review` pass;
   merge; closeout stage X7 archives this WI.
