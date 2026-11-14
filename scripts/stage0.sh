#!/usr/bin/env bash
# scripts/stage0.sh — stage-0 bootstrap for the self-hosted toolchain.
#
#   build (default)  compile bootstrap/stage0/oxl.c -> target/oxl
#   emit             regenerate bootstrap/stage0/oxl.c from an installed
#                    oxl ($OXL, else `oxl` on PATH)
#
# The snapshot is the C emit of cmd/oxl (the whole driver: argv dispatch
# over bootstrap/check + bootstrap/codegen + std). Compiling it with cc
# + runtime/rt.c yields a working `oxl` that builds the driver from
# source — tests/run.sh then runs the gen1/gen2 fixpoint, which doubles
# as the snapshot-freshness gate: a snapshot emitted by an older
# compiler fails the fixpoint and points back here.
set -euo pipefail
cd "$(dirname "$0")/.."

CC="${LANG_CC:-cc}"
SNAP="bootstrap/stage0/oxl.c"
OUT="target/oxl"

case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
        EXE=".exe"; THREAD_FLAG=""; NET_LIB="-lws2_32"; MATH_LIB=""; GC_FLAG="-Wl,--gc-sections" ;;
    Darwin)
        EXE=""; THREAD_FLAG="-pthread"; NET_LIB=""; MATH_LIB="-lm"; GC_FLAG="-Wl,-dead_strip" ;;
    *)
        EXE=""; THREAD_FLAG="-pthread"; NET_LIB=""; MATH_LIB="-lm"; GC_FLAG="-Wl,--gc-sections" ;;
esac

emit() {
    oxl="${OXL:-$(command -v oxl || true)}"
    if [ -z "$oxl" ]; then
        echo "stage0 emit: no oxl found — set OXL or put an installed oxl on PATH" >&2
        exit 1
    fi
    # codegen prints the driver's C (all imported modules inlined) on
    # stdout; diagnostics stay on stderr
    "$oxl" run bootstrap/cmd/codegen -- cmd/oxl > "$SNAP"
    echo "stage0: wrote $SNAP ($(wc -c < "$SNAP") bytes) via $oxl"
}

build() {
    if [ ! -f "$SNAP" ]; then
        echo "stage0: $SNAP missing — run scripts/stage0.sh emit first" >&2
        exit 1
    fi
    mkdir -p target
    # mirror cmd/oxl's emit_and_cc link decisions: the driver's own
    # source carries the sqlite/net/math marker strings, so the scan
    # below lands the same -D/-l set a self-build would
    args=(-O2 $THREAD_FLAG -ffunction-sections -fdata-sections "$GC_FLAG" -I runtime -o "$OUT$EXE" "$SNAP" runtime/rt.c)
    if grep -q 'rt_sqlite_' "$SNAP"; then
        args+=(-DOXL_SQLITE)
        if [ -n "${LANG_SQLITE_SRC:-}" ]; then
            args+=("-I$(dirname "$LANG_SQLITE_SRC")" "$LANG_SQLITE_SRC")
        else
            args+=(-lsqlite3)
        fi
    fi
    if grep -qE 'rt_sock_|rt_bind_any|rt_set_reuseaddr|rt_set_rcvtimo|rt_set_sndtimo|rt_htons|rt_htonl|rt_lookup_ipv4' "$SNAP"; then
        args+=(-DOXL_NET)
        if [ -n "$NET_LIB" ]; then
            args+=("$NET_LIB")
        fi
    fi
    if grep -q 'rt_m_' "$SNAP"; then
        args+=(-DOXL_MATH)
        if [ -n "$MATH_LIB" ]; then
            args+=("$MATH_LIB")
        fi
    fi
    "$CC" "${args[@]}"
    echo "stage0: built $OUT$EXE"
}

case "${1:-build}" in
    build) build ;;
    emit) emit ;;
    *) echo "usage: scripts/stage0.sh [build|emit]" >&2; exit 2 ;;
esac
