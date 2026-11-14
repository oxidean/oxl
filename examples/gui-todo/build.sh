#!/usr/bin/env bash
# build the gui-todo example: the extra/gui/gtk shim with gtk4 cflags,
# the oxl app linked against it via LANG_LDFLAGS
set -euo pipefail
cd "$(dirname "$0")"

if [ -z "${OXL:-}" ]; then
    # source checkout builds into target/ (scripts/stage0.sh); the
    # packaged toolchain drops `oxl` at the root next to stdlib/ +
    # examples/
    if [ -x ../../target/oxl ]; then
        OXL=../../target/oxl
    else
        OXL=../../oxl
    fi
fi
GTK_CFLAGS=$(pkg-config --cflags gtk4)
GTK_LIBS=$(pkg-config --libs gtk4)

"${LANG_CC:-cc}" -O2 $GTK_CFLAGS -c ../../extra/gui/gtk/gtk_shim.c -o gtk_shim.o
# relative shim path: LANG_LDFLAGS is whitespace-split by the driver, so an
# absolute path breaks on checkouts whose directory contains spaces
LANG_LDFLAGS="gtk_shim.o $GTK_LIBS" "$OXL" build todo.oxl -o todo
echo "built ./todo"
