# Milestone U — plan

Spec: `shape.md` + `lsp-depth.md` + `items/editor-assets.md`,
ADR-0014, WI-0014 artifacts.

## Stages

### U1 — stage-0 snapshot + Rust removal

- Generate `bootstrap/stage0/oxl.c` from current sources via an
  installed release toolchain; commit it.
- `scripts/stage0.sh` — regen entry point (documented in
  CONTRIBUTING; fixpoint failure message points at it).
- ci.yml: drop `dtolnay/rust-toolchain` + `cargo build`; compile
  `stage0/oxl.c` + `runtime/rt.c` → `oxl-seed`; pass to run.sh.
- release.yml: same swap in the build/test + toolchain-asset legs.
- tests/run.sh: SEEDOXL resolution prefers the compiled snapshot
  (arg or `bootstrap/stage0` build); keep gen1/gen2/fixpoint.
- Delete `oxl/`; dependabot cargo block; ISSUE_TEMPLATE/README/
  CONTRIBUTING/docs references to cargo/rust.
- Gate: full suite green on all 3 OSes, zero cargo references.

### U2 — LSP JSON + core depth

- Probe `std/encoding/json` against the LSP method set (round-trip
  + alloc behavior on per-keystroke paths); adopt or fall back to
  `cmd/oxl/lsp/json.oxl`.
- Port `cmd_lsp`'s wire I/O off `json_str`/`json_num`/`extract_id`/
  `json_escape`; keep Content-Length framing.
- completion, signatureHelp, documentSymbol, documentHighlight,
  references (UseRec def-span grouping), formatting via
  `fmt_text(src)->str` factored from `cmd_fmt`.
- Fixtures per capability under the existing LSP harness.
- Gate: suite green + per-capability fixture asserts.

### U3 — semantic layer

- semanticTokens: lexer token-span entry (additive in
  `bootstrap/lexlib`/`parser` if needed), legend negotiated at
  initialize, UseRec kind upgrades.
- rename: WorkspaceEdit assembly + shadow/capture rejection +
  showMessage warning path.
- didChangeWatchedFiles: file-event → `Anl` invalidation →
  republish diagnostics for affected package dirs.
- workspaceFolders accepted-but-single; rootUri → analysis root.
- Gate: suite green + token/rename/watch fixtures.

### U4 — editor assets

- `editors/grammars/oxl.tmLanguage.json` — full grammar
  (comments, keywords, types, strings, numbers, fns, fields,
  operators, builtins); JSON-validate.
- `editors/vscode/` — package.json, language-configuration.json,
  syntaxes/ (grammar copy or reference), launch config for
  `oxl lsp`, README install-from-source.
- `docs/editors.md` — VS Code + Neovim (lspconfig) setup.
- README/CONTRIBUTING snapshot-bootstrap notes.
- Gate: grammar parses; scripted `initialize` handshake proves
  capabilities advertised; docs build clean.

### U5 — closeout

- docs/self-hosting.md + docs/install.md refresh for the
  snapshot toolchain.
- CHANGELOG-facing summary for the release notes lane.
- WI-0014 archive prep; follow-up issue filed for the
  oxidean-app grammar vendoring.

## Follow-up (not this PR)

oxidean-app: `languages.rs` `oxl` row → `make rpc-gen` →
`lib/grammars/oxl.tmLanguage.json` vendor → `highlight.ts`
`CUSTOM_LANG_INPUTS` registration.

## Parking

callHierarchy, inlayHint, codeAction, range formatting,
multi-root workspaces, rename capture analysis, tree-sitter
grammar, VS Code marketplace publish.
