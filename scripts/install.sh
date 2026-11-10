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
        --) ;;
        latest|v[0-9]*|[0-9]*) want="$a" ;;
        *) echo "install.sh: unknown argument \`$a\`" >&2; exit 2 ;;
    esac
done
[ "${OXL_VERSION:-}" ] && want="$OXL_VERSION" || true
[ "$want" != latest ] && case "$want" in v*) : ;; *) want="v$want" ;; esac

# ---------- the shim (single source — also serves `oxl toolchain`) ----------
write_shim() {
    mkdir -p "$OXL_HOME/bin" "$OXL_HOME/versions"
    cat > "$OXL_HOME/bin/.oxl.tmp.$$" <<'SHIM_EOF'
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

norm() { case "$1" in v*) printf '%s\n' "$1" ;; *) printf 'v%s\n' "${1#v}" ;; esac; }

# strict tag validation — a tag lands in $VERS/$tag paths (install dir,
# rm -rf on uninstall), so reject anything that is not vX.Y.Z(+suffix):
# blocks `..`/separator traversal and junk directives alike
vtag() { # raw -> normalized tag on stdout; nonzero exit if invalid
    t=$(norm "$1")
    # single line only — grep -q matches ANY line, so a multiline tag
    # would pass on its first line and traverse $VERS paths downstream
    [ "$(printf '%s' "$t" | tr -d '[:space:]')" = "$t" ] || return 1
    # semver.rs parity: numeric fields reject leading zeros, idents are
    # alnum+'-' dot-separated.
    printf '%s\n' "$t" | grep -qE '^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?(\+[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$' \
        || return 1
    # numeric prerelease idents reject leading zeros (v1.2.3-01) on both
    # drivers — the ERE above can't express it, so a second pass covers it
    case "$t" in
        *-*) pre=${t#*-}; pre=${pre%%+*}
             printf '%s\n' "$pre" | grep -qE '(^|\.)0[0-9]+(\.|$)' \
                 && return 1 ;;
    esac
    printf '%s\n' "$t"
}

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
    # carries the tag; no API quota involved. Take the full tag path,
    # not the basename: the extras lane (extra/vX.Y.Z) can hold
    # GitHub's "latest" and basename extraction would strip `extra/`
    # and resolve an unrelated toolchain tag.
    have curl || die "curl is required for toolchain install"
    url=$(curl -fsIL -o /dev/null -w '%{url_effective}' "$BASE/latest") \
        || die "cannot resolve latest release at $BASE/latest"
    case "$url" in
        */releases/tag/*) lt="${url##*/releases/tag/}" ;;
        *) lt="${url##*/}" ;;
    esac
    vtag "$lt" 2>/dev/null \
        || die "latest release is not a toolchain tag ($lt) — pass a tag explicitly"
}

