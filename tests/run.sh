#!/usr/bin/env bash
# tests/run.sh <path-to-oxl-binary> — end-to-end suite run by CI.
set -euo pipefail
# trap-path tests abort on purpose; without this each run litters the
# repo root with core.* dumps (they're gitignored but still junk)
ulimit -c 0 2>/dev/null || true
OXL="${1:-oxl}"
cd "$(dirname "$0")/.."
# absolutize — subshell gates (gui pilot) invoke $OXL from other dirs
case "$OXL" in /*) ;; *) OXL="$PWD/$OXL";; esac

# platform knobs — Git Bash/MSYS (windows-latest legs) spell .exe
# explicitly, drop -pthread (pthread APIs come from the rt.h Win32
# veneer, not a lib), link ws2_32 for the socket shims, and resolve
# python by whatever name the image gives it
EXE=""; THREAD_FLAG="-pthread"; NET_LIBS=""; MATH_LIBS="-lm"; PY=python3
case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
        EXE=".exe"; THREAD_FLAG=""; NET_LIBS="-lws2_32"; MATH_LIBS=""; PY=python ;;
esac
command -v "$PY" >/dev/null 2>&1 || PY=python3
CC="${LANG_CC:-cc}"
# sqlite reaches a build either as a system lib (POSIX dev packages) or
# as an amalgamation source (LANG_SQLITE_SRC — the only form a stock
# Windows box provides); -I its dir supplies sqlite3.h
if [ -n "${LANG_SQLITE_SRC:-}" ]; then
    SQLITE_LINK="-I$(dirname "$LANG_SQLITE_SRC") $LANG_SQLITE_SRC"
else
    SQLITE_LINK="-lsqlite3"
fi

# peak RSS of pid $1 in kB — ps reads /proc, which doesn't exist for a
# native child on Windows; ask the OS instead
rss_kb() {
    case "$(uname -s)" in
        MINGW*|MSYS*|CYGWIN*)
            # git-bash tracks native children by msys pid (not the winpid)
            # and exposes their WorkingSet in /proc — no powershell hop
            # (powershell.exe is not on the msys PATH anyway)
            awk '/VmRSS/{printf "%d", $2}' "/proc/$1/status" 2>/dev/null ;;
        *) ps -o rss= -p "$1" 2>/dev/null | tr -d ' ' ;;
    esac
}

# GNU timeout doesn't exist on stock macOS; fall back to gtimeout
# (brew coreutils), else a bash watchdog that kills the child at the
# deadline — a hang must never run unbounded.
with_timeout() {
    if command -v timeout >/dev/null 2>&1; then timeout "$@"
    elif command -v gtimeout >/dev/null 2>&1; then gtimeout "$@"
    else
        local secs=$1; shift
        "$@" & local pid=$!
        # watchdog redirects away from the caller's capture pipe: inside
        # out=$(with_timeout ..) the subshell would inherit that pipe, and
        # a killed dog can orphan its sleep child still holding it open —
        # the $() then hangs past the deadline it was enforcing
        ( sleep "$secs"; kill -KILL "$pid" 2>/dev/null ) >/dev/null 2>&1 & local dog=$!
        local rc=0
        wait "$pid" 2>/dev/null || rc=$?
        if kill -0 "$dog" 2>/dev/null; then
            kill "$dog" 2>/dev/null; wait "$dog" 2>/dev/null
        else
            rc=124 # watchdog fired — same sentinel as GNU timeout
        fi
        return "$rc"
    fi
}

# one run-owned scratch dir: fixed /tmp paths collide between parallel
# runs (CWE-377), and an EXIT trap guarantees the http pilot's server
# dies even when a probe fails mid-suite
scratch=$(mktemp -d)
srv_pid=""
cleanup() {
    if [ -n "$srv_pid" ]; then kill "$srv_pid" 2>/dev/null || true; fi
    # v2's sealed module-cache slots are read-only — restore write
    # permission or rm leaves them behind
    chmod -R u+w "$scratch" 2>/dev/null
    rm -rf "$scratch"
}
trap cleanup EXIT

echo "== self-built product driver (t6) =="
# ADR-0006: the Rust seed is the bootstrap input only — it builds the
# product driver once (gen 1), the product driver rebuilds itself
# (gen 2), and the C each generation emits for the driver sources must
# be byte-identical (the fixpoint — not a binary hash: build-ids and
# embedded paths legitimately differ) — seed emit included, so the
# seed-vs-self spec criterion is checked directly, not just via
# output parity. Every section below then runs
# under the product driver; SEEDOXL stays only where a seed-vs-self
# output comparison needs it.
SEEDOXL="$OXL"
"$SEEDOXL" build cmd/oxl -o "target/oxl-self$EXE" || { echo "FAIL gen1 driver build"; exit 1; }
SELFOXL="$PWD/target/oxl-self$EXE"
"$SELFOXL" build cmd/oxl -o "target/oxl-self2$EXE" || { echo "FAIL gen2 driver build"; exit 1; }
SELFOXL2="$PWD/target/oxl-self2$EXE"
"$SEEDOXL" run bootstrap/cmd/codegen -- cmd/oxl > "$scratch/drv0.c" || { echo "FAIL seed emit"; exit 1; }
"$SELFOXL" run bootstrap/cmd/codegen -- cmd/oxl > "$scratch/drv1.c" || { echo "FAIL gen1 emit"; exit 1; }
"$SELFOXL2" run bootstrap/cmd/codegen -- cmd/oxl > "$scratch/drv2.c" || { echo "FAIL gen2 emit"; exit 1; }
diff "$scratch/drv0.c" "$scratch/drv1.c" >/dev/null || { echo "FAIL driver C fixpoint (seed vs gen1)"; diff "$scratch/drv0.c" "$scratch/drv1.c" | head -20; exit 1; }
diff "$scratch/drv1.c" "$scratch/drv2.c" >/dev/null || { echo "FAIL driver C fixpoint (gen1 vs gen2)"; diff "$scratch/drv1.c" "$scratch/drv2.c" | head -20; exit 1; }
OXL="$SELFOXL"

echo "== hello =="
out=$("$OXL" run examples/hello.oxl)
[ "$out" = "hello, world" ] || { echo "FAIL hello: $out"; exit 1; }
# G2: informational binary size — section GC + feature gates should
# keep hello tiny; printed like the a1 memory timings, no hard assert
"$OXL" build examples/hello.oxl -o "$scratch/hello$EXE" || { echo "FAIL hello build"; exit 1; }
echo "  hello.oxl binary: $(wc -c <"$scratch/hello$EXE") bytes"

# the README's language-surface example (the fenced 'oxl' code block) is
# a byte-identical copy of examples/http-hello minus its comment banner —
# extract both sides and diff them so the doc can't drift, then prove the
# file still compiles. Backticks can't appear in this comment or the
# FAIL message below: bash parses them as command substitution.
awk '/^```oxl$/{f=1;next} /^```$/{f=0} f' README.md > "$scratch/readme-snippet.oxl"
sed -n '/^import /,$p' examples/http-hello/main.oxl > "$scratch/http-hello-body.oxl"
{ echo "package main"; echo; cat "$scratch/http-hello-body.oxl"; } > "$scratch/http-hello-expected.oxl"
diff -u "$scratch/http-hello-expected.oxl" "$scratch/readme-snippet.oxl" >/dev/null \
    || { echo "FAIL README example drift: sync the fenced oxl block with examples/http-hello/main.oxl"; exit 1; }
"$OXL" build examples/http-hello/main.oxl -o "$scratch/http-hello$EXE" || { echo "FAIL http-hello build"; exit 1; }

echo "== features =="
out=$("$OXL" run examples/features.oxl)
[ "$(tail -1 <<<"$out")" = "done" ] || { echo "FAIL features"; exit 1; }

echo "== cli pilot =="
out=$("$OXL" run examples/cli/main.oxl -- Jesse)
grep -q "hello, Jesse" <<<"$out" || { echo "FAIL cli"; exit 1; }

echo "== oxl test: smoke =="
out=$("$OXL" test examples/smoke_test.oxl)
printf '%s\n' "$out" >&2
grep -q "test_chan ... ok" <<<"$out" || { echo "FAIL smoke: $out"; exit 1; }

echo "== oxl test: stdlib =="
out=$("$OXL" test tests/stdlib_test.oxl)
grep -q "test_loops ... ok" <<<"$out" || { echo "FAIL stdlib: $out"; exit 1; }

echo "== oxl test: os =="
out=$("$OXL" test tests/os_test.oxl)
grep -q "test_file ... ok" <<<"$out" || { echo "FAIL os: $out"; exit 1; }

echo "== oxl test: io (s2) =="
out=$("$OXL" test tests/io_test.oxl)
printf '%s
' "$out" >&2
for t in test_bytes test_strconv test_fmt test_errs test_fill_keeps_err_bytes test_flush_keeps_unwritten test_fill_nop_progress test_stdstreams test_io_files test_err_chain; do
    grep -q "$t ... ok" <<<"$out" || { echo "FAIL io: $out"; exit 1; }
done
# char literals decode to their scalar (scratch, not corpus — fmt
# normalizes 'a' to 97 in formatted files)
cat > "$scratch/charlit.oxl" <<'EOF'
package main
fn main() {
    ok := 'a' == 97 && '\n' == 10 && '\\' == 92 && '\'' == 39 && 'A' == 65
    if ok {
        println("charlit ok")
    }
}
EOF
out=$("$OXL" run "$scratch/charlit.oxl")
grep -q "charlit ok" <<<"$out" || { echo "FAIL charlit: $out"; exit 1; }
# char-literal lex errors — '' and multi-char are rejected at lex time
cat > "$scratch/badchar.oxl" <<'EOF'
package main
fn main() { x := '' }
EOF
diag=$("$OXL" build "$scratch/badchar.oxl" -o "$scratch/badchar$EXE" 2>&1 || true)
grep -q "char literal" <<<"$diag" || { echo "FAIL charlit diag: $diag"; exit 1; }

echo "== oxl test: util (s3) =="
out=$("$OXL" test tests/util_test.oxl)
printf '%s
' "$out" >&2
for t in test_path test_filepath test_cmp test_sort test_slices test_maps test_math test_rand test_utf8; do
    grep -q "$t ... ok" <<<"$out" || { echo "FAIL util: $out"; exit 1; }
done
out=$("$OXL" test tests/flaglog_test.oxl)
printf '%s
' "$out" >&2
for t in test_flag test_log; do
    grep -q "$t ... ok" <<<"$out" || { echo "FAIL flaglog: $out"; exit 1; }
done
# cli exercises std/flag's argv paths end to end: -n=N, --n N, bools,
# positionals, and the bad-flag usage path
got=$("$OXL" run examples/cli/main.oxl -- -n=2 Jesse)
want=$(printf 'hello, Jesse\n0\n1')
[ "$got" = "$want" ] || { echo "FAIL cli -n=2: $got"; exit 1; }
got=$("$OXL" run examples/cli/main.oxl -- --n 2 Jesse)
[ "$got" = "$want" ] || { echo "FAIL cli --n 2: $got"; exit 1; }
got=$("$OXL" run examples/cli/main.oxl -- -v Jesse)
want2=$(printf 'hello, Jesse\nverbose mode on')
[ "$got" = "$want2" ] || { echo "FAIL cli -v: $got"; exit 1; }
errout=$("$OXL" run examples/cli/main.oxl -- -bogus Jesse 2>&1) && rc=0 || rc=$?
[ "$rc" -eq 2 ] || { echo "FAIL cli bad-flag rc: $rc $errout"; exit 1; }
grep -q "Usage of cli:" <<<"$errout" || { echo "FAIL cli bad-flag usage: $errout"; exit 1; }
out=$("$OXL" run examples/cli/main.oxl -- -- Jesse)
[ "$out" = "hello, Jesse" ] || { echo "FAIL cli -- positional: $out"; exit 1; }

echo "== oxl test: net & enc (s4) =="
out=$("$OXL" test tests/enc_test.oxl)
printf '%s
' "$out" >&2
for t in test_base64 test_hex test_binary test_csv; do
    grep -q "$t ... ok" <<<"$out" || { echo "FAIL enc: $out"; exit 1; }
done
out=$("$OXL" test tests/hash_test.oxl)
printf '%s
' "$out" >&2
for t in test_fnv test_adler_crc test_incremental; do
    grep -q "$t ... ok" <<<"$out" || { echo "FAIL hash: $out"; exit 1; }
done
out=$("$OXL" test tests/crypto_test.oxl)
printf '%s
' "$out" >&2
for t in test_sha256 test_md5 test_hmac; do
    grep -q "$t ... ok" <<<"$out" || { echo "FAIL crypto: $out"; exit 1; }
done
out=$("$OXL" test tests/net_test.oxl)
printf '%s
' "$out" >&2
for t in test_refused test_lookup test_badip; do
    grep -q "$t ... ok" <<<"$out" || { echo "FAIL net: $out"; exit 1; }
done
# socket-dependent half — the js lane's socket natives are trap21
# stubs, so this file stays native-only (the w4 lane runs net_test's
# socket-free tests)
out=$("$OXL" test tests/net_sock_test.oxl)
printf '%s
' "$out" >&2
for t in test_echo test_closer; do
    grep -q "$t ... ok" <<<"$out" || { echo "FAIL net-sock: $out"; exit 1; }
done

echo "== oxl test: regexp (s5) =="
out=$("$OXL" test tests/regexp_test.oxl)
printf '%s
' "$out" >&2
for t in test_literals test_anchors test_dot test_classes test_posix test_alternation test_quantifiers test_lazy test_escapes test_word_boundary test_utf8 test_findall test_replaceall test_split test_compile_errors test_pathological; do
    grep -q "$t ... ok" <<<"$out" || { echo "FAIL regexp: $out"; exit 1; }
done
# the client test runs under `oxl run`: it exits the process to end
# serve()'s accept loop, so the oxl-test task drain can't hang on it
out=$("$OXL" run tests/httpclient_test.oxl)
printf '%s
' "$out" >&2
grep -q "httpclient done" <<<"$out" || { echo "FAIL httpclient: $out"; exit 1; }

echo "== oxl test: exec + fs (t0) =="
out=$("$OXL" test tests/exec_test.oxl)
printf '%s
' "$out" >&2
for t in test_output_git test_nonzero_is_status_not_err test_spawn_failure_is_err test_env_override; do
    grep -q "$t ... ok" <<<"$out" || { echo "FAIL exec: $out"; exit 1; }
done
out=$("$OXL" test tests/fsops_test.oxl)
printf '%s
' "$out" >&2
for t in test_mkdir_ls_rename_remove test_mkdir_all_idempotent; do
    grep -q "$t ... ok" <<<"$out" || { echo "FAIL fsops: $out"; exit 1; }
done

echo "== stdmods (json/sync/time) =="
out=$("$OXL" run tests/stdmods_test.oxl)
grep -q '"name":"widget"' <<<"$out" || { echo "FAIL stdmods json: $out"; exit 1; }
grep -q "^surr=3:4 00000$" <<<"$out" || { echo "FAIL stdmods surrogates: $out"; exit 1; }
grep -q "^4000$" <<<"$out" || { echo "FAIL stdmods sync counter: $out"; exit 1; }
[ "$(tail -1 <<<"$out")" = "done" ] || { echo "FAIL stdmods time: $out"; exit 1; }

echo "== float (d1) =="
out=$("$OXL" test tests/float_test.oxl)
grep -q "test_json_float ... ok" <<<"$out" || { echo "FAIL float: $out"; exit 1; }
# int/float mixing must be a compile error, not silent widening
cat > "$scratch/floatmix.oxl" <<'EOF'
package main
fn main() { x := 1 + 2.5 }
EOF
if "$OXL" build "$scratch/floatmix.oxl" -o "$scratch/floatmix$EXE" 2>/dev/null; then
    echo "FAIL: int+float compiled (should be a type error)"; exit 1
fi

echo "== enum (b1) =="
out=$("$OXL" run tests/enum_test.oxl)
[ "$(tail -1 <<<"$out")" = "enum fns ok" ] || { echo "FAIL enum: $out"; exit 1; }

echo "== match (b2) =="
out=$("$OXL" run tests/match.oxl)
[ "$(tail -1 <<<"$out")" = "match ok" ] || { echo "FAIL match: $out"; exit 1; }
# non-exhaustive match must name the missing variant
cat > "$scratch/matchnex.oxl" <<'EOF'
package main
enum E { A(int), B, }
fn f(e: E) -> int { return match e { E.A(v) => v } }
fn main() { }
EOF
if "$OXL" build "$scratch/matchnex.oxl" -o "$scratch/matchnex$EXE" 2>/dev/null; then
    echo "FAIL: non-exhaustive match compiled"; exit 1
fi
diag=$("$OXL" build "$scratch/matchnex.oxl" -o "$scratch/matchnex$EXE" 2>&1 || true)
grep -q "missing B" <<<"$diag" || { echo "FAIL: missing-variant diagnostic: $diag"; exit 1; }

echo "== slices (b3) =="
out=$("$OXL" run tests/slices.oxl)
[ "$(tail -1 <<<"$out")" = "slices ok" ] || { echo "FAIL slices: $out"; exit 1; }
# out-of-range index must trap, not corrupt — build first so a compile
# break can't pass as a runtime trap
"$OXL" build tests/slice_oob.oxl -o "$scratch/slice_oob$EXE" || { echo "FAIL: slice_oob did not compile"; exit 1; }
if "$scratch/slice_oob$EXE" >/dev/null 2>&1; then
    echo "FAIL slice_oob: expected nonzero exit"; exit 1
fi
# inverted view range must trap, not corrupt
"$OXL" build tests/slice_range.oxl -o "$scratch/slice_range$EXE" || { echo "FAIL: slice_range did not compile"; exit 1; }
if "$scratch/slice_range$EXE" >/dev/null 2>&1; then
    echo "FAIL slice_range: expected nonzero exit"; exit 1
fi

echo "== fn values (b4) =="
out=$("$OXL" run tests/fnval.oxl)
[ "$(tail -1 <<<"$out")" = "fnval ok" ] || { echo "FAIL fnval: $out"; exit 1; }
# fn values can't suspend, capture susp, compare, or wrap generics/pairs
for bad in susp clsusp ctrans gen pair eq; do
    cat > "$scratch/fnv_$bad.oxl" <<EOF
package main
$(case $bad in
  susp)   printf 'fn s() { sleep(1) }\nfn main() { f := s }' ;;
  clsusp) printf 'fn main() { f := { |x: int| sleep(1); return x } }' ;;
  ctrans) printf 'fn w() { sleep(1) }\nfn main() { f := { |x: int| w(); return x } }' ;;
  gen)    printf 'fn id[T any](x: T) -> T { return x }\nfn main() { f := id[int] }' ;;
  pair)   printf 'fn p() -> [int, err] { return 1, nil }\nfn main() { f := p }' ;;
  eq)     printf 'fn a() {}\nfn main() { f := a; if f == a { println(1) } }' ;;
esac)
EOF
    if "$OXL" build "$scratch/fnv_$bad.oxl" -o "$scratch/fnv_$bad" 2>/dev/null; then
        echo "FAIL: fnval/$bad compiled (should be rejected)"; exit 1
    fi
done

echo "== collections (b6) =="
out=$("$OXL" run tests/collections_test.oxl)
[ "$(tail -1 <<<"$out")" = "collections ok" ] || { echo "FAIL collections: $out"; exit 1; }

echo "== defer (b5) =="
out=$("$OXL" run tests/defer_order.oxl)
grep -q "defer order ok" <<<"$out" || { echo "FAIL defer order: $out"; exit 1; }
out=$("$OXL" run tests/defer_test.oxl)
# fixed sequence: LIFO drain (3 2 1), error-path defer (9), per-iteration
# loop defers (2 1 0), the untaken branch registering nothing (7 only)
[ "$out" = $'3\n2\n1\n9\n2\n1\n0\n7\ndone' ] || { echo "FAIL defer: $out"; exit 1; }
# trap unwind still drains the task's defer stack before aborting
cat > "$scratch/d5trap.oxl" <<'EOF'
package main
fn dmark(x: int) { println(itoa(x)) }
fn willtrap() {
    defer dmark(6)
    defer dmark(5)
    s := mkslice(int, 2)
    println(s[9])
}
fn main() { willtrap() }
EOF
"$OXL" build "$scratch/d5trap.oxl" -o "$scratch/d5trap$EXE" || { echo "FAIL: d5trap did not compile"; exit 1; }
trapout=$(with_timeout 10 "$scratch/d5trap$EXE" 2>&1 || true)
grep -q "^5$" <<<"$trapout" || { echo "FAIL defer trap drain: $trapout"; exit 1; }
grep -q "^6$" <<<"$trapout" || { echo "FAIL defer trap drain order: $trapout"; exit 1; }

echo "== methods + interfaces (d3) =="
out=$("$OXL" run tests/methods.oxl)
[ "$out" = "methods ok" ] || { echo "FAIL methods: $out"; exit 1; }
# a method-less type must not satisfy a method interface
cat > "$scratch/d3sat.oxl" <<'D3EOF'
package main
interface Writer { write(s: str) -> int }
struct Bare { n: int }
fn emit(w: Writer) -> int { return w.write("x") }
fn main() { emit(Bare{n: 1}) }
D3EOF
if "$OXL" build "$scratch/d3sat.oxl" -o "$scratch/d3sat" 2>/dev/null; then
    echo "FAIL: unsatisfied iface compiled"; exit 1
fi
# a susp method that an interface can dispatch can't compile —
# vtable calls carry no task frame
cat > "$scratch/d3susp.oxl" <<'D3EOF'
package main
interface Waiter { wait() }
struct S { n: int }
fn (s S) wait() { sleep(1) }
fn main() { s := S{n: 0}; s.wait() }
D3EOF
if "$OXL" build "$scratch/d3susp.oxl" -o "$scratch/d3susp" 2>/dev/null; then
    echo "FAIL: vtable-reachable suspending method compiled"; exit 1
fi
diag=$("$OXL" build "$scratch/d3susp.oxl" -o "$scratch/d3susp" 2>&1 || true)
grep -q 'satisfies interface `Waiter`' <<<"$diag" || { echo "FAIL d3susp diag: $diag"; exit 1; }
# a susp method no interface claims is legal — direct call gets a frame
cat > "$scratch/d3suspok.oxl" <<'D3EOF'
package main
struct S { n: int }
fn (s S) wait() -> int {
    select {
        timeout(5) => { return s.n + 1 }
    }
    return 0
}
fn main() { s := S{n: 3}; println(itoa(s.wait())) }
D3EOF
"$OXL" build "$scratch/d3suspok.oxl" -o "$scratch/d3suspok$EXE" || { echo "FAIL: off-vtable suspending method rejected"; exit 1; }
out=$(with_timeout 10 "$scratch/d3suspok$EXE")
[ "$out" = "4" ] || { echo "FAIL susp method run: $out"; exit 1; }

echo "== move tracking (d2) =="
# use-after-move must be a compile error naming the binding
cat > "$scratch/d2move.oxl" <<'EOF'
package main
struct P { v: int }
fn take(p: own P) { }
fn main() { p := new(P); take(p); take(p) }
EOF
if "$OXL" build "$scratch/d2move.oxl" -o "$scratch/d2move" 2>/dev/null; then
    echo "FAIL: use-after-move compiled"; exit 1
fi
diag=$("$OXL" build "$scratch/d2move.oxl" -o "$scratch/d2move" 2>&1 || true)
grep -q 'use of moved value `p`' <<<"$diag" || { echo "FAIL moved diag: $diag"; exit 1; }
# the headline bug class — one own cell into two spawned workers
cat > "$scratch/d2spawn.oxl" <<'EOF'
package main
struct P { v: int }
fn w(p: own P) { }
fn main() { p := new(P); spawn w(p); spawn w(p) }
EOF
if "$OXL" build "$scratch/d2spawn.oxl" -o "$scratch/d2spawn" 2>/dev/null; then
    echo "FAIL: double-spawn of own compiled"; exit 1
fi
# moved inside a loop body — the next iteration would read a moved value
cat > "$scratch/d2for.oxl" <<'EOF'
package main
struct P { v: int }
fn take(p: own P) { }
fn main() { p := new(P); for true { take(p) } }
EOF
if "$OXL" build "$scratch/d2for.oxl" -o "$scratch/d2for" 2>/dev/null; then
    echo "FAIL: move-in-loop compiled"; exit 1
fi
# re-init clears the mark
cat > "$scratch/d2ok.oxl" <<'EOF'
package main
struct P { v: int }
fn take(p: own P) { }
fn main() {
    p := new(P)
    take(p)
    p = new(P)
    take(p)
    println("ok")
}
EOF
out=$("$OXL" run "$scratch/d2ok.oxl")
[ "$out" = "ok" ] || { echo "FAIL d2 reinit: $out"; exit 1; }
# moved in one branch: the join can't prove which path ran — reject the
# later read unless EVERY path re-initializes the binding
cat > "$scratch/d2branch.oxl" <<'EOF'
package main
struct P { v: int }
fn take(p: own P) { }
fn main() { p := new(P); if len("x") > 0 { take(p) }; take(p) }
EOF
if "$OXL" build "$scratch/d2branch.oxl" -o "$scratch/d2branch" 2>/dev/null; then
    echo "FAIL: one-branch move compiled"; exit 1
fi
# shared cells are copy/shareable — same cell to four workers is intended
out=$("$OXL" run tests/stdmods_test.oxl)
grep -q "^4000$" <<<"$out" || { echo "FAIL d2 shared workers: $out"; exit 1; }

echo "== d5 module qualification =="
out=$("$OXL" run tests/d5_qual.oxl)
[ "$(tail -1 <<<"$out")" = "d5 qual ok" ] || { echo "FAIL d5 qual: $out"; exit 1; }
# an imported name with no qualifier and no selective flatten must not
# resolve — silent shadowing was the bug d5 exists to kill
cat > "$scratch/d5unqual.oxl" <<'EOF'
package main
import "std/strings"
fn main() { println(strings.startswith("ab","a")); println(trim(" x ")) }
EOF
if "$OXL" build "$scratch/d5unqual.oxl" -o "$scratch/d5unqual" 2>/dev/null; then
    echo "FAIL: unqualified import call compiled"; exit 1
fi
diag=$("$OXL" build "$scratch/d5unqual.oxl" -o "$scratch/d5unqual" 2>&1 || true)
# an unresolved import emits "undefined `trim`" too — without it the
# probe tests nothing. Fail on resolution diags so the check really
# exercises qualification, not import fallback.
if grep -q "cannot resolve import" <<<"$diag"; then
    echo "FAIL unqual probe: stdlib unresolved: $diag"; exit 1
fi
grep -q "undefined \`trim\`" <<<"$diag" || { echo "FAIL unqual diag: $diag"; exit 1; }

echo "== bootstrap lexer =="
out=$("$OXL" run bootstrap/cmd/lex -- examples/hello.oxl)
grep -q "13 tokens" <<<"$out" || { echo "FAIL lexer"; exit 1; }

echo "== bootstrap parser =="
out=$("$OXL" run bootstrap/cmd/parse -- examples/features.oxl)
printf '%s' "$out" | $PY -c 'import json,sys
d=json.load(sys.stdin)
assert len(d["items"])==7 and not any("skip" in i for i in d["items"]), d' || { echo "FAIL parser"; exit 1; }
out=$("$OXL" run bootstrap/cmd/parse -- bootstrap/parser/parser.oxl)
# stdin not argv for the payload — a self-parse AST is far past the
# ~32KB command-line cap Windows puts on every child process
printf '%s' "$out" | $PY -c 'import json,sys
d=json.load(sys.stdin)
assert len(d["items"])>20 and not any("skip" in i for i in d["items"]), d' || { echo "FAIL parser self-parse"; exit 1; }

echo "== bootstrap checker =="
# the self-hosted typechecker must check itself and representative sources
for f in bootstrap/check bootstrap/codegen examples/features.oxl tests/match.oxl std/collections; do
    out=$("$OXL" run bootstrap/cmd/check -- "$f")
    [ "$out" = "ok" ] || { echo "FAIL checker $f: $out"; exit 1; }
done

echo "== differential diagnostics (c1) =="
# tests/diag/ holds files that parse cleanly in both pipelines but fail
# checking — the seed checker's diagnostics must equal the self-hosted
# one's, line for line and in order. The seed driver prefixes each diag
# `file:line:col:` (stripped here); check.oxl reports {kind,msg} only.
# Out of corpus scope by design: parse/lex failures (the [parse]/[lex]
# kinds don't surface through check.oxl's diag list) and cases neither
# checker diagnoses (cc or the runtime catches those downstream — that
# silence is already parity). The self side runs a prebuilt binary:
# `oxl run` would recompile check.oxl's C per fixture, and clang's
# -Wparentheses-equality warnings on the generated code (macOS cc) land
# in the captured output and break the diff.
"$OXL" build bootstrap/cmd/check -o "$scratch/selfcheck$EXE"     || { echo "FAIL selfcheck build"; exit 1; }
for f in tests/diag/*.oxl; do
    # both checkers must reject every fixture (pipefail carries the
    # build's nonzero status through the sed) — and their diagnostics
    # must be identical. A fixture either side accepts is a test bug.
    if seed=$("$SEEDOXL" build "$f" -o "$scratch/diagbin" 2>&1 | sed 's/^[^:]*:[0-9][0-9]*:[0-9][0-9]*: //'); then
        echo "FAIL diag parity $f: seed checker accepted"; exit 1
    fi
    if self=$("$scratch/selfcheck$EXE" "$f" 2>&1); then
        echo "FAIL diag parity $f: self checker accepted"; exit 1
    fi
    if [ "$seed" != "$self" ]; then
        echo "FAIL diag parity $f"
        echo "-- seed --"; printf '%s\n' "$seed"
        echo "-- self --"; printf '%s\n' "$self"
        exit 1
    fi
    # a corpus file neither side diagnoses is a test bug, not parity
    if [ -z "$seed" ] || [ "$self" = "ok" ]; then
        echo "FAIL diag corpus $f: no diagnostics from either checker"; exit 1
    fi
done

echo "== module resolution (m2) =="
# tests/mod/ holds self-contained module trees; each carries its own
# oxl.mod so root discovery never escapes into the repo's module.
# `expected` marks the outcome — `ok` fixtures must build in the seed toolchain and
# print `ok` in the self-hosted checker; error fixtures must be
# rejected by both checkers with byte-identical diagnostics. The
# module cache is pointed at an empty dir so `missing module` is
# deterministic; `tests/mod/widget` and `tests/mod/intmod` are shared
# replace-targets, not cases.
mkdir -p "$scratch/oxlmodcache"
export OXLMODCACHE="$scratch/oxlmodcache"
for f in tests/mod/*/; do
    case "$f" in tests/mod/widget/|tests/mod/intmod/) continue ;; esac
    seed_out=$("$SEEDOXL" build "$f" -o "$scratch/modbin" 2>&1 | sed 's/^[^:]*:[0-9][0-9]*:[0-9][0-9]*: //') && seed_rc=0 || seed_rc=1
    self_out=$("$scratch/selfcheck$EXE" "$f" 2>&1) && self_rc=0 || self_rc=1
    if [ "$(cat "$f/expected")" = ok ]; then
        if [ "$seed_rc" != 0 ]; then
            echo "FAIL module $f: seed checker rejected"; printf '%s\n' "$seed_out"; exit 1
        fi
        if [ "$self_rc" != 0 ] || [ "$self_out" != ok ]; then
            echo "FAIL module $f: self checker rejected"; printf '%s\n' "$self_out"; exit 1
        fi
    else
        if [ "$seed_rc" = 0 ]; then
            echo "FAIL module $f: seed checker accepted"; exit 1
        fi
        if [ "$self_rc" = 0 ]; then
            echo "FAIL module $f: self checker accepted"; exit 1
        fi
        if [ "$seed_out" != "$self_out" ]; then
            echo "FAIL module parity $f"
            echo "-- seed --"; printf '%s\n' "$seed_out"
            echo "-- self --"; printf '%s\n' "$self_out"
            exit 1
        fi
        if [ -z "$seed_out" ]; then
            echo "FAIL module corpus $f: no diagnostics from either checker"; exit 1
        fi
    fi
