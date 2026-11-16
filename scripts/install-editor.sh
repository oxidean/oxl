#!/bin/sh
# install-editor.sh — install oxl editor integrations from a GitHub release.
#
#   install-editor.sh vscode [tag] [editor-bin]
#   install-editor.sh nvim   [tag]
#   install-editor.sh bat    [tag]
#   install-editor.sh list   [tag]
#
# `tag` defaults to the newest release carrying editor assets (the same
# release train as the toolchain). Editor assets are platform-independent.
#
# env: OXL_RELEASE_BASE (release host override — tests use file://),
#      OXL_NVIM_REPO   (mirror repo override, default
#                       https://github.com/oxidean/nvim-oxl),
#      OXL_NVIM_HOME   (nvim pack target override, for tests)
set -eu

die() { echo "install-editor.sh: $*" >&2; exit 1; }

BASE="${OXL_RELEASE_BASE:-https://github.com/oxidean/oxl/releases}"
BASE="${BASE%/}"
NVIM_REPO="${OXL_NVIM_REPO:-https://github.com/oxidean/nvim-oxl}"

have() { command -v "$1" >/dev/null 2>&1; }

fetch() { # url out
    have curl || die "curl is required"
    curl -fsSL --connect-timeout 15 --max-time 300 "$1" -o "$2"
}

norm() { case "$1" in v*) printf '%s\n' "$1" ;; *) printf 'v%s\n' "$1" ;; esac; }

vtag() { # raw -> normalized tag on stdout; nonzero exit if invalid
    t=$(norm "$1")
    [ "$(printf '%s' "$t" | tr -d '[:space:]')" = "$t" ] || return 1
    printf '%s\n' "$t" | grep -qE '^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?(\+[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$' \
        || return 1
    printf '%s\n' "$t"
}

# newest release tag whose expanded_assets page lists the editor bundle —
# extras/docs-manifest releases carry no editor assets and must be skipped,
# same rule the toolchain shim applies to oxl-toolchain- assets.
latest_editor_tag() {
    have curl || die "curl is required"
    url=$(curl -fsIL --connect-timeout 15 --max-time 60 -o /dev/null -w '%{url_effective}' "$BASE/latest") \
        || die "cannot resolve latest release at $BASE/latest"
    case "$url" in
        */releases/tag/*) lt="${url##*/releases/tag/}" ;;
        *) lt="${url##*/}" ;;
    esac
    case "$lt" in v[0-9]*) ;; *) lt="" ;; esac
    if [ -n "$lt" ] && tag_has_editors "$lt"; then
        printf '%s\n' "$lt"; return
    fi
    page=1
    while [ "$page" -le 10 ]; do
        if [ "$page" -eq 1 ]; then u="$BASE.atom"; else u="$BASE.atom?page=$page"; fi
        feed=$(curl -fsSL --connect-timeout 15 --max-time 60 "$u" 2>/dev/null) || break
        printf '%s' "$feed" | grep -q 'releases/tag/' || break
        # set -f: an unquoted $() glob-expands candidates against the
        # caller's cwd — a stray v1.* file could shadow a real tag
        set -f
        for c in $(printf '%s\n' "$feed" \
                 | grep -o 'releases/tag/v[0-9][^"<]*' \
                 | sed 's|releases/tag/||'); do
            case "${c%%+*}" in *-*) continue ;; esac
            vtag "$c" >/dev/null 2>&1 || continue
            tag_has_editors "$c" || continue
            printf '%s\n' "$c"; return
        done
        set +f
        page=$((page + 1))
    done
    die "no release with editor assets found — pass a tag explicitly"
}

tag_has_editors() { # tag -> 0 when the release lists oxl-editor-assets
    page=$(curl -fsSL --connect-timeout 15 --max-time 60 \
        "$BASE/expanded_assets/$1" 2>/dev/null) || return 0
    printf '%s' "$page" | grep -q 'oxl-editor-assets'
}

resolve_tag() { # arg-or-empty|latest -> tag on stdout
    t="$1"
    { [ -z "$t" ] || [ "$t" = latest ]; } && t=$(latest_editor_tag)
    vtag "$t" || die "invalid release tag: $t"
}

