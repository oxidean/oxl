# ADR-0014: self-host-only toolchain — checked-in C snapshot stage-0; editor support via LSP depth + one tmLanguage grammar

Status: accepted (WI-0014) — 2026-11-14

## Decision

Milestone U removes the Rust seed driver (`oxl/`) entirely and
makes the self-hosted `cmd/oxl` driver bootstrappable from a
checked-in C snapshot, then grows `oxl lsp` into a daily-driver
language server with editor assets (TextMate grammar, VS Code
extension, Neovim docs) shipped in the same PR.

Forks resolved (brainstorm detail in WI-0014 artifacts):

1. **Stage-0 is a checked-in C snapshot** —
   `bootstrap/stage0/oxl.c` (~1.6 MB) compiles with `cc` +
   `runtime/rt.c` alone; CI/release build it to `oxl-seed` and
   feed `tests/run.sh` as SEEDOXL. The existing fixpoint
   (seed-emit == gen1-emit == gen2-emit) doubles as the
   snapshot-freshness gate; `scripts/stage0.sh` regenerates via
   an installed release toolchain. Rejected: fetching the
   previous release as seed (network dep + pin in every CI run,
   per-OS asset selection, bootstrap deadlock on asset-shape
   change) and a frozen minimal Rust seed (keeps the second
   compiler surface forever).
2. **`oxl/` is deleted in full** — crate, cargo CI steps,
   dependabot cargo ecosystem, rust-toolchain action, doc
   references. `prototype/` (unrelated C experiments) stays.
   Releases continue to ship `target/oxl-self`; only the seed
   leg changes source.
3. **LSP depth lives only in `cmd/oxl/lsp.oxl`** — with the
   Rust driver gone there is no dual-driver parity tax. Wire
   I/O moves onto `std/encoding/json` (probe-gated; fallback a
   scoped `cmd/oxl/lsp/json.oxl` reader). New capabilities:
   completion, signatureHelp, documentSymbol, formatting
   (via a `fmt_text` lib entry factored from `cmd_fmt`),
   semanticTokens, references, rename, documentHighlight,
   didChangeWatchedFiles. Parked: callHierarchy, inlayHint,
   codeAction, range formatting.
4. **Semantic tokens classify by lexer kind + UseRec
   resolution** — checker-accurate legend fixed at initialize;
   the tmLanguage grammar is *not* reused for LSP tokens
   (it would be a second, drifting engine).
5. **Workspace model stays single-root** — `oxl.mod` is the
   project boundary; `rootUri` honored, `workspaceFolders`
   accepted-but-single. Multi-root parked.
6. **Rename v1 rejects captures** — WorkspaceEdit assembled
   from UseRec def-span groups; a rename that would bind the
   new name to a different def returns empty changes + a
   `showMessage` warning, never a silent wrong rewrite.
7. **One grammar, three consumers** —
   `editors/grammars/oxl.tmLanguage.json` feeds the in-repo VS
   Code extension (`editors/vscode/`), Neovim docs
   (`docs/editors.md` lspconfig snippet), and — vendored in a
   *separate* oxidean-app PR — the forge's Shiki blob lane
   (same pattern as tsrx/ripple grammars).

## Consequences

- No reference implementation remains: correctness rests on the
  test suite + spec fixtures. The fixpoint still proves
  self-consistency (gen1 == gen2 == snapshot-emit), which is the
  strongest available signal without a second compiler.
- Adding language features usable by `cmd/oxl`/`bootstrap`
  sources may require snapshot regeneration when the snapshot's
  embedded compiler predates them — the fixpoint fails loudly
  and points at `scripts/stage0.sh`.
- The LSP becomes the only implementation of every capability —
  bugs have one home, fixes have one place to land.
- The forge gets oxl blob highlighting only after the
  oxidean-app follow-up PR lands; until then the grammar ships
  in-repo for VS Code/Neovim/tmLanguage consumers.