done
# module-off: a tree with no oxl.mod ancestor resolves std only —
# the local import must fail identically on both checkers.
mkdir -p "$scratch/modoff"
printf 'package main\n\nimport "localpkg"\n\nfn main() {}\n' > "$scratch/modoff/main.oxl"
seed_out=$("$SEEDOXL" build "$scratch/modoff" -o "$scratch/modbin" 2>&1 | sed 's/^[^:]*:[0-9][0-9]*:[0-9][0-9]*: //') && seed_rc=0 || seed_rc=1
self_out=$("$scratch/selfcheck$EXE" "$scratch/modoff" 2>&1) && self_rc=0 || self_rc=1
if [ "$seed_rc" = 0 ] || [ "$self_rc" = 0 ] || [ "$seed_out" != "$self_out" ]; then
    echo "FAIL module-off parity"
    echo "-- seed --"; printf '%s\n' "$seed_out"
    echo "-- self --"; printf '%s\n' "$self_out"
    exit 1
fi
# file mode: a lone oxl.work with no oxl.mod is ignored entirely —
# the `use` dir doesn't even exist, so honoring it would diagnose
# (no std import: the scratch-built selfcheck lives outside the tree
# and its exe-anchored std walk can't reach it)
mkdir -p "$scratch/workfm"
printf 'oxlwork 0.3\nuse ./nonexistent\n' > "$scratch/workfm/oxl.work"
printf 'package main\n\nfn main() {}\n' > "$scratch/workfm/main.oxl"
seed_out=$("$SEEDOXL" build "$scratch/workfm/main.oxl" -o "$scratch/workfmbin" 2>&1 | sed 's/^[^:]*:[0-9][0-9]*:[0-9][0-9]*: //') && seed_rc=0 || seed_rc=1
self_out=$("$scratch/selfcheck$EXE" "$scratch/workfm/main.oxl" 2>&1) && self_rc=0 || self_rc=1
if [ "$seed_rc" != 0 ] || [ "$self_rc" != 0 ] || [ "$self_out" != ok ]; then
    echo "FAIL work-filemode: work file not ignored"
    echo "-- seed --"; printf '%s\n' "$seed_out"
    echo "-- self --"; printf '%s\n' "$self_out"
    exit 1
