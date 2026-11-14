# Milestone U — shape: self-host-only toolchain + editor support

Two surfaces, one PR: (1) remove the Rust seed and make the
self-hosted driver bootstrappable from a checked-in C snapshot;
(2) grow `oxl lsp` into a daily-driver language server and ship the
editor assets (TextMate grammar, VS Code extension, Neovim docs).

## Why now

- Releases already ship `target/oxl-self` — the self-hosted driver
  is the product; `oxl/` is bootstrap plumbing that costs a cargo
  build on every CI leg and a second implementation to keep aligned
  with `bootstrap/`.
- `oxl lsp` exists (diagnostics/hover/definition) but is the
  thinnest part of the toolchain story — no completion, no
  formatting, no semantic tokens, no editor integration anywhere.
- The web target (W) and GUI layer (G) landed, so highlighting now
  has three real consumers: LSP clients, VS Code/Neovim, and the
  Oxidean forge's Shiki blob view.

## The two halves

### Toolchain half — stage-0 snapshot

ADR-0006 made the Rust seed "bootstrap input only". Milestone U
completes that arc: the seed is replaced by
`bootstrap/stage0/oxl.c`, a checked-in C snapshot of the
self-hosted driver emitted by the last release toolchain.

- CI compiles the snapshot with `cc` + `runtime/rt.c` → `oxl-seed`,
  hands it to `tests/run.sh` as SEEDOXL. The fixpoint
  (seed-emit == gen1-emit == gen2-emit for `cmd/oxl`) is unchanged
  and doubles as the snapshot-freshness gate: a stale snapshot's
  emit diverges and the suite fails with a regen pointer.
- `scripts/stage0.sh` regenerates the snapshot using an installed
  oxl (release toolchain via install.sh / `oxl toolchain`).
- `oxl/` is deleted wholesale: crate, CI cargo steps, dependabot
  cargo ecosystem, rust-toolchain action, doc references.
  `prototype/` stays (unrelated C experiments).

Rejected: fetching the previous release as seed (network dep +
version pin in every CI run, per-OS asset selection, bootstrap
deadlock if asset shape changes) and a frozen minimal Rust seed
(the thing being removed).

### Editor half — LSP depth + assets

`oxl lsp` keeps its stdio JSON-RPC framing and full-text sync;
the wire layer moves onto `std/encoding/json` (probe-gated — a
scoped `cmd/oxl/lsp/json.oxl` reader is the fallback if the stdlib
DOM is too heavy per keystroke).

New capabilities, all backed by the existing checker index
(`check.UseRec` records file/span/sig/def-span per use site;
`Ck.declsv`/`DeclEnt` + fn/struct/enum/global tables carry decls):

- completion — in-scope decls + keywords, prefix-ranked v1
- signatureHelp — `FnSig` at the enclosing call
- documentSymbol — `declsv` spans nested by containment
- formatting — `oxl fmt` output via a `fmt_text` lib entry factored
  out of `cmd_fmt` (range formatting parked)
- semanticTokens — lexer token kinds + UseRec-resolved symbol
  kinds; legend fixed at `initialize`
- references / documentHighlight — UseRecs sharing a def span
- rename — `WorkspaceEdit` of per-file `TextEdit[]`; rejects with
  a `showMessage` warning when the new name would capture a
  different binding (def-span shadow check)
- didChangeWatchedFiles — invalidates the per-dir `Anl` cache so
  on-disk edits re-analyze

Workspace model stays single-root: `oxl.mod` is the project
boundary; `rootUri` is honored, `workspaceFolders` is
accepted-but-single. True multi-root is parked.

### Highlighting — one grammar, three consumers

`editors/grammars/oxl.tmLanguage.json` is authored once in this
repo and feeds:

1. **VS Code** — `editors/vscode/` minimal extension: language
   configuration, the grammar, `oxl lsp` launch config, README.
   No build step, no marketplace publish.
2. **Neovim** — `docs/editors.md` lspconfig snippet; treesitter
   grammar parked behind an upstream trigger.
3. **Oxidean forge** — vendored into oxidean-app's Shiki lane
   (`lib/grammars/` + `highlight.ts` `CUSTOM_LANG_INPUTS` +
   `languages.rs` row + api-client regen). Separate repo → separate
   PR, tracked as a follow-up.

Semantic tokens (checker-accurate, LSP clients) and the
tmLanguage grammar (syntax-level, everywhere else) coexist on
purpose — same split tsrx/ripple already use on the forge.

## Non-goals

oxidean-app vendoring (follow-up PR), marketplace publish,
tree-sitter, callHierarchy, inlayHint, codeAction, range
formatting, multi-root workspaces, rename capture analysis, any
`runtime/rt.c`/`std/`/language-semantics change.
