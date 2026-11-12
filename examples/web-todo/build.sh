#!/bin/sh
# builds the web-todo bundle into dist/:
#   web-todo.mjs + rt.mjs/rt-node/rt-browser/rt-dom + web-todo.mjs.html
# index.html + style.css are the hand-authored page (kept — the
# --html scaffold output rides alongside as web-todo.mjs.html).
set -e
cd "$(dirname "$0")"
OXL="${OXL:-../../target/oxl-self}"
[ -x "$OXL" ] || OXL="$(command -v oxl)"
"$OXL" build --target js --html . -o dist/web-todo.mjs
cp index.html style.css dist/ 2>/dev/null || true
echo "dist/web-todo.mjs + runtime written"
