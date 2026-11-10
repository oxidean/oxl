# Spec — toolchain installer + version manager (issue #60)

## Goal

A first-class install path for the oxl toolchain: one curl command, a
version manager that keeps multiple toolchains installed side by side,
and project-aware version selection. Repo docs and site docs gain real
install instructions.

## Design decisions (forks resolved)

1. **The manager is a shim, not the toolchain** (nvm/gvm model). A
   POSIX `oxl` shim sits on PATH, resolves a version, and execs the
   real binary under `$OXL_HOME/versions/<tag>/`. `oxl toolchain …`
   verbs are intercepted by the shim — the real binaries never see
   them. Keeps version management outside the language surface; no
   driver-parity work for the verbs themselves.
2. **Resolution order** (first hit wins):
   `OXL_TOOLCHAIN` env > `.oxl-version` file (walk up from cwd) >
   `toolchain` directive in the nearest `oxl.mod` (walk up) >
   `$OXL_HOME/default-version`.
   The `oxl` language-floor directive is NOT a dispatch input — the
   toolchain binary already enforces it at check time; using it for
   dispatch conflates language and release version lines.
3. **New `toolchain` directive in `oxl.mod`** — exact-pin analogue of
   Go's `toolchain` line: `toolchain v0.9.0`. Both manifest parsers
   (Rust `oxl/src/main.rs`, self-hosted `cmd/oxl`) accept and carry
   it; `mod tidy` preserves it; drivers take no action on it beyond
   parsing. The shim greps it.
4. **Missing resolved version**: instruct-and-exit (status 127)
   naming `oxl toolchain install <tag>` — no silent network on build.
5. **`oxl version`** added to both drivers: prints the release tag
   read from a `RELEASE` file shipped beside the binary (the release
   workflow writes it into the toolchain tree — both drivers read it
   at runtime via `rt_readfile`), else `dev`, plus the language
   version.
6. **Release integrity**: workflow publishes `<asset>.sha256`
   alongside the tarball; installer verifies when the file exists.
7. **Platforms**: today only `linux-x86_64` ships. The installer maps
   `uname -sm` → asset names, errors clearly on unshipped platforms
   with a build-from-source pointer.

## Layout

```
$OXL_HOME/                    (default ~/.oxl)
  bin/oxl                     # dispatch shim — the PATH entry
  versions/<tag>/             # unpacked oxl-toolchain trees
  default-version             # file: e.g. "v0.9.0"
```

`oxl.mod` may add `toolchain vX.Y.Z`; `.oxl-version` holds a bare tag.

## Commands

- `install.sh` (`scripts/install.sh`, curl-pipeable):
  `install.sh [vX.Y.Z|latest]`, env `OXL_HOME`/`OXL_VERSION`; resolves
  the tag (`/releases/latest` redirect — no API quota; extras-lane
  tags rejected), downloads the platform asset,
  verifies `.sha256` when published, unpacks to `versions/<tag>/`,
  writes/refreshes the shim, seeds `default-version` if absent, prints
  PATH guidance. Idempotent; `--default` forces the default switch.
- Shim verbs: `toolchain install <tag|latest>`, `toolchain list`,
  `toolchain use <tag>` (writes default-version; `--local` writes
  `./.oxl-version`), `toolchain uninstall <tag>` (refuses when the tag
  is the default unless `--force`), `toolchain current` (resolved
  version + source), `toolchain default`.
- `oxl version` (real binary): `oxl <release|dev> (language <X.Y.Z>)`.

## Acceptance criteria

- `install.sh` end-to-end on linux-x86_64 against a real release:
  PATH-less invocation `~/.oxl/bin/oxl version` reports the tag.
- Shim dispatch: env > dotfile > directive > default, each proven by
  a fake-version test fixture (no network) in tests/run.sh.
- `toolchain install/list/use/uninstall/current` exercised offline.
- `toolchain` directive parses in both drivers; manifests carrying it
  check clean on both; `mod tidy` preserves the line.
- `oxl version` identical shape on both drivers.
- Unshipped platform → clear error + source-build pointer.
- README gains the curl one-liner; docs + docs/site gain install pages.
- Suite green; both-drivers parity tests still pass.

## Out of scope

- Windows-native installs (WSL covered by linux-x86_64).
- Auto-install on miss (explicit non-goal; instruct-and-exit).
- Publishing new platform tarballs (matrix stays linux-x86_64).
