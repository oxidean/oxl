#!/bin/sh
# install.sh — install the oxl toolchain + the version-manager shim.
#
#   curl -fsSL https://raw.githubusercontent.com/oxidean/oxl/main/scripts/install.sh | sh
#   curl -fsSL ... | sh -s -- v0.9.0          # pin a release
#   ./scripts/install.sh --shim-only          # just write the shim (dev/testing)
#
# Layout (OXL_HOME, default ~/.oxl):
#   bin/oxl            dispatch shim — put this dir on PATH
#   versions/<tag>/    unpacked oxl-toolchain trees
#   default-version    the fallback tag
#
# env: OXL_HOME, OXL_VERSION (arg equivalent), OXL_RELEASE_BASE
#      (release host override — tests point it at file:// fixtures)
set -eu

OXL_HOME="${OXL_HOME:-$HOME/.oxl}"
BASE="${OXL_RELEASE_BASE:-https://github.com/oxidean/oxl/releases}"
REPO_RAW="https://raw.githubusercontent.com/oxidean/oxl/main"

want="latest"
shim_only=0
set_default=0
for a in "$@"; do
    case "$a" in
        --shim-only) shim_only=1 ;;
        --default)   set_default=1 ;;
        -h|--help)
            cat <<'EOF'
install.sh — install the oxl toolchain + version-manager shim

  install.sh [vX.Y.Z|latest]   download + unpack a release, write the
                               shim, seed default-version when unset
  install.sh --shim-only       write bin/oxl only (no download)
  install.sh --default         also force default-version to the tag

env: OXL_HOME (def ~/.oxl), OXL_VERSION (same as the arg),
     OXL_RELEASE_BASE (release host override)
EOF
            exit 0 ;;
        v[0-9]*|[0-9]*) want="$a" ;;
        *) echo "install.sh: unknown argument \`$a\`" >&2; exit 2 ;;
    esac
done
[ "${OXL_VERSION:-}" ] && want="$OXL_VERSION" || true
[ "$want" != latest ] && case "$want" in v*) : ;; *) want="v$want" ;; esac

# ---------- the shim (single source — also serves `oxl toolchain`) ----------
write_shim() {
    mkdir -p "$OXL_HOME/bin" "$OXL_HOME/versions"
    cat > "$OXL_HOME/bin/oxl" <<'SHIM_EOF'
#!/bin/sh
# oxl — toolchain version manager + dispatcher (gvm-style).
# Resolves a release tag, execs versions/<tag>/oxl-toolchain/oxl.
# `oxl toolchain <verb>` is handled here and never reaches the
# dispatched binary.
#
# Resolution (first hit wins):
#   1. $OXL_TOOLCHAIN
#   2. .oxl-version file, walking up from the cwd
#   3. `toolchain vX.Y.Z` in the nearest oxl.mod, walking up
#   4. $OXL_HOME/default-version
set -eu

OXL_HOME="${OXL_HOME:-$HOME/.oxl}"
VERS="$OXL_HOME/versions"
BASE="${OXL_RELEASE_BASE:-https://github.com/oxidean/oxl/releases}"

die() {
    code=1
    case "$1" in ''|*[!0-9]*) ;; *) code="$1"; shift ;; esac
    echo "oxl: $*" >&2; exit "$code"
}

norm() { case "$1" in v*) echo "$1" ;; *) echo "v$1" ;; esac; }

# platform asset suffix, e.g. linux-x86_64
asset_os_arch() {
    os=$(uname -s | tr '[:upper:]' '[:lower:]')
    arch=$(uname -m)
    case "$arch" in
        x86_64|amd64) arch=x86_64 ;;
        arm64|aarch64) arch=arm64 ;;
    esac
    echo "$os-$arch"
}

have() { command -v "$1" >/dev/null 2>&1; }

fetch() { # url out  — download url to file out
    have curl || die "curl is required for toolchain install"
    curl -fsSL "$1" -o "$2"
}

