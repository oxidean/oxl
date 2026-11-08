# Git-backed index protocol (E4 contract)

Index repo layout — one file per module, JSON Lines:

```
index/github.com~oxidean~oxl~extra.json   # see path encoding below
{"version":"v0.1.0","commit":"<sha>","h1":"<sum>","tag":"extra/v0.1.0"}
{"version":"v0.2.0","commit":"<sha>","h1":"<sum>","tag":"extra/v0.2.0"}
```

The filename is derived mechanically — `index/` + the module path
with each `/` replaced by `~`, then `.json`. Module path segments
are restricted to `[a-zA-Z0-9._-]` (the existing git-derived-path
rule), which cannot contain `~`, so the mapping is injective:
`github.com/acme/lib` → `index/github.com~acme~lib.json` and
`github.com/acme/lib.json/extra` → `index/github.com~acme~lib.json~
extra.json` never collide. Publish and lookup share the same
derivation, so they can never disagree on the key.

Rules:
- Entries are append-only; each line is one published version.
  `h1` is the module-tree hash `oxl.sum` records.
- `oxl publish` runs the pre-publish checks (clean tree, suite
  green per policy), creates and **pushes** the tag to the source
  repo, and only then publishes the index entry — an entry never
  names a tag consumers cannot reach. If the tag push fails,
  nothing is published. Retry is idempotent end to end: a
  pre-existing remote tag is accepted iff it points at the same
  commit (mismatch → stop); an existing index entry identical to
  the one being published (same version, commit, `h1`) is treated
  as already-published success, while a conflicting entry for the
  same version is rejected. An interrupted run therefore resumes
  safely at either step without duplicating the entry.
- `oxl get` resolution order: index (`OXLMODINDEX`, local path or
  git URL fetched shallow) → direct git derive-from-path.
- Integrity is checked at two points. `oxl get` compares the index
  entry's `h1` against the fetched module tree and fails on
  mismatch. This detects entries whose content no longer matches
  the fetched tree — it does **not** authenticate the entry: a
  rewrite that swaps both `commit` and `h1` to a different valid
  tree is outside v1's threat model (index-repo write access is the
  trust boundary). `oxl mod verify` re-hashes cache slots against
  `oxl.sum` — that catches cache/local tamper, unchanged.
- Namespace: module path prefix ownership = index-repo write
  access; no other auth in v1.
