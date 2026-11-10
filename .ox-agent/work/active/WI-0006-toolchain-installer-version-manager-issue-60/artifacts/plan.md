# Plan — toolchain installer + version manager (WI-0006)

Single-PR delivery, staged commits. Each stage lands suite-green.

## S1 — `toolchain` directive + `oxl version` (both drivers)

- `oxl/src/main.rs` `parse_manifest`: accept `toolchain vX.Y.Z`
  (semver-checked, `v`-prefix optional, single line, no block);
  extend the return tuple with the pin. Callers: `mod_ctx`,
  `mk_ctx`, publish path — carry, no action.
- `bootstrap/check/check.oxl` `parse_manifest_to`: `ManRes` gains
  `toolchain: str`; same directive arm; `parse_manifest` wrapper
  copies to new `Ck.mod_toolchain`. `cmd/oxl/getmod.oxl` reads it
  where needed (dispatch metadata only — print in `mod list`? no:
  parse-only, per spec).
- `mod tidy` needs zero work — `rewrite_requires`/`mod_rewrite` are
  surgical; non-require lines survive byte-for-byte. Add a fixture
  manifest carrying `toolchain` to prove it.
- `oxl version` subcommand, both drivers:
  `oxl <OXL_RELEASE-stamped tag|"dev"> (language <X.Y.Z>)`.
  Rust: `option_env!("OXL_RELEASE")`. Self-hosted: always `dev`.
  Usage text + unknown-command paths updated.

## S2 — release workflow

- `OXL_RELEASE: ${{ needs.version.outputs.tag }}` on the toolchain
  build step → stamped binary.
- `sha256sum oxl-toolchain-linux-x86_64.tar.gz > …sha256`; attach the
  sidecar in the release step.

## S3 — shim + installer (`scripts/install.sh`)

- `install.sh [vX.Y.Z|latest]` env `OXL_HOME` (def `~/.oxl`),
  `OXL_VERSION`; `--shim-only` writes the shim without downloading;
  `--default` re-seeds default-version.
- Shim (embedded heredoc, sole source): POSIX sh, resolves per spec,
  intercepts `oxl toolchain …`, execs the real binary otherwise.
- Verbs: install/list/use[--local]/uninstall[--force]/current/default.
- Integrity: fetch `<asset>.sha256` when present; verify else warn.
- Platform map `uname -sm` → asset; unshipped → error + source pointer.

## S4 — tests

- `tests/toolchain/shim_test.sh`: fake `versions/` fixture, assert
  resolution order (env > dotfile > directive > default), missing-
  version exit 127 + hint, all verbs offline. Wired into run.sh.
- `tests/mod/toolchain_directive/` fixture: manifest with `toolchain`
  checks clean on both drivers; `mod tidy` preserves the line.

## S5 — docs + un-park sweep

- README: curl one-liner + `~/.oxl` layout + `oxl toolchain` summary.
- `docs/install.md`: full install/upgrade/pin/build-from-source doc.
- `docs/site`: install page per site manifest conventions.
- `docs/specs/2026-11-07-phase-2-plan/parked.md`: record the fresh
  D4 measurement (23 generic fns, ~0 shared-shape instantiations —
  stays parked); web target un-parked (G trigger fired, DOM-map
  proven) → moves to roadmap as milestone W.
- `docs/product/roadmap.md`: milestone W entry.
- WI-0007 opened for milestone W (intake — future item).
