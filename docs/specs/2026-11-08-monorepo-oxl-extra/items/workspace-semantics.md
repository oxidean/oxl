# oxl.work semantics (E1 contract)

File: `oxl.work` at workspace root. Grammar reuses the manifest
parser — directives, one per line, comment rules identical.

```
oxlwork 0.3          // schema version line, mirrors `oxl` in oxl.mod
use ./               // module dir, relative to the work file
use ./extra
```

Rules:
- Discovery: from the entry file upward (same walk as `oxl.mod`);
  a found `oxl.work` extends — does not replace — module discovery.
- Resolution order: `use` module trees (longest path wins) →
  `replace` dirs → module cache → std anchor.
- A `use`d module shadows any `require` for the same path (go.work
  semantics) — the `require` line still documents the minimum
  version for published consumers.
- Diagnostics (`mod_work_*`): malformed directive, `use` dir without
  `oxl.mod`, two `use`d modules claiming overlapping paths.
- File mode (no `oxl.mod` found): `oxl.work` is ignored entirely.
