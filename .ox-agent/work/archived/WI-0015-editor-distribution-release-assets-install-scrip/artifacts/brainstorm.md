# WI-0015 brainstorm — editor distribution

Goal: ship editor support as installable, release-tracked artifacts —
no marketplace account, no npm on the user path; everything rides the
existing `v*` release rail.

## Forks resolved

1. **VS Code client: real LSP or grammar-only?**
   Real client. `editors/vscode` currently contributes grammar +
   `oxl.lsp.path` config but no `main` — the setting is dead without a
   client. Add `vscode-languageclient` bundled by esbuild at package
   time. npm/esbuild run in CI only; the vsix is self-contained, so
   users never touch npm.

2. **Where does the vsix come from?**
   Hand-rolled zip is fragile (vsixmanifest schema, content types).
   `npx @vscode/vsce package` in the release job — pinned major, CI-side
   npm only. Local dev path documented in the extension README.

3. **Neovim distribution.**
   Mirror `editors/nvim/` to `oxidean/nvim-oxl` on each release tag
   (subtree-style copy + tag push). Plugin managers (lazy.nvim etc.)
   then track releases like any git plugin. Highlighting comes from the
   server's semanticTokens — no tree-sitter grammar needed. Fallback
   `syntax/oxl.vim` for sessions without the LSP attached.

4. **Mirror push credentials.**
   `GITHUB_TOKEN` cannot push to another repo. Needs a PAT/App secret;
   the job fails soft with a notice when unset so a missing secret
   never blocks a toolchain release.

5. **Open VSX.**
   `npx ovsx publish` from the same job, gated on `OVSX_TOKEN` secret;
   fail-soft when absent. Namespace = package.json `publisher`
   (`oxidean`). This is the only path to auto-update inside VS Code /
   VSCodium / Cursor without the MS marketplace.

6. **Generic highlight assets.**
   Ship `editors/sublime/oxl.sublime-syntax` (bat/syntect + Sublime
   Text consume the same format). Hand-authored to mirror the
   tmLanguage scopes; Helix/Zed tree-sitter deferred (needs a compiled
   parser — separate effort).

7. **install-editor.sh shape.**
   Mirror `install.sh` conventions: POSIX sh, `set -eu`, `die()`,
   `OXL_RELEASE_BASE` override for file:// fixtures, latest-tag
   resolution via the releases/latest redirect (same trick as the
   shim). Subcommands: `vscode`, `nvim`, `bat`, `list`. nvim clones the
   mirror into the native pack dir (works with zero plugin managers);
   bat/sublime install the syntax file into the user config dir.

8. **Version coupling.**
   package.json `version` is rewritten from the release tag inside the
   packaging step (not committed) so vsix/OVSX versions equal the tag.
