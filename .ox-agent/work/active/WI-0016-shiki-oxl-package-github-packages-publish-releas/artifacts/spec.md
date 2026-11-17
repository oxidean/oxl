# WI-0016 spec — @oxidean/shiki-oxl package (issue #122)

## Intent
Ship `editors/grammars/oxl.tmLanguage.json` as a versioned, installable
package so downstream consumers (oxidean.dev, oxidean forge) stop
vendoring drifting copies. Tracked downstream in oxidean/oxidean.dev#48.

## Scope
- `editors/grammars/` becomes an npm package root: `package.json`
  (`@oxidean/shiki-oxl`, `publishConfig.registry` → npm.pkg.github.com,
  `files` whitelist, `exports` for `.` and `./grammar.json`),
  `index.mjs` (grammar → Shiki lang object, `name: "oxl"`),
  `README.md` (tarball + GitHub Packages install paths), `.npmrc`
  (NODE_AUTH_TOKEN auth line for publish).
- `release.yml` `editors` job: `packages: write` permission, version
  stamped from tag, `npm pack` → `dist/oxidean-shiki-oxl-<ver>.tgz` +
  fixed-name `dist/shiki-oxl.tgz`, both uploaded to the release,
  `npm publish` hard-fail step.
- Docs fence normalization: ` ```text title="*.oxl" ` → ` ```oxl ` in
  `docs/site/` (3 fences; CLI-listing `text` fence untouched).
- `tests/run.sh` editor section: manifest/pack/import assertions.
- Post-merge backfill: pack + upload tgz to `v0.14.1`; npm publish
  needs a `write:packages` PAT (gh token lacks the scope).

## Non-goals
- No changes to the grammar itself; vscode extension untouched.
- No downstream consumer wiring (oxidean.dev / oxidean PRs are separate).

## Acceptance
- `npm pack --dry-run` lists exactly index.mjs, oxl.tmLanguage.json,
  README.md, package.json.
- `node -e import` of index.mjs yields name=oxl, scopeName=source.oxl.
- tests/run.sh editor section green; CI green on the PR.
- On next tag, release carries both tgz assets and the package resolves
  on npm.pkg.github.com.
