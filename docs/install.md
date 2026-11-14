# Installing oxl

One command installs the toolchain plus the version manager:

```sh
curl -fsSL https://raw.githubusercontent.com/oxidean/oxl/main/scripts/install.sh | sh
```

To pick a specific release instead of the latest:

```sh
curl -fsSL https://raw.githubusercontent.com/oxidean/oxl/main/scripts/install.sh | sh -s -- v0.9.0
```

Then put the shim on `PATH` (the installer prints this too):

```sh
export PATH="$HOME/.oxl/bin:$PATH"
```

`oxl version` confirms the install: `oxl v0.9.0 (language 0.3)`.

## What goes where

```
~/.oxl/                    (override with $OXL_HOME)
  bin/oxl                  dispatch shim — the PATH entry
  versions/v0.9.0/         one directory per installed release
  default-version          the fallback tag
```

The installer needs `curl` and `tar`. Checksum verification uses
`sha256sum`, `shasum -a 256`, or `openssl dgst -sha256`, whichever is on
`PATH`. It verifies the release's `.sha256` when one is published (new releases ship the
sidecar; releases cut before it warn and skip). With no sha256 tool on
`PATH` it warns and skips verification — install coreutils or openssl
for a verified install. It never runs the toolchain — only unpacks it.

Prebuilt tarballs ship for **Linux x86_64**. On any other platform the
installer stops with a pointer to [building from
source](#building-from-source) — macOS (aarch64) and Windows (x86_64,
via MinGW gcc or LLVM clang) are supported that way.

## The version manager

The `oxl` on `PATH` is a shim. It resolves which installed toolchain to
dispatch to — first hit wins:

1. `$OXL_TOOLCHAIN` — an explicit override for one command
2. `.oxl-version` — a dotfile pin, found by walking up from the cwd
3. `toolchain vX.Y.Z` in the nearest `oxl.mod` — the project's pin
4. `~/.oxl/default-version` — the fallback

The `oxl toolchain` verbs live in the shim — a source-built `oxl`
binary answers `unknown command`; only release installs under `~/.oxl`
are managed.

Resolution is per-command, so two projects can pin different toolchains
and both just work:

```sh
oxl toolchain install v0.9.0    # download + verify + unpack a release
oxl toolchain list              # installed versions ((default) marked)
oxl toolchain use v0.9.0        # set the default
oxl toolchain default            # print the default tag
oxl toolchain use --local v0.9.0   # pin this directory (.oxl-version)
oxl toolchain current           # resolved tag + where it came from
oxl toolchain uninstall v0.8.0  # remove (refuses the default; --force)
```

A resolved-but-missing toolchain exits 127 naming the fix:

```
oxl: toolchain v0.10.0 (from /path/to/oxl.mod toolchain directive) is not
installed — install it with:  oxl toolchain install v0.10.0
```

The `oxl` directive in `oxl.mod` stays a **language** floor enforced by
the toolchain itself; it does not select a toolchain. `toolchain` is
the dispatch pin.

## Keeping the toolchain fresh

`oxl toolchain install latest` fetches the newest **toolchain**
release — an `extra/v*` extras release never shadows it. `oxl
toolchain use <tag>` moves the default. Nothing is auto-installed —
a missing version always names the command that fixes it.

## Uninstalling

```sh
rm -rf ~/.oxl
```

and drop the `~/.oxl/bin` line from your shell profile.

## Building from source

For developers working on oxl itself (or on a platform without a
prebuilt tarball):

```sh
git clone https://github.com/oxidean/oxl && cd oxl
bash scripts/stage0.sh   # stage-0 snapshot -> target/oxl
export PATH="$PWD/target:$PATH"
```

The stage-0 binary builds the product driver (`cmd/oxl`) the same way
the release does — `tests/run.sh` runs that gen1/gen2 fixpoint plus
the full suite:

```sh
bash tests/run.sh ./target/oxl
```

A source-built binary reports `oxl dev (language 0.3)` — no `RELEASE`
file sits beside it. The version manager only manages release installs;
a dev build lives outside `~/.oxl/versions/` and can shadow the shim
by sitting earlier on `PATH`.
