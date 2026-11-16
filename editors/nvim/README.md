# nvim-oxl

Neovim support for [oxl](https://github.com/oxidean/oxl): filetype
detection, LSP client wiring (`oxl lsp`), and semantic-token
highlighting from the server. A vim syntax file covers sessions where
the language server is not attached.

This directory is mirrored to
[oxidean/nvim-oxl](https://github.com/oxidean/nvim-oxl) on every toolchain
release; tags there match `oxl` release tags.

## Install

Native package (no plugin manager):

```sh
oxl-editor-install nvim        # see scripts/install-editor.sh in the oxl repo
# or manually:
git clone --depth 1 https://github.com/oxidean/nvim-oxl \
  ~/.local/share/nvim/site/pack/vendor/start/nvim-oxl
```

lazy.nvim:

```lua
{ 'oxidean/nvim-oxl', ft = 'oxl' }
```

packer:

```lua
use { 'oxidean/nvim-oxl', ft = 'oxl' }
```

## Configuration

Defaults spawn `oxl lsp` from `PATH`. Override:

```lua
require('oxl').setup { cmd = { '/path/to/oxl', 'lsp' } }
```

Set `vim.g.oxl_no_auto_setup = true` before the plugin loads to disable
auto-setup entirely.

Requires Neovim 0.11+ for native `vim.lsp.config`, or 0.10 with
nvim-lspconfig installed.
