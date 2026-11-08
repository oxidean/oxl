# Git-backed index protocol (E4 contract)

Index repo layout — one file per module, JSON Lines:

```
index/github.com/oxidean/oxl/extra.json   # module path → index/<path>.json
{"version":"v0.1.0","commit":"<sha>","h1":"<sum>","tag":"extra/v0.1.0"}
{"version":"v0.2.0","commit":"<sha>","h1":"<sum>","tag":"extra/v0.2.0"}
```

The filename is derived mechanically — `index/` + the module path +
`.json` — so publish and lookup can never disagree on the key.

Rules:
- Entries are append-only; each line is one published version.
  `h1` is the module-tree hash `oxl.sum` records.
- `oxl publish` runs the pre-publish checks (clean tree, suite
  green per policy), writes the tag, appends the index entry, and
  pushes — or emits the entry for an index-repo PR. Ordering is
  tag-then-entry so an entry never names a tag that does not exist;
  the retry path is idempotent: a pre-existing tag is accepted iff
  it points at the same commit, otherwise publish stops. A retry
  after an interrupted run therefore skips the tag step and
  completes the entry.
- `oxl get` resolution order: index (`OXLMODINDEX`, local path or
  git URL fetched shallow) → direct git derive-from-path.
- Integrity is checked at two points. `oxl get` compares the index
  entry's `h1` against the fetched module tree — an edited index
  entry fails the fetch, so index tamper is caught at get time.
  `oxl mod verify` re-hashes cache slots against `oxl.sum` — that
  catches cache/local tamper, unchanged.
- Namespace: module path prefix ownership = index-repo write
  access; no other auth in v1.
