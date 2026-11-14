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

## VS Code

Install the extension in `editors/vscode/` (see its README) for syntax
highlighting and language configuration, then attach the language
server. With a generic LSP client extension, or the built-in
`vscode-languageclient` if you wire one up, the server command is:

```json
{
  "command": "oxl",
  "args": ["lsp"]
}
```

Set `oxl.lsp.path` if your `oxl` binary is not on `PATH`.

## Neovim (nvim-lspconfig)

```lua
require('lspconfig').oxl = {
  default_config = {
    cmd = { 'oxl', 'lsp' },
    filetypes = { 'oxl' },
    root_dir = function(fname)
      return vim.fs.dirname(vim.fs.find({ 'oxl.mod', '.git' }, { path = fname, upward = true })[1] or fname)
    end,
  },
}
require('lspconfig').oxl.setup {}
```

If `oxl` is not on `PATH`, give the absolute path in `cmd`.

## Other editors

Any LSP client works: the server needs no initialization beyond the
standard handshake and honors `rootUri`/`workspaceFolders` (first
folder only).