fi
# dangling oxl.work: stat-style probes see through the link to a missing
# target, so the work file counts as absent and discovery continues —
# identical on both checkers. Windows symlinks aren't reliably creatable
# in CI, so the fixture is POSIX-gated like the get one above.
case "$(uname -s)" in
MINGW*|MSYS*|CYGWIN*) ;;
*)
mkdir -p "$scratch/workdangle/app"
printf 'module local/dangle\noxl 0.3\n' > "$scratch/workdangle/oxl.mod"
printf 'package main\nfn main() {}\n' > "$scratch/workdangle/app/main.oxl"
ln -s "$scratch/workdangle/no-such-target" "$scratch/workdangle/oxl.work"
seed_out=$("$SEEDOXL" build "$scratch/workdangle/app" -o "$scratch/danglebin" 2>&1 | sed 's/^[^:]*:[0-9][0-9]*:[0-9][0-9]*: //') && seed_rc=0 || seed_rc=1
self_out=$("$scratch/selfcheck$EXE" "$scratch/workdangle/app" 2>&1) && self_rc=0 || self_rc=1
if [ "$seed_rc" != 0 ] || [ "$self_rc" != 0 ] || [ "$self_out" != ok ]; then
    echo "FAIL work-dangle: dangling oxl.work not treated as absent"
    echo "-- seed --"; printf '%s\n' "$seed_out"
    echo "-- self --"; printf '%s\n' "$self_out"
    exit 1
fi
;;
esac
# invalid UTF-8 inside a comment: the seed's read_to_string rejects the
# file outright; the self-hosted driver must degrade to the documented
# missing-directive diagnostic — validating before comment stripping,
# not during line parsing. Diagnostics differ by contract, so only the
# self side's text is asserted.
mkdir -p "$scratch/workbadutf8/app"
printf 'module local/badutf8\noxl 0.3\n' > "$scratch/workbadutf8/oxl.mod"
printf 'package main\nfn main() {}\n' > "$scratch/workbadutf8/app/main.oxl"
printf 'oxlwork 0.3\n// \xff\xfe\nuse ./app\n' > "$scratch/workbadutf8/oxl.work"
seed_out=$("$SEEDOXL" build "$scratch/workbadutf8/app" -o "$scratch/utf8bin" 2>&1 | sed 's/^[^:]*:[0-9][0-9]*:[0-9][0-9]*: //') && seed_rc=0 || seed_rc=1
self_out=$("$scratch/selfcheck$EXE" "$scratch/workbadutf8/app" 2>&1) && self_rc=0 || self_rc=1
if [ "$seed_rc" = 0 ] || [ "$self_rc" = 0 ]; then
    echo "FAIL work-badutf8: invalid UTF-8 accepted"
    echo "-- seed --"; printf '%s\n' "$seed_out"
    echo "-- self --"; printf '%s\n' "$self_out"
    exit 1
fi
case "$self_out" in
*"oxl.work: missing oxlwork directive"*) ;;
*) echo "FAIL work-badutf8 self diag: $self_out"; exit 1 ;;
esac
unset OXLMODCACHE

echo "== v1 build list (oxl list -m all) =="
# MVS: depb wins at v1.2.0 (depc's edge), versioned replace supplies
# the dir; depb@v1.0.0 is never fetched and needn't exist. Point the
# cache at scratch so nothing in the user cache can leak a depb
# manifest (or any edge) into selection.
export OXLMODCACHE="$scratch/modcache-empty"
( cd tests/mod/mvs && "$OXL" list -m all ) > "$scratch/mvlist" 2>&1 || { echo "FAIL oxl list rc"; cat "$scratch/mvlist"; exit 1; }
grep -qx 'mvstest' "$scratch/mvlist" || { echo "FAIL list main"; cat "$scratch/mvlist"; exit 1; }
grep -q 'depb v1\.2\.0 => ' "$scratch/mvlist" || { echo "FAIL list depb"; cat "$scratch/mvlist"; exit 1; }
grep -q 'depc v1\.0\.0 => ' "$scratch/mvlist" || { echo "FAIL list depc"; cat "$scratch/mvlist"; exit 1; }

echo "== v2 module cache + oxl get =="
# `oxl get` fetches through git into a sealed, content-addressed slot
# and pins both h1 lines in oxl.sum; every build then verifies the
# cache against those sums. file:// module paths hold ':' which can't
# form a Windows-legal slot name, so the fetch fixture is POSIX-only —
# the verify path itself is platform-clean and covered above.
case "$(uname -s)" in
MINGW*|MSYS*|CYGWIN*) ;;
*)
getwork="$scratch/getwork"
mkdir -p "$getwork/dep/util" "$getwork/app/app" "$getwork/cache"
# upstream module repo: v1.0.0 now, v1.1.0 tagged mid-test
( cd "$getwork/dep" && git init -q . && git config user.email t@t && git config user.name t
  printf 'module file://%s/dep\noxl 0.3\n' "$getwork" > oxl.mod
  printf 'package util\nfn answer() -> int { return 42 }\n' > util/u.oxl
  printf 'root readme\n' > README && printf 'ext readme\n' > README.md
  git add -A && git commit -qm init && git tag v1.0.0 )
printf 'module local/app\noxl 0.3\n' > "$getwork/app/oxl.mod"
printf 'package main\nimport "file://%s/dep/util"\n\nfn main() { println("answer=" + itoa(util.answer())) }\n' "$getwork" > "$getwork/app/app/main.oxl"
( cd "$getwork/app" && OXLMODCACHE="$getwork/cache" "$OXL" get "file://$getwork/dep@v1.0.0" ) > "$getwork/get1" 2>&1 || { echo "FAIL get rc"; cat "$getwork/get1"; exit 1; }
grep -q 'added file://' "$getwork/get1" || { echo "FAIL get report"; cat "$getwork/get1"; exit 1; }
grep -q "require file://$getwork/dep v1.0.0" "$getwork/app/oxl.mod" || { echo "FAIL get require"; cat "$getwork/app/oxl.mod"; exit 1; }
[ "$(grep -c ' h1:' "$getwork/app/oxl.sum")" = 2 ] || { echo "FAIL get sum"; cat "$getwork/app/oxl.sum"; exit 1; }
# slot sealed read-only — find the escaped slot (scratch paths may hold
# case-folding chars, which `!`-escape in the slot name)
slot=$(find "$getwork/cache" -name '*@v1.0.0' -type d)
[ -n "$slot" ] || { echo "FAIL cache slot missing"; exit 1; }
touch "$slot/probe" 2>/dev/null && { echo "FAIL cache not read-only"; exit 1; }
# resolve + run purely from cache — dep repo moved away (network "off")
mv "$getwork/dep" "$getwork/dep-gone"
( cd "$getwork/app" && OXLMODCACHE="$getwork/cache" "$OXL" build app -o "$getwork/appbin" ) || { echo "FAIL offline build"; exit 1; }
[ "$("$getwork/appbin")" = "answer=42" ] || { echo "FAIL offline run"; "$getwork/appbin"; exit 1; }
mv "$getwork/dep-gone" "$getwork/dep"
# tamper a sealed file -> checksum mismatch on BOTH checkers
depf=$(find "$getwork/cache" -name u.oxl -path '*/util/*')
[ -n "$depf" ] || { echo "FAIL cached source missing"; exit 1; }
chmod u+w "$depf" && printf '// tampered\n' >> "$depf" && chmod a-w "$depf"
( cd "$getwork/app" && OXLMODCACHE="$getwork/cache" "$SEEDOXL" build app -o /dev/null ) > "$getwork/tamp.seed" 2>&1 && { echo "FAIL tamper accepted (seed)"; exit 1; }
( cd "$getwork/app" && OXLMODCACHE="$getwork/cache" "$scratch/selfcheck$EXE" app ) > "$getwork/tamp.self" 2>&1 && { echo "FAIL tamper accepted (self)"; exit 1; }
grep -q 'checksum mismatch' "$getwork/tamp.seed" || { echo "FAIL tamper text"; cat "$getwork/tamp.seed"; exit 1; }
diff "$getwork/tamp.seed" "$getwork/tamp.self" >/dev/null || { echo "FAIL tamper parity"; cat "$getwork/tamp.seed" "$getwork/tamp.self"; exit 1; }
# restore: re-get into a fresh cache, then @latest upgrade bumps require+sum
chmod -R u+w "$getwork/cache" 2>/dev/null; rm -rf "$getwork/cache" && mkdir -p "$getwork/cache"
( cd "$getwork/dep" && printf 'package util\nfn answer() -> int { return 43 }\n' > util/u.oxl && git add -A && git commit -qm bump && git tag v1.1.0 )
( cd "$getwork/app" && OXLMODCACHE="$getwork/cache" "$OXL" get "file://$getwork/dep@v1.0.0" >/dev/null && OXLMODCACHE="$getwork/cache" "$OXL" get "file://$getwork/dep@latest" ) > "$getwork/get2" 2>&1 || { echo "FAIL latest rc"; cat "$getwork/get2"; exit 1; }
grep -q 'upgraded file://' "$getwork/get2" || { echo "FAIL upgrade report"; cat "$getwork/get2"; exit 1; }
grep -q "require file://$getwork/dep v1.1.0" "$getwork/app/oxl.mod" || { echo "FAIL upgrade require"; cat "$getwork/app/oxl.mod"; exit 1; }
# v1.0.0's sum lines survive the upgrade — another module may still
# select it via MVS and needs them to verify (4 lines: 2 per version)
[ "$(grep -c ' h1:' "$getwork/app/oxl.sum")" = 4 ] || { echo "FAIL upgrade sum"; cat "$getwork/app/oxl.sum"; exit 1; }
# re-get of the same version hits the sealed slot — validated against
# the archive and reported unchanged
( cd "$getwork/app" && OXLMODCACHE="$getwork/cache" "$OXL" get "file://$getwork/dep@v1.1.0" ) > "$getwork/get3" 2>&1 || { echo "FAIL reget rc"; cat "$getwork/get3"; exit 1; }
grep -q 'unchanged file://' "$getwork/get3" || { echo "FAIL reget report"; cat "$getwork/get3"; exit 1; }
# missing oxl.sum -> missing-entry error, byte-identical
rm "$getwork/app/oxl.sum"
( cd "$getwork/app" && OXLMODCACHE="$getwork/cache" "$SEEDOXL" build app -o /dev/null ) > "$getwork/nosum.seed" 2>&1 && { echo "FAIL missing-sum accepted (seed)"; exit 1; }
( cd "$getwork/app" && OXLMODCACHE="$getwork/cache" "$scratch/selfcheck$EXE" app ) > "$getwork/nosum.self" 2>&1 && { echo "FAIL missing-sum accepted (self)"; exit 1; }
grep -q 'missing oxl.sum entry for module' "$getwork/nosum.seed" || { echo "FAIL missing-sum text"; cat "$getwork/nosum.seed"; exit 1; }
diff "$getwork/nosum.seed" "$getwork/nosum.self" >/dev/null || { echo "FAIL missing-sum parity"; cat "$getwork/nosum.seed" "$getwork/nosum.self"; exit 1; }

echo "== e3 subdirectory-module fetch =="
# one repo may host several modules under subdirectories — the module
# path's repo prefix is discovered by trying progressively shorter
# repos (`file://$getwork/sub/extra` resolves repo `sub` + subdir
# `extra`), each module carries its own `<sub>/v*` tag series, and the
# cache slot + oxl.sum cover only the module subtree.
subwork="$scratch/subwork"
mkdir -p "$subwork/sub/extra/thing" "$subwork/sub/tool" "$subwork/app/app" "$subwork/cache"
( cd "$subwork/sub" && git init -q . && git config user.email t@t && git config user.name t
  printf 'module file://%s/sub/extra\noxl 0.3\n' "$subwork" > extra/oxl.mod
  printf 'package thing\n\nfn val() -> int { return 7 }\n' > extra/thing/thing.oxl
  printf 'package main\nfn main() { println("tool") }\n' > tool/main.oxl
  git add -A && git commit -qm init && git tag extra/v1.0.0 && git tag v1.0.0 )
printf 'module local/subapp\noxl 0.3\n' > "$subwork/app/oxl.mod"
printf 'package main\nimport "file://%s/sub/extra/thing"\n\nfn main() { println("thing=" + itoa(thing.val())) }\n' "$subwork" > "$subwork/app/app/main.oxl"
( cd "$subwork/app" && OXLMODCACHE="$subwork/cache" "$OXL" get "file://$subwork/sub/extra@v1.0.0" ) > "$subwork/get1" 2>&1 || { echo "FAIL subdir get rc"; cat "$subwork/get1"; exit 1; }
grep -q "added file://$subwork/sub/extra@v1.0.0" "$subwork/get1" || { echo "FAIL subdir get report"; cat "$subwork/get1"; exit 1; }
grep -q "require file://$subwork/sub/extra v1.0.0" "$subwork/app/oxl.mod" || { echo "FAIL subdir require"; cat "$subwork/app/oxl.mod"; exit 1; }
[ "$(grep -c ' h1:' "$subwork/app/oxl.sum")" = 2 ] || { echo "FAIL subdir sum"; cat "$subwork/app/oxl.sum"; exit 1; }
# the sealed slot names the module path (…/sub/extra@…), not the repo
slot=$(find "$subwork/cache" -type d -name 'extra@v1.0.0')
[ -n "$slot" ] || { echo "FAIL subdir slot missing"; find "$subwork/cache"; exit 1; }
[ -f "$slot/oxl.mod" ] && [ -f "$slot/thing/thing.oxl" ] && [ ! -e "$slot/tool" ] || { echo "FAIL subdir slot shape"; find "$slot"; exit 1; }
# resolve offline: repo moved away, the app still builds from cache
mv "$subwork/sub" "$subwork/sub-gone"
( cd "$subwork/app" && OXLMODCACHE="$subwork/cache" "$OXL" build app -o "$subwork/appbin" ) || { echo "FAIL subdir offline build"; exit 1; }
[ "$("$subwork/appbin")" = "thing=7" ] || { echo "FAIL subdir run"; "$subwork/appbin"; exit 1; }
mv "$subwork/sub-gone" "$subwork/sub"
# the self-declared-path check refuses the repo prefix — fetching
# `file://$subwork/sub` would clone fine but its root has no oxl.mod
# declaring that path (the module lives at sub/extra)
# the repo root carries a bare v1.0.0 so resolution reaches the
# manifest check — which must refuse: no oxl.mod declares `…/sub` at
# the repo root (the module lives at sub/extra)
( cd "$subwork/app" && OXLMODCACHE="$subwork/cache" "$OXL" get "file://$subwork/sub@v1.0.0" ) > "$subwork/getbad" 2>&1 && { echo "FAIL repo-prefix fetch accepted"; cat "$subwork/getbad"; exit 1; }
grep -q 'no oxl.mod at' "$subwork/getbad" || { echo "FAIL repo-prefix text"; cat "$subwork/getbad"; exit 1; }

echo "== e4 git-backed index =="
# OXLMODINDEX maps module paths to {version,commit,h1,tag} JSONL
# entries: `oxl publish` tags the module + appends the entry, `oxl
# get` resolves the index first and verifies the entry h1 against the
# fetched tree. git's url.insteadOf rewires the example.com path to a
# local repo so the publish→get round-trip stays offline.
ixw="$scratch/idxwork"
mkdir -p "$ixw/idx/index" "$ixw/dep/extra/thing" "$ixw/app/app" "$ixw/cache"
( cd "$ixw/idx" && git init -q . && git config user.email t@t && git config user.name t
  git commit -qm init --allow-empty )
( cd "$ixw/dep" && git init -q . && git config user.email t@t && git config user.name t
  printf 'module example.com/dep/extra\noxl 0.3\n' > extra/oxl.mod
  printf 'package thing\n\nfn val() -> int { return 7 }\n' > extra/thing/thing.oxl
  git add -A && git commit -qm init )
printf '[url "file://%s/"]\n\tinsteadOf = https://example.com/\n' "$ixw" > "$ixw/gitconfig"
printf 'module local/ixapp\noxl 0.3\n' > "$ixw/app/oxl.mod"
printf 'package main\nimport "example.com/dep/extra/thing"\n\nfn main() { println("thing=" + itoa(thing.val())) }\n' > "$ixw/app/app/main.oxl"
# publish: tag + per-package compile + index entry, committed in idx
( cd "$ixw/dep/extra" && GIT_CONFIG_GLOBAL="$ixw/gitconfig" OXLMODINDEX="$ixw/idx" "$OXL" publish v1.0.0 ) > "$ixw/pub" 2>&1 || { echo "FAIL publish rc"; cat "$ixw/pub"; exit 1; }
grep -q 'published example.com/dep/extra v1.0.0' "$ixw/pub" || { echo "FAIL publish report"; cat "$ixw/pub"; exit 1; }
git -C "$ixw/dep" rev-parse --verify -q "refs/tags/extra/v1.0.0^{commit}" >/dev/null || { echo "FAIL publish tag"; exit 1; }
grep -q '"tag":"extra/v1.0.0"' "$ixw/idx/index/example.com/dep/extra.json" || { echo "FAIL index entry"; cat "$ixw/idx/index/example.com/dep/extra.json"; exit 1; }
# an identical republish is already-published; a moved commit refuses
( cd "$ixw/dep/extra" && GIT_CONFIG_GLOBAL="$ixw/gitconfig" OXLMODINDEX="$ixw/idx" "$OXL" publish v1.0.0 ) > "$ixw/pub2" 2>&1 || { echo "FAIL republish rc"; cat "$ixw/pub2"; exit 1; }
grep -q 'already published' "$ixw/pub2" || { echo "FAIL republish report"; cat "$ixw/pub2"; exit 1; }
( cd "$ixw/dep" && printf 'package thing\n\nfn val() -> int { return 8 }\n' > extra/thing/thing.oxl
  git add -A && git commit -qm bump )
