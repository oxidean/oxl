# WI-0016 plan

1. Package files under editors/grammars/ (package.json, index.mjs,
   README.md, .npmrc) — version "0.0.0" stamped in CI.
2. release.yml editors job: packages:write, pack step after
   "assemble editor assets", tgz assets in "upload release assets",
   "publish shiki-oxl to GitHub Packages" step (hard fail).
3. docs/site fence normalization to ```oxl for oxl/oxl.mod snippets.
4. tests/run.sh: shiki-oxl manifest + npm pack dry-run + index.mjs
   import assertions in the editor assets section.
5. Verify: bash -n, yaml parse, local pack/import probes, full
   tests/run.sh, push → PR → CI → self-review → merge.
6. Post-merge: backfill v0.14.1 release assets; npm publish blocked on
   write:packages PAT — hand scope list to Jesse.
