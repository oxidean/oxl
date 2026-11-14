# Spec — milestone U: self-host-only toolchain + editor support

Status: draft for review (U0)

## Problem

Two gaps in the language story:

1. **The Rust seed is still load-bearing.** `oxl/` (~25k LOC of
   Rust) exists only to emit gen-1 C for the self-host fixpoint —
   releases already ship `target/oxl-self`, the self-hosted driver.
   Every CI leg pays a `cargo build`; the repo carries a second
   compiler implementation that must be kept semantically aligned
   with `bootstrap/` forever.
2. **Editor support is a stub.** `oxl lsp` advertises three
   capabilities (diagnostics, hover, definition) over hand-rolled
   JSON extraction; no completion, no formatting, no semantic
tokens, no editor assets ship anywhere. Highlighting exists only
as an LSP hover/def trickle — nothing for VS Code, Neovim, or the
Oxidean forge's blob view.

## Direction (WI-0014 brainstorm — all forks resolved)

- **Checked-in C snapshot as stage-0** (`bootstrap/stage0/oxl.c`,
  ~1.6 MB, verified to compile with `cc` + `runtime/rt.c` alone).
  CI/release compile it to `oxl-seed` and hand it to run.sh as
  SEEDOXL; the existing fixpoint (seed-emit == gen1-emit ==
  gen2-emit) doubles as the snapshot-freshness gate. Regeneration
  is `scripts/stage0.sh` against an installed release toolchain —
  documented in CONTRIBUTING; a stale snapshot fails the fixpoint
  with a pointer to the script.
- **`oxl/` deleted in full** — Cargo.toml, src/, dependabot cargo
  ecosystem, rust-toolchain steps, and every doc/script reference.
  `prototype/` (unrelated C experiments) stays. One atomic removal:
  no half-state with two bootstrap paths.
- **LSP depth in `cmd/oxl/lsp.oxl` only** — the self-hosted driver
  is now the *only* driver, so the old dual-driver parity tax is
  gone. Wire I/O moves onto `std/encoding/json` (probe-gated at
  U2: if its DOM is too heavy for per-keystroke paths, a scoped
  `lsp/json.oxl` reader inside `cmd/oxl/` is the fallback — decided
  by measurement, not up front).
- **Capability set**: completion, signatureHelp, documentSymbol,
  formatting (via a `fmt_text` lib entry factored out of fmt.oxl's
  `cmd_fmt`), semanticTokens, references, rename, documentHighlight,
  didChangeWatchedFiles. Parked: callHierarchy, inlayHint,
  codeAction, range formatting, true multi-root workspaces
  (`oxl.mod` is the workspace boundary; `rootUri` honored,
  `workspaceFolders` accepted-but-single).
- **Semantic tokens = lexer kinds + UseRec resolution** — a
  checker-accurate legend, not a grammar re-skin.
- **Rename v1** rejects when the new name would capture a different
  binding (def-span shadow check); full capture analysis parked.
- **Highlighting = one grammar, three consumers**:
  `editors/grammars/oxl.tmLanguage.json` authored in-repo feeds the
  VS Code extension (`editors/vscode/`, minimal: language config +
  grammar + `oxl lsp` launch config + README) and — vendored —
  oxidean-app's Shiki blob lane (`lib/grammars/` +
  `highlight.ts` `CUSTOM_LANG_INPUTS` + a languages.rs row +
  api-client regen). The oxidean-app change is a **separate repo's
  PR** — tracked as a follow-up item, not part of this one.
- **Neovim** gets `docs/editors.md` with the lspconfig snippet;
  treesitter grammar parked behind an upstream-trigger.

## Contracts

- **Bootstrap**: `tests/run.sh` keeps its shape — SEEDOXL becomes
  the compiled snapshot, gen1/gen2/fixpoint unchanged. Release
  ships `target/oxl-self` exactly as today; only the seed leg
  changes source.
- **LSP protocol**: `initialize` advertises the full capability
  block; `textDocumentSync` stays full-text (kind 1). Every new
  request/notification answers per LSP 3.17; unknown methods get
  `-32601`; parse failures get `-32700`. Positions remain
  UTF-16-column, 0-based.
- **Semantic tokens legend** is fixed at `initialize` and never
  reordered (clients cache by index).
- **Formatting** returns the whole-document `oxl fmt` output for
  `textDocument/formatting`; `rangeFormatting` is not advertised.
- **Rename** returns `WorkspaceEdit` with per-file `TextEdit[]`;
  a rename that would shadow/capture a different binding returns
  an empty edit set plus a `window/showMessage` warning, never a
  silent wrong rewrite.
- **No new runtime/ABI surface** — all work is driver-side
  (`cmd/oxl/`), checker index reads (`check.UseRec`, decl tables),
  and repo assets. `bootstrap/` compiler internals change only if
  the semantic-token path needs a lexer token-span entry — that
  addition is additive and fixpoint-covered.
- **Editor assets are data, not code**: the tmLanguage grammar is
  JSON, the VS Code extension is manifest+config, Neovim is docs.
  Nothing here compiles into the toolchain.

## Acceptance criteria

- `bash tests/run.sh <oxl>` green end-to-end with **no cargo
  anywhere** — snapshot-seed → gen1 → gen2 → fixpoint → full suite.
- `cargo` references gone from ci.yml, release.yml, dependabot,
  scripts, docs; `oxl/` deleted.
- `oxl lsp` answers completion, signatureHelp, documentSymbol,
  formatting, semanticTokens, references, rename,
  documentHighlight, and didChangeWatchedFiles correctly against
  the existing LSP test fixtures plus new ones per capability
  (tests/lsp/ fixtures extended; suite asserts via the same
  Content-Length JSON-RPC harness).
- VS Code extension installs from source (`code --install-extension`
  or folder open) and gets diagnostics+completion+semantic tokens
  against `oxl lsp` — verified by a scripted LSP handshake, not by
  hand.
- `oxl.tmLanguage.json` validates (plutil/JSON parse + scope sanity)
  and is documented for vendoring into oxidean-app.
- docs/editors.md covers VS Code + Neovim setup; README/CONTRIBUTING
  reflect the snapshot bootstrap and the Rust removal.
- Full suite green on all three CI OSes.

## Non-goals

- oxidean-app grammar vendoring + language-table row (separate
  repo → separate PR; tracked as follow-up).
- Marketplace/publish of the VS Code extension.
- Tree-sitter grammar, callHierarchy, inlayHint, codeAction, range
  formatting, multi-root workspaces, rename capture analysis.
- Any change to `runtime/rt.c`, `std/` semantics, or the language
  itself.
