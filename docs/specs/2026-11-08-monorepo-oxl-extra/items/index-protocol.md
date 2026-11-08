# Git-backed index protocol (E4 contract)

Index repo layout — one file per module, JSON Lines:

```
index/github.com/oxidean/oxl-extra.json   # or .../oxl/extra — TBD in E4
{"version":"v0.1.0","commit":"<sha>","h1":"<sum>","tag":"extra/v0.1.0"}
{"version":"v0.2.0","commit":"<sha>","h1":"<sum>","tag":"extra/v0.2.0"}
```

Rules:
- Entries are append-only; each line is one published version.
  `h1` is the module-tree hash `oxl.sum` records.
- `oxl publish` runs the pre-publish checks (clean tree, tag free,
  suite green per policy), writes the tag, appends the entry, and
  pushes — or emits the entry for an index-repo PR.
- `oxl get` resolution order: index (`OXLMODINDEX`, local path or
  git URL fetched shallow) → direct git derive-from-path.
- `oxl mod verify` re-hashes cache slots and fails on mismatch —
  index tamper is caught there.
- Namespace: module path prefix ownership = index-repo write
  access; no other auth in v1.