latest_tag() {
    # releases/latest 302s to releases/tag/<tag> — the redirect target
    # carries the tag; no API quota involved
    have curl || die "curl is required for toolchain install"
    url=$(curl -fsIL -o /dev/null -w '%{url_effective}' "$BASE/latest") \
        || die "cannot resolve latest release at $BASE/latest"
    echo "${url##*/}"
}

resolve() { # echoes "tag<TAB>source" or nothing
    if [ "${OXL_TOOLCHAIN:-}" ]; then
        echo "$(norm "$OXL_TOOLCHAIN")	env OXL_TOOLCHAIN"; return
    fi
    d=$(pwd -P)
    while :; do
        if [ -f "$d/.oxl-version" ]; then
            t=$(head -n1 "$d/.oxl-version" | tr -d '[:space:]')
            [ -n "$t" ] && { echo "$(norm "$t")	$d/.oxl-version"; return; }
        fi
        [ "$d" = / ] && break
        d=$(dirname "$d")
    done
    d=$(pwd -P)
    while :; do
        if [ -f "$d/oxl.mod" ]; then
            t=$(sed -n 's/^[[:space:]]*toolchain[[:space:]][[:space:]]*\(v[^[:space:]]*\).*/\1/p' \
                "$d/oxl.mod" | head -n1)
            [ -n "$t" ] && { echo "$t	$d/oxl.mod toolchain directive"; return; }
            break   # nearest oxl.mod wins even without a pin — do not climb past it
        fi
        [ "$d" = / ] && break
        d=$(dirname "$d")
    done
    if [ -f "$OXL_HOME/default-version" ]; then
        t=$(head -n1 "$OXL_HOME/default-version" | tr -d '[:space:]')
        [ -n "$t" ] && { echo "$(norm "$t")	default-version"; return; }
    fi
    return 0
}

exe_for() { echo "$VERS/$1/oxl-toolchain/oxl"; }

tc_install() { # tag|latest
    tag="$1"; [ "$tag" = latest ] && tag=$(latest_tag); tag=$(norm "$tag")
    [ -d "$VERS/$tag" ] && { echo "oxl: $tag already installed"; return 0; }
    suf=$(asset_os_arch)
    asset="oxl-toolchain-$suf.tar.gz"
    tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
    echo "oxl: downloading $tag ($asset)"
    fetch "$BASE/download/$tag/$asset" "$tmp/$asset" \
        || die "no toolchain asset for $suf at $tag — build from source instead:
    https://github.com/oxidean/oxl#building-from-source"
    if fetch "$BASE/download/$tag/$asset.sha256" "$tmp/$asset.sha256" 2>/dev/null; then
        if have sha256sum; then (cd "$tmp" && sha256sum -c "$asset.sha256");
        elif have shasum; then (cd "$tmp" && shasum -a 256 -c "$asset.sha256");
        else echo "oxl: warning: no sha256 tool — skipping integrity check" >&2; fi \
            || die "sha256 mismatch on $asset — download corrupted or tampered"
    else
        echo "oxl: warning: $tag ships no .sha256 — skipping integrity check" >&2
    fi
    mkdir -p "$VERS/$tag"
    tar xzf "$tmp/$asset" -C "$VERS/$tag" \
        || die "corrupt tarball for $tag"
    rm -rf "$tmp"; trap - EXIT
    echo "oxl: installed $tag -> $VERS/$tag"
    [ -f "$OXL_HOME/default-version" ] || echo "$tag" > "$OXL_HOME/default-version"
}

tc_uninstall() {
    tag=""; force=0
    for a in "$@"; do
        case "$a" in --force) force=1 ;; *) tag="$a" ;; esac
    done
    [ -n "$tag" ] || { echo "usage: oxl toolchain uninstall <tag> [--force]" >&2; exit 2; }
    tag=$(norm "$tag")
    [ -d "$VERS/$tag" ] || die "$tag is not installed"
    if [ -f "$OXL_HOME/default-version" ] \
        && [ "$(cat "$OXL_HOME/default-version")" = "$tag" ] && [ "$force" = 0 ]; then
        die "$tag is the default — \`oxl toolchain uninstall $tag --force\` to remove anyway"
    fi
    rm -rf "${VERS:?}/$tag"
    echo "oxl: removed $tag"
}