cmd_vscode() {
    tag=$(resolve_tag "${1:-}")
    [ $# -gt 0 ] && shift
    bin=""
    for a in "$@"; do
        case "$a" in
            code|codium|cursor|code-insiders) bin="$a" ;;
            *) die "unknown vscode editor bin: $a" ;;
        esac
    done
    if [ -z "$bin" ]; then
        for c in code codium cursor code-insiders; do
            have "$c" && { bin="$c"; break; }
        done
    fi
    [ -n "$bin" ] || die "no VS Code-family binary found (code/codium/cursor) — install one or pass it explicitly"
    url="$BASE/download/$tag/oxl-language.vsix"
    echo "install-editor: installing $tag for $bin"
    "$bin" --install-extension "$url" \
        || die "extension install failed — is '$bin' on PATH?"
    echo "install-editor: done — restart $bin if the extension does not appear"
}

cmd_nvim() {
    tag=$(resolve_tag "${1:-}")
    have git || die "git is required for the nvim plugin"
    dest="${OXL_NVIM_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/nvim/site/pack/vendor/start/nvim-oxl}"
    case "$dest" in /*) ;; *) die "nvim pack dir must be absolute: $dest" ;; esac
    mkdir -p "$(dirname "$dest")"
    if [ -d "$dest/.git" ]; then
        echo "install-editor: updating $dest to $tag"
        git -C "$dest" fetch --depth 1 origin "refs/tags/$tag" \
            || die "fetch of $tag from $NVIM_REPO failed — is the mirror published?"
        git -C "$dest" checkout --detach FETCH_HEAD \
            || die "checkout of $tag failed"
    else
        [ -e "$dest" ] && die "$dest exists and is not a git checkout — remove it or set OXL_NVIM_HOME"
        echo "install-editor: cloning $NVIM_REPO@$tag -> $dest"
        git clone --depth 1 --branch "$tag" "$NVIM_REPO" "$dest" \
            || die "clone failed — mirror may not be published for $tag yet"
    fi
    echo "install-editor: nvim-oxl $tag installed — .oxl files get filetype + oxl lsp"
}

cmd_bat() {
    tag=$(resolve_tag "${1:-}")
    dest="${BAT_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/bat}/syntaxs"
    case "$dest" in /*) ;; *) die "bat syntax dir must be absolute: $dest" ;; esac
    have curl || die "curl is required"
    mkdir -p "$dest"
    url="$BASE/download/$tag/oxl.sublime-syntax"
    echo "install-editor: installing oxl.sublime-syntax ($tag) -> $dest"
    fetch "$url" "$dest/oxl.sublime-syntax" \
        || die "no oxl.sublime-syntax asset at $tag"
    echo "install-editor: done — 'bat --list-languages' should show oxl"
    echo "install-editor: Sublime Text users: copy the same file into their Packages dir"
}

cmd_list() {
    tag=$(resolve_tag "${1:-}")
    echo "editor assets for $tag:"
    echo "  vscode : $BASE/download/$tag/oxl-language.vsix"
    echo "  bundle : $BASE/download/$tag/oxl-editor-assets.tar.gz"
    echo "  syntax : $BASE/download/$tag/oxl.sublime-syntax"
    echo "  nvim   : $NVIM_REPO (tag $tag)"
}

usage() {
    cat <<'EOF'
install-editor.sh — install oxl editor integrations from a GitHub release

  install-editor.sh vscode [tag] [code|codium|cursor|code-insiders]
  install-editor.sh nvim   [tag]
  install-editor.sh bat    [tag]
  install-editor.sh list   [tag]

tag defaults to the newest release carrying editor assets.
env: OXL_RELEASE_BASE, OXL_NVIM_REPO, OXL_NVIM_HOME, BAT_CONFIG_DIR,
     XDG_CONFIG_HOME, XDG_DATA_HOME
EOF
}

cmd="${1:-}"; [ -n "$cmd" ] || { usage >&2; exit 2; }
shift
case "$cmd" in
    -h|--help|help) usage; exit 0 ;;
    vscode) cmd_vscode "$@" ;;
    nvim)   cmd_nvim "$@" ;;
    bat)    cmd_bat "$@" ;;
    list)   cmd_list "$@" ;;
    *) usage >&2; exit 2 ;;
esac
