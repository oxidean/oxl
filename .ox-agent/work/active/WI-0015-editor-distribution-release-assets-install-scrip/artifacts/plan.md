# WI-0015 plan — editor distribution

1. **e1 assets** — `editors/nvim/` plugin (ftdetect, lsp config +
   lspconfig fallback, syntax fallback, ftplugin, README);
   `editors/sublime/oxl.sublime-syntax`; extend
   `editors/vscode/` (src/client.js, build.mjs, package.json main/
   files/scripts, README rewrite).
2. **e2 installer** — `scripts/install-editor.sh` (vscode|nvim|bat|
   list, latest-tag resolution, OXL_RELEASE_BASE fixtures).
3. **e3 release wiring** — `release.yml` `editors` job: npm ci +
   build + vsce package, assets tarball + sha256, `gh release upload`,
   nvim-oxl mirror push (secret-gated), Open VSX publish (secret-gated).
4. **e4 docs** — `docs/editors.md` rewrite around install-editor.sh;
   README pointer if warranted.
5. **e5 tests** — run.sh section: install-editor.sh offline fixtures
   (file:// release base), vsix zip structure check, sublime-syntax
   sanity, nvim lua syntax check (soft-skip without nvim).
6. **e6 closeout** — full suite green, PR, review loop, merge; WI
   archive rides the chore PR per convention.