tc_use() {
    local_tag=""; tag=""
    for a in "$@"; do
        case "$a" in --local) local_tag=1 ;; *) tag="$a" ;; esac
    done
    tag=$(norm "$tag")
    [ -d "$VERS/$tag" ] || die "$tag is not installed — \`oxl toolchain install $tag\` first"
    if [ "$local_tag" ]; then
        echo "$tag" > .oxl-version
        echo "oxl: pinned $tag in ./.oxl-version"
    else
        echo "$tag" > "$OXL_HOME/default-version"
        echo "oxl: default toolchain -> $tag"
    fi
}

tc_list() {
    def=""; [ -f "$OXL_HOME/default-version" ] && def=$(cat "$OXL_HOME/default-version")
    found=0
    for d in "$VERS"/*/; do
        [ -d "$d" ] || continue
        t=$(basename "$d"); found=1
        mark=""; [ "$t" = "$def" ] && mark=" (default)"
        echo "$t$mark"
    done
    [ "$found" = 0 ] && echo "(none installed)"
}

if [ "${1:-}" = toolchain ]; then
    shift
    case "${1:-}" in
        install)   tc_install "${2:?usage: oxl toolchain install <tag|latest>}" ;;
        uninstall) shift; tc_uninstall "$@" ;;
        use)       shift; tc_use "$@" ;;
        list|ls)   tc_list ;;
        default)   [ -f "$OXL_HOME/default-version" ] && cat "$OXL_HOME/default-version" || die "no default — \`oxl toolchain use <tag>\`" ;;
        current)
            r=$(resolve); [ -n "$r" ] || die "no version resolved — set one with \`oxl toolchain use <tag>\`"
            tag=${r%%	*}; src=${r#*	}
            if [ -x "$(exe_for "$tag")" ]; then st=installed; else st="NOT INSTALLED — \`oxl toolchain install $tag\`"; fi
            echo "$tag	($src, $st)" ;;
        *) echo "usage: oxl toolchain <install|uninstall|use|list|default|current>" >&2; exit 2 ;;
    esac
    exit 0
fi

r=$(resolve)
if [ -z "$r" ]; then
    die "no toolchain selected — \`oxl toolchain use <tag>\` after installing one,
or run the installer:  curl -fsSL https://raw.githubusercontent.com/oxidean/oxl/main/scripts/install.sh | sh"
fi
tag=${r%%	*}; src=${r#*	}
exe=$(exe_for "$tag")
[ -x "$exe" ] || die 127 "toolchain $tag (from $src) is not installed —
install it with:  oxl toolchain install $tag"
exec "$exe" "$@"
SHIM_EOF
    chmod +x "$OXL_HOME/bin/oxl"
    echo "wrote $OXL_HOME/bin/oxl"
}

write_shim

[ "$shim_only" = 1 ] && { echo "shim-only — done. Add to PATH: export PATH=\"$OXL_HOME/bin:\$PATH\""; exit 0; }

if [ "$want" = latest ]; then
    url=$(curl -fsIL -o /dev/null -w '%{url_effective}' "$BASE/latest") \
        || { echo "install.sh: cannot resolve latest release at $BASE/latest" >&2; exit 1; }
    want="${url##*/}"
fi
"$OXL_HOME/bin/oxl" toolchain install "$want"
tag="$want"
if [ ! -f "$OXL_HOME/default-version" ] || [ "$set_default" = 1 ]; then
    echo "$tag" > "$OXL_HOME/default-version"
fi

cat <<EOF

Installed oxl $tag.

Add the shim to your PATH (once, in your shell profile):

    export PATH="$OXL_HOME/bin:\$PATH"

Then:
    oxl version                 # the dispatched toolchain
    oxl toolchain list          # installed versions
    oxl toolchain install vX.Y.Z
    oxl toolchain use vX.Y.Z    # set the default
    oxl toolchain use --local vX.Y.Z   # pin a directory via .oxl-version
EOF