( cd "$ixw/dep/extra" && GIT_CONFIG_GLOBAL="$ixw/gitconfig" OXLMODINDEX="$ixw/idx" "$OXL" publish v1.0.0 ) > "$ixw/pub3" 2>&1 && { echo "FAIL moved-tag accepted"; cat "$ixw/pub3"; exit 1; }
grep -q 'refusing to republish' "$ixw/pub3" || { echo "FAIL moved-tag text"; cat "$ixw/pub3"; exit 1; }
( cd "$ixw/dep" && git checkout -q extra/thing/thing.oxl )
# get resolves through the index: pinned commit + h1 verify + install
( cd "$ixw/app" && GIT_CONFIG_GLOBAL="$ixw/gitconfig" OXLMODINDEX="$ixw/idx" OXLMODCACHE="$ixw/cache" "$OXL" get "example.com/dep/extra@v1.0.0" ) > "$ixw/get1" 2>&1 || { echo "FAIL index get rc"; cat "$ixw/get1"; exit 1; }
grep -q 'added example.com/dep/extra@v1.0.0' "$ixw/get1" || { echo "FAIL index get report"; cat "$ixw/get1"; exit 1; }
mv "$ixw/dep" "$ixw/dep-gone"
( cd "$ixw/app" && OXLMODINDEX="$ixw/idx" OXLMODCACHE="$ixw/cache" "$OXL" build app -o "$ixw/appbin" ) || { echo "FAIL index offline build"; exit 1; }
[ "$("$ixw/appbin")" = "thing=7" ] || { echo "FAIL index run"; "$ixw/appbin"; exit 1; }
mv "$ixw/dep-gone" "$ixw/dep"
# an entry the index lacks falls back to direct git (tagged but
# unpublished — the bump commit above)
( cd "$ixw/dep" && git tag extra/v1.1.0 )
( cd "$ixw/app" && GIT_CONFIG_GLOBAL="$ixw/gitconfig" OXLMODINDEX="$ixw/idx" OXLMODCACHE="$ixw/cache" "$OXL" get "example.com/dep/extra@v1.1.0" ) > "$ixw/get2" 2>&1 || { echo "FAIL fallback get rc"; cat "$ixw/get2"; exit 1; }
grep -q 'v1.1.0' "$ixw/get2" || { echo "FAIL fallback get report"; cat "$ixw/get2"; exit 1; }
# a git-URL OXLMODINDEX takes the shallow-clone path — same answer
chmod -R u+w "$ixw/cache" 2>/dev/null; rm -rf "$ixw/cache" && mkdir "$ixw/cache"
sed 's|example.com/dep/extra v1.1.0|example.com/dep/extra v1.0.0|' "$ixw/app/oxl.mod" > "$ixw/app/m.tmp" && mv "$ixw/app/m.tmp" "$ixw/app/oxl.mod" && rm -f "$ixw/app/oxl.sum"
( cd "$ixw/app" && GIT_CONFIG_GLOBAL="$ixw/gitconfig" OXLMODINDEX="file://$ixw/idx" OXLMODCACHE="$ixw/cache" "$OXL" get "example.com/dep/extra@v1.0.0" ) > "$ixw/get3" 2>&1 || { echo "FAIL cloned-index get rc"; cat "$ixw/get3"; exit 1; }
grep -q 'v1.0.0' "$ixw/get3" || { echo "FAIL cloned-index report"; cat "$ixw/get3"; exit 1; }
# a tampered entry h1 hard-fails — never a silent fallback to git
sed 's|"h1":"h1:|"h1":"h2:|' "$ixw/idx/index/example.com/dep/extra.json" > "$ixw/idx/e.tmp" && mv "$ixw/idx/e.tmp" "$ixw/idx/index/example.com/dep/extra.json"
chmod -R u+w "$ixw/cache" 2>/dev/null; rm -rf "$ixw/cache" && mkdir "$ixw/cache" && rm -f "$ixw/app/oxl.sum"
( cd "$ixw/app" && GIT_CONFIG_GLOBAL="$ixw/gitconfig" OXLMODINDEX="$ixw/idx" OXLMODCACHE="$ixw/cache" "$OXL" get "example.com/dep/extra@v1.0.0" ) > "$ixw/get4" 2>&1 && { echo "FAIL tamper accepted"; cat "$ixw/get4"; exit 1; }
grep -q 'does not match the fetched tree' "$ixw/get4" || { echo "FAIL tamper text"; cat "$ixw/get4"; exit 1; }

echo "== e3/e4 seed-driver parity =="
# $OXL is the product driver at this point, so the e3/e4 fixtures
# exercised only it — replay the same three paths under the seed:
# publish (tag + index append), index-first get, and the vanity
# candidate walk that finds the module one directory below a repo.
sw="$scratch/seedx"
mkdir -p "$sw/repo/extra/thing" "$sw/app/app" "$sw/cache" "$sw/idx/index"
( cd "$sw/repo" && git init -q . && git config user.email t@t && git config user.name t
  printf 'module example.com/repo/extra\noxl 0.3\n' > extra/oxl.mod
  printf 'package thing\n\nfn val() -> int { return 5 }\n' > extra/thing/thing.oxl
  git add -A && git commit -qm init )
printf '[url "file://%s/"]\n\tinsteadOf = https://example.com/\n' "$sw" > "$sw/gitconfig"
printf 'module local/seedapp\noxl 0.3\n' > "$sw/app/oxl.mod"
printf 'package main\nimport "example.com/repo/extra/thing"\n\nfn main() { println("thing=" + itoa(thing.val())) }\n' > "$sw/app/app/main.oxl"
( cd "$sw/repo/extra" && GIT_CONFIG_GLOBAL="$sw/gitconfig" OXLMODINDEX="$sw/idx" "$SEEDOXL" publish v1.0.0 ) > "$sw/pub" 2>&1 || { echo "FAIL seed publish rc"; cat "$sw/pub"; exit 1; }
grep -q 'published example.com/repo/extra v1.0.0' "$sw/pub" || { echo "FAIL seed publish report"; cat "$sw/pub"; exit 1; }
grep -q '"h1":"h1:' "$sw/idx/index/example.com/repo/extra.json" || { echo "FAIL seed index entry"; cat "$sw/idx/index/example.com/repo/extra.json"; exit 1; }
( cd "$sw/app" && GIT_CONFIG_GLOBAL="$sw/gitconfig" OXLMODINDEX="$sw/idx" OXLMODCACHE="$sw/cache" "$SEEDOXL" get "example.com/repo/extra@v1.0.0" ) > "$sw/get1" 2>&1 || { echo "FAIL seed index get rc"; cat "$sw/get1"; exit 1; }
grep -q 'added example.com/repo/extra@v1.0.0' "$sw/get1" || { echo "FAIL seed index get report"; cat "$sw/get1"; exit 1; }
mv "$sw/repo" "$sw/repo-gone"
( cd "$sw/app" && OXLMODINDEX="$sw/idx" OXLMODCACHE="$sw/cache" "$SEEDOXL" build app -o "$sw/appbin" ) || { echo "FAIL seed offline build"; exit 1; }
[ "$("$sw/appbin")" = "thing=5" ] || { echo "FAIL seed offline run"; "$sw/appbin"; exit 1; }
mv "$sw/repo-gone" "$sw/repo"
mkdir -p "$sw/multi/lib"
( cd "$sw/multi" && git init -q . && git config user.email t@t && git config user.name t
  printf 'module file://%s/multi/lib\noxl 0.3\n' "$sw" > lib/oxl.mod
  printf 'package lib\n\nfn v() -> int { return 3 }\n' > lib/l.oxl
  git add -A && git commit -qm init && git tag lib/v2.0.0 )
( cd "$sw/app" && GIT_CONFIG_GLOBAL="$sw/gitconfig" OXLMODCACHE="$sw/cache" "$SEEDOXL" get "file://$sw/multi/lib@v2.0.0" ) > "$sw/get2" 2>&1 || { echo "FAIL seed subdir get rc"; cat "$sw/get2"; exit 1; }
grep -q "added file://$sw/multi/lib@v2.0.0" "$sw/get2" || { echo "FAIL seed subdir get report"; cat "$sw/get2"; exit 1; }

echo "== v3 oxl mod commands =="
# tidy syncs the manifest with what the source imports — an
# un-required import is fetched through the same veneer (its dep's
# own requires land as // indirect), a require nothing imports is
# dropped, and oxl.sum is rewritten to the final require set.
# Same file:// POSIX-only constraint as the get fixture.
tv="$scratch/tidywork"
mkdir -p "$tv/dep/util" "$tv/leafpkg/leaf" "$tv/app/app" "$tv/cache" "$tv/locdep/thing"
( cd "$tv/dep" && git init -q . && git config user.email t@t && git config user.name t
  printf 'module file://%s/dep\noxl 0.3\nrequire file://%s/leafpkg v1.0.0\n' "$tv" "$tv" > oxl.mod
  printf 'package util\nimport "file://%s/leafpkg/leaf"\n\nfn answer() -> int { return leaf.leafval() + 41 }\n' "$tv" > util/util.oxl
  git add -A && git commit -qm dep && git tag v1.0.0 )
( cd "$tv/leafpkg" && git init -q . && git config user.email t@t && git config user.name t
  printf 'module file://%s/leafpkg\noxl 0.3\n' "$tv" > oxl.mod
  printf 'package leaf\n\nfn leafval() -> int { return 1 }\n' > leaf/leaf.oxl
  git add -A && git commit -qm leaf && git tag v1.0.0 )
printf 'package thing\n\nfn val() -> int { return 7 }\n' > "$tv/locdep/thing/thing.oxl"
printf 'module file://%s/locdep\noxl 0.3\n' "$tv" > "$tv/locdep/oxl.mod"
printf 'package main\nimport "file://%s/dep/util"\n\nfn main() { println("answer=" + itoa(util.answer())) }\n' "$tv" > "$tv/app/app/main.oxl"
# init: skeleton is a valid manifest, second init refuses
mkdir "$tv/fresh" && ( cd "$tv/fresh" && "$OXL" mod init example.com/fresh ) > "$tv/init1" 2>&1 || { echo "FAIL init rc"; cat "$tv/init1"; exit 1; }
grep -q '^module example.com/fresh$' "$tv/fresh/oxl.mod" || { echo "FAIL init manifest"; cat "$tv/fresh/oxl.mod"; exit 1; }
( cd "$tv/fresh" && "$OXL" mod init example.com/other ) > "$tv/init2" 2>&1 && { echo "FAIL re-init accepted"; cat "$tv/init2"; exit 1; }
grep -q 'already exists' "$tv/init2" || { echo "FAIL re-init text"; cat "$tv/init2"; exit 1; }
# tidy with no requires: fetches dep@latest, leafpkg lands // indirect
( cd "$tv/app" && printf 'module file://%s/app\noxl 0.3\n' "$tv" > oxl.mod
  OXLMODCACHE="$tv/cache" "$OXL" mod tidy ) > "$tv/tidy1" 2>&1 || { echo "FAIL tidy rc"; cat "$tv/tidy1"; exit 1; }
grep -q "added file://$tv/dep@" "$tv/tidy1" || { echo "FAIL tidy fetch"; cat "$tv/tidy1"; exit 1; }
grep -q "file://$tv/leafpkg v1.0.0 // indirect" "$tv/app/oxl.mod" || { echo "FAIL tidy indirect"; cat "$tv/app/oxl.mod"; exit 1; }
[ "$(grep -c ' h1:' "$tv/app/oxl.sum")" = 4 ] || { echo "FAIL tidy sums"; cat "$tv/app/oxl.sum"; exit 1; }
( cd "$tv/app" && OXLMODCACHE="$tv/cache" "$OXL" build app -o "$tv/appbin" ) || { echo "FAIL tidy build"; exit 1; }
[ "$("$tv/appbin")" = "answer=42" ] || { echo "FAIL tidy run"; "$tv/appbin"; exit 1; }
# tidy drops an unused require; second tidy is a no-op (idempotent)
printf 'module file://%s/app\noxl 0.3\n\nrequire (\n\tfile://%s/unused v1.9.9 // stale\n\tfile://%s/dep v1.0.0\n\tfile://%s/leafpkg v1.0.0 // indirect\n)\n' "$tv" "$tv" "$tv" "$tv" > "$tv/app/oxl.mod"
( cd "$tv/app" && OXLMODCACHE="$tv/cache" "$OXL" mod tidy ) > "$tv/tidy2" 2>&1 || { echo "FAIL tidy2 rc"; cat "$tv/tidy2"; exit 1; }
grep -q 'dropped file://' "$tv/tidy2" || { echo "FAIL tidy drop"; cat "$tv/tidy2"; exit 1; }
! grep -q unused "$tv/app/oxl.mod" || { echo "FAIL unused kept"; cat "$tv/app/oxl.mod"; exit 1; }
cp "$tv/app/oxl.mod" "$tv/m.save" && cp "$tv/app/oxl.sum" "$tv/s.save"
( cd "$tv/app" && OXLMODCACHE="$tv/cache" "$OXL" mod tidy ) >/dev/null 2>&1 || { echo "FAIL tidy3 rc"; exit 1; }
diff "$tv/m.save" "$tv/app/oxl.mod" >/dev/null || { echo "FAIL tidy idempotent"; diff "$tv/m.save" "$tv/app/oxl.mod"; exit 1; }
# replace-only coverage: require is added at the placeholder version
printf 'module file://%s/app\noxl 0.3\n\nreplace file://%s/locdep => ../locdep\n' "$tv" "$tv" > "$tv/app/oxl.mod"
rm -f "$tv/app/oxl.sum"
printf 'package main\nimport "file://%s/locdep/thing"\n\nfn main() { println("thing=" + itoa(thing.val())) }\n' "$tv" > "$tv/app/app/main.oxl"
( cd "$tv/app" && OXLMODCACHE="$tv/cache" "$OXL" mod tidy ) > "$tv/tidy4" 2>&1 || { echo "FAIL tidy4 rc"; cat "$tv/tidy4"; exit 1; }
grep -q 'v0.0.0-00010101000000-000000000000' "$tv/app/oxl.mod" || { echo "FAIL replace placeholder"; cat "$tv/app/oxl.mod"; exit 1; }
# verify + list + unresolvable error
( cd "$tv/app" && OXLMODCACHE="$tv/cache" "$OXL" mod verify ) > "$tv/vfy" 2>&1 || { echo "FAIL verify rc"; cat "$tv/vfy"; exit 1; }
grep -q 'all modules verified' "$tv/vfy" || { echo "FAIL verify text"; cat "$tv/vfy"; exit 1; }
( cd "$tv/app" && OXLMODCACHE="$tv/cache" "$OXL" mod list ) > "$tv/mlist" 2>&1 || { echo "FAIL mod list rc"; cat "$tv/mlist"; exit 1; }
grep -q "file://$tv/locdep" "$tv/mlist" || { echo "FAIL list locdep"; cat "$tv/mlist"; exit 1; }
printf 'package main\nimport "file://%s/nosuch/pkg"\n\nfn main() {}\n' "$tv" > "$tv/app/app/main.oxl"
printf 'module file://%s/app\noxl 0.3\n' "$tv" > "$tv/app/oxl.mod" && rm -f "$tv/app/oxl.sum"
( cd "$tv/app" && OXLMODCACHE="$tv/cache" "$OXL" mod tidy ) > "$tv/tidy5" 2>&1 && { echo "FAIL tidy5 accepted"; cat "$tv/tidy5"; exit 1; }
grep -q 'no required module provides package' "$tv/tidy5" || { echo "FAIL tidy5 text"; cat "$tv/tidy5"; exit 1; }
# restore keeps the floor: a require pinned at v1.0.0 whose MVS
# selection is bumped to v1.2.0 by a dependency's own manifest gets
# re-fetched at the SELECTED version — but the require line is a
# minimum and must not move; only the missing sums are rewritten
mkdir -p "$tv/escdep/util" "$tv/esclib/leaf" "$tv/escapp/escapp"
( cd "$tv/esclib" && git init -q . && git config user.email t@t && git config user.name t
  printf 'module file://%s/esclib\noxl 0.3\n' "$tv" > oxl.mod
  printf 'package leaf\n\nfn leafval() -> int { return 1 }\n' > leaf/leaf.oxl
  git add -A && git commit -qm v1 && git tag v1.0.0
  printf 'package leaf\n\nfn leafval() -> int { return 2 }\n' > leaf/leaf.oxl
  git add -A && git commit -qm v2 && git tag v1.2.0 )
( cd "$tv/escdep" && git init -q . && git config user.email t@t && git config user.name t
  printf 'module file://%s/escdep\noxl 0.3\nrequire file://%s/esclib v1.2.0\n' "$tv" "$tv" > oxl.mod
  printf 'package util\nimport "file://%s/esclib/leaf"\n\nfn answer() -> int { return leaf.leafval() + 40 }\n' "$tv" > util/util.oxl
  git add -A && git commit -qm dep && git tag v1.0.0 )
printf 'package main\nimport "file://%s/escdep/util"\nimport "file://%s/esclib/leaf"\n\nfn main() { println("esc=" + itoa(util.answer()) + "/" + itoa(leaf.leafval())) }\n' "$tv" "$tv" > "$tv/escapp/escapp/main.oxl"
( cd "$tv/escapp" && printf 'module file://%s/escapp\noxl 0.3\n\nrequire file://%s/escdep v1.0.0\nrequire file://%s/esclib v1.0.0\n' "$tv" "$tv" "$tv" > oxl.mod
  OXLMODCACHE="$tv/cache" "$OXL" get "file://$tv/escdep@v1.0.0" >/dev/null
  OXLMODCACHE="$tv/cache" "$OXL" get "file://$tv/esclib@v1.0.0" >/dev/null
  OXLMODCACHE="$tv/cache" "$OXL" mod tidy ) > "$tv/tidy6" 2>&1 || { echo "FAIL tidy6 rc"; cat "$tv/tidy6"; exit 1; }
