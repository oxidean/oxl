# oxl-language

Syntax highlighting and language configuration for
[oxl](https://github.com/oxidean-org/language-selfhost-editor) (`.oxl`
files).

## Install

From this repository:

```sh
cd editors/vscode
npm install -g @vscode/vsce   # once
vsce package                  # produces oxl-language-*.vsix
code --install-extension oxl-language-*.vsix
```

Or symlink `editors/vscode` into `~/.vscode/extensions/oxl-language-0.1.0`
for development.

## Language server

This extension ships grammar and configuration only. To get diagnostics,
hover, completion, and the rest of the LSP surface, point any LSP client
at the `oxl` binary:

```sh
oxl lsp    # stdio JSON-RPC server
```

The `oxl.lsp.path` setting records where your `oxl` binary lives (used by
clients that read it, e.g. a generic LSP launcher).
