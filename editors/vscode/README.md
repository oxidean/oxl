# oxl-language

VS Code extension for [oxl](https://github.com/oxidean/oxl): syntax
highlighting plus a bundled language client that spawns `oxl lsp`
(stdio) for diagnostics, hover, go-to-definition, completion,
signature help, document symbols/highlight, references, rename,
formatting, semantic tokens, and watched-file invalidation.

## Install

Every toolchain release ships `oxl-language.vsix` on
[GitHub Releases](https://github.com/oxidean/oxl/releases) under
`/releases/download/vX.Y.Z/oxl-language.vsix`.

```sh
scripts/install-editor.sh vscode   # resolves the newest release with
                                   # editor assets, downloads, installs
```

`code --install-extension` needs a local `.vsix` path — download the
asset first, then install it.

The extension is also published to Open VSX (namespace `oxidean`), so
VS Code forks that use Open VSX (VSCodium, Cursor, …) pick it up from
their extension panel and keep it updated automatically. Direct
GitHub-vsix installs do not self-update — re-run per release.

## Requirements

The `oxl` binary on `PATH` (or set `oxl.lsp.path` in settings to its
absolute path). Install it with `scripts/install.sh` or
`scripts/install-editor.sh` — see `docs/editors.md`.

## Develop / package locally

```sh
cd editors/vscode
npm ci
npm run build      # bundles src/client.js -> dist/extension.js (esbuild)
npm run package    # vsce package -> oxl-language-<version>.vsix
```

The shipped extension is the esbuild bundle — no `node_modules`, no npm
at install time.