grep -q "file://$tv/esclib v1.0.0" "$tv/escapp/oxl.mod" || { echo "FAIL floor bumped"; cat "$tv/escapp/oxl.mod"; exit 1; }
grep -q "file://$tv/esclib v1.2.0 h1:" "$tv/escapp/oxl.sum" || { echo "FAIL restore sums"; cat "$tv/escapp/oxl.sum"; exit 1; }
( cd "$tv/escapp" && OXLMODCACHE="$tv/cache" "$OXL" build escapp -o "$tv/escbin" ) || { echo "FAIL esc build"; exit 1; }
[ "$("$tv/escbin")" = "esc=42/2" ] || { echo "FAIL esc run"; "$tv/escbin"; exit 1; }
# a dropped require takes its MVS edges with it: raiser is never
# imported but holds libx at v1.2.0 — the version the walk checked.
# Once raiser drops, keeping the v1.0.0 floor would select an
# unfetched version whose leaf package doesn't even exist, so tidy
# bumps the kept floor to the checked selection
mkdir -p "$tv/raiser/r" "$tv/libx" "$tv/rapp/rapp"
( cd "$tv/libx" && git init -q . && git config user.email t@t && git config user.name t
  printf 'module file://%s/libx\noxl 0.3\n' "$tv" > oxl.mod
  git add -A && git commit -qm v1 && git tag v1.0.0
  mkdir -p leaf && printf 'package leaf\n\nfn leafval() -> int { return 5 }\n' > leaf/leaf.oxl
  git add -A && git commit -qm v2 && git tag v1.2.0 )
( cd "$tv/raiser" && git init -q . && git config user.email t@t && git config user.name t
  printf 'module file://%s/raiser\noxl 0.3\nrequire file://%s/libx v1.2.0\n' "$tv" "$tv" > oxl.mod
  printf 'package r\n\nfn rval() -> int { return 0 }\n' > r/r.oxl
  git add -A && git commit -qm raiser && git tag v1.0.0 )
printf 'package main\nimport "file://%s/libx/leaf"\n\nfn main() { println("lv=" + itoa(leaf.leafval())) }\n' "$tv" > "$tv/rapp/rapp/main.oxl"
( cd "$tv/rapp" && printf 'module file://%s/rapp\noxl 0.3\n' "$tv" > oxl.mod
  OXLMODCACHE="$tv/cache" "$OXL" get "file://$tv/raiser@v1.0.0" >/dev/null
  OXLMODCACHE="$tv/cache" "$OXL" get "file://$tv/libx@v1.2.0" >/dev/null
  sed 's|libx v1.2.0|libx v1.0.0|' oxl.mod > oxl.mod.tmp && mv oxl.mod.tmp oxl.mod
  OXLMODCACHE="$tv/cache" "$OXL" mod tidy ) > "$tv/tidy7" 2>&1 || { echo "FAIL tidy7 rc"; cat "$tv/tidy7"; exit 1; }
grep -q 'dropped file://' "$tv/tidy7" || { echo "FAIL tidy7 drop"; cat "$tv/tidy7"; exit 1; }
! grep -q 'raiser' "$tv/rapp/oxl.mod" || { echo "FAIL raiser kept"; cat "$tv/rapp/oxl.mod"; exit 1; }
grep -q "file://$tv/libx v1.2.0" "$tv/rapp/oxl.mod" || { echo "FAIL floor not raised"; cat "$tv/rapp/oxl.mod"; exit 1; }
( cd "$tv/rapp" && OXLMODCACHE="$tv/cache" "$OXL" build rapp -o "$tv/rbin" ) || { echo "FAIL rapp build"; exit 1; }
[ "$("$tv/rbin")" = "lv=5" ] || { echo "FAIL rapp run"; "$tv/rbin"; exit 1; }
# two-hop floor bump: dropping the unused raiser lowers mida below
# its checked selection so its floor moves — but the raised version
# drops the edge that was holding libb at the checked version. A
# single recheck pass would leave libb's floor untouched and write a
# manifest whose build selects a version lacking the package
mkdir -p "$tv/libb" "$tv/mida/a" "$tv/raiser2/r" "$tv/tapp/tapp"
( cd "$tv/libb" && git init -q . && git config user.email t@t && git config user.name t
  printf 'module file://%s/libb\noxl 0.3\n' "$tv" > oxl.mod
  git add -A && git commit -qm v1 && git tag v1.0.0
  mkdir b && printf 'package b\n\nfn bval() -> int { return 3 }\n' > b/b.oxl
  git add -A && git commit -qm v2 && git tag v1.2.0 )
( cd "$tv/mida" && git init -q . && git config user.email t@t && git config user.name t
  printf 'module file://%s/mida\noxl 0.3\nrequire file://%s/libb v1.2.0\n' "$tv" "$tv" > oxl.mod
  printf 'package a\n\nfn aval() -> int { return 10 }\n' > a/a.oxl
  git add -A && git commit -qm v1 && git tag v1.0.0
  printf 'module file://%s/mida\noxl 0.3\n' "$tv" > oxl.mod
  git add -A && git commit -qm v2 && git tag v1.1.0 )
( cd "$tv/raiser2" && git init -q . && git config user.email t@t && git config user.name t
  printf 'module file://%s/raiser2\noxl 0.3\nrequire file://%s/mida v1.1.0\nrequire file://%s/libb v1.2.0\n' "$tv" "$tv" "$tv" > oxl.mod
  printf 'package r\n\nfn rval() -> int { return 0 }\n' > r/r.oxl
  git add -A && git commit -qm r && git tag v1.0.0 )
printf 'package main\nimport "file://%s/mida/a"\nimport "file://%s/libb/b"\n\nfn main() { println("ab=" + itoa(a.aval()) + "/" + itoa(b.bval())) }\n' "$tv" "$tv" > "$tv/tapp/tapp/main.oxl"
( cd "$tv/tapp" && printf 'module file://%s/tapp\noxl 0.3\n' "$tv" > oxl.mod
  OXLMODCACHE="$tv/cache" "$OXL" get "file://$tv/mida@v1.0.0" >/dev/null
  OXLMODCACHE="$tv/cache" "$OXL" get "file://$tv/mida@v1.1.0" >/dev/null
  OXLMODCACHE="$tv/cache" "$OXL" get "file://$tv/libb@v1.0.0" >/dev/null
  OXLMODCACHE="$tv/cache" "$OXL" get "file://$tv/libb@v1.2.0" >/dev/null
  OXLMODCACHE="$tv/cache" "$OXL" get "file://$tv/raiser2@v1.0.0" >/dev/null
  printf 'module file://%s/tapp\noxl 0.3\n\nrequire file://%s/mida v1.0.0\nrequire file://%s/libb v1.0.0\nrequire file://%s/raiser2 v1.0.0\n' "$tv" "$tv" "$tv" "$tv" > oxl.mod
  OXLMODCACHE="$tv/cache" "$OXL" mod tidy ) > "$tv/tidy8" 2>&1 || { echo "FAIL tidy8 rc"; cat "$tv/tidy8"; exit 1; }
grep -q "file://$tv/mida v1.1.0" "$tv/tapp/oxl.mod" || { echo "FAIL tidy8 mida floor"; cat "$tv/tapp/oxl.mod"; exit 1; }
grep -q "file://$tv/libb v1.2.0" "$tv/tapp/oxl.mod" || { echo "FAIL tidy8 libb floor"; cat "$tv/tapp/oxl.mod"; exit 1; }
! grep -q raiser2 "$tv/tapp/oxl.mod" || { echo "FAIL tidy8 raiser kept"; cat "$tv/tapp/oxl.mod"; exit 1; }
( cd "$tv/tapp" && OXLMODCACHE="$tv/cache" "$OXL" build tapp -o "$tv/tbin" ) || { echo "FAIL tidy8 build"; exit 1; }
[ "$("$tv/tbin")" = "ab=10/3" ] || { echo "FAIL tidy8 run"; "$tv/tbin"; exit 1; }
;;
esac

echo "== bootstrap codegen =="
# the self-hosted C emitter must produce working binaries — every
# example plus representative tests, run-and-compared end to end
cgen_dir=$(mktemp -d "$scratch/cgen.XXXXXX")
cgen() {  # cgen <src> <name> — emit C via codegen.oxl, compile it
    "$OXL" run bootstrap/cmd/codegen -- "$1" > "$cgen_dir/$2.c"
    # sqlite only when the emitted C calls it — mirrors emit_and_cc;
    # -l must follow the sources: with --as-needed a library listed
    # before them is dropped and rt.o's sqlite refs go undefined
    def=""; lib=""; net=""
    grep -q 'rt_sqlite_' "$cgen_dir/$2.c" && { def="-DOXL_SQLITE"; lib="$SQLITE_LINK"; }
    # OXL_NET mirrors emit_and_cc's socket scan — without it rt.c's
    # sock section isn't compiled and rt.h hides the prototypes
    grep -qE 'rt_sock_|rt_bind_any|rt_set_(reuseaddr|rcvtimo|sndtimo)|rt_htons|rt_htonl' "$cgen_dir/$2.c" && net="-DOXL_NET"
    # OXL_MATH mirrors emit_and_cc's rt_m_ scan — the -D compiles the
    # wrappers and -lm links them; the lib follows the sources
    mdef=""; mlib=""
    grep -q 'rt_m_' "$cgen_dir/$2.c" && { mdef="-DOXL_MATH"; mlib="$MATH_LIBS"; }
    "$CC" -O2 $THREAD_FLAG -Iruntime $def $net $mdef "$cgen_dir/$2.c" runtime/rt.c $lib $mlib $NET_LIBS -o "$cgen_dir/$2$EXE" || { echo "FAIL codegen cc $1"; exit 1; }
}
for f in examples/hello.oxl examples/features.oxl tests/match.oxl tests/chanbuf.oxl tests/methods.oxl tests/pairfwd.oxl; do
    n=$(basename "$f" .oxl)
    cgen "$f" "$n"
    got=$("$cgen_dir/$n$EXE")
    want=$("$OXL" run "$f")
    [ "$got" = "$want" ] || { echo "FAIL codegen $f"; exit 1; }
done
# cli takes argv — the emitted binary gets them directly (no `--`)
cgen examples/cli/main.oxl cli
got=$("$cgen_dir/cli$EXE" Jesse)
want=$("$OXL" run examples/cli/main.oxl -- Jesse)
[ "$got" = "$want" ] || { echo "FAIL codegen cli: $got"; exit 1; }
# --test mode: scope-wrapped runner like `oxl test`
"$OXL" run bootstrap/cmd/codegen -- --test examples/smoke_test.oxl > "$cgen_dir/t.c"
tnet=""; tmath=""; tmathlib=""
grep -qE 'rt_sock_|rt_bind_any|rt_set_(reuseaddr|rcvtimo|sndtimo)|rt_htons|rt_htonl' "$cgen_dir/t.c" && tnet="-DOXL_NET"
grep -q 'rt_m_' "$cgen_dir/t.c" && { tmath="-DOXL_MATH"; tmathlib="$MATH_LIBS"; }
"$CC" -O2 $THREAD_FLAG -Iruntime $tnet $tmath "$cgen_dir/t.c" runtime/rt.c -DOXL_SQLITE $SQLITE_LINK $tmathlib $NET_LIBS -o "$cgen_dir/t$EXE" || { echo "FAIL codegen cc --test"; exit 1; }
out=$("$cgen_dir/t$EXE")
grep -q "test_chan ... ok" <<<"$out" || { echo "FAIL codegen --test: $out"; exit 1; }
# s3 generics through the self-hosted emitter + cc — the same util
# coverage as `oxl test` above, exercising generic inst emission and
# the rt_m_ math-link scan
"$OXL" run bootstrap/cmd/codegen -- --test tests/util_test.oxl > "$cgen_dir/util.c"
um=""; umlib=""
grep -q 'rt_m_' "$cgen_dir/util.c" && { um="-DOXL_MATH"; umlib="$MATH_LIBS"; }
"$CC" -O2 $THREAD_FLAG -Iruntime $um "$cgen_dir/util.c" runtime/rt.c $umlib $NET_LIBS -o "$cgen_dir/util$EXE" || { echo "FAIL codegen cc util"; exit 1; }
out=$("$cgen_dir/util$EXE")
printf '%s
' "$out" >&2
for t in test_path test_filepath test_cmp test_sort test_slices test_maps test_math test_rand test_utf8; do
    grep -q "$t ... ok" <<<"$out" || { echo "FAIL codegen util: $out"; exit 1; }
done
# s4 enc/hash/crypto through the self-hosted emitter + cc — exercises
# [][]str return emission (csv.read_all) and hash/crypto under -test
for tf in enc hash crypto; do
    "$OXL" run bootstrap/cmd/codegen -- --test "tests/${tf}_test.oxl" > "$cgen_dir/$tf.c"
    "$CC" -O2 $THREAD_FLAG -Iruntime "$cgen_dir/$tf.c" runtime/rt.c $NET_LIBS -o "$cgen_dir/$tf$EXE" || { echo "FAIL codegen cc $tf"; exit 1; }
    "$cgen_dir/$tf$EXE" > "$cgen_dir/$tf.out"
    printf '%s
' "$(cat "$cgen_dir/$tf.out")" >&2
done
for t in test_base64 test_hex test_binary test_csv; do
    grep -q "$t ... ok" "$cgen_dir/enc.out" || { echo "FAIL codegen enc $t"; cat "$cgen_dir/enc.out"; exit 1; }
done
for t in test_fnv test_adler_crc test_incremental; do
    grep -q "$t ... ok" "$cgen_dir/hash.out" || { echo "FAIL codegen hash $t"; cat "$cgen_dir/hash.out"; exit 1; }
done
for t in test_sha256 test_md5 test_hmac; do
    grep -q "$t ... ok" "$cgen_dir/crypto.out" || { echo "FAIL codegen crypto $t"; cat "$cgen_dir/crypto.out"; exit 1; }
done
# s5 regexp through the self-hosted emitter + cc — the NFA engine is
# the heaviest pure-.oxl package (struct slices, closures, utf8)
"$OXL" run bootstrap/cmd/codegen -- --test "tests/regexp_test.oxl" > "$cgen_dir/rx.c"
"$CC" -O2 $THREAD_FLAG -Iruntime "$cgen_dir/rx.c" runtime/rt.c $NET_LIBS -o "$cgen_dir/rx$EXE" || { echo "FAIL codegen cc regexp"; exit 1; }
"$cgen_dir/rx$EXE" > "$cgen_dir/rx.out"
printf '%s
' "$(cat "$cgen_dir/rx.out")" >&2
for t in test_literals test_anchors test_dot test_classes test_posix test_alternation test_quantifiers test_lazy test_escapes test_word_boundary test_utf8 test_findall test_replaceall test_split test_compile_errors test_pathological; do
    grep -q "$t ... ok" "$cgen_dir/rx.out" || { echo "FAIL codegen regexp $t"; cat "$cgen_dir/rx.out"; exit 1; }
done
# http pilot through the self-hosted codegen: the Handler param is an
# iface value, exercising the RtIface/vtab emission end to end
cgen examples/http-crud-sqlite/main.oxl httpsrv_cgen
httpwork=$(mktemp -d "$scratch/httpcgen.XXXXXX")
cp "$cgen_dir/httpsrv_cgen" "$httpwork/"
curl -s -m 1 -o /dev/null localhost:8080/items && { echo "FAIL: :8080 already bound"; exit 1; } || true
(cd "$httpwork"; ./httpsrv_cgen > srv.log 2>&1 & echo $! > srv.pid)
srv_pid=$(cat "$httpwork/srv.pid")
for _ in $(seq 1 50); do
    grep -q "listening" "$httpwork/srv.log" && break
    sleep 0.2
done
grep -q "listening" "$httpwork/srv.log" || { echo "FAIL: cgen server did not bind"; cat "$httpwork/srv.log"; kill $srv_pid 2>/dev/null; exit 1; }
got=$(curl -s -d widget localhost:8080/items)
[ "$got" = '{"created":"widget"}' ] || { echo "FAIL cgen post: $got"; kill $srv_pid 2>/dev/null; exit 1; }
got=$(curl -s localhost:8080/items)
grep -q '"name":"widget"' <<<"$got" || { echo "FAIL cgen get: $got"; kill $srv_pid 2>/dev/null; exit 1; }
kill $srv_pid 2>/dev/null || true
# gui pilot via codegen: emit + link against the shim whenever gtk4 dev
# files exist (same gate as the gui section below — headless compiles,
# DISPLAY additionally selftests)
if command -v pkg-config >/dev/null 2>&1 && pkg-config --exists gtk4 2>/dev/null; then
    "$CC" -O2 $(pkg-config --cflags gtk4) -c extra/gui/gtk/gtk_shim.c -o "$cgen_dir/gui_shim.o"
    "$OXL" run bootstrap/cmd/codegen -- examples/gui-todo/todo.oxl > "$cgen_dir/todo.c"
    todonet=""
    grep -qE 'rt_sock_|rt_bind_any|rt_set_(reuseaddr|rcvtimo|sndtimo)|rt_htons|rt_htonl' "$cgen_dir/todo.c" && todonet="-DOXL_NET"
    "$CC" -O2 $THREAD_FLAG -Iruntime $todonet "$cgen_dir/todo.c" runtime/rt.c "$cgen_dir/gui_shim.o" $(pkg-config --libs gtk4) $NET_LIBS -o "$cgen_dir/todo$EXE" || { echo "FAIL codegen cc gui"; exit 1; }
    if [ -n "${DISPLAY:-}" ]; then
        out=$(with_timeout 30 "$cgen_dir/todo$EXE" --selftest 2>/dev/null)
        grep -q "selftest rows=2" <<<"$out" || { echo "FAIL codegen gui selftest: $out"; exit 1; }
    fi