resolve() { # echoes "tag<TAB>source" or nothing
    if [ "${OXL_TOOLCHAIN:-}" ]; then
        v=$(vtag "$OXL_TOOLCHAIN") || die "invalid OXL_TOOLCHAIN: $OXL_TOOLCHAIN"
        echo "$v	env OXL_TOOLCHAIN"; return
    fi
    d=$(pwd -P)
    while :; do
        if [ -f "$d/.oxl-version" ]; then
            t=$(head -n1 "$d/.oxl-version" | tr -d '\r\n' | sed 's/^[ \t]*//;s/[ \t]*$//')
            [ -n "$t" ] && { v=$(vtag "$t") || die "invalid version in $d/.oxl-version: $t"
                echo "$v	$d/.oxl-version"; return; }
        fi
        [ "$d" = / ] && break
        d=$(dirname "$d")
    done
    d=$(pwd -P)
    while :; do
        if [ -f "$d/oxl.mod" ]; then
            # manifest-parser parity: `//` comments (line start or
            # after whitespace) are stripped — `#` is not a comment.
            # The directive must be exactly `toolchain <tag>` and
            # appear at most once — a duplicate, extra-token, or bare
            # form is an error, not a silent skip
            pa=$(awk '
                { sub(/(^|[[:space:]])\/\/.*/, "") }
                /^[ \t]*(require|replace)[ \t]*\(/ { depth++ }
                /^[ \t]*\)/ { if (depth > 0) depth-- }
                depth == 0 && /^[ \t]*toolchain([ \t]|$)/ {
                    n++
                    r = $0
                    sub(/^[ \t]*toolchain[ \t]*/, "", r)
                    gsub(/^[ \t\r]+|[ \t\r]+$/, "", r)
                    if (n == 1) first = r
                }
                END { print n+0; if (n == 1) print first }' "$d/oxl.mod") \
                || die "cannot read $d/oxl.mod"
            case "$(printf '%s\n' "$pa" | sed -n '1p')" in
                0) ;;
                1) t=$(printf '%s\n' "$pa" | sed -n '2p')
                   [ -n "$t" ] || die "toolchain directive in $d/oxl.mod requires a tag"
                   case $t in *[[:space:]]*)
                       die "invalid toolchain directive in $d/oxl.mod: $t" ;; esac
                   v=$(vtag "$t") \
                       || die "invalid toolchain directive in $d/oxl.mod: $t"
                   echo "$v	$d/oxl.mod toolchain directive"; return ;;
                *) die "duplicate toolchain directive in $d/oxl.mod" ;;
            esac
            break   # nearest oxl.mod wins even without a pin — do not climb past it
        fi
        [ "$d" = / ] && break
        d=$(dirname "$d")
    done
    if [ -f "$OXL_HOME/default-version" ]; then
        t=$(head -n1 "$OXL_HOME/default-version" | tr -d '\r\n' | sed 's/^[ \t]*//;s/[ \t]*$//')
        [ -n "$t" ] && { v=$(vtag "$t") || die "invalid version in default-version: $t"
            echo "$v	default-version"; return; }
    fi
    return 0
}

exe_for() { echo "$VERS/$1/oxl-toolchain/oxl"; }

tc_install() { # tag|latest
    tag="$1"; [ "$tag" = latest ] && tag=$(latest_tag)
    tag=$(vtag "$tag") || die "invalid toolchain tag: $1"
    [ -d "$VERS/$tag" ] && { echo "oxl: $tag already installed"; return 0; }
    suf=$(asset_os_arch)
    asset="oxl-toolchain-$suf.tar.gz"
    mkdir -p "$VERS"
    rm -rf "$VERS"/.stage.* 2>/dev/null || :  # orphans from killed installs
    stage=""
    tmp=$(mktemp -d "${TMPDIR:-/tmp}/oxl-install.XXXXXX")
    trap 'rm -rf "$tmp" ${stage:+"$stage"}' EXIT
    stage=$(mktemp -d "$VERS/.stage.XXXXXX")
    echo "oxl: downloading $tag ($asset)"
    fetch "$BASE/download/$tag/$asset" "$tmp/$asset" \
        || die "no toolchain asset for $suf at $tag — build from source instead:
    https://github.com/oxidean/oxl#building-from-source"
    sha_code=$(curl -fsSL "$BASE/download/$tag/$asset.sha256" -o "$tmp/$asset.sha256" \
        -w '%{http_code}' 2>/dev/null) && sha_rc=0 || sha_rc=$?
    if [ "${sha_rc:-1}" = 0 ]; then
        if have sha256sum; then (cd "$tmp" && sha256sum -c "$asset.sha256");
        elif have shasum; then (cd "$tmp" && shasum -a 256 -c "$asset.sha256");
        else echo "oxl: warning: no sha256 tool — skipping integrity check" >&2; fi \
            || die "sha256 mismatch on $asset — download corrupted or tampered"
    elif [ "${sha_code:-}" = "404" ]; then
        echo "oxl: warning: $tag ships no .sha256 — skipping integrity check" >&2
    else
        die "checksum fetch failed for $asset (http ${sha_code:-none}) — refusing unverified install"
    fi
    tar xzf "$tmp/$asset" -C "$stage" \
        || die "corrupt tarball for $tag"
    [ -x "$stage/oxl-toolchain/oxl" ] \
        || die "tarball for $tag has no oxl-toolchain/oxl"
    # same-filesystem rename — a partial extract can never read as
    # installed; .stage.* is hidden so `tc_list`'s "$VERS"/*/ glob skips it
    [ -e "$VERS/$tag" ] && die "$tag appeared during install — retry"
    chmod 755 "$stage"
    mv "$stage" "$VERS/$tag"
    # a same-tag dir materializing between the check and mv nests the
    # stage inside it ($VERS/$tag/.stage.*) — clean the orphan and fail
    if ls -d "$VERS/$tag"/.stage.* >/dev/null 2>&1; then
        rm -rf "$VERS/$tag"/.stage.*
        die "$tag install raced — a same-tag dir appeared; retry"
    fi
    [ -x "$VERS/$tag/oxl-toolchain/oxl" ] \
        || die "$tag install raced — a same-tag dir appeared; retry"
    rm -rf "$tmp"; trap - EXIT
    echo "oxl: installed $tag -> $VERS/$tag"
    [ -f "$OXL_HOME/default-version" ] || echo "$tag" > "$OXL_HOME/default-version"
}

