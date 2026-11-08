# Git-backed index protocol (E4 contract)

Index repo layout — one file per module, JSON Lines, nested
directories per module-path segment:

```
index/github.com/oxidean/oxl/extra.json   # see path encoding below
{"version":"v0.1.0","commit":"<sha>","h1":"<sum>","tag":"extra/v0.1.0"}
{"version":"v0.2.0","commit":"<sha>","h1":"<sum>","tag":"extra/v0.2.0"}
```

**Index alphabet.** A module path is index-eligible iff every
segment matches `[a-zA-Z0-9._-]` and its *escaped* form (below) is
≤ 200 bytes. Eligibility is checked before any key is derived —
`oxl publish` rejects ineligible paths outright, and `oxl get`
skips the index and falls back to direct git for them (a path
containing e.g. `~` or a separator-adjacent byte must never be
allowed to derive a key that selects another module's entry).
The 200-byte bound keeps every filesystem component — escaped
segment or `<leaf>.json` — under the 255-byte limit on all
supported platforms, no matter how deep the path nests.

**Key derivation.** Apply the module-cache case escaping
(`oxl/src/modcache.rs` `escape_path`: every uppercase letter
becomes `!` + its lowercase form) to each segment — index repos
must check out on case-insensitive filesystems, and paths
differing only by case (`acme/Lib` vs `acme/lib`) must not
collide. Each escaped segment becomes a directory component under
`index/`; the leaf segment gains `.json`. The mapping is
injective: `!` is produced only by the escape and is outside the
source alphabet, so segments decode unambiguously, and a file
`lib.json` vs directory `lib/` cannot collide by construction.
`github.com/acme/lib` → `index/github.com/acme/lib.json`,
`github.com/Acme/lib` → `index/github.com/!acme/lib.json`, and
`github.com/acme/lib.json/extra` → `index/github.com/acme/lib.json/
extra.json` never collide — even on Windows/macOS checkouts.
Publish and lookup share the same derivation, so they can never
disagree on the key.

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