fi
# bootstrap chain: all four self-host components compiled by the
# self-hosted codegen must behave identically to `oxl run`
cgen "bootstrap/cmd/lex" "self_lexer"
cgen "bootstrap/cmd/parse" "self_parser"
cgen "bootstrap/cmd/check" "self_check"
cgen "bootstrap/cmd/codegen" "self_codegen"
out=$("$cgen_dir/self_lexer$EXE" examples/hello.oxl)
want=$("$OXL" run bootstrap/cmd/lex -- examples/hello.oxl)
[ "$out" = "$want" ] || { echo "FAIL self lexer: $out"; exit 1; }
grep -q "13 tokens" <<<"$out" || { echo "FAIL self lexer tokens: $out"; exit 1; }
out=$("$cgen_dir/self_parser$EXE" examples/features.oxl)
want=$("$OXL" run bootstrap/cmd/parse -- examples/features.oxl)
[ "$out" = "$want" ] || { echo "FAIL self parser"; exit 1; }
printf '%s' "$out" | $PY -c 'import json,sys
d=json.load(sys.stdin)
assert len(d["items"])==7 and not any("skip" in i for i in d["items"]), d' || { echo "FAIL self parser shape"; exit 1; }
out=$("$cgen_dir/self_check$EXE" examples/features.oxl)
[ "$out" = "ok" ] || { echo "FAIL self check: $out"; exit 1; }
# deeper chain: the self-compiled checker's diagnostics must equal the
# `oxl run` interpretation's on a corpus file — transitively the seed's
out=$("$cgen_dir/self_check$EXE" tests/diag/own_use_moved.oxl || true)
want=$("$OXL" run bootstrap/cmd/check -- tests/diag/own_use_moved.oxl || true)
[ "$out" = "$want" ] || { echo "FAIL self check diag: $out vs $want"; exit 1; }
# codegen self-compile emits byte-identical C to the direct emission
"$cgen_dir/self_codegen$EXE" examples/hello.oxl > "$cgen_dir/chain.c"
"$OXL" run bootstrap/cmd/codegen -- examples/hello.oxl > "$cgen_dir/direct.c"
cmp "$cgen_dir/chain.c" "$cgen_dir/direct.c" || { echo "FAIL bootstrap chain"; exit 1; }

echo "== toolchain driver in .oxl (t2) =="
# cmd/oxl is the product driver ported to .oxl — argv dispatch, the
# pkg-args/file-list rule, compile orchestration over bootstrap/check +
# bootstrap/codegen, and the cc invocation itself (emit_and_cc's flag
# order, -DOXL_* feature scans, scratch dirs). The seed builds it once
# under target/ — an in-repo path, so the binary's exe-walk finds std/
# and runtime/ — then seed-vs-self outputs must match on the diag and
# module corpora plus the run/test/list paths. Diagnostics follow the
# c1 convention: the seed's `file:line:col:` prefix is stripped before
# comparison since check.oxl diags carry {kind,msg} only.
# the driver was built (gen1+gen2) and fixpoint-verified in the
# t6 section above — SELFOXL is the product binary
# command surface: bare usage, unknown command, and list's usage error
# are byte-identical stderr + exit codes (2/2/2) — modulo the
# sanctioned W-extension: the self driver documents `[--target js]`
# and `[--html]` on build/run/test, flags the frozen seed can never
# grow (its emit lane is C-only). Scrub exactly those markers off
# the self side before comparing; any other drift still fails.
for inv in "" "bogus" "list"; do
    seed_out=$("$SEEDOXL" $inv 2>&1) && seed_rc=0 || seed_rc=$?
    self_out=$("$SELFOXL" $inv 2>&1) && self_rc=0 || self_rc=$?
    self_out=$(printf '%s\n' "$self_out" | sed 's/ \[--target js\]//g; s/ \[--html\]//g')
    if [ "$seed_out" != "$self_out" ] || [ "$seed_rc" != "$self_rc" ]; then
        echo "FAIL driver parity: \`oxl $inv\`"
        echo "-- seed ($seed_rc) --"; printf '%s\n' "$seed_out"
        echo "-- self ($self_rc) --"; printf '%s\n' "$self_out"
        exit 1
    fi
done
# the diag corpus through the whole driver pipeline (load + check +
# emit + cc): every fixture must fail identically on both drivers —
# same text, same exit code, and neither side may accept
for f in tests/diag/*.oxl; do
    seed_out=$("$SEEDOXL" build "$f" -o "$scratch/drvbin" 2>&1 | sed 's/^[^:]*:[0-9][0-9]*:[0-9][0-9]*: //') && seed_rc=0 || seed_rc=$?
    self_out=$("$SELFOXL" build "$f" -o "$scratch/drvbin2" 2>&1) && self_rc=0 || self_rc=$?
    if [ "$seed_rc" = 0 ] || [ "$self_rc" = 0 ]; then
        echo "FAIL driver corpus $f: a driver accepted"; exit 1
    fi
    if [ "$seed_out" != "$self_out" ] || [ "$seed_rc" != "$self_rc" ]; then
        echo "FAIL driver parity $f"
        echo "-- seed --"; printf '%s\n' "$seed_out"
        echo "-- self --"; printf '%s\n' "$self_out"
        exit 1
    fi
done
# module modes: the m2 fixture walk through the full driver — ok
# fixtures must build on both sides, error fixtures must fail with
# identical diagnostics (empty module cache keeps `missing module`
# deterministic, same as m2)
mkdir -p "$scratch/oxlmodcache-drv"
export OXLMODCACHE="$scratch/oxlmodcache-drv"
for f in tests/mod/*/; do
    case "$f" in tests/mod/widget/|tests/mod/intmod/) continue ;; esac
    seed_out=$("$SEEDOXL" build "$f" -o "$scratch/drvbin" 2>&1 | sed 's/^[^:]*:[0-9][0-9]*:[0-9][0-9]*: //') && seed_rc=0 || seed_rc=$?
    self_out=$("$SELFOXL" build "$f" -o "$scratch/drvbin2" 2>&1) && self_rc=0 || self_rc=$?
    if [ "$(cat "$f/expected")" = ok ]; then
        if [ "$seed_rc" != 0 ] || [ "$self_rc" != 0 ]; then
            echo "FAIL driver module $f: a driver rejected (seed=$seed_rc self=$self_rc)"
            echo "-- seed --"; printf '%s\n' "$seed_out"
            echo "-- self --"; printf '%s\n' "$self_out"
            exit 1
        fi
    else
        if [ "$seed_rc" = 0 ] || [ "$self_rc" = 0 ]; then
            echo "FAIL driver module corpus $f: a driver accepted"; exit 1
        fi
        if [ "$seed_out" != "$self_out" ] || [ "$seed_rc" != "$self_rc" ]; then
            echo "FAIL driver module parity $f"
            echo "-- seed --"; printf '%s\n' "$seed_out"
            echo "-- self --"; printf '%s\n' "$self_out"
            exit 1
        fi
    fi
done
# `oxl list -m all` — the MVS build list with replace markers —
# byte-identical stdout from the module root
( cd tests/mod/mvs && "$SEEDOXL" list -m all ) > "$scratch/mlist.seed" 2>&1 || { echo "FAIL driver list seed rc"; cat "$scratch/mlist.seed"; exit 1; }
( cd tests/mod/mvs && "$SELFOXL" list -m all ) > "$scratch/mlist.self" 2>&1 || { echo "FAIL driver list self rc"; cat "$scratch/mlist.self"; exit 1; }
diff "$scratch/mlist.seed" "$scratch/mlist.self" >/dev/null || { echo "FAIL driver list parity"; cat "$scratch/mlist.seed" "$scratch/mlist.self"; exit 1; }
# `not a module` is the driver's own diagnostic, emitted from a cwd
# with no oxl.mod ancestor (scratch is outside the repo)
( cd "$scratch" && "$SEEDOXL" list -m all ) > "$scratch/nmod.seed" 2>&1 && { echo "FAIL driver list seed accepted"; exit 1; } || true
( cd "$scratch" && "$SELFOXL" list -m all ) > "$scratch/nmod.self" 2>&1 && { echo "FAIL driver list self accepted"; exit 1; } || true
diff "$scratch/nmod.seed" "$scratch/nmod.self" >/dev/null || { echo "FAIL driver not-a-module parity"; cat "$scratch/nmod.seed" "$scratch/nmod.self"; exit 1; }
unset OXLMODCACHE
# file-list mode: a multi-file program runs identically, and the
# one-directory rule reports identically
mkdir -p "$scratch/flist" "$scratch/flother"
printf 'package main\nfn helper() -> int { return 7 }\n' > "$scratch/flist/h.oxl"
printf 'package main\nfn main() { println("flist=" + itoa(helper())) }\n' > "$scratch/flist/m.oxl"
printf 'package main\nfn main() {}\n' > "$scratch/flother/o.oxl"
seed_out=$("$SEEDOXL" run "$scratch/flist/m.oxl" "$scratch/flist/h.oxl" 2>&1) && seed_rc=0 || seed_rc=$?
self_out=$("$SELFOXL" run "$scratch/flist/m.oxl" "$scratch/flist/h.oxl" 2>&1) && self_rc=0 || self_rc=$?
if [ "$seed_out" != "$self_out" ] || [ "$seed_rc" != "$self_rc" ]; then
    echo "FAIL driver file-list parity"
    echo "-- seed ($seed_rc) --"; printf '%s\n' "$seed_out"
    echo "-- self ($self_rc) --"; printf '%s\n' "$self_out"
    exit 1
fi
seed_out=$("$SEEDOXL" build "$scratch/flist/m.oxl" "$scratch/flother/o.oxl" -o "$scratch/flbin" 2>&1 | sed 's/^[^:]*:[0-9][0-9]*:[0-9][0-9]*: //') && seed_rc=0 || seed_rc=$?
self_out=$("$SELFOXL" build "$scratch/flist/m.oxl" "$scratch/flother/o.oxl" -o "$scratch/flbin2" 2>&1) && self_rc=0 || self_rc=$?
if [ "$seed_out" != "$self_out" ] || [ "$seed_rc" != "$self_rc" ]; then
    echo "FAIL driver one-directory parity"
    echo "-- seed ($seed_rc) --"; printf '%s\n' "$seed_out"
    echo "-- self ($self_rc) --"; printf '%s\n' "$self_out"
    exit 1
fi
# run/test child-status passthrough: an exit code propagates
# losslessly, and a trapping child reports 1 on both drivers (the
# seed's status->code maps signal death to None -> 1)
printf 'package main\nfn main() { exit(42) }\n' > "$scratch/e42.oxl"
"$SEEDOXL" run "$scratch/e42.oxl" >/dev/null 2>&1 && seed_rc=0 || seed_rc=$?
"$SELFOXL" run "$scratch/e42.oxl" >/dev/null 2>&1 && self_rc=0 || self_rc=$?
[ "$seed_rc" = "$self_rc" ] || { echo "FAIL driver exit passthrough: $seed_rc vs $self_rc"; exit 1; }
printf 'package main\nfn main() { assert(false) }\n' > "$scratch/trap.oxl"
"$SEEDOXL" run "$scratch/trap.oxl" >/dev/null 2>&1 && seed_rc=0 || seed_rc=$?
"$SELFOXL" run "$scratch/trap.oxl" >/dev/null 2>&1 && self_rc=0 || self_rc=$?
[ "$seed_rc" = "$self_rc" ] || { echo "FAIL driver trap parity: $seed_rc vs $self_rc"; exit 1; }
# the self driver covers the suite's core sections end to end —
# build, run with args, test, and the sqlite/net feature gates
out=$("$SELFOXL" run examples/hello.oxl)
[ "$out" = "hello, world" ] || { echo "FAIL self driver hello: $out"; exit 1; }
out=$("$SELFOXL" run examples/features.oxl)
[ "$(tail -1 <<<"$out")" = "done" ] || { echo "FAIL self driver features"; exit 1; }
out=$("$SELFOXL" run examples/cli/main.oxl -- Jesse)
grep -q "hello, Jesse" <<<"$out" || { echo "FAIL self driver cli"; exit 1; }
out=$("$SELFOXL" test examples/smoke_test.oxl)
grep -q "test_chan ... ok" <<<"$out" || { echo "FAIL self driver test: $out"; exit 1; }
out=$("$SELFOXL" test tests/stdlib_test.oxl)
grep -q "test_loops ... ok" <<<"$out" || { echo "FAIL self driver stdlib: $out"; exit 1; }
"$SELFOXL" build examples/http-crud-sqlite/main.oxl -o "$scratch/httpsrv-self$EXE" || { echo "FAIL self driver sqlite+net build"; exit 1; }
# the interpreted path too — the seed runs cmd/oxl itself (its
# std/runtime resolution then anchors at the compiled package's tree)
out=$("$SEEDOXL" run cmd/oxl -- run examples/hello.oxl)
[ "$out" = "hello, world" ] || { echo "FAIL oxl-run driver hello: $out"; exit 1; }

echo "== toolchain driver fmt + doc (t3) =="
# `fmt --check` under the self driver across the same corpus the
# seed covers below — every tracked .oxl is canonically formatted,
# so both drivers must agree the tree is clean
if ! "$SELFOXL" fmt --check $(find std bootstrap tests examples cmd -name '*.oxl' | sort); then
    echo "FAIL self driver fmt --check: corpus not canonical"; exit 1
fi
# a valid but unformatted file must fail --check with exit 1 and the
# `not formatted` diagnostic — a crash or parse reject would also exit
# nonzero, so assert both the code and the message
printf 'package main\n\nfn add(a:int,b:int) -> int {\n  return a+b\n}\n' > "$scratch/unfmt.oxl"
rc=0
"$SELFOXL" fmt --check "$scratch/unfmt.oxl" >"$scratch/unfmt.out" 2>&1 || rc=$?
[ "$rc" -eq 1 ] || { echo "FAIL fmt --check: expected exit 1, got $rc"; cat "$scratch/unfmt.out"; exit 1; }
grep -q "not formatted" "$scratch/unfmt.out" || { echo "FAIL fmt --check missing diagnostic"; cat "$scratch/unfmt.out"; exit 1; }
# fmt -w stages then renames: the replacement must carry the source's
# owner/group and access mode — not the creator's — and must still
# succeed on a read-only source. POSIX-only; Windows maps this
# through ACLs the suite can't stat the same way.
case "$(uname -s)" in
MINGW*|MSYS*|CYGWIN*) ;;
*)
cp "$scratch/unfmt.oxl" "$scratch/modekeep.oxl"
chmod 640 "$scratch/modekeep.oxl"
"$SELFOXL" fmt -w "$scratch/modekeep.oxl" || { echo "FAIL fmt -w modekeep"; exit 1; }
[ -n "$(find "$scratch/modekeep.oxl" -perm 0640 -print)" ] || { echo "FAIL fmt -w: mode not preserved"; stat "$scratch/modekeep.oxl"; exit 1; }
grep -q 'a + b' "$scratch/modekeep.oxl" || { echo "FAIL fmt -w: not formatted"; cat "$scratch/modekeep.oxl"; exit 1; }
printf 'package main\n\nfn z(a:int)->int{return a}\n' > "$scratch/ro.oxl"
chmod 444 "$scratch/ro.oxl"
"$SELFOXL" fmt -w "$scratch/ro.oxl" || { echo "FAIL fmt -w read-only source"; exit 1; }
[ -n "$(find "$scratch/ro.oxl" -perm 0444 -print)" ] || { echo "FAIL fmt -w: read-only mode not preserved"; stat "$scratch/ro.oxl"; exit 1; }
;;
esac
# fmt output parity: the port must reproduce the seed's output
# byte-for-byte on a corpus slice — round-trip, not a reformat
for f in std/strings/strings.oxl std/io/io.oxl std/errors/errors.oxl \
         bootstrap/parser/parser.oxl bootstrap/check/check.oxl \
         bootstrap/codegen/codegen.oxl std/net/http/http.oxl \
         cmd/oxl/main.oxl cmd/oxl/fmt.oxl examples/hello.oxl tests/util_test.oxl; do
    "$SEEDOXL" fmt "$f" > "$scratch/fmt.seed" 2>&1 || { echo "FAIL seed fmt $f"; cat "$scratch/fmt.seed"; exit 1; }
    "$SELFOXL" fmt "$f" > "$scratch/fmt.self" 2>&1 || { echo "FAIL self fmt $f"; cat "$scratch/fmt.self"; exit 1; }
    diff "$scratch/fmt.seed" "$scratch/fmt.self" >/dev/null || { echo "FAIL driver fmt parity $f"; diff "$scratch/fmt.seed" "$scratch/fmt.self" | head -20; exit 1; }
