# Impl notes — E2–E6 (one-PR landing of remaining milestone E)

Branch `feat/e2-e6-monorepo`. Status legend: `[x]` done+verified.
Landed as one PR: suite green, extras section, e3 subdir fetch +
e4 index publish/get/tamper fixtures run under the product driver;
E6 coverage in stdmods (surrogates), io_test (err chain), net_test
(localhost lookup).

## E2 — extra/ + workspace (done, in-tree)

- `extra/oxl.mod` — `module github.com/oxidean/oxl/extra`, `oxl 0.3`.
- `extra/testutil/testutil.oxl` — tempdir/rmtree, has([]str), approx,
  expect_ok, expect_err_contains.
- Root `oxl.mod` gained `require github.com/oxidean/oxl/extra v0.0.0`;
  new root `oxl.work` (`oxlwork 0.3`, `use ./`, `use ./extra`).
- `tests/extra_testutil.oxl` (package main) consumes it via the module
  path; run.sh "extras" section asserts + seed parity.
- **Workspace/module fixes this exposed (both drivers):**
  - `module_dir` (check.oxl + main.rs) now consults `mod_uses`/`uses`
    first — a `use`d tree supplies the module for (path, ver) lookups
    too, or tidy's provider misses and fetches over the network.
  - `mk_ctx` (getmod.oxl + main.rs) now runs `find_work` + `load_work`
    like `mod_ctx_load` — tidy previously ignored workspaces entirely.
  - `mod_verify` + tidy's sums rewrite skip `use`d modules (no cache
    slot, no oxl.sum lines — same class as replaces).
  - Seed `load_work` extracted from mod_ctx into a shared helper
    returning `Result<(), String>`; mod_ctx eprintln's the diag,
    mk_ctx propagates it.
- Verified: `oxl test tests/extra_testutil.oxl` → "extra testutil ok";
  scratch workspace tidy/verify/build/run on BOTH drivers; in-repo
  `mod verify` → "all modules verified"; `mod list` shows the require.

## E3 — subdir-module fetch (done, in-tree)

Design: `fetch_mod` tries full module path as repo (subdir=""); on
clone failure / resolve failure / missing or mismatched manifest it
strips the last path segment and retries with tag-prefix
`<sub>/`, bounded to ≥1 repo segment after the authority. `Fetched`
gains `subdir`; `untar`/`stage_tmp`/`slot_matches`/`install` root the
module at `<tmp>/<subdir>`; `fetch_resolve`/`fetch_tags`/`pseudo` take
a tag prefix (glob `<prefix>v*`, strip prefix → module version);
manifest read from `<sha>:<subdir>oxl.mod`; slot + sums keyed on full
mp — checker resolution unchanged. Self-driver only (get is not
parity-tested on the seed; builds of cached slots are layout-identical).

## E4 — git index (done, in-tree)

index/<escaped-segments>/<leaf>.json JSONL {version,commit,h1,tag}.
OXLMODINDEX local path or git URL. `oxl publish vX.Y.Z` (new cmd in
main.oxl dispatch): find_root + git toplevel → subdir → tag
`<sub>/vX`; eligibility per index-protocol.md alphabet BEFORE tag push;
clean subtree + per-package `oxl build`; create+push annotated tag;
append idempotent entry (same entry ok, conflicting reject); commit
(+push if origin). `oxl get` index-first for eligible paths: entry →
repo = mp minus tag-prefix, fetch @commit, dir_h1 vs entry.h1 tamper
check → install + pin. `mod verify` unchanged.

## E5 — extras release lane (done, in-tree)

release-version.sh: optional tag-prefix arg (`latest [PFX]`,
`next [RANGE] [PFX]`) globs `<pfx>v*`; release.yml: toolchain lane
only when non-`extra/` paths changed since last v* tag (pathspec
exclude), extras lane when `extra/` changed → `extra/v*` tag +
separate GH release, no toolchain tarball. CI gates extra/ build+test.

## E6 — polish (done, in-tree)

- #26 json: combine \uD800–\uDBFF + \uDC00–\uDFFF pairs → 4-byte UTF-8;
  lone surrogate stays an error (existing strictness, no CESU-8).
- #27 errors: rt.c registry gains cause slot — `rt_err_wrap(msg,cause)`,
  `rt_err_cause(code)`; errors.oxl wrap/unwrap/is (chain walk).
  `as` → parked: err is int64 codes, no typed targets exist to bind.
- #29 net: `rt_lookup_ipv4(host,tmo)` via getaddrinfo; net.oxl
  lookup_ipv4 runs it through spawnBlocking + mkchan(1) done signal +
  mkshared result cells (codebase idiom); dial hostnames.
- #30 time: document the blocking-worker contract permanently (usleep
  stays the deliberate-blocking escape hatch).
- #28: parked — needs runtime type descriptors; close issue, record in
  parked-stdlib.md.
