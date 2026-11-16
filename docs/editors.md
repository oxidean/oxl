# Editor support

The `oxl` binary ships a stdio language server:

```sh
oxl lsp
```

It speaks LSP over `Content-Length`-framed JSON-RPC and provides
diagnostics on open/change, hover, go-to-definition, completion,
signature help, document symbols, document highlight, references,
rename (with capture rejection), whole-document formatting, semantic
tokens, and watched-file invalidation. Positions are 0-based lines
with UTF-16 columns; documents sync as full text.

Every toolchain release publishes editor assets on
[GitHub Releases](https://github.com/oxidean/oxl/releases):

- `oxl-language.vsix` — the VS Code extension (stable URL under
  `releases/latest/download/`)
- `oxl-editor-assets.tar.gz` — vsix + grammars + nvim plugin bundle
- `oxl.sublime-syntax` — bat/Sublime Text syntax

`scripts/install-editor.sh` wraps all of them:

```sh
scripts/install-editor.sh vscode [tag] [code|codium|cursor]
scripts/install-editor.sh nvim   [tag]
scripts/install-editor.sh bat    [tag]
scripts/install-editor.sh list   [tag]
```

`tag` defaults to the newest release carrying editor assets;
`OXL_RELEASE_BASE` overrides the release host (used by the test suite).

## VS Code

```sh
code --install-extension \
  https://github.com/oxidean/oxl/releases/latest/download/oxl-language.vsix
```

The extension bundles a language client — no separate LSP setup. It
spawns `oxl lsp` from `PATH`; set `oxl.lsp.path` in settings to an
absolute binary path when `oxl` is not on `PATH`. The same extension
is published to Open VSX (namespace `oxidean`), so VSCodium, Cursor,
and other Open-VS-X-default forks install and auto-update it from
their extension panel. GitHub-vsix installs do not self-update —
re-run the install command (or `install-editor.sh vscode`) per release.

## Neovim

`oxidean/nvim-oxl` mirrors `editors/nvim/` on every release; its tags
match toolchain tags, so plugin managers track releases like any git
plugin.

```sh
scripts/install-editor.sh nvim          # native pack dir, no plugin manager
git clone --depth 1 --branch v0.13.0 \
  https://github.com/oxidean/nvim-oxl \
  ~/.local/share/nvim/site/pack/vendor/start/nvim-oxl
```

lazy.nvim / packer:

```lua
{ 'oxidean/nvim-oxl', ft = 'oxl' }
```

Requires Neovim 0.11+ (native `vim.lsp.config`) or 0.10 with
nvim-lspconfig. Highlighting comes from the server's semantic tokens;
`syntax/oxl.vim` covers sessions without the LSP. Custom server
command: `require('oxl').setup { cmd = { '/path/to/oxl', 'lsp' } }`.

## bat / Sublime Text / other grammars

```sh
scripts/install-editor.sh bat           # ~/.config/bat/syntaxs/oxl.sublime-syntax
```

`editors/grammars/oxl.tmLanguage.json` is the TextMate grammar —
VS Code consumes it via `editors/vscode/syntaxes/`, and any
TextMate-compatible highlighter (e.g. Shiki-based sites) can vendor it
directly.

## Other editors

Any LSP client works: the server needs no initialization beyond the
standard handshake and honors `rootUri`/`workspaceFolders` (first
folder only). Helix and Zed need a compiled tree-sitter parser —
tracked as future work, not part of the release assets.