done
# idempotent: formatting a formatted file is a no-op — a second
# pass must not move anything
"$SELFOXL" fmt cmd/oxl/fmt.oxl > "$scratch/fmt1.oxl"
"$SELFOXL" fmt "$scratch/fmt1.oxl" > "$scratch/fmt2.oxl"
diff "$scratch/fmt1.oxl" "$scratch/fmt2.oxl" >/dev/null || { echo "FAIL fmt idempotency"; exit 1; }
# `doc` output is byte-identical vs the seed on the std corpus
for f in std/strings/strings.oxl std/io/io.oxl std/errors/errors.oxl std/bytes/bytes.oxl; do
    "$SEEDOXL" doc "$f" > "$scratch/doc.seed" 2>&1 || { echo "FAIL seed doc $f"; exit 1; }
    "$SELFOXL" doc "$f" > "$scratch/doc.self" 2>&1 || { echo "FAIL self doc $f"; exit 1; }
    diff "$scratch/doc.seed" "$scratch/doc.self" >/dev/null || { echo "FAIL driver doc parity $f"; diff "$scratch/doc.seed" "$scratch/doc.self" | head -20; exit 1; }
done

echo "== v4 self driver get/mod =="
# the .oxl driver's get/mod run the same git veneer + sealed
# content-addressed cache + manifest rewrite the seed driver does —
# replay the v2/v3 fixtures end to end under $SELFOXL. POSIX-only for
# the same reason: file:// module paths can't form Windows slot names.
case "$(uname -s)" in
MINGW*|MSYS*|CYGWIN*) ;;
*)
sw="$scratch/sgetwork"
mkdir -p "$sw/dep/util" "$sw/app/app" "$sw/cache"
( cd "$sw/dep" && git init -q . && git config user.email t@t && git config user.name t
  printf 'module file://%s/dep\noxl 0.3\n' "$sw" > oxl.mod
  printf 'package util\nfn answer() -> int { return 42 }\n' > util/u.oxl
  git add -A && git commit -qm init && git tag v1.0.0
  printf 'package util\nfn answer() -> int { return 43 }\n' > util/u.oxl
  git add -A && git commit -qm bump && git tag v1.1.0 )
printf 'module local/app\noxl 0.3\n' > "$sw/app/oxl.mod"
printf 'package main\nimport "file://%s/dep/util"\n\nfn main() { println("answer=" + itoa(util.answer())) }\n' "$sw" > "$sw/app/app/main.oxl"
# get pins require + both h1 lines and seals the slot read-only
( cd "$sw/app" && OXLMODCACHE="$sw/cache" "$SELFOXL" get "file://$sw/dep@v1.0.0" ) > "$sw/get1" 2>&1 || { echo "FAIL self get rc"; cat "$sw/get1"; exit 1; }
grep -q 'added file://' "$sw/get1" || { echo "FAIL self get report"; cat "$sw/get1"; exit 1; }
grep -q "require file://$sw/dep v1.0.0" "$sw/app/oxl.mod" || { echo "FAIL self get require"; cat "$sw/app/oxl.mod"; exit 1; }
[ "$(grep -c ' h1:' "$sw/app/oxl.sum")" = 2 ] || { echo "FAIL self get sum"; cat "$sw/app/oxl.sum"; exit 1; }
slot=$(find "$sw/cache" -name '*@v1.0.0' -type d)
[ -n "$slot" ] || { echo "FAIL self cache slot missing"; exit 1; }
touch "$slot/probe" 2>/dev/null && { echo "FAIL self cache not read-only"; exit 1; }
# resolve + run purely from the sealed slot (dep repo moved away)
mv "$sw/dep" "$sw/dep-gone"
( cd "$sw/app" && OXLMODCACHE="$sw/cache" "$SELFOXL" build app -o "$sw/appbin" ) || { echo "FAIL self offline build"; exit 1; }
[ "$("$sw/appbin")" = "answer=42" ] || { echo "FAIL self offline run"; "$sw/appbin"; exit 1; }
mv "$sw/dep-gone" "$sw/dep"
# @latest upgrade rewrites require+sums; re-get reports unchanged
( cd "$sw/app" && OXLMODCACHE="$sw/cache" "$SELFOXL" get "file://$sw/dep@latest" ) > "$sw/get2" 2>&1 || { echo "FAIL self latest rc"; cat "$sw/get2"; exit 1; }
grep -q 'upgraded file://' "$sw/get2" || { echo "FAIL self upgrade"; cat "$sw/get2"; exit 1; }
grep -q "require file://$sw/dep v1.1.0" "$sw/app/oxl.mod" || { echo "FAIL self upgrade require"; cat "$sw/app/oxl.mod"; exit 1; }
( cd "$sw/app" && OXLMODCACHE="$sw/cache" "$SELFOXL" get "file://$sw/dep@v1.1.0" ) > "$sw/get3" 2>&1 || { echo "FAIL self reget rc"; cat "$sw/get3"; exit 1; }
grep -q 'unchanged file://' "$sw/get3" || { echo "FAIL self reget"; cat "$sw/get3"; exit 1; }
# mod init writes a skeleton; a second init refuses to overwrite
mkdir "$sw/fresh" && ( cd "$sw/fresh" && "$SELFOXL" mod init example.com/fresh ) > "$sw/init1" 2>&1 || { echo "FAIL self init rc"; cat "$sw/init1"; exit 1; }
grep -q '^module example.com/fresh$' "$sw/fresh/oxl.mod" || { echo "FAIL self init manifest"; cat "$sw/fresh/oxl.mod"; exit 1; }
( cd "$sw/fresh" && "$SELFOXL" mod init example.com/other ) > "$sw/init2" 2>&1 && { echo "FAIL self re-init accepted"; cat "$sw/init2"; exit 1; }
grep -q 'already exists' "$sw/init2" || { echo "FAIL self re-init text"; cat "$sw/init2"; exit 1; }
# mod tidy: fetch the un-required provider, dep's own require lands
# // indirect, sums rewritten; a second tidy is a no-op
tv="$scratch/stidywork"
mkdir -p "$tv/dep/util" "$tv/leafpkg/leaf" "$tv/app/app" "$tv/cache"
( cd "$tv/dep" && git init -q . && git config user.email t@t && git config user.name t
  printf 'module file://%s/dep\noxl 0.3\nrequire file://%s/leafpkg v1.0.0\n' "$tv" "$tv" > oxl.mod
  printf 'package util\nimport "file://%s/leafpkg/leaf"\n\nfn answer() -> int { return leaf.leafval() + 41 }\n' "$tv" > util/util.oxl
  git add -A && git commit -qm dep && git tag v1.0.0 )
( cd "$tv/leafpkg" && git init -q . && git config user.email t@t && git config user.name t
  printf 'module file://%s/leafpkg\noxl 0.3\n' "$tv" > oxl.mod
  printf 'package leaf\n\nfn leafval() -> int { return 1 }\n' > leaf/leaf.oxl
  git add -A && git commit -qm leaf && git tag v1.0.0 )
printf 'package main\nimport "file://%s/dep/util"\n\nfn main() { println("answer=" + itoa(util.answer())) }\n' "$tv" > "$tv/app/app/main.oxl"
( cd "$tv/app" && printf 'module file://%s/app\noxl 0.3\n' "$tv" > oxl.mod
  OXLMODCACHE="$tv/cache" "$SELFOXL" mod tidy ) > "$tv/tidy1" 2>&1 || { echo "FAIL self tidy rc"; cat "$tv/tidy1"; exit 1; }
grep -q "added file://$tv/dep@" "$tv/tidy1" || { echo "FAIL self tidy fetch"; cat "$tv/tidy1"; exit 1; }
grep -q "file://$tv/leafpkg v1.0.0 // indirect" "$tv/app/oxl.mod" || { echo "FAIL self tidy indirect"; cat "$tv/app/oxl.mod"; exit 1; }
[ "$(grep -c ' h1:' "$tv/app/oxl.sum")" = 4 ] || { echo "FAIL self tidy sums"; cat "$tv/app/oxl.sum"; exit 1; }
( cd "$tv/app" && OXLMODCACHE="$tv/cache" "$SELFOXL" build app -o "$tv/appbin" ) || { echo "FAIL self tidy build"; exit 1; }
[ "$("$tv/appbin")" = "answer=42" ] || { echo "FAIL self tidy run"; "$tv/appbin"; exit 1; }
cp "$tv/app/oxl.mod" "$tv/m.save" && cp "$tv/app/oxl.sum" "$tv/s.save"
( cd "$tv/app" && OXLMODCACHE="$tv/cache" "$SELFOXL" mod tidy ) >/dev/null 2>&1 || { echo "FAIL self tidy2 rc"; exit 1; }
diff "$tv/m.save" "$tv/app/oxl.mod" >/dev/null || { echo "FAIL self tidy idempotent"; diff "$tv/m.save" "$tv/app/oxl.mod"; exit 1; }
( cd "$tv/app" && OXLMODCACHE="$tv/cache" "$SELFOXL" mod verify ) > "$tv/vfy" 2>&1 || { echo "FAIL self verify rc"; cat "$tv/vfy"; exit 1; }
grep -q 'all modules verified' "$tv/vfy" || { echo "FAIL self verify text"; cat "$tv/vfy"; exit 1; }
( cd "$tv/app" && OXLMODCACHE="$tv/cache" "$SELFOXL" mod list ) > "$tv/mlist" 2>&1 || { echo "FAIL self mod list rc"; cat "$tv/mlist"; exit 1; }
grep -q "file://$tv/leafpkg v1.0.0" "$tv/mlist" || { echo "FAIL self list leafpkg"; cat "$tv/mlist"; exit 1; }
# unresolvable import reports the get hint with a nonzero exit
printf 'package main\nimport "file://%s/nosuch/pkg"\n\nfn main() {}\n' "$tv" > "$tv/app/app/main.oxl"
( cd "$tv/app" && printf 'module file://%s/app\noxl 0.3\n' "$tv" > oxl.mod && rm -f oxl.sum
  OXLMODCACHE="$tv/cache" "$SELFOXL" mod tidy ) > "$tv/tidy5" 2>&1 && { echo "FAIL self tidy5 accepted"; cat "$tv/tidy5"; exit 1; }
grep -q 'no required module provides package' "$tv/tidy5" || { echo "FAIL self tidy5 text"; cat "$tv/tidy5"; exit 1; }
;;
esac

echo "== extras: workspace module + tidy interplay (e2) =="
# root oxl.work `use ./extra` resolves github.com/oxidean/oxl/extra
# imports to the local tree — the require documents the published
# floor for consumers outside the workspace. The test consumes the
# package through its module path.
out=$("$OXL" test tests/extra_testutil.oxl)
for t in test_tempdir test_helpers test_err_asserts; do
    grep -q "$t ... ok" <<<"$out" || { echo "FAIL extra: $out"; exit 1; }
done
# the extra module also builds standalone from its own root
# a library package compile-checks through `oxl test` (its driver
# main means no package-main requirement — same path the extras
# release gate runs)
( cd extra && "$OXL" test testutil ) || { echo "FAIL extra module build"; exit 1; }
# a `use`d+`require`d module: tidy keeps the require without a fetch,
# verify needs no cache slot, and no oxl.sum lines are written for it
wsw="$scratch/wsuse"
mkdir -p "$wsw/extra/thing" "$wsw/app/app"
printf 'module example.com/ws/extra\noxl 0.3\n' > "$wsw/extra/oxl.mod"
printf 'package thing\n\nfn val() -> int { return 7 }\n' > "$wsw/extra/thing/thing.oxl"
printf 'module example.com/app\noxl 0.3\n\nrequire example.com/ws/extra v0.0.0\n' > "$wsw/app/oxl.mod"
printf 'oxlwork 0.3\n\nuse ../extra\n' > "$wsw/app/oxl.work"
printf 'package main\nimport "example.com/ws/extra/thing"\n\nfn main() { println("thing=" + itoa(thing.val())) }\n' > "$wsw/app/app/main.oxl"
( cd "$wsw/app" && "$OXL" mod tidy ) > "$wsw/tidy" 2>&1 || { echo "FAIL ws tidy rc"; cat "$wsw/tidy"; exit 1; }
grep -q 'require example.com/ws/extra v0.0.0' "$wsw/app/oxl.mod" || { echo "FAIL ws tidy require"; cat "$wsw/app/oxl.mod"; exit 1; }
if [ -f "$wsw/app/oxl.sum" ]; then
    ! grep -q 'ws/extra' "$wsw/app/oxl.sum" || { echo "FAIL ws sum written"; cat "$wsw/app/oxl.sum"; exit 1; }
fi
( cd "$wsw/app" && "$OXL" mod verify ) > "$wsw/vfy" 2>&1 || { echo "FAIL ws verify rc"; cat "$wsw/vfy"; exit 1; }
grep -q 'all modules verified' "$wsw/vfy" || { echo "FAIL ws verify text"; cat "$wsw/vfy"; exit 1; }
( cd "$wsw/app" && "$OXL" build app -o "$wsw/appbin" ) || { echo "FAIL ws build"; exit 1; }
[ "$("$wsw/appbin")" = "thing=7" ] || { echo "FAIL ws run"; "$wsw/appbin"; exit 1; }
# seed driver parity on the same fixture
( cd "$wsw/app" && "$SEEDOXL" mod tidy ) > "$wsw/stidy" 2>&1 || { echo "FAIL seed ws tidy rc"; cat "$wsw/stidy"; exit 1; }
grep -q 'require example.com/ws/extra v0.0.0' "$wsw/app/oxl.mod" || { echo "FAIL seed ws tidy require"; cat "$wsw/app/oxl.mod"; exit 1; }
( cd "$wsw/app" && "$SEEDOXL" mod verify ) > "$wsw/svfy" 2>&1 || { echo "FAIL seed ws verify rc"; cat "$wsw/svfy"; exit 1; }
grep -q 'all modules verified' "$wsw/svfy" || { echo "FAIL seed ws verify text"; cat "$wsw/svfy"; exit 1; }

echo "== a1 coroutine scale =="
# spec bar: 10k spawned tasks parked on recv must cost heap frames,
# not OS threads — assert on the per-task delta over this binary's
# own zero-task baseline. An absolute cap can't separate task memory
# from the platform's process baseline (Windows carries ~4 MB of
# CRT/winsock/heap before main runs vs ~2 MB on POSIX).
"$OXL" build tests/conc_scale.oxl -o "$scratch/conc_scale$EXE" || {
    echo "FAIL conc_scale: compile failed"; exit 1; }
"$scratch/conc_scale$EXE" 0 0 2500 > "$scratch/base.out" 2>&1 &
base_pid=$!
base_rss=0
# sample before the liveness gate: a just-spawned native child can lag
# the git-bash process table on Windows, so a leading kill -0 can skip
# the whole window and leave base_rss empty on a healthy run
for try in 1 2; do
    while :; do
        r=$(rss_kb $base_pid || true)
        [ -n "$r" ] && [ "$r" -gt "$base_rss" ] && base_rss=$r
        kill -0 $base_pid 2>/dev/null || break
        sleep 0.2
    done
    wait $base_pid 2>/dev/null || true
    # retry only the observed flake: the run completed (printed done)
    # yet yielded no sample — a spawn-registration race, not a crash;
    # relaunch only while an iteration remains to consume it
    if [ "$base_rss" -gt 0 ] || [ "$(tail -1 "$scratch/base.out")" != "done" ] || [ "$try" -eq 2 ]; then
        break
    fi
    "$scratch/conc_scale$EXE" 0 0 2500 > "$scratch/base.out" 2>&1 &
    base_pid=$!
done
"$scratch/conc_scale$EXE" 10000 1 2500 > "$scratch/scale.out" 2>&1 &
scale_pid=$!
# watchdog: a wedged channel/task regression must not hang the whole
# suite — kill the measured binary at the deadline; the "done" check
# below then reports the failure instead of blocking forever
( sleep 120; kill -KILL $scale_pid 2>/dev/null;   echo "watchdog: killed after 120s" >> "$scratch/scale.out" ) >/dev/null 2>&1 &
scale_dog=$!
# peak matters, not a point sample: poll RSS until exit and take the
# max. `ps -o rss=` is the portable form (/proc is Linux-only).
# The process can exit between kill -0 and ps — under pipefail a failed
# ps makes the substitution nonzero and `set -e` would abort the suite
# before `wait` can report the real result; `|| true` pins it.
rss=0
while :; do
    r=$(rss_kb $scale_pid || true)
    [ -n "$r" ] && [ "$r" -gt "$rss" ] && rss=$r
    kill -0 $scale_pid 2>/dev/null || break
    sleep 0.2
done
kill "$scale_dog" 2>/dev/null || true
wait "$scale_dog" 2>/dev/null || true
scale_rc=0
wait $scale_pid || scale_rc=$?
[ "$scale_rc" -eq 0 ] && [ "$(tail -1 "$scratch/scale.out")" = "done" ] || {
    echo "FAIL scale: rc=$scale_rc: $(cat "$scratch/scale.out")"; exit 1; }
[ -n "$rss" ] && [ "$rss" -gt 0 ] || { echo "FAIL scale: no RSS sample"; exit 1; }
[ -n "$base_rss" ] && [ "$base_rss" -gt 0 ] || {
    echo "FAIL scale: no baseline RSS sample"; cat "$scratch/base.out"; exit 1; }
# ~0.3kB/parked task observed on POSIX (RtTask + frame, one alloc);
# 1kB/task leaves >3x headroom for Windows heap commit granularity
# yet still fails an order of magnitude under any OS-thread-per-task
# regression (a thread costs tens of kB minimum).
delta=$((rss - base_rss))
[ "$delta" -lt 10240 ] || { echo "FAIL scale: ${delta}kB over ${base_rss}kB baseline at 10k parked (spec < 1kB/task)"; exit 1; }
echo "  10k parked tasks: ${delta}kB over ${base_rss}kB baseline"
out=$("$OXL" run tests/conc_ping.oxl -- 5000)
grep -q "bounces=5000" <<<"$out" || { echo "FAIL ping: $out"; exit 1; }

