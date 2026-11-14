# WI-0013 discovery notes

Scope decision (user, 2026-11-14): one milestone, one PR.

- Drop the Rust driver in favor of the self-hosted `cmd/oxl` driver.
- Full editor story: LSP depth + VS Code + Neovim.
- Web/application highlighting follows the oxidean-app tsrx lane: vendored TextMate grammar + Shiki-compatible artifact.

Key facts verified in tree:

- `cmd/oxl` is already the product driver; `oxl/` Rust crate is the bootstrap seed (ADR-0006).
- `tests/run.sh` currently requires a seed binary, builds gen1/gen2 product drivers, and asserts C fixpoint.
- `cmd/oxl/lsp.oxl` implements stdio JSON-RPC with diagnostics, hover, definition only; JSON handling is naive string extraction.
- `bootstrap/check/check.oxl` already records `UseRec` index entries (`file`, span, `sig`, def span) used by hover/definition.
- `std/encoding/json` has a real `Json` tree + parser/serializer; LSP does not use it yet.
- oxidean-app highlighting uses Shiki + vendored `*.tmLanguage.json` grammars and branded `oxidean-light`/`oxidean-dark` themes (`apps/web/src/lib/highlight.ts`).

Open design forks to resolve in brainstorm/spec:

1. Bootstrap path after removing the Rust seed (previous release vs checked-in C snapshot vs minimal seed).
2. LSP capability set for v1 (completion/signature/symbols/formatting/semantic tokens/references/rename).
3. JSON-RPC payload strategy (port to `std/encoding/json` vs targeted extractor upgrade).
4. Editor asset layout (`editors/vscode`, `editors/neovim`, `syntax/oxl.tmLanguage.json`).
5. Cross-repo highlighting handoff: oxl repo ships grammar; oxidean-app consumes it (separate repo/PR if wiring is required).
