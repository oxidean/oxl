# Git-backed index protocol (E4 contract)

Index repo layout — one file per module, JSON Lines, nested
directories per module-path segment:

```
index/github.com/oxidean/oxl/extra.json   # see path encoding below
{"version":"v0.1.0","commit":"<sha>","h1":"<sum>","tag":"extra/v0.1.0"}
{"version":"v0.2.0","commit":"<sha>","h1":"<sum>","tag":"extra/v0.2.0"}
```

**Index alphabet.** A module path is index-eligible iff every
segment:

- fully matches `^[a-zA-Z0-9._-]+$` (one or more allowed chars —
  a search match would admit `ac~me`; an empty segment fails),
- passes the module-cache `check_component` rules (`oxl/src/
  modcache.rs`: rejects `.`/`..` — so `.` can never normalize the
  key onto a shorter path and `..` can never escape `index/` —
  no trailing `.` or space, no Windows-reserved device stem such
  as `con`, `aux`, `nul`, `com1-9`, `lpt1-9`),
- is not `.git` in any letter case — git's path verification
  refuses `.git` components in index entries, so `git add` of
  `index/<…>/.git/<leaf>.json` fails at append time. This check
  runs during eligibility, before `oxl publish` pushes the tag,
  so an unpublishable path cannot strand a pushed tag
  (`check_component` does not cover it: the module cache is not
  a git worktree, so the cache rules have no `.git` arm),
- does not end in `.json` when it is a *non-leaf* segment — a
  `lib.json` segment midway must become a directory while the
  same path `…/lib` derives a *file* `lib.json`, and one name
  cannot be both. A trailing-segment `.json` is safe (its entry
  file just gains a second suffix) so the rule is positional;
  ineligible paths keep the direct-git fallback, and
- has an *escaped* form (below) of ≤ 200 bytes.

The derived index path (`index/` + components + `.json`) must
additionally be ≤ 240 bytes in full — a long multi-segment path
must not produce a file Windows cannot check out (Git for
Windows disables long paths by default). Eligibility is checked
before any key is derived: `oxl publish` rejects ineligible
paths outright, and `oxl get` skips the index and falls back to
direct git for them — an ineligible path can never derive a key
that selects another module's entry.

**Key derivation.** Apply the module-cache case escaping
(`oxl/src/modcache.rs` `escape_path`: every uppercase letter
becomes `!` + its lowercase form) to each segment — index repos
must check out on case-insensitive filesystems, and paths
differing only by case (`acme/Lib` vs `acme/lib`) must not
collide. Each escaped segment becomes a directory component under
`index/`; the leaf segment gains `.json`. The mapping is
injective: `!` is produced only by the escape and is outside the
source alphabet, so segments decode unambiguously. The only
residual file/directory collision — a non-leaf segment that itself
ends in `.json` needing to be a directory beside a `…/lib`-derived
file — is excluded by the positional eligibility rule above, so
`github.com/acme/lib` → `index/github.com/acme/lib.json`,
`github.com/Acme/lib` → `index/github.com/!acme/lib.json`, and
`github.com/acme/lib.json` → `index/github.com/acme/lib.json.json`
never collide — even on Windows/macOS checkouts. (`github.com/
acme/lib.json/extra` is ineligible and resolves via direct git.)
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