echo "== a2 select =="
out=$("$OXL" run tests/select_fair.oxl)
grep -qE "^select fair ok a=[0-9]+$" <<<"$(tail -1 <<<"$out")" || { echo "FAIL select_fair: $out"; exit 1; }
out=$("$OXL" run tests/select.oxl)
[ "$(tail -1 <<<"$out")" = "select done" ] || { echo "FAIL select: $out"; exit 1; }

echo "== g1 typed chans + named scopes =="
out=$("$OXL" run tests/chan_own.oxl)
[ "$(tail -1 <<<"$out")" = "chan_own done" ] || { echo "FAIL chan_own: $out"; exit 1; }

echo "== susp closures + zero values =="
# closures in susp fns keep their own defer mark + snapshot captures;
# bare `let` zero-inits its slot on both emitters
out=$("$OXL" run tests/susp_closure.oxl)
[ "$(tail -1 <<<"$out")" = "susp closure ok" ] || { echo "FAIL susp_closure: $out"; exit 1; }
out=$("$OXL" run tests/zero_str.oxl)
[ "$(tail -1 <<<"$out")" = "zero str ok" ] || { echo "FAIL zero_str: $out"; exit 1; }

echo "== g1 gui: mock backend + cancel gate =="
out=$("$OXL" run tests/gui_mock.oxl)
[ "$(tail -1 <<<"$out")" = "done" ] || { echo "FAIL gui_mock: $out"; exit 1; }
# cancellation: `scope { gui.run(...) }` + scancel while `pump` waits —
# the watcher's defer fires `b.stop()`, `run` returns, the canceller's
# scope joins (spec G1 gate). Build + run directly so a hang shows as
# with_timeout's 124 rather than a driver-side kill.
"$OXL" build tests/gui_cancel.oxl -o "$scratch/gui_cancel$EXE" || {
    echo "FAIL gui_cancel: compile failed"; exit 1; }
rc=0
out=$(with_timeout 30 "$scratch/gui_cancel$EXE") || rc=$?
[ "$rc" -eq 0 ] && [ "$(tail -1 <<<"$out")" = "cancel ok" ] || {
    echo "FAIL gui_cancel: rc=$rc: $out"; exit 1; }
# select-composability: `chan own gui.Event` must sit in one select next
# to an app's own chan (spec G3 gate); both arms fire before gui.stop.
out=$("$OXL" run tests/gui_select.oxl)
grep -q "select ok" <<<"$out" && [ "$(tail -1 <<<"$out")" = "done" ] || {
    echo "FAIL gui_select: $out"; exit 1; }
# stress: 200 rounds of add/remove row churn through the mock mailbox +
# dispatcher, List.rows() asserted live from a second task (spec G3/G5).
# Build + run directly so a hang shows as with_timeout's 124.
"$OXL" build tests/gui_stress.oxl -o "$scratch/gui_stress$EXE" || {
    echo "FAIL gui_stress: compile failed"; exit 1; }
rc=0
out=$(with_timeout 60 "$scratch/gui_stress$EXE") || rc=$?
[ "$rc" -eq 0 ] && grep -q "stress ok" <<<"$out" && \
    [ "$(tail -1 <<<"$out")" = "done" ] || {
    echo "FAIL gui_stress: rc=$rc: $out"; exit 1; }
# overflow policy at cap 1 (spec G3): all-protected posts land whole,
# close dedup through delivery + dismissal + re-arm, last eligible post
# survives eviction, events_dropped() reads the stashed count post-run.
"$OXL" build tests/gui_overflow.oxl -o "$scratch/gui_overflow$EXE" || {
    echo "FAIL gui_overflow: compile failed"; exit 1; }
rc=0
out=$(with_timeout 30 "$scratch/gui_overflow$EXE") || rc=$?
[ "$rc" -eq 0 ] && [ "$(tail -1 <<<"$out")" = "overflow ok" ] || {
    echo "FAIL gui_overflow: rc=$rc: $out"; exit 1; }
# lifecycle contracts (spec G1/G3): cancel mid-create fires the
# lost-reply destroy reconcile mid-run, dead-handle calls record
# violations, and post-run mutators are accepted-and-dropped.
"$OXL" build tests/gui_lifecycle.oxl -o "$scratch/gui_lifecycle$EXE" || {
    echo "FAIL gui_lifecycle: compile failed"; exit 1; }
rc=0
out=$(with_timeout 30 "$scratch/gui_lifecycle$EXE") || rc=$?
[ "$rc" -eq 0 ] && [ "$(tail -1 <<<"$out")" = "lifecycle ok" ] || {
    echo "FAIL gui_lifecycle: rc=$rc: $out"; exit 1; }
# parked select must unwedge on sibling trap — exits nonzero, not a hang.
# 124 = with_timeout expiry = the hang this test exists to catch. Build
# first so a compile error fails the check instead of passing as a
# non-124 nonzero exit.
"$OXL" build tests/select_cancel.oxl -o "$scratch/select_cancel$EXE" || {
    echo "FAIL select_cancel: compile failed"; exit 1; }
rc=0
with_timeout 10 "$scratch/select_cancel$EXE" >/dev/null 2>&1 || rc=$?
if [ "$rc" -eq 0 ] || [ "$rc" -eq 124 ]; then
    echo "FAIL select_cancel: expected trap exit, got rc=$rc"; exit 1
fi

# orphan drain: a frame task returning inside an open scope orphans it;
# its teardown must not lock the joined scope's destroyed mutex. Build
# first so a compile error fails the check, and run the binary directly —
# under `oxl run` the watchdog would kill only the driver while the child
# keeps the capture pipe and $( ) hangs past the deadline.
"$OXL" build tests/orphan_join.oxl -o "$scratch/orphan_join$EXE" || {
    echo "FAIL orphan_join: compile failed"; exit 1; }
rc=0
out=$(with_timeout 30 "$scratch/orphan_join$EXE") || rc=$?
# marker alone isn't enough: a crash/time-out after the print must fail
[ "$rc" -eq 0 ] && [ "$(tail -1 <<<"$out")" = "orphan-join ok" ] || { echo "FAIL orphan_join: rc=$rc: $out"; exit 1; }

# joiner lost-wakeup: a trap's descendant cancel temp-holds a scope
# whose owner is parked joining it; if the temp drop is the pending->0
# transition it must still wake the joiner. Build first so a compile
# error fails instead of passing as a non-124 nonzero.
"$OXL" build tests/cancel_join.oxl -o "$scratch/cancel_join$EXE" || {
    echo "FAIL cancel_join: compile failed"; exit 1; }
rc=0
with_timeout 25 "$scratch/cancel_join$EXE" >/dev/null 2>&1 || rc=$?
if [ "$rc" -eq 0 ] || [ "$rc" -eq 124 ]; then
    echo "FAIL cancel_join: expected trap exit, got rc=$rc"; exit 1
fi

# scope-exit join: break/continue/return inside a loop-nested scope must
# drain its children — a bare goto orphaned them. Build + run the binary
# directly like orphan_join: detached children would hold the capture
# pipe open past the deadline under `oxl run`.
"$OXL" build tests/scope_exit.oxl -o "$scratch/scope_exit$EXE" || {
    echo "FAIL scope_exit: compile failed"; exit 1; }
rc=0
out=$(with_timeout 30 "$scratch/scope_exit$EXE") || rc=$?
[ "$rc" -eq 0 ] && [ "$(tail -1 <<<"$out")" = "scope-exit ok" ] || { echo "FAIL scope_exit: rc=$rc: $out"; exit 1; }

echo "== a3 buffered channels =="
out=$("$OXL" run tests/chanbuf.oxl)
[ "$(tail -1 <<<"$out")" = "chanbuf done" ] || { echo "FAIL chanbuf: $out"; exit 1; }
out=$("$OXL" run tests/chanbuf_close.oxl)
[ "$(tail -1 <<<"$out")" = "chanbuf close ok" ] || { echo "FAIL chanbuf_close: $out"; exit 1; }

echo "== fmt check =="
# the whole .oxl corpus must be canonically formatted
if ! "$OXL" fmt --check $(find std bootstrap tests examples -name '*.oxl' | sort); then
    echo "FAIL fmt: run \`oxl fmt -w\` on the corpus"; exit 1
fi


echo "== lsp hover/definition =="
# a Windows python can't exec an msys path — hand it the native spelling
OXL_WIN=$(cygpath -w "$OXL" 2>/dev/null || printf '%s' "$OXL")
$PY - "$OXL_WIN" <<'PYEOF'
import json, pathlib, subprocess, sys
oxl = sys.argv[1]
p = subprocess.Popen([oxl, "lsp"], stdin=subprocess.PIPE, stdout=subprocess.PIPE)
def send(m):
    b = json.dumps(m).encode()
    p.stdin.write(b"Content-Length: %d\r\n\r\n" % len(b) + b); p.stdin.flush()
def recv():
    h = {}
    while True:
        l = p.stdout.readline().decode().strip()
        if not l: break
        k, v = l.split(":", 1); h[k.strip()] = v.strip()
    return json.loads(p.stdout.read(int(h["Content-Length"])).decode())
uri = pathlib.Path("bootstrap/cmd/parse/main.oxl").resolve().as_uri()
src = open("bootstrap/cmd/parse/main.oxl").read()
send({"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}); recv()
send({"jsonrpc":"2.0","method":"initialized","params":{}})
send({"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":uri,"languageId":"oxl","version":1,"text":src}}}); recv()
lines = src.split("\n")
i = next(i for i,l in enumerate(lines) if "lexlib.lex(src)" in l)
col = lines[i].index("lexlib.lex") + 7
pos = {"textDocument":{"uri":uri},"position":{"line":i,"character":col}}
send({"jsonrpc":"2.0","id":2,"method":"textDocument/hover","params":pos})
h = recv(); assert "fn lexlib.lex(src: str)" in json.dumps(h), h
send({"jsonrpc":"2.0","id":3,"method":"textDocument/definition","params":pos})
d = recv(); assert d["result"]["uri"].endswith("lexlib/lexlib.oxl"), d
# UTF-16 columns: a non-ASCII literal ahead of the use on its line makes
# the char/UTF-16/byte columns all differ — hover must still land on lex
src2 = src.replace("ast := parser.parse(", 'e := "\U0001f389"; ast := parser.parse(', 1)
assert src2 != src
send({"jsonrpc":"2.0","method":"textDocument/didChange","params":{"textDocument":{"uri":uri,"version":2},"contentChanges":[{"text":src2}]}}); recv()
lines2 = src2.split("\n")
i2 = next(i for i,l in enumerate(lines2) if "lexlib.lex(src)" in l)
cidx = lines2[i2].index("lexlib.lex") + 7
# the client speaks UTF-16 units — the emoji ahead on this line is two
pos2 = {"textDocument":{"uri":uri},"position":{"line":i2,"character":len(lines2[i2][:cidx].encode("utf-16-le"))//2}}
send({"jsonrpc":"2.0","id":4,"method":"textDocument/hover","params":pos2})
h2 = recv(); assert "fn lexlib.lex(src: str)" in json.dumps(h2), h2
send({"jsonrpc":"2.0","method":"exit","params":{}})
PYEOF

echo "== http pilot =="
work=$(mktemp -d "$scratch/http.XXXXXX")
"$OXL" build examples/http-crud-sqlite/main.oxl -o "$work/httpsrv$EXE"
curl -s -m 1 -o /dev/null localhost:8080/items && { echo "FAIL: :8080 already bound"; exit 1; } || true
(cd "$work"; ./httpsrv$EXE > srv.log 2>&1 & echo $! > srv.pid)
srv_pid=$(cat "$work/srv.pid")
# readiness can lag on slow runners — poll the log instead of a fixed sleep
for _ in $(seq 1 50); do
    grep -q "listening" "$work/srv.log" && break
    sleep 0.2
done
grep -q "listening" "$work/srv.log" || { echo "FAIL: server did not bind"; cat "$work/srv.log"; kill $srv_pid 2>/dev/null; exit 1; }
got=$(curl -s -d widget localhost:8080/items)
[ "$got" = '{"created":"widget"}' ] || { echo "FAIL post: $got"; kill $srv_pid 2>/dev/null; exit 1; }
code=$(curl -s -o /dev/null -w '%{http_code}' -d widget localhost:8080/items)
[ "$code" = "201" ] || { echo "FAIL post status: $code"; kill $srv_pid 2>/dev/null; exit 1; }
# newline in a name would split one stored row into two items on read —
# the server must reject it with a 400 rather than corrupt the list
code=$(curl -s -o /dev/null -w '%{http_code}' -d $'bad\nname' localhost:8080/items)
[ "$code" = "400" ] || { echo "FAIL newline status: $code"; kill $srv_pid 2>/dev/null; exit 1; }
got=$(curl -s localhost:8080/items)
grep -q '"name":"widget"' <<<"$got" || { echo "FAIL get: $got"; kill $srv_pid 2>/dev/null; exit 1; }
kill $srv_pid 2>/dev/null || true

echo "== gui pilot =="
# GTK4 FFI pilot: build whenever gtk4 dev files exist; run the
# signal-path selftest only when a display is available (CI macOS /
# headless runners build but don't launch)
if command -v pkg-config >/dev/null 2>&1 && pkg-config --exists gtk4 2>/dev/null; then
    (cd examples/gui-todo && OXL="$OXL" ./build.sh >/dev/null)
    if [ -n "${DISPLAY:-}" ]; then
        out=$(with_timeout 30 examples/gui-todo/todo --selftest 2>/dev/null)
        grep -q "selftest rows=2" <<<"$out" || { echo "FAIL gui selftest: $out"; exit 1; }
        grep -q "gui done" <<<"$out" || { echo "FAIL gui run: $out"; exit 1; }
    fi
else
    echo "  (skipped: gtk4 not installed)"
fi

echo "== w1 js runtime smoke =="
# node-gated: the hand-written driver exercises the rt.mjs poll
# contract (spawn/scope/trap/defer/chan/err) — W1's suite gate;
# skips cleanly where node is absent
if command -v node >/dev/null 2>&1; then
    node tests/js/rt-core-smoke.mjs || { echo "FAIL rt-core-smoke"; exit 1; }
    node tests/js/rt-browser-stub.mjs || { echo "FAIL rt-browser-stub"; exit 1; }
else
    echo "  (skipped: node not installed)"
fi

echo "== w4 js driver lane =="
# node-gated: the whitelisted corpus (W3 concurrency suite + W2
# pure-stdlib corpus) through the self-built product driver's
# `--target js` lane — the W4 conformance gate. Lane skips cleanly
# where node is absent.
if command -v node >/dev/null 2>&1; then
    # gui_* joined the lane in W5 — the susp-pump contract lets the
    # mock's cooperative pump drive the same gates single-threaded
    for f in conc_ping conc_scale select select_fair chan_own chanbuf chanbuf_close scope_exit orphan_join defer_order pairfwd match methods fnval d5_qual stdmods_test susp_closure zero_str gui_mock gui_lifecycle gui_overflow gui_select gui_stress gui_cancel gui_dom; do
        out=$(with_timeout 60 "$SELFOXL" run --target js "tests/$f.oxl" 2>&1) || { echo "FAIL js lane $f: $out"; exit 1; }
    done
    for f in enc_test hash_test regexp_test float_test util_test stdlib_test collections_test enum_test defer_test os_test exec_test net_test flaglog_test extra_testutil; do
        out=$(with_timeout 60 "$SELFOXL" test --target js "tests/$f.oxl" 2>&1) || { echo "FAIL js lane test $f: $out"; exit 1; }
        grep -q 'FAIL' <<<"$out" && { echo "FAIL js lane test $f: $out"; exit 1; }
    done
    for f in select_cancel cancel_join; do
        "$SELFOXL" build --target js "tests/$f.oxl" -o "$scratch/$f.mjs" || { echo "FAIL js lane $f: emit"; exit 1; }
        rc=0
        out=$(with_timeout 30 node "$scratch/$f.mjs" 2>&1) || rc=$?
        [ "$rc" -ne 0 ] || { echo "FAIL js lane $f: expected trap exit"; exit 1; }
        grep -q 'escaped top scope' <<<"$out" || { echo "FAIL js lane $f: trap line: $out"; exit 1; }
    done
else
    echo "  (skipped: node not installed)"
fi

echo "== w6 dom backend + web bundle =="
# node-gated: the reference app's emitted bundle structure plus its
# headless-DOM selftest — the same rows=2 churn=200 gate the gtk
# pilot asserts, driven through the dom backend's listener path.
if command -v node >/dev/null 2>&1; then
    "$SELFOXL" build --target js --html examples/web-todo -o "$scratch/web-todo.mjs" || {
        echo "FAIL web-todo emit"; exit 1; }
    for r in rt.mjs rt-node.mjs rt-browser.mjs rt-dom.mjs web-todo.mjs web-todo.mjs.html; do
        [ -f "$scratch/$r" ] || { echo "FAIL web-todo bundle missing $r"; exit 1; }
    done
    grep -q 'type="module"' "$scratch/web-todo.mjs.html" || {
        echo "FAIL web-todo html scaffold"; exit 1; }
    out=$(cd "$scratch" && with_timeout 60 node -e "process.argv[1]='web-todo.mjs'; process.argv[2]='--selftest'; import('./web-todo.mjs')" 2>&1) || {
        echo "FAIL web-todo selftest: $out"; exit 1; }
    grep -q 'selftest rows=2 churn=200 ok' <<<"$out" || {
        echo "FAIL web-todo selftest line: $out"; exit 1; }
else
    echo "  (skipped: node not installed)"
fi

echo "ALL TESTS PASSED"
