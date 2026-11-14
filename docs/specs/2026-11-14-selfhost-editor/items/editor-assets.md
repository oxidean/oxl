# items/editor-assets — U4 detail

## `editors/grammars/oxl.tmLanguage.json`

Hand-authored TextMate grammar, `scopeName: source.oxl`. Must
cover the real token surface (see `bootstrap/lexlib` +
`docs/semantics`): line/block comments, raw strings, all keyword
classes (fn/struct/enum/iface/import/use/if/else/match/for/
while/select/go/spawn/scope/chan/own/mut/ref/shared/susp/err/
nil/true/false/break/continue/defer/go/return), builtin types
(int/str/bool/float/byte/cstr/err/fn/[]/map?), operators incl.
`->`/`=>`-class tokens the lexer actually emits, number literals
(dec/hex/bin/float/char), identifiers, field access, call vs decl
contexts where regex-feasible. Embed nothing — oxl has no
string-interpolation or nested-language surface to inherit.

Validation: JSON parse + a smoke file through a tmLanguage
engine (VS Code's own grammar test or `npx vscode-textmate`-class
tooling) asserting keyword/string/comment scopes land.

## `editors/vscode/`

Minimal extension, no build:

- `package.json` — `contributes.languages` (`.oxl`,
  `oxlmod`?), `grammars` (tmLanguage path), `configuration`
  (oxl.lsp.* settings minimal), activation on language.
- `language-configuration.json` — line comments `//`, block
  `/* */`, brackets, auto-closing pairs.
- `syntaxes/oxl.tmLanguage.json` — copy of the canonical
  grammar (single source of truth stays
  `editors/grammars/`; document the copy direction).
- Launch: `oxl lsp` server definition (command `oxl`, args
  `["lsp"]`, transport stdio).
- README — install-from-source (`code --install-extension
  editors/vscode` or folder open), requirements (oxl on PATH),
  feature list matching the advertised capabilities.

## `docs/editors.md`

- VS Code: extension install + manual server config fallback.
- Neovim: lspconfig snippet —
  `require'lspconfig'.oxl.setup{cmd={'oxl','lsp'}, filetypes={'oxl'}}`
  + `vim.filetype.add` for `.oxl`; mention `:checkhealth` and
  root-marker `oxl.mod`.
- Note the semanticTokens legend is negotiated — themes that
  support LSP semantic tokens get checker-accurate highlighting;
  others fall back to the tmLanguage grammar where the editor
  loads it.
- Forge/web highlighting pointer: grammar vendored into
  oxidean-app (follow-up PR link when it lands).

## Verification

- `plutil -lint` / `python -m json.tool` on the grammar.
- Scripted LSP `initialize` against a built `oxl` asserting the
  capability block (the same JSON-RPC harness the suite uses).
- VS Code extension: `code --list-extensions` after install +
  a smoke `textDocument/didOpen` round-trip if a CLI-driveable
  check exists; otherwise document manual verification steps.
