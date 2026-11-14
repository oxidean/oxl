# WI-0014 plan — milestone U

Spec: `docs/specs/2026-11-14-selfhost-editor/` (shape + plan +
lsp-depth + items/editor-assets), ADR-0014.

Stages per `docs/specs/2026-11-14-selfhost-editor/plan.md`:

- U1 stage-0 snapshot — `bootstrap/stage0/oxl.c` + `scripts/stage0.sh`
  regen path; ci.yml/release.yml/run.sh swap cargo→snapshot-seed;
  delete `oxl/`; dependabot/docs/templates de-Rusted; fixpoint green
- U2 LSP JSON + core depth — `std/encoding/json` probe (fallback
  `cmd/oxl/lsp/json.oxl`); completion, signatureHelp,
  documentSymbol, formatting (`fmt_text` lib entry), documentHighlight,
  references; fixtures per capability
- U3 semantic layer — semanticTokens (lexer kinds + UseRec legend),
  rename (WorkspaceEdit + shadow rejection), didChangeWatchedFiles
  invalidation, workspaceFolders accepted-but-single
- U4 editor assets — `editors/grammars/oxl.tmLanguage.json`,
  `editors/vscode/` extension skeleton, `docs/editors.md` (VS Code +
  Neovim), README/CONTRIBUTING sweep
- U5 closeout — docs/self-hosting.md + docs/install.md refresh,
  CHANGELOG-facing notes, WI archive prep

Follow-up (not this PR): oxidean-app `oxl` language row +
`lib/grammars/oxl.tmLanguage.json` vendor + `highlight.ts`
registration — separate repo, separate PR.

Parking: callHierarchy, inlayHint, codeAction, range formatting,
multi-root workspaces, rename capture analysis, tree-sitter
grammar, VS Code marketplace publish.