tc_uninstall() {
    tag=""; force=0
    for a in "$@"; do
        case "$a" in --force) force=1 ;; *) [ -z "$tag" ] || die "unexpected argument: $a"; tag="$a" ;; esac
    done
    [ -n "$tag" ] || { echo "usage: oxl toolchain uninstall <tag> [--force]" >&2; exit 2; }
    raw=$tag; tag=$(vtag "$raw") || die "invalid toolchain tag: $raw"
    [ -d "$VERS/$tag" ] || die "$tag is not installed"
    if [ -f "$OXL_HOME/default-version" ] && [ "$force" = 0 ]; then
        def=$(head -n1 "$OXL_HOME/default-version" | tr -d '\r\n' | sed 's/^[ \t]*//;s/[ \t]*$//')
        [ "$(vtag "$def" 2>/dev/null || printf '%s' "$def")" = "$tag" ] \
            && die "$tag is the default — \`oxl toolchain uninstall $tag --force\` to remove anyway"
    fi
    rm -rf "${VERS:?}/$tag"
    echo "oxl: removed $tag"
}

tc_use() {
    local_tag=""; tag=""
    for a in "$@"; do
        case "$a" in --local) local_tag=1 ;; *) [ -z "$tag" ] || die "unexpected argument: $a"; tag="$a" ;; esac
    done
    [ -n "$tag" ] || { echo "usage: oxl toolchain use [--local] <tag>" >&2; exit 2; }
    raw=$tag; tag=$(vtag "$raw") || die "invalid toolchain tag: $raw"
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
    if [ "$found" = 0 ]; then echo "(none installed)"; fi
}

if [ "${1:-}" = toolchain ]; then
    shift
    case "${1:-}" in
        install)   [ -z "${3:-}" ] || die "usage: oxl toolchain install <tag|latest>"
                   tc_install "${2:?usage: oxl toolchain install <tag|latest>}" ;;
        uninstall) shift; tc_uninstall "$@" ;;
        use)       shift; tc_use "$@" ;;
        list|ls)   tc_list ;;
        default)   { [ -f "$OXL_HOME/default-version" ] && [ -s "$OXL_HOME/default-version" ]; } \
                       || die "no default — \`oxl toolchain use <tag>\`"
                   def=$(head -n1 "$OXL_HOME/default-version" | tr -d '\r\n' | sed 's/^[ \t]*//;s/[ \t]*$//')
                   vtag "$def" || die "invalid version in default-version: $def" ;;
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
    chmod +x "$OXL_HOME/bin/.oxl.tmp.$$" \
        && mv "$OXL_HOME/bin/.oxl.tmp.$$" "$OXL_HOME/bin/oxl"
    echo "wrote $OXL_HOME/bin/oxl"
}

write_shim

[ "$shim_only" = 1 ] && { echo "shim-only — done. Add to PATH: export PATH=\"$OXL_HOME/bin:\$PATH\""; exit 0; }

if [ "$want" = latest ]; then
    url=$(curl -fsIL -o /dev/null -w '%{url_effective}' "$BASE/latest") \
        || { echo "install.sh: cannot resolve latest release at $BASE/latest" >&2; exit 1; }
    # full tag path — an extras-lane tag (extra/vX.Y.Z) can hold
    # "latest"; basename extraction would strip `extra/` and resolve
    # an unrelated toolchain tag
    case "$url" in
        */releases/tag/*) want="${url##*/releases/tag/}" ;;
        *) want="${url##*/}" ;;
    esac
    case "$want" in
        v[0-9]*.[0-9]*.[0-9]*) ;;
        *) echo "install.sh: latest release is not a toolchain tag ($want) — pass one: install.sh vX.Y.Z" >&2; exit 1 ;;
    esac
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
