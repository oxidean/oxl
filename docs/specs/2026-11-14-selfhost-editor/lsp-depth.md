# LSP depth — protocol contract

Extends `cmd/oxl/lsp.oxl` from diagnostics/hover/definition to the
daily-driver set. All positions: 0-based line, UTF-16 column
(`initialize` does not negotiate `positionEncoding`). Sync stays
full-text (`textDocumentSync: 1`).

## Wire layer

- Content-Length framing unchanged.
- JSON via `std/encoding/json` (or `cmd/oxl/lsp/json.oxl` fallback
  per the U2 probe). Requests dispatch on `method`; unknown →
  `-32601`, malformed → `-32700`.
- Responses are built through the same JSON writer — no hand-rolled
  escaping.

## Capabilities (initialize result)

```
capabilities: {
  textDocumentSync: 1,
  hoverProvider: true,
  definitionProvider: true,
  completionProvider: { triggerCharacters: [".", "("] },
  signatureHelpProvider: { triggerCharacters: ["(", ","] },
  documentSymbolProvider: true,
  documentFormattingProvider: true,
  semanticTokensProvider: {
    legend: { tokenTypes, tokenModifiers },   // fixed order
    full: { delta: null }                      // full-document only
  },
  referencesProvider: true,
  renameProvider: { prepareProvider: false },
  documentHighlightProvider: true,
  workspace: { didChangeWatchedFiles: { dynamicRegistration: false } }
}
```

`rangeFormattingProvider`, `callHierarchyProvider`,
`inlayHintProvider`, `codeActionProvider` are NOT advertised.

## Request semantics

- **completion** — context: identifier prefix at cursor (or empty).
  Candidates: in-scope decls (fns, structs, enums, consts, fields
  after `.`), package-scope decls, keywords, builtin types.
  `sortText` = kind rank then name; `detail` = `sig` text;
  `kind` mapped LSP-side (Function/Struct/Field/Keyword/…).
- **signatureHelp** — enclosing `(` of a call resolved via UseRec
  or span walk; `signatures[]` from `FnSig`; `activeParameter`
  from top-level comma count; `activeSignature` = 0 (overloads
  don't exist).
- **documentSymbol** — `declsv` entries for the doc's file, nested
  by span containment; `kind` from decl class; `range`/`selectionRange`
  from lo/hi.
- **formatting** — whole-document `fmt_text(src)`; returns
  `TextEdit[]` with one full-range edit (or null when already
  canonical — client no-ops either way).
- **semanticTokens** — full-document token stream. Legend:
  namespace, type, class, enum, interface, struct, typeParameter,
  parameter, variable, property, enumMember, event, function,
  method, macro, keyword, modifier, comment, string, number,
  regexp, operator, decorator + modifiers none/default/
  definition/declaration/static/readonly/abstract/async/
  modification/deprecated. Classification: lexer token kind first;
  identifiers upgraded via UseRec → def kind (fn→function,
  struct→class/struct, field→property, …). Encoded as the spec's
  delta-ints.
- **references / documentHighlight** — all UseRecs whose
  (def_file, def_lo, def_hi) equals the target's; highlight caps
  display, references returns `Location[]`.
- **rename** — resolve target → def span → collect UseRecs +
  decl-site edit → `WorkspaceEdit{changes: {uri: TextEdit[]}}`.
  Rejection: if any collected site's enclosing scope binds the
  new name to a *different* def span (shadow/capture), return
  `{}` changes + `window/showMessage` (Warning) naming the
  conflict — never a silent wrong rewrite.
- **didChangeWatchedFiles** — on FileChange events under the
  analysis root: drop matching `Anl` entries (and their `pubs`
  rows), re-analyze open docs in affected package dirs,
  republish diagnostics. Events for unopened files still
  invalidate — next request re-analyzes.
- **workspaceFolders** — accepted in initialize; only the first
  folder is honored (others ignored, not errored). `rootUri`
  maps to the package dir via `oxl.mod` discovery upward from
  the doc path — same rule the CLI uses.

## Diagnostics

Unchanged contract: scoped `publishDiagnostics` per
(file → package-dir) so one package's analysis never clears
another's. Versioned per didChange; stale publishes for
superseded versions are dropped.

## Errors

- Unknown method → `-32601`.
- Malformed JSON / missing Content-Length → `-32700`, connection
  stays up.
- Request on unopened/unanalyzed doc → analyze on demand (current
  behavior), then answer.
- Rename rejection → successful response with empty `changes`
  plus the showMessage notification (not a JSON-RPC error — the
  request itself was valid).
