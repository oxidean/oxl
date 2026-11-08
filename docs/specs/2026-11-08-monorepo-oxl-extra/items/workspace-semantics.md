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
- Resolution runs ONE longest-prefix competition across every
  candidate tree — main module, `use`d trees, `replace`d requires,
  cached requires — and the longest matching module path wins
  regardless of source; source order only breaks exact-path ties.
  A `use`d `example.org/a` therefore does *not* capture imports
  under a required `example.org/a/b` — the longer require still
  wins. `std/` is the final anchor after all module candidates.
- A `use`d module shadows a `require` for the *same* path only
  (the tie case above; go.work semantics) — the `require` line
  still documents the minimum version for published consumers.
- Diagnostics are `error [check] oxl.work:<line>: <msg>` on both
  drivers — malformed directive, `use` dir without `oxl.mod`, and
  two `use`d modules declaring the *same* module path. Nested
  module paths (`example.org/a` and `example.org/a/b`) are valid —
  longest-path-wins already disambiguates them.
- File mode (no `oxl.mod` found): `oxl.work` is ignored entirely.
