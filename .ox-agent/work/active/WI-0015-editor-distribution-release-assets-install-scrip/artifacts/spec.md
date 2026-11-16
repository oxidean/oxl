# WI-0015 spec — editor distribution

## Scope

Make every editor surface installable from GitHub releases and kept
current by the release pipeline:

- `editors/vscode/` becomes a real extension: bundled
  `vscode-languageclient` spawning `oxl lsp` (stdio), honoring
  `oxl.lsp.path`. Packaged to `oxl-language-<ver>.vsix` in CI.
- `editors/nvim/` — native Neovim plugin: filetype detection,
  `vim.lsp.config`/`vim.lsp.enable` (0.11+) with lspconfig fallback
  (0.10), semantic-token highlighting via the server, `syntax/oxl.vim`
  fallback, ftplugin commentstring.
- `editors/sublime/oxl.sublime-syntax` — bat/syntect + Sublime Text.
- `scripts/install-editor.sh` — `vscode|nvim|bat|list [tag]`, latest
  resolution, `OXL_RELEASE_BASE` fixture override.
- `release.yml` — `editors` job after `release`: builds vsix +
  `oxl-editor-assets.tar.gz` (+ .sha256), uploads to the release,
  pushes `editors/nvim` mirror to `oxidean/nvim-oxl` @ tag, publishes
  to Open VSX. Secret-gated legs fail soft.
- `docs/editors.md` + extension/plugin READMEs updated to the install
  paths.

## Contracts

- vsix filename: `oxl-language-<semver>.vsix`; package.json version ==
  tag minus `v` at package time.
- Assets tarball: `oxl-editor-assets.tar.gz` + `.sha256`, containing
  `vscode/oxl-language.vsix`, `grammars/oxl.tmLanguage.json`,
  `sublime/oxl.sublime-syntax`, `nvim/` (full plugin tree).
- Mirror repo tags mirror release tags (`vX.Y.Z`).
- install-editor.sh exit codes mirror install.sh (2 usage, 1 runtime).

## Acceptance

- `bash tests/run.sh ./target/oxl` green incl. new editor-asset checks.
- release.yml `editors` job valid; secret-gated legs emit
  `::notice::` and skip, never fail the job.
- vsix contains manifest + bundled client + grammar.
- No npm/node requirement on the user path anywhere.

## Non-goals

- VS Code Marketplace publish (no marketplace, per decision).
- Helix/Zed tree-sitter grammars.
- Multi-root workspace LSP changes.
- oxidean.dev / oxidean-app consumption (separate repos, separate PRs).
