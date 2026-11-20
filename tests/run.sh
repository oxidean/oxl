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
EXE=""; THREAD_FLAG="-pthread"; NET_LIBS=""; MATH_LIBS="-lm"; CRYPTO_LIBS=""; PY=python3
case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
        EXE=".exe"; THREAD_FLAG=""; NET_LIBS="-lws2_32"; MATH_LIBS=""; CRYPTO_LIBS="-lbcrypt"; PY=python ;;
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
        # setsid makes the child a process-group leader so the watchdog
        # can kill the whole tree — `oxl run`'s compiled binary is a
        # grandchild of the driver, and killing only the direct pid
        # orphans it holding the caller's capture pipe open
        if command -v setsid >/dev/null 2>&1; then
            setsid "$@" & local pid=$!
        else
            "$@" & local pid=$!
        fi
        # watchdog redirects away from the caller's capture pipe: inside
        # out=$(with_timeout ..) the subshell would inherit that pipe, and
        # a killed dog can orphan its sleep child still holding it open —
        # the $() then hangs past the deadline it was enforcing. Kills
        # the process group when setsid made one (kill -- -pid), then the
        # direct pid, then a one-level pkill -P sweep for the no-setsid
        # path — best-effort, GNU timeout's own tree kill is deeper.
        ( sleep "$secs"
          kill -KILL -- "-$pid" 2>/dev/null || kill -KILL "$pid" 2>/dev/null
          pkill -KILL -P "$pid" 2>/dev/null ) >/dev/null 2>&1 & local dog=$!
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
relsrv=""
cleanup() {
    if [ -n "$srv_pid" ]; then kill "$srv_pid" 2>/dev/null || true; fi
    if [ -n "$relsrv" ]; then kill "$relsrv" 2>/dev/null || true; wait "$relsrv" 2>/dev/null || true; fi
    # v2's sealed module-cache slots are read-only — restore write
    # permission or rm leaves them behind
    chmod -R u+w "$scratch" 2>/dev/null
    rm -rf "$scratch"
}
trap cleanup EXIT

echo "== self-built product driver (t6) =="
# ADR-0006/ADR-0014: the stage-0 snapshot (bootstrap/stage0/oxl.c,
# compiled by scripts/stage0.sh) is the bootstrap input only — it
# builds the product driver once (gen 1), the product driver rebuilds
# itself (gen 2), and the C each generation emits for the driver
# sources must be byte-identical (the fixpoint — not a binary hash:
# build-ids and embedded paths legitimately differ) — seed emit
# included, so the seed-vs-self spec criterion is checked directly,
# not just via output parity. Every section below then runs
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
# the checked-in snapshot must be the emit of the current driver
# sources — drv0 is that emit via the seed, so a stale snapshot fails
# here with a pointer back to scripts/stage0.sh emit
diff "$scratch/drv0.c" bootstrap/stage0/oxl.c >/dev/null || { echo "FAIL stage-0 snapshot stale: regenerate with scripts/stage0.sh emit"; diff "$scratch/drv0.c" bootstrap/stage0/oxl.c | head -20; exit 1; }
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
# iface-boxed borrow escapes (issue #138): `as*` borrows must not leave
# their scope, while heap-backed receivers and `into_*` owned variants
# stay legal
cat > "$scratch/ifaceescape.oxl" <<'EOF'
package main

import "std/bufio"
import "std/bytes"
import "std/io"

fn via_into() -> io.Reader {
    h := new(bytes.Buffer)
    [wn, we] = h.write("owned" as []byte)
    return h.into_reader()
}

fn via_heap() -> io.Reader {
    h := new(bytes.Buffer)
    [wn, we] = h.write("heap" as []byte)
    return h.asreader()
}

fn scoped() -> int {
    buf := bytes.newbuffer()
    [wn, we] = buf.write("scoped" as []byte)
    r := buf.asreader()
    b := mkslice(byte, 16)
    [n, err] = r.read(b)
    return n
}

// every select arm replaces the borrow with a heap-backed reader —
// the join must not retain the pre-select taint
fn select_clear() -> io.Reader {
    buf := bytes.newbuffer()
    h := new(bytes.Buffer)
    [wh, weh] = h.write("sel" as []byte)
    r := buf.asreader()
    c := mkchan(1)
    select {
        v := recv(c) => {
            r = h.asreader()
        }
        timeout(0) => {
            r = h.asreader()
        }
    }
    return r
}

// slice aliases share backing — a borrow written through `a` is
// readable through `b`, but in-scope use stays legal
fn alias_scoped() -> int {
    a := mkslice(io.Reader, 1)
    b := a
    buf := bytes.newbuffer()
    [wa, wea] = buf.write("alias" as []byte)
    a[0] = buf.asreader()
    r := b[0]
    bb := mkslice(byte, 16)
    [n, err] = r.read(bb)
    return n
}

// rebinding `b` drops its membership in `a`'s backing group — writes
// through `a` must not taint the fresh slice `b` now denotes
fn alias_rebind() -> io.Reader {
    a := mkslice(io.Reader, 1)
    b := a
    b = mkslice(io.Reader, 1)
    buf := bytes.newbuffer()
    [wb, web] = buf.write("x" as []byte)
    a[0] = buf.asreader()
    return b[0]
}

// an owned `into_*` conversion on a value-local receiver is the
// documented remediation — it must not itself be flagged as a borrow
fn value_into() -> io.Reader {
    b := bytes.newbuffer()
    [wv, wev] = b.write("vinto" as []byte)
    return b.into_reader()
}

// a shadowing same-named binding in an inner scope is not the borrow's
// storage owner — popping it must not condemn `r`
fn shadow_scoped() -> int {
    buf := bytes.newbuffer()
    [ws, wes] = buf.write("shadow" as []byte)
    r := buf.asreader()
    if true {
        buf := 42
        println("inner:" + itoa(buf))
    }
    b := mkslice(byte, 16)
    [n, err] = r.read(b)
    return n
}

fn main() {
    b := mkslice(byte, 16)
    r := via_into()
    [n, err] = r.read(b)
    println("into:" + substr(b as str, 0, n))
    r2 := via_heap()
    [n2, err2] = r2.read(b)
    println("heap:" + substr(b as str, 0, n2))
    h2 := new(bytes.Buffer)
    bw := bufio.newwriter(h2.aswriter())
    [wn3, we3] = bw.write("bufio" as []byte)
    w := bw.into_writer()
    [nw, we2] = w.write("direct" as []byte)
    println("bufio:" + itoa(nw))
    println("sink:" + h2.str())
    println("scoped:" + itoa(scoped()))
    r3 := select_clear()
    [n3, err3] = r3.read(b)
    println("select:" + substr(b as str, 0, n3))
    println("alias:" + itoa(alias_scoped()))
    println("shadow:" + itoa(shadow_scoped()))
    rv := value_into()
    [nv, ev] = rv.read(b)
    println("vinto:" + substr(b as str, 0, nv))
}
EOF
out=$("$OXL" run "$scratch/ifaceescape.oxl")
grep -q "into:owned" <<<"$out" || { echo "FAIL ifaceescape into: $out"; exit 1; }
grep -q "heap:heap" <<<"$out" || { echo "FAIL ifaceescape heap: $out"; exit 1; }
grep -q "scoped:6" <<<"$out" || { echo "FAIL ifaceescape scoped: $out"; exit 1; }
grep -q "bufio:6" <<<"$out" || { echo "FAIL ifaceescape bufio: $out"; exit 1; }
grep -q "sink:bufiodirect" <<<"$out" || { echo "FAIL ifaceescape sink: $out"; exit 1; }
grep -q "select:sel" <<<"$out" || { echo "FAIL ifaceescape select: $out"; exit 1; }
grep -q "alias:5" <<<"$out" || { echo "FAIL ifaceescape alias: $out"; exit 1; }
grep -q "shadow:6" <<<"$out" || { echo "FAIL ifaceescape shadow: $out"; exit 1; }
grep -q "vinto:vinto" <<<"$out" || { echo "FAIL ifaceescape vinto: $out"; exit 1; }
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

# a missing `:` between params used to parse as extra untyped params —
# the separator is required so the signature fails loudly (#149)
cat > "$scratch/badparam.oxl" <<'EOF'
package main
fn id(r io.Reader) -> int { return 0 }
fn main() {}
EOF
if diag=$("$OXL" build "$scratch/badparam.oxl" -o "$scratch/badparam$EXE" 2>&1); then
    echo "FAIL param-sep: build succeeded: $diag"; exit 1
fi
grep -q "parameter list" <<<"$diag" || { echo "FAIL param-sep diag: $diag"; exit 1; }

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


echo "== oxl test: aead (x2) =="
out=$("$OXL" test tests/aesgcm_test.oxl) || { printf '%s
' "$out" >&2; exit 1; }
printf '%s
' "$out" >&2
for t in test_aes_block test_gcm test_gcm_carry test_aead_perf; do
    grep -q "$t ... ok" <<<"$out" || { echo "FAIL aesgcm: $out"; exit 1; }
done
out=$("$OXL" test tests/chacha_test.oxl) || { printf '%s
' "$out" >&2; exit 1; }
printf '%s
' "$out" >&2
for t in test_chacha20 test_poly1305 test_aead; do
    grep -q "$t ... ok" <<<"$out" || { echo "FAIL chacha: $out"; exit 1; }
done

echo "== oxl test: tls ground (x1) =="
out=$("$OXL" test tests/crypto_rand_test.oxl) || { printf '%s
' "$out" >&2; exit 1; }
printf '%s
' "$out" >&2
for t in test_csrand; do
    grep -q "$t ... ok" <<<"$out" || { echo "FAIL crypto_rand: $out"; exit 1; }
done
out=$("$OXL" test tests/sha512_test.oxl) || { printf '%s
' "$out" >&2; exit 1; }
printf '%s
' "$out" >&2
for t in test_sha512 test_sha384 test_hmac_sha512; do
    grep -q "$t ... ok" <<<"$out" || { echo "FAIL sha512: $out"; exit 1; }
done
out=$("$OXL" test tests/hkdf_test.oxl) || { printf '%s
' "$out" >&2; exit 1; }
printf '%s
' "$out" >&2
for t in test_hkdf; do
    grep -q "$t ... ok" <<<"$out" || { echo "FAIL hkdf: $out"; exit 1; }
done

echo "== oxl test: bignum+rsa (x3) =="
out=$("$OXL" test tests/bignum_test.oxl) || { printf '%s
' "$out" >&2; exit 1; }
printf '%s
' "$out" >&2
for t in test_modmul test_modexp test_modinv; do
    grep -q "$t ... ok" <<<"$out" || { echo "FAIL bignum: $out"; exit 1; }
done
out=$("$OXL" test tests/rsa_test.oxl) || { printf '%s
' "$out" >&2; exit 1; }
printf '%s
' "$out" >&2
for t in test_rsav15 test_rsapss; do
    grep -q "$t ... ok" <<<"$out" || { echo "FAIL rsa: $out"; exit 1; }
done
out=$("$OXL" test tests/net_test.oxl)
printf '%s
' "$out" >&2
for t in test_badport test_lookup; do
    grep -q "$t ... ok" <<<"$out" || { echo "FAIL net: $out"; exit 1; }
done
# socket-dependent half — the js lane's socket natives are trap21
# stubs, so this file stays native-only (the w4 lane runs net_test's
# socket-free tests)
out=$("$OXL" test tests/net_sock_test.oxl)
printf '%s
' "$out" >&2
for t in test_echo test_closer test_refused test_resolve test_badip; do
    grep -q "$t ... ok" <<<"$out" || { echo "FAIL net-sock: $out"; exit 1; }
done
out=$("$OXL" test tests/net_url.oxl)
printf '%s
' "$out" >&2
for t in test_escape test_parse test_values test_resolve test_parsehost; do
    grep -q "$t ... ok" <<<"$out" || { echo "FAIL net_url: $out"; exit 1; }
done
out=$("$OXL" test tests/net_mail.oxl)
printf '%s
' "$out" >&2
for t in test_parseaddress test_parseaddresslist test_string test_domainliteral; do
    grep -q "$t ... ok" <<<"$out" || { echo "FAIL net_mail: $out"; exit 1; }
done
out=$("$OXL" test tests/mime.oxl)
printf '%s
' "$out" >&2
for t in test_extensions test_parsemediatype test_formatmediatype test_dupparam; do
    grep -q "$t ... ok" <<<"$out" || { echo "FAIL mime: $out"; exit 1; }
done
# slog records land on stderr (timestamps vary) — capture 2>&1 so the
# emitted text/json shapes are asserted too
out=$("$OXL" test tests/log_slog.oxl 2>&1)
printf '%s
' "$out" >&2
for t in test_levels test_attrs test_handlers test_json test_default test_quoting; do
    grep -q "$t ... ok" <<<"$out" || { echo "FAIL log_slog: $out"; exit 1; }
done
grep -q 'level=INFO msg=started app=demo req.method=GET req.status=200' <<<"$out" || { echo "FAIL slog text shape: $out"; exit 1; }
grep -q 'req.note="has space"' <<<"$out" || { echo "FAIL slog text quoting: $out"; exit 1; }
grep -q '"level":"ERROR","msg":"failed","pid":42,"http":{"hdr":{"ct":"json"},"retry":true}' <<<"$out" || { echo "FAIL slog json shape: $out"; exit 1; }
grep -q '"msg":"default-json","src":"set_default"' <<<"$out" || { echo "FAIL slog set_default: $out"; exit 1; }
grep -q '"msg":"grp"' <<<"$out" || { echo "FAIL slog grp marker: $out"; exit 1; }
grep -q 'msg=hidden' <<<"$out" && { echo "FAIL slog level drop: $out"; exit 1; }
grep -q '"empty"' <<<"$out" && { echo "FAIL slog empty group: $out"; exit 1; }
grep -q '"gone"' <<<"$out" && { echo "FAIL slog bound empty group: $out"; exit 1; }
grep -q 'bad="\\ufffd"' <<<"$out" || { echo "FAIL slog ufffd quoting: $out"; exit 1; }
grep -q 'del="\\x7f"' <<<"$out" || { echo "FAIL slog del quoting: $out"; exit 1; }
grep -q 'esc="\\a\\b\\v\\f"' <<<"$out" || { echo "FAIL slog short escapes: $out"; exit 1; }
grep -q 'ufffd="\\ufffd"' <<<"$out" || { echo "FAIL slog valid ufffd: $out"; exit 1; }
true

echo "== oxl test: curves (x4) =="
out=$("$OXL" test tests/x25519_test.oxl) || { printf '%s
' "$out" >&2; exit 1; }
printf '%s
' "$out" >&2
for t in test_x25519; do
    grep -q "$t ... ok" <<<"$out" || { echo "FAIL x25519: $out"; exit 1; }
done
out=$("$OXL" test tests/nistec_test.oxl) || { printf '%s
' "$out" >&2; exit 1; }
printf '%s
' "$out" >&2
for t in test_ecdh_p256 test_ecdh_p384 test_ecdsa; do
    grep -q "$t ... ok" <<<"$out" || { echo "FAIL nistec: $out"; exit 1; }
done
out=$("$OXL" test tests/ed25519_test.oxl) || { printf '%s
' "$out" >&2; exit 1; }
printf '%s
' "$out" >&2
for t in test_ed25519; do
    grep -q "$t ... ok" <<<"$out" || { echo "FAIL ed25519: $out"; exit 1; }
done

echo "== oxl test: x509 (x5) =="
out=$("$OXL" test tests/x509_test.oxl) || { printf '%s\n' "$out" >&2; exit 1; }
printf '%s\n' "$out" >&2
for t in test_parse test_chain_ok test_expired test_bad_name test_wildcard test_untrusted test_bad_ca test_sha1_reject test_eku test_ip_san test_self_anchor test_anchor_exemption test_critical_ext test_search_bounds test_badsig test_xsign_alternates; do
    grep -q "$t ... ok" <<<"$out" || { echo "FAIL x509: $out"; exit 1; }
done
# env-root discovery — three configurations over one file; each
# test_ fn returns early outside its scenario
out=$(OXL_SSL_CERT_FILE=tests/fixtures/x509/roots.pem OXL_SSL_CERT_DIR= "$OXL" test tests/x509_env_test.oxl) || { printf '%s\n' "$out" >&2; exit 1; }
printf '%s\n' "$out" >&2
for t in test_env_file; do
    grep -q "$t ... ok" <<<"$out" || { echo "FAIL x509 env_file: $out"; exit 1; }
done
out=$(OXL_SSL_CERT_FILE= OXL_SSL_CERT_DIR=tests/fixtures/x509/dir "$OXL" test tests/x509_env_test.oxl) || { printf '%s\n' "$out" >&2; exit 1; }
printf '%s\n' "$out" >&2
for t in test_env_dir; do
    grep -q "$t ... ok" <<<"$out" || { echo "FAIL x509 env_dir: $out"; exit 1; }
done
out=$(OXL_SSL_CERT_FILE=tests/fixtures/x509/does-not-exist.pem OXL_SSL_CERT_DIR= "$OXL" test tests/x509_env_test.oxl) || { printf '%s\n' "$out" >&2; exit 1; }
printf '%s\n' "$out" >&2
for t in test_env_bad_path_fails; do
    grep -q "$t ... ok" <<<"$out" || { echo "FAIL x509 env_bad: $out"; exit 1; }
done

out=$(OXL_SSL_CERT_FILE= OXL_SSL_CERT_DIR=tests/fixtures/x509/dirbad "$OXL" test tests/x509_env_test.oxl) || { printf '%s\n' "$out" >&2; exit 1; }
printf '%s\n' "$out" >&2
for t in test_env_dir_bad_entry; do
    grep -q "$t ... ok" <<<"$out" || { echo "FAIL x509 env_dirbad: $out"; exit 1; }
done

echo "== oxl test: tls (x6) =="
out=$("$OXL" test tests/tls_keys_test.oxl) || { printf '%s
' "$out" >&2; exit 1; }
printf '%s
' "$out" >&2
for t in test_keyschedule test_record; do
    grep -q "$t ... ok" <<<"$out" || { echo "FAIL tls_keys: $out"; exit 1; }
done
out=$("$OXL" test tests/tls_handshake_test.oxl) || { printf '%s
' "$out" >&2; exit 1; }
printf '%s
' "$out" >&2
for t in test_handshake test_handshake_hrr test_handshake_cookie test_rawfd_and_adapters; do
    grep -q "$t ... ok" <<<"$out" || { echo "FAIL tls_handshake: $out"; exit 1; }
done

echo "== openssl interop: tls (x6) =="
# Live wire: real openssl s_server instances answer each scenario —
# the only suite piece that execs openssl. Where it is absent the
# lane skips cleanly; the replay fixtures above still pin the wire
# contract. Scenarios:
#   ok      trusted-root handshake + -www page round trip
#   hrr     s_server -groups P-384 demands a group CH1 didn't share
#           → HelloRetryRequest → CH2 → full flight
#   badroot chain under an unrelated CA bundle → err_root
#   badname trusted root, wrong server_name    → err_name
# A cookie-only HRR can't be coaxed out of s_server over TCP
# (-stateless is DTLS); that branch is replay-pinned by
# tests/tls/flight_cookie.hex from tests/tls/cookie_server.py.
# LibreSSL s_server lacks -tls1_3/-groups — that's "openssl absent"
# for this lane's purposes; macos-latest's stock openssl is LibreSSL
if command -v openssl >/dev/null 2>&1 && openssl version 2>/dev/null | grep -q '^OpenSSL'; then
    tls_interop() { # <scenario> <port> <ca.pem> <marker>
        local out
        out=$("$OXL" run tests/tls/interop.oxl -- "$1" "$2" "$3") || {
            printf '%s\n' "$out" >&2
            return 1
        }
        grep -q "$4" <<<"$out"
    }
    iport="${TLS_INTEROP_PORT:-24443}"
    hport=$((iport + 1))
    openssl s_server -accept "$iport" \
        -cert tests/tls/server.pem -key tests/tls/server-key.pem \
        -tls1_3 -www -naccept 16 -quiet >/dev/null 2>&1 &
    isrv=$!
    openssl s_server -accept "$hport" \
        -cert tests/tls/server.pem -key tests/tls/server-key.pem \
        -tls1_3 -www -groups P-384 -naccept 4 -quiet >/dev/null 2>&1 &
    hsrv=$!
    # wait for both listeners — each probe connect eats one -naccept
    # slot, which the counts above already budget for
    iready=0
    for i in $(seq 1 50); do
        kill -0 "$isrv" 2>/dev/null || break
        (exec 3<>"/dev/tcp/127.0.0.1/$iport") 2>/dev/null && { exec 3>&- 3<&-; iready=1; break; }
        sleep 0.1
    done
    hready=0
    for i in $(seq 1 50); do
        kill -0 "$hsrv" 2>/dev/null || break
        (exec 3<>"/dev/tcp/127.0.0.1/$hport") 2>/dev/null && { exec 3>&- 3<&-; hready=1; break; }
        sleep 0.1
    done
    if [ "$iready" != 1 ] || [ "$hready" != 1 ]; then
        echo "FAIL tls interop: s_server did not listen" >&2
        kill "$isrv" "$hsrv" 2>/dev/null || true
        exit 1
    fi
    tls_interop ok "$iport" tests/tls/ca.pem INTEROP_OK \
        || { echo "FAIL tls interop ok"; kill "$isrv" "$hsrv" 2>/dev/null || true; exit 1; }
    tls_interop hrr "$hport" tests/tls/ca.pem INTEROP_HRR \
        || { echo "FAIL tls interop hrr"; kill "$isrv" "$hsrv" 2>/dev/null || true; exit 1; }
    tls_interop badroot "$iport" tests/fixtures/x509/roots.pem INTEROP_BADROOT \
        || { echo "FAIL tls interop badroot"; kill "$isrv" "$hsrv" 2>/dev/null || true; exit 1; }
    tls_interop badname "$iport" tests/tls/ca.pem INTEROP_BADNAME \
        || { echo "FAIL tls interop badname"; kill "$isrv" "$hsrv" 2>/dev/null || true; exit 1; }
    # x7 https seam — the same s_server through http.Client.request:
    # env roots carry the CA bundle, server_name defaults to the URL
    # host (an iPAddress SAN on the fixture cert)
    hout=$(OXL_HTTPS_TEST_PORT="$iport" OXL_HTTPS_TEST_CA=tests/tls/ca.pem \
        "$OXL" test tests/https_test.oxl) || {
        printf '%s\n' "$hout" >&2
        kill "$isrv" "$hsrv" 2>/dev/null || true
        exit 1
    }
    printf '%s\n' "$hout" >&2
    for t in test_https_get test_https_bad_cert test_https_wrong_name; do
        grep -q "$t ... ok" <<<"$hout" || { echo "FAIL https interop $t: $hout"; kill "$isrv" "$hsrv" 2>/dev/null || true; exit 1; }
    done
    # https redirect credential-strip — a TLS 302 down to cleartext
    # must not carry authorization. s_server can't emit redirects and
    # the oxl TLS server is parked, so the stubs are python+ssl:
    # redirect_server answers the TLS hop with a 302 to the plain
    # capture_server, which records the request head for the test
    if command -v python3 >/dev/null 2>&1 && python3 -c 'import ssl' 2>/dev/null; then
        rport=$((iport + 2))
        cport=$((iport + 3))
        capfile=$(mktemp)
        python3 tests/tls/redirect_server.py tests/tls/server.pem tests/tls/server-key.pem \
            "$rport" "http://127.0.0.1:$cport/leak" >/dev/null 2>&1 &
        rsrv=$!
        python3 tests/tls/capture_server.py "$cport" "$capfile" >/dev/null 2>&1 &
        csrv=$!
        rready=0
        for i in $(seq 1 50); do
            kill -0 "$rsrv" 2>/dev/null || break
            (exec 3<>"/dev/tcp/127.0.0.1/$rport") 2>/dev/null && { exec 3>&- 3<&-; rready=1; break; }
            sleep 0.1
        done
        cready=0
        for i in $(seq 1 50); do
            kill -0 "$csrv" 2>/dev/null || break
            (exec 3<>"/dev/tcp/127.0.0.1/$cport") 2>/dev/null && { exec 3>&- 3<&-; cready=1; break; }
            sleep 0.1
        done
        if [ "$rready" != 1 ] || [ "$cready" != 1 ]; then
            echo "FAIL https redirect: stubs did not listen" >&2
            kill "$rsrv" "$csrv" "$isrv" "$hsrv" 2>/dev/null || true
            exit 1
        fi
        rout=$(OXL_HTTPS_TEST_REDIR_PORT="$rport"             OXL_HTTPS_TEST_CAPTURE_FILE="$capfile"             OXL_HTTPS_TEST_CA=tests/tls/ca.pem             "$OXL" test tests/https_test.oxl) || {
            printf '%s\n' "$rout" >&2
            kill "$rsrv" "$csrv" "$isrv" "$hsrv" 2>/dev/null || true
            rm -f "$capfile"
            exit 1
        }
        printf '%s\n' "$rout" >&2
        grep -q "test_https_redirect_noleak ... ok" <<<"$rout" \
            || { echo "FAIL https redirect noleak: $rout"; kill "$rsrv" "$csrv" "$isrv" "$hsrv" 2>/dev/null || true; rm -f "$capfile"; exit 1; }
        kill "$rsrv" "$csrv" 2>/dev/null || true
        wait "$rsrv" "$csrv" 2>/dev/null || true
        rm -f "$capfile"
        echo "  interop: ok hrr badroot badname https redirect-noleak"
    else
        echo "  python3+ssl not found — skipping https redirect interop"
        echo "  interop: ok hrr badroot badname https"
    fi
    kill "$isrv" "$hsrv" 2>/dev/null || true
    wait "$isrv" "$hsrv" 2>/dev/null || true
else
    echo "  openssl not found — skipping live interop"
fi

echo "== oxl test: https (x7) =="
# parse-level coverage runs everywhere; the live tests see no
# OXL_HTTPS_TEST_* env here so they skip clean (their markers print
# ok either way — the real assertions for them are the greps inside
# the openssl gate above, where the env is set)
out=$("$OXL" test tests/https_test.oxl) || { printf '%s
' "$out" >&2; exit 1; }
printf '%s
' "$out" >&2
for t in test_url_https test_https_get test_https_bad_cert test_https_wrong_name test_https_redirect_noleak; do
    grep -q "$t ... ok" <<<"$out" || { echo "FAIL https: $out"; exit 1; }
done

echo "== oxl test: compress & archive =="
out=$("$OXL" test tests/compress_flate.oxl)
printf '%s
' "$out" >&2
for t in test_fixed test_stored test_dynamic test_multiblock test_mixedblocks test_empty test_truncated test_zlib test_zlib_stream test_zlib_badheader test_zlib_badadler test_coreturn test_zlib_shorttrailer; do
    grep -q "$t ... ok" <<<"$out" || { echo "FAIL flate/zlib: $out"; exit 1; }
done
out=$("$OXL" test tests/compress_gzip.oxl)
printf '%s
' "$out" >&2
for t in test_basic test_header_fields test_multimember test_badcrc test_badmagic test_truncated test_fextra_fhcrc; do
    grep -q "$t ... ok" <<<"$out" || { echo "FAIL gzip: $out"; exit 1; }
done
out=$("$OXL" test tests/archive_tar.oxl)
printf '%s
' "$out" >&2
for t in test_roundtrip test_prefix_split test_pax_longname test_gnu_longname test_skip_payload test_truncated_midheader test_truncated_member test_pax_badlen test_meta_oversize test_b256_size test_signed_checksum test_gnu_foreign; do
    grep -q "$t ... ok" <<<"$out" || { echo "FAIL tar: $out"; exit 1; }
done
out=$("$OXL" test tests/archive_zip.oxl)
printf '%s
' "$out" >&2
for t in test_read test_open test_lookup test_corrupt test_open_badindex; do
    grep -q "$t ... ok" <<<"$out" || { echo "FAIL zip: $out"; exit 1; }
done

echo "== oxl test: hostile archive/compress inputs =="
# bounded: a decoder hang must fail the gate, not stall the suite
out=$(with_timeout 120 "$OXL" test tests/archive_hostile.oxl || true)
printf '%s
' "$out" >&2
for t in test_dist_oob test_overlap_ok test_btype3 test_oversub test_stored_badlen test_rep_noprev test_random test_gz_nonul_name test_gz_badhcrc test_gz_goodhcrc test_gz_fextra_short test_gz_trailgarbage test_gz_halfmember test_zip64 test_zip_mismatch test_zip_bigcsize test_tar_badsum test_tar_badoctal test_zlib_keepalive; do
    grep -q "$t ... ok" <<<"$out" || { echo "FAIL hostile: $out"; exit 1; }
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
out=$("$OXL" run tests/httpclient_rich.oxl)
printf '%s
' "$out" >&2
grep -q "httpclient rich done" <<<"$out" || { echo "FAIL httpclient rich: $out"; exit 1; }

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

echo "== oxl test: term + signal =="
out=$("$OXL" test tests/term_signal_test.oxl)
printf '%s
' "$out" >&2
for t in test_isatty test_size test_raw_needs_tty test_signal_names test_signal_arm_take test_signal_sigwinch; do
    grep -q "$t ... ok" <<<"$out" || { echo "FAIL term_signal: $out"; exit 1; }
done
# POSIX extras: a pty probe for the real-terminal paths and a shell-
# delivered SIGUSR1 for the take() observation contract. Windows has
# no pty/`script` and no POSIX kill semantics — the unit tests above
# already cover its console-ctrl surface shape.
case "$(uname -s)" in
MINGW*|MSYS*|CYGWIN*) ;;
*)
    if command -v script >/dev/null 2>&1; then
        # script(1) differs: util-linux wants -c, BSD/macOS takes the
        # command as trailing argv. || true keeps set -e from eating
        # the diagnostic below
        case "$(uname -s)" in
        Darwin)
            pout=$(script -q /dev/null sh -c 'stty rows 24 cols 80; "'"$OXL"'" run tests/term_probe.oxl' 2>/dev/null | tr -d '\r') || true ;;
        *)
            pout=$(script -qefc "stty rows 24 cols 80; \"$OXL\" run tests/term_probe.oxl" /dev/null 2>/dev/null | tr -d '\r') || true ;;
        esac
        grep -q "term probe ok" <<<"$pout" || { echo "FAIL term probe: $pout"; exit 1; }
        grep -q "term probe ok" <<<"$pout" || { echo "FAIL term probe: $pout"; exit 1; }
    fi
    "$OXL" build tests/sigusr1_wait.oxl -o "$scratch/sigusr1$EXE"         || { echo "FAIL sigusr1 build"; exit 1; }
    "$scratch/sigusr1$EXE" > "$scratch/sigusr1.out" 2>&1 &
    sigpid=$!
    # the child prints "armed" once signal.arm returns — poll for it
    # rather than racing a fixed sleep on slow CI runners
    armed=0
    tries=0
    while [ "$armed" -eq 0 ] && [ "$tries" -lt 100 ]; do
        if grep -q "^armed" "$scratch/sigusr1.out" 2>/dev/null; then
            armed=1
        else
            sleep 0.05
            tries=$((tries + 1))
        fi
    done
    kill -USR1 "$sigpid" 2>/dev/null || true
    src=0
    wait "$sigpid" || src=$?
    cat "$scratch/sigusr1.out" >&2
    [ "$src" -eq 0 ] || { echo "FAIL sigusr1 delivery rc=$src"; exit 1; }
    grep -q "got sigusr1" "$scratch/sigusr1.out"         || { echo "FAIL sigusr1 delivery: $(cat "$scratch/sigusr1.out")"; exit 1; }
    ;;
esac

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

echo "== containers (b7) =="
for t in heap list ring; do
    out=$("$OXL" run tests/container_$t.oxl)
    [ "$(tail -1 <<<"$out")" = "$t ok" ] || { echo "FAIL container/$t: $out"; exit 1; }
done

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
# tests/container_heap.oxl rides along as the main-package case for
# check.oxl's `recv == nil` method-sugar gate: it declares len/push/pop
# methods in package main — without the gate the self checker would
# misread the builtins as method calls.
for f in bootstrap/check bootstrap/codegen examples/features.oxl tests/match.oxl tests/container_heap.oxl std/collections \
    std/container/heap std/container/list std/container/ring; do
    out=$("$OXL" run bootstrap/cmd/check -- "$f")
    [ "$out" = "ok" ] || { echo "FAIL checker $f: $out"; exit 1; }
done

echo "== differential diagnostics (c1) =="
# tests/diag/ holds files that parse cleanly but fail checking. Since
# ADR-0014 both sides run the same self-hosted checker — the "seed"
# side through the driver build path, the "self" side through the
# standalone check binary — so this now guards the driver's diag
# plumbing (prefix strip, ordering, acceptance) rather than a second
# implementation. The driver prefixes each diag `file:line:col:`
# (stripped here); check.oxl reports {kind,msg} only.
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
    if seed=$("$SEEDOXL" build "$f" -o "$scratch/diagbin" 2>&1 | sed -E 's/^([A-Za-z]:)?[^:]*:[0-9]+:[0-9]+: //'); then
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
# `expected` marks the outcome — `ok` fixtures must build under the
# driver and print `ok` in the standalone checker; error fixtures must
# be rejected by both paths with identical diagnostics. The
# module cache is pointed at an empty dir so `missing module` is
# deterministic; `tests/mod/widget` and `tests/mod/intmod` are shared
# replace-targets, not cases.
mkdir -p "$scratch/oxlmodcache"
export OXLMODCACHE="$scratch/oxlmodcache"
for f in tests/mod/*/; do
    case "$f" in tests/mod/widget/|tests/mod/intmod/) continue ;; esac
    seed_out=$("$SEEDOXL" build "$f" -o "$scratch/modbin" 2>&1 | sed -E 's/^([A-Za-z]:)?[^:]*:[0-9]+:[0-9]+: //') && seed_rc=0 || seed_rc=1
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
seed_out=$("$SEEDOXL" build "$scratch/modoff" -o "$scratch/modbin" 2>&1 | sed -E 's/^([A-Za-z]:)?[^:]*:[0-9]+:[0-9]+: //') && seed_rc=0 || seed_rc=1
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
seed_out=$("$SEEDOXL" build "$scratch/workfm/main.oxl" -o "$scratch/workfmbin" 2>&1 | sed -E 's/^([A-Za-z]:)?[^:]*:[0-9]+:[0-9]+: //') && seed_rc=0 || seed_rc=1
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
seed_out=$("$SEEDOXL" build "$scratch/workdangle/app" -o "$scratch/danglebin" 2>&1 | sed -E 's/^([A-Za-z]:)?[^:]*:[0-9]+:[0-9]+: //') && seed_rc=0 || seed_rc=1
self_out=$("$scratch/selfcheck$EXE" "$scratch/workdangle/app" 2>&1) && self_rc=0 || self_rc=1
if [ "$seed_rc" != 0 ] || [ "$self_rc" != 0 ] || [ "$self_out" != ok ]; then
    echo "FAIL work-dangle: dangling oxl.work not treated as absent"
    echo "-- seed --"; printf '%s\n' "$seed_out"
    echo "-- self --"; printf '%s\n' "$self_out"
    exit 1
fi
;;
esac
# invalid UTF-8 inside a comment: strict readers reject the file
# outright; the driver must degrade to the documented
# missing-directive diagnostic — validating before comment stripping,
# not during line parsing. Diagnostics differ by contract, so only the
# driver side's text is asserted.
mkdir -p "$scratch/workbadutf8/app"
printf 'module local/badutf8\noxl 0.3\n' > "$scratch/workbadutf8/oxl.mod"
printf 'package main\nfn main() {}\n' > "$scratch/workbadutf8/app/main.oxl"
printf 'oxlwork 0.3\n// \xff\xfe\nuse ./app\n' > "$scratch/workbadutf8/oxl.work"
seed_out=$("$SEEDOXL" build "$scratch/workbadutf8/app" -o "$scratch/utf8bin" 2>&1 | sed -E 's/^([A-Za-z]:)?[^:]*:[0-9]+:[0-9]+: //') && seed_rc=0 || seed_rc=1
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
# tidy must not drop requires when a package file fails to parse —
# the skipped file can't prove its imports are unused (#151)
printf 'module file://%s/app\noxl 0.3\n\nrequire file://%s/dep v1.0.0\n' "$tv" "$tv" > "$tv/app/oxl.mod"
printf 'package main\nfn broken(a b) {}\n' > "$tv/app/app/broken.oxl"
cp "$tv/app/oxl.mod" "$tv/m.save"
( cd "$tv/app" && OXLMODCACHE="$tv/cache" "$OXL" mod tidy ) > "$tv/tidy5b" 2>&1 && { echo "FAIL tidy5b accepted"; cat "$tv/tidy5b"; exit 1; }
grep -q 'failed to parse' "$tv/tidy5b" || { echo "FAIL tidy5b text"; cat "$tv/tidy5b"; exit 1; }
diff "$tv/m.save" "$tv/app/oxl.mod" >/dev/null || { echo "FAIL tidy5b rewrote manifest"; diff "$tv/m.save" "$tv/app/oxl.mod"; exit 1; }
rm "$tv/app/app/broken.oxl"
printf 'module file://%s/app\noxl 0.3\n' "$tv" > "$tv/app/oxl.mod"
rm -f "$tv/app/oxl.sum"
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

echo "== reflect + fmt %v (r2) =="
# std/reflect's public walk (Type/Field/Variant/Value, enum lanes,
# decode mints, cstr) and fmt's %v/%+v/%T/%#v over the same
# descriptor table — both fixtures assert in-process and end with an
# ok line; db_sql exercises scan[T]'s column-order-onto-fields
# mapping through sqlite (driver links it automatically — the
# emitted C references rt_sqlite_)
out=$("$OXL" run tests/reflect.oxl) || { echo "FAIL reflect run exit=$?: $out"; exit 1; }
[ "$(tail -1 <<<"$out")" = "reflect ok" ] || { echo "FAIL reflect: $out"; exit 1; }
out=$("$OXL" run tests/fmt_v.oxl) || { echo "FAIL fmt_v run exit=$?: $out"; exit 1; }
[ "$(tail -1 <<<"$out")" = "fmt_v ok" ] || { echo "FAIL fmt_v: $out"; exit 1; }
out=$("$OXL" run tests/db_sql.oxl) || { echo "FAIL db_sql run exit=$?: $out"; exit 1; }
[ "$(tail -1 <<<"$out")" = "db_sql ok" ] || { echo "FAIL db_sql: $out"; exit 1; }
# r4: std/encoding/gob's descriptor-driven round-trip — preamble +
# field-delta wire, minted own/slice slots, name-matched tolerance
out=$("$OXL" run tests/enc_gob.oxl) || { echo "FAIL enc_gob run exit=$?: $out"; exit 1; }
[ "$(tail -1 <<<"$out")" = "enc_gob ok" ] || { echo "FAIL enc_gob: $out"; exit 1; }

echo "== xml + text/template (r5) =="
# the descriptor consumers: encoding/xml marshal/unmarshal routed by
# `tag "xml:..."` field metadata, text/template {{.F}}/{{range}}/{{if}}
# against descriptor names — both fixtures assert in-process and end
# with an ok line
out=$("$OXL" run tests/enc_xml.oxl)
[ "$(tail -1 <<<"$out")" = "enc_xml ok" ] || { echo "FAIL enc_xml: $out"; exit 1; }
out=$("$OXL" run tests/text_template.oxl)
[ "$(tail -1 <<<"$out")" = "text_template ok" ] || { echo "FAIL text_template: $out"; exit 1; }

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
    # OXL_CRYPTO mirrors emit_and_cc's rt_csrand scan — bcrypt links
    # only on Windows (the ws2_32/net pairing)
    cdef=""; clib=""
    grep -q 'rt_csrand(' "$cgen_dir/$2.c" && { cdef="-DOXL_CRYPTO"; clib="$CRYPTO_LIBS"; }
    "$CC" -O2 $THREAD_FLAG -Iruntime $def $net $mdef $cdef "$cgen_dir/$2.c" runtime/rt.c $lib $mlib $clib $NET_LIBS -o "$cgen_dir/$2$EXE" || { echo "FAIL codegen cc $1"; exit 1; }
}
for f in examples/hello.oxl examples/features.oxl tests/match.oxl tests/chanbuf.oxl tests/methods.oxl tests/pairfwd.oxl tests/spawn_forms.oxl tests/iface_susp.oxl tests/iface_susp_shim.oxl tests/iface_susp_pair.oxl tests/iface_susp_nested.oxl tests/iface_susp_rewrap.oxl tests/iface_susp_prop.oxl tests/iface_susp_convdest.oxl tests/iface_susp_cancel.oxl tests/iface_susp_ownarg.oxl tests/vtab_fn.oxl tests/reflect.oxl tests/fmt_v.oxl tests/enc_xml.oxl tests/text_template.oxl tests/enc_gob.oxl tests/db_sql.oxl; do
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
tnet=""; tmath=""; tmathlib=""; tcrypto=""; tcryptolib=""
grep -qE 'rt_sock_|rt_bind_any|rt_set_(reuseaddr|rcvtimo|sndtimo)|rt_htons|rt_htonl' "$cgen_dir/t.c" && tnet="-DOXL_NET"
grep -q 'rt_m_' "$cgen_dir/t.c" && { tmath="-DOXL_MATH"; tmathlib="$MATH_LIBS"; }
grep -q 'rt_csrand(' "$cgen_dir/t.c" && { tcrypto="-DOXL_CRYPTO"; tcryptolib="$CRYPTO_LIBS"; }
"$CC" -O2 $THREAD_FLAG -Iruntime $tnet $tmath $tcrypto "$cgen_dir/t.c" runtime/rt.c -DOXL_SQLITE $SQLITE_LINK $tmathlib $tcryptolib $NET_LIBS -o "$cgen_dir/t$EXE" || { echo "FAIL codegen cc --test"; exit 1; }
out=$("$cgen_dir/t$EXE")
grep -q "test_chan ... ok" <<<"$out" || { echo "FAIL codegen --test: $out"; exit 1; }
# s3 generics through the self-hosted emitter + cc — the same util
# coverage as `oxl test` above, exercising generic inst emission and
# the rt_m_ math-link scan
"$OXL" run bootstrap/cmd/codegen -- --test tests/util_test.oxl > "$cgen_dir/util.c"
um=""; umlib=""; ucrypto=""; ucryptolib=""
grep -q 'rt_m_' "$cgen_dir/util.c" && { um="-DOXL_MATH"; umlib="$MATH_LIBS"; }
grep -q 'rt_csrand(' "$cgen_dir/util.c" && { ucrypto="-DOXL_CRYPTO"; ucryptolib="$CRYPTO_LIBS"; }
"$CC" -O2 $THREAD_FLAG -Iruntime $um $ucrypto "$cgen_dir/util.c" runtime/rt.c $umlib $ucryptolib $NET_LIBS -o "$cgen_dir/util$EXE" || { echo "FAIL codegen cc util"; exit 1; }
out=$("$cgen_dir/util$EXE")
printf '%s
' "$out" >&2
for t in test_path test_filepath test_cmp test_sort test_slices test_maps test_math test_rand test_utf8; do
    grep -q "$t ... ok" <<<"$out" || { echo "FAIL codegen util: $out"; exit 1; }
done
# s4 enc/hash/crypto + x1/x3/x4 crypto through the self-hosted emitter +
# cc — exercises [][]str return emission (csv.read_all), hash/crypto,
# and the big-limb arithmetic under -test
for tf in enc hash crypto aesgcm chacha sha512 hkdf crypto_rand bignum rsa x25519 nistec ed25519 x509 tls_keys tls_handshake https; do
    "$OXL" run bootstrap/cmd/codegen -- --test "tests/${tf}_test.oxl" > "$cgen_dir/$tf.c"
    tfcrypto=""; tfcryptolib=""; tfnet=""
    grep -q 'rt_csrand(' "$cgen_dir/$tf.c" && { tfcrypto="-DOXL_CRYPTO"; tfcryptolib="$CRYPTO_LIBS"; }
    grep -qE 'rt_sock_|rt_bind_any|rt_set_(reuseaddr|rcvtimo|sndtimo)|rt_htons|rt_htonl' "$cgen_dir/$tf.c" && tfnet="-DOXL_NET"
    "$CC" -O2 $THREAD_FLAG -Iruntime $tfnet $tfcrypto "$cgen_dir/$tf.c" runtime/rt.c $tfcryptolib $NET_LIBS -o "$cgen_dir/$tf$EXE" || { echo "FAIL codegen cc $tf"; exit 1; }
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
for t in test_aes_block test_gcm test_gcm_carry; do
    grep -q "$t ... ok" "$cgen_dir/aesgcm.out" || { echo "FAIL codegen aesgcm $t"; cat "$cgen_dir/aesgcm.out"; exit 1; }
done
for t in test_chacha20 test_poly1305 test_aead; do
    grep -q "$t ... ok" "$cgen_dir/chacha.out" || { echo "FAIL codegen chacha $t"; cat "$cgen_dir/chacha.out"; exit 1; }
done
for t in test_sha512 test_sha384 test_hmac_sha512; do
    grep -q "$t ... ok" "$cgen_dir/sha512.out" || { echo "FAIL codegen sha512 $t"; cat "$cgen_dir/sha512.out"; exit 1; }
done
for t in test_hkdf; do
    grep -q "$t ... ok" "$cgen_dir/hkdf.out" || { echo "FAIL codegen hkdf $t"; cat "$cgen_dir/hkdf.out"; exit 1; }
done
for t in test_csrand; do
    grep -q "$t ... ok" "$cgen_dir/crypto_rand.out" || { echo "FAIL codegen crypto_rand $t"; cat "$cgen_dir/crypto_rand.out"; exit 1; }
done
for t in test_modmul test_modexp test_modinv; do
    grep -q "$t ... ok" "$cgen_dir/bignum.out" || { echo "FAIL codegen bignum $t"; cat "$cgen_dir/bignum.out"; exit 1; }
done
for t in test_rsav15 test_rsapss; do
    grep -q "$t ... ok" "$cgen_dir/rsa.out" || { echo "FAIL codegen rsa $t"; cat "$cgen_dir/rsa.out"; exit 1; }
done
for t in test_x25519; do
    grep -q "$t ... ok" "$cgen_dir/x25519.out" || { echo "FAIL codegen x25519 $t"; cat "$cgen_dir/x25519.out"; exit 1; }
done
for t in test_ecdh_p256 test_ecdh_p384 test_ecdsa; do
    grep -q "$t ... ok" "$cgen_dir/nistec.out" || { echo "FAIL codegen nistec $t"; cat "$cgen_dir/nistec.out"; exit 1; }
done
for t in test_ed25519; do
    grep -q "$t ... ok" "$cgen_dir/ed25519.out" || { echo "FAIL codegen ed25519 $t"; cat "$cgen_dir/ed25519.out"; exit 1; }
done
for t in test_parse test_chain_ok test_expired test_bad_name test_wildcard test_untrusted test_bad_ca test_sha1_reject test_eku test_ip_san test_self_anchor test_anchor_exemption test_critical_ext test_search_bounds test_badsig test_xsign_alternates; do
    grep -q "$t ... ok" "$cgen_dir/x509.out" || { echo "FAIL codegen x509 $t"; cat "$cgen_dir/x509.out"; exit 1; }
done
for t in test_keyschedule test_record; do
    grep -q "$t ... ok" "$cgen_dir/tls_keys.out" || { echo "FAIL codegen tls_keys $t"; cat "$cgen_dir/tls_keys.out"; exit 1; }
done
for t in test_handshake test_handshake_hrr test_handshake_cookie test_rawfd_and_adapters; do
    grep -q "$t ... ok" "$cgen_dir/tls_handshake.out" || { echo "FAIL codegen tls_handshake $t"; cat "$cgen_dir/tls_handshake.out"; exit 1; }
done
for t in test_url_https test_https_get test_https_bad_cert test_https_wrong_name test_https_redirect_noleak; do
    grep -q "$t ... ok" "$cgen_dir/https.out" || { echo "FAIL codegen https $t"; cat "$cgen_dir/https.out"; exit 1; }
done
# x5 env-root discovery through codegen — the same three
# configurations as the native lane
"$OXL" run bootstrap/cmd/codegen -- --test "tests/x509_env_test.oxl" > "$cgen_dir/x509env.c"
x5crypto=""; x5cryptolib=""
grep -q 'rt_csrand(' "$cgen_dir/x509env.c" && { x5crypto="-DOXL_CRYPTO"; x5cryptolib="$CRYPTO_LIBS"; }
"$CC" -O2 $THREAD_FLAG -Iruntime $x5crypto "$cgen_dir/x509env.c" runtime/rt.c $x5cryptolib $NET_LIBS -o "$cgen_dir/x509env$EXE" || { echo "FAIL codegen cc x509env"; exit 1; }
OXL_SSL_CERT_FILE=tests/fixtures/x509/roots.pem OXL_SSL_CERT_DIR= "$cgen_dir/x509env$EXE" > "$cgen_dir/x509env_file.out"
grep -q "test_env_file ... ok" "$cgen_dir/x509env_file.out" || { echo "FAIL codegen x509env file"; cat "$cgen_dir/x509env_file.out"; exit 1; }
OXL_SSL_CERT_FILE= OXL_SSL_CERT_DIR=tests/fixtures/x509/dir "$cgen_dir/x509env$EXE" > "$cgen_dir/x509env_dir.out"
grep -q "test_env_dir ... ok" "$cgen_dir/x509env_dir.out" || { echo "FAIL codegen x509env dir"; cat "$cgen_dir/x509env_dir.out"; exit 1; }
OXL_SSL_CERT_FILE=tests/fixtures/x509/does-not-exist.pem OXL_SSL_CERT_DIR= "$cgen_dir/x509env$EXE" > "$cgen_dir/x509env_bad.out"
grep -q "test_env_bad_path_fails ... ok" "$cgen_dir/x509env_bad.out" || { echo "FAIL codegen x509env bad"; cat "$cgen_dir/x509env_bad.out"; exit 1; }
OXL_SSL_CERT_FILE= OXL_SSL_CERT_DIR=tests/fixtures/x509/dirbad "$cgen_dir/x509env$EXE" > "$cgen_dir/x509env_dirbad.out"
grep -q "test_env_dir_bad_entry ... ok" "$cgen_dir/x509env_dirbad.out" || { echo "FAIL codegen x509env dirbad"; cat "$cgen_dir/x509env_dirbad.out"; exit 1; }
# s5 regexp through the self-hosted emitter + cc — the NFA engine is
# the heaviest pure-.oxl package (struct slices, closures, utf8)
"$OXL" run bootstrap/cmd/codegen -- --test "tests/regexp_test.oxl" > "$cgen_dir/rx.c"
rxcrypto=""; rxcryptolib=""
grep -q 'rt_csrand(' "$cgen_dir/rx.c" && { rxcrypto="-DOXL_CRYPTO"; rxcryptolib="$CRYPTO_LIBS"; }
"$CC" -O2 $THREAD_FLAG -Iruntime $rxcrypto "$cgen_dir/rx.c" runtime/rt.c $rxcryptolib $NET_LIBS -o "$cgen_dir/rx$EXE" || { echo "FAIL codegen cc regexp"; exit 1; }
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
    todocrypto=""; todocryptolib=""
    grep -q 'rt_csrand(' "$cgen_dir/todo.c" && { todocrypto="-DOXL_CRYPTO"; todocryptolib="$CRYPTO_LIBS"; }
    "$CC" -O2 $THREAD_FLAG -Iruntime $todonet $todocrypto "$cgen_dir/todo.c" runtime/rt.c "$cgen_dir/gui_shim.o" $(pkg-config --libs gtk4) $todocryptolib $NET_LIBS -o "$cgen_dir/todo$EXE" || { echo "FAIL codegen cc gui"; exit 1; }
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

echo "== llvm lane (l1) =="
# the emitted .ll + the rt.h-offset shim must agree on every boundary
# type — a drifted %OxlStr/%RtSlice/%RtFnv/%RtIface decl turns the
# shim's reads to garbage. Gated on clang (the lane's only consumer).
# Windows: `clang` on the runner is MSVC-target — it links only the
# msvcrt/kernel32 defaults, so rt.c's advapi32 (security attrs) and
# shell32 (CommandLineToArgvW) callers need explicit libs MinGW gcc
# would add itself.
if command -v clang >/dev/null 2>&1; then
    abilibs=""
    case "$(uname -s)" in
        MINGW*|MSYS*|CYGWIN*) abilibs="-ladvapi32 -lshell32" ;;
    esac
    # pin the emit-side ABI guess: a stale OXL_LLVM_ABI in the env
    # would spell the wrong boundary while the shim below is always
    # the host build
    OXL_LLVM_ABI= "$OXL" run bootstrap/cmd/codegen -- --emit llvm tests/llvm_abi_check.oxl > "$scratch/abi.ll" || { echo "FAIL llvm emit"; exit 1; }
    echo "  llvm abi: emitted"
    clang -O0 $THREAD_FLAG -Iruntime "$scratch/abi.ll" tests/llvm_abi_shim.c runtime/rt.c $abilibs -o "$scratch/abi_check$EXE" || { echo "FAIL llvm abi cc"; exit 1; }
    echo "  llvm abi: built"
    out=$("$scratch/abi_check$EXE" 2>&1) || {
        rc=$?
        echo "FAIL llvm abi run rc=$rc"
        printf '%s\n' "$out"
        # on a segfault, dump the backtrace — x86_64 can't reproduce
        if command -v lldb >/dev/null 2>&1; then
            lldb -b -o run -o "bt all" -o quit -- "$scratch/abi_check$EXE" 2>&1 | tail -50
        fi
        exit 1
    }
    grep -q "llvm_abi_check ok" <<<"$out" || { echo "FAIL llvm abi: $out"; exit 1; }
    echo "  llvm abi: ok"
else
    echo "  clang not found — skipping llvm abi probe"
fi

# fixture + success-marker table shared by the L2 (manual --emit llvm
# + clang) and L3 (driver --target llvm) gates — add a conformance
# file once and both lanes pick it up; a missing marker case is a
# suite bug, not a silent pass
LLVM_FIXTURES="conc_ping conc_scale select select_fair chan_own chanbuf chanbuf_close scope_exit orphan_join defer_order pairfwd susp_closure zero_str match methods fnval d5_qual stdmods_test susp_ownarg spawn_forms spawn_extern recv_narrow select_shadow susp_guard iface_susp iface_susp_shim iface_susp_pair iface_susp_nested iface_susp_rewrap iface_susp_prop iface_susp_convdest iface_susp_cancel iface_susp_ownarg vtab_fn closure_mcall closure_fnfield closure_shadow"
llvm_fixture_marker() {
    case "$1" in
        conc_ping)      marker='bounces=' ;;
        conc_scale)     marker='done' ;;
        select)         marker='select done' ;;
        select_fair)    marker='select fair ok' ;;
        chan_own)       marker='chan_own done' ;;
        chanbuf)        marker='chanbuf done' ;;
        chanbuf_close)  marker='chanbuf close ok' ;;
        scope_exit)     marker='scope-exit ok' ;;
        orphan_join)    marker='orphan-join ok' ;;
        defer_order)    marker='defer order ok' ;;
        pairfwd)        marker='pairfwd ok' ;;
        match)          marker='match ok' ;;
        methods)        marker='methods ok' ;;
        fnval)          marker='fnval ok' ;;
        d5_qual)        marker='d5 qual ok' ;;
        stdmods_test)   marker='done' ;;
        susp_closure)   marker='susp closure ok' ;;
        closure_mcall)  marker='closure mcall ok' ;;
        closure_fnfield) marker='closure fnfield ok' ;;
        closure_shadow) marker='closure shadow ok' ;;
        zero_str)       marker='zero str ok' ;;
        susp_ownarg)    marker='susp ownarg ok' ;;
        spawn_forms)    marker='spawn forms ok' ;;
        spawn_extern)   marker='spawn extern ok' ;;
        recv_narrow)    marker='recv narrow ok' ;;
        select_shadow)  marker='select shadow ok' ;;
        susp_guard)     marker='susp guard ok' ;;
        iface_susp)         marker='iface susp ok' ;;
        iface_susp_shim)    marker='iface susp shim ok' ;;
        iface_susp_pair)    marker='iface susp pair ok' ;;
        iface_susp_nested)  marker='iface susp nested ok' ;;
        iface_susp_rewrap)  marker='iface susp rewrap ok' ;;
        iface_susp_prop)    marker='iface susp prop ok' ;;
        iface_susp_convdest) marker='iface susp convdest ok' ;;
        iface_susp_cancel)  marker='iface susp cancel ok' ;;
        iface_susp_ownarg)  marker='iface susp ownarg ok' ;;
        vtab_fn)            marker='vtab fn ok' ;;
        *)                  marker='' ;;
    esac
}

echo "== llvm lane (l2) =="
# L2 conformance gate: the concurrency whitelist plus the non-conc
# corpus through the manual `--emit llvm` path — codegen emits .ll,
# clang compiles it against rt.c, each file's success marker is
# grepped (the js lane's marker table). Trap-expectation files
# (select_cancel/cancel_join) must print `escaped top scope` and exit
# non-zero — the native lane's abort shape. Same runtime, same
# observable behavior, IR instead of C.
if command -v clang >/dev/null 2>&1; then
    llibs="$THREAD_FLAG"
    case "$(uname -s)" in
        MINGW*|MSYS*|CYGWIN*) llibs="-ladvapi32 -lshell32" ;;
    esac
    for f in $LLVM_FIXTURES; do
        llvm_fixture_marker "$f"
        [ -n "$marker" ] || { echo "FAIL llvm lane $f: no marker in the shared table"; exit 1; }
        "$OXL" run bootstrap/cmd/codegen -- --emit llvm "tests/$f.oxl" > "$scratch/$f.ll" || { echo "FAIL llvm lane $f: emit"; exit 1; }
        clang -O0 -Iruntime "$scratch/$f.ll" runtime/rt.c $llibs -o "$scratch/$f$EXE" || { echo "FAIL llvm lane $f: cc"; exit 1; }
        out=$(with_timeout 60 "$scratch/$f$EXE" 2>&1) || { echo "FAIL llvm lane $f: $out"; exit 1; }
        grep -q "$marker" <<<"$out" || { echo "FAIL llvm lane $f marker '$marker': $out"; exit 1; }
        echo "  llvm l2: $f ok"
    done
    for f in select_cancel cancel_join; do
        "$OXL" run bootstrap/cmd/codegen -- --emit llvm "tests/$f.oxl" > "$scratch/$f.ll" || { echo "FAIL llvm lane $f: emit"; exit 1; }
        clang -O0 -Iruntime "$scratch/$f.ll" runtime/rt.c $llibs -o "$scratch/$f$EXE" || { echo "FAIL llvm lane $f: cc"; exit 1; }
        rc=0
        out=$(with_timeout 30 "$scratch/$f$EXE" 2>&1) || rc=$?
        # 124 is the watchdog's hang sentinel, not a trap — count it as
        # a hang like the native probes do, not a passing trap exit
        if [ "$rc" -eq 0 ] || [ "$rc" -eq 124 ]; then
            echo "FAIL llvm lane $f: expected trap exit, got rc=$rc"; exit 1
        fi
        grep -q 'escaped top scope' <<<"$out" || { echo "FAIL llvm lane $f: trap line: $out"; exit 1; }
        echo "  llvm l2: $f ok"
    done
else
    echo "  (skipped: clang not installed)"
fi

echo "== llvm lane (l3) =="
# L3 driver gate: the L1+L2 whitelist through the product driver's own
# `--target llvm` — compile_res picks emit_llvm, emit_and_llvm drives
# clang on out.ll+rt.c in one shot, run execs the produced native
# binary directly (no launcher — unlike the js lane's node). The
# _test corpus goes through `test --target llvm`, the trap files
# through `build --target llvm` + exec, and the flag surface probes
# --emit-llvm (out.ll kept beside -o, triple-neutral), the
# --triple/--emit-llvm/--html wrong-lane rejections, a host --triple
# passthrough, and pick_clang's named floor error under a stale
# LANG_CLANG. Gated on clang like the node gate — a runner without it
# skips with the reason spelled out.
if command -v clang >/dev/null 2>&1; then
    for f in $LLVM_FIXTURES; do
        llvm_fixture_marker "$f"
        [ -n "$marker" ] || { echo "FAIL llvm l3 $f: no marker in the shared table"; exit 1; }
        out=$(with_timeout 180 "$OXL" run --target llvm "tests/$f.oxl" 2>&1) || { echo "FAIL llvm l3 $f: $out"; exit 1; }
        grep -q "$marker" <<<"$out" || { echo "FAIL llvm l3 $f marker '$marker': $out"; exit 1; }
        echo "  llvm l3 run: $f ok"
    done
    # the _test corpus through `test --target llvm` — the testm=1
    # wrappers (dynamic RtScope allocas) through the same driver path.
    # Output goes to a file, not $( ) — a capture pipe whose write end a
    # spawned grandchild inherits can't hold the substitution open past
    # the watchdog, and on timeout the survivors report themselves
    for f in stdlib_test float_test regexp_test util_test enc_test; do
        lf="$scratch/l3test-$f.out"
        if ! with_timeout 180 "$OXL" test --target llvm "tests/$f.oxl" >"$lf" 2>&1; then
            echo "FAIL llvm l3 test $f:"
            cat "$lf"
            ps -axo pid,ppid,pgid,stat,etime,command 2>/dev/null | head -50
            exit 1
        fi
        grep -q ' \.\.\. ok' "$lf" || { echo "FAIL llvm l3 test $f:"; cat "$lf"; exit 1; }
        echo "  llvm l3 test: $f ok"
    done
    # trap files through build + exec — the produced native binary
    # must carry the abort shape itself
    for f in select_cancel cancel_join; do
        "$OXL" build --target llvm "tests/$f.oxl" -o "$scratch/$f-l3$EXE" || { echo "FAIL llvm l3 $f: build"; exit 1; }
        rc=0
        out=$(with_timeout 30 "$scratch/$f-l3$EXE" 2>&1) || rc=$?
        # same as the native probes: 124 is the watchdog's hang
        # sentinel — a hang is a fail, not a trap exit
        if [ "$rc" -eq 0 ] || [ "$rc" -eq 124 ]; then
            echo "FAIL llvm l3 $f: expected trap exit, got rc=$rc"; exit 1
        fi
        grep -q 'escaped top scope' <<<"$out" || { echo "FAIL llvm l3 $f: trap line: $out"; exit 1; }
        echo "  llvm l3: $f ok"
    done
    # --emit-llvm keeps <out>.ll beside the binary — and the kept IR
    # must stay triple-neutral (no `target triple`/`datalayout` lines:
    # clang supplies both from -target, an emitted triple would
    # override the --triple passthrough)
    "$OXL" build --target llvm tests/select.oxl -o "$scratch/el$EXE" || { echo "FAIL llvm l3 build"; exit 1; }
    [ ! -f "$scratch/el$EXE.ll" ] || { echo "FAIL llvm l3: .ll kept without --emit-llvm"; exit 1; }
    "$OXL" build --target llvm --emit-llvm tests/select.oxl -o "$scratch/el$EXE" || { echo "FAIL llvm l3 --emit-llvm build"; exit 1; }
    [ -f "$scratch/el$EXE.ll" ] || { echo "FAIL llvm l3: --emit-llvm kept no .ll"; exit 1; }
    grep -qE '^target (triple|datalayout)' "$scratch/el$EXE.ll" && { echo "FAIL llvm l3: .ll not triple-neutral"; exit 1; }
    # a second --emit-llvm build to a different -o lands its own .ll
    # (the fixed out.ll name used to overwrite across builds)
    "$OXL" build --target llvm --emit-llvm tests/select.oxl -o "$scratch/el2$EXE" || { echo "FAIL llvm l3 --emit-llvm second build"; exit 1; }
    [ -f "$scratch/el2$EXE.ll" ] || { echo "FAIL llvm l3: second build kept no .ll"; exit 1; }
    # --triple passthrough: the lane's own reach claim is the local
    # clang's configured reach — smoke the flag with the host triple
    # (cross sysroots are the runner's clang's problem)
    host_triple=$(clang -print-target-triple 2>/dev/null || true)
    if [ -n "$host_triple" ]; then
        "$OXL" build --target llvm --triple "$host_triple" tests/select.oxl -o "$scratch/tr$EXE" || { echo "FAIL llvm l3 --triple host: build"; exit 1; }
        out=$(with_timeout 30 "$scratch/tr$EXE") || { echo "FAIL llvm l3 --triple host: run"; exit 1; }
        grep -q 'select done' <<<"$out" || { echo "FAIL llvm l3 --triple host: $out"; exit 1; }
        # the triple must reach the SELECTED clang's argv — a dropped
        # -target compiles for the compiler's default while the ABI
        # spelling targets --triple. A LANG_CLANG spy logs every argv
        # and delegates to the real clang; POSIX-only like the floor
        # probe (CreateProcess can't exec a shell script)
        case "$(uname -s)" in
            MINGW*|MSYS*|CYGWIN*) ;;
            *)
                cat > "$scratch/clangspy" <<EOF
#!/bin/sh
echo "\$@" >> "$scratch/clangspy.args"
for a in "\$@"; do
    if [ "\$a" = "--version" ]; then
        echo "clang version 17.0.0 (spy)"
        exit 0
    fi
done
exec clang "\$@"
EOF
                chmod +x "$scratch/clangspy"
                : > "$scratch/clangspy.args"
                out=$(LANG_CLANG="$scratch/clangspy" "$OXL" build --target llvm --triple "$host_triple" tests/select.oxl -o "$scratch/tr2$EXE" 2>&1) || { echo "FAIL llvm l3 --triple spy build: $out"; exit 1; }
                # the link invocation (the argv carrying -o) must spell
                # -target with the resolved triple
                awk -v t="$host_triple" 'index($0, "-o ") && index($0, "-target " t) {ok=1} END{exit !ok}' "$scratch/clangspy.args" || { echo "FAIL llvm l3 --triple: selected clang got no -target: $(cat "$scratch/clangspy.args")"; exit 1; }
                out=$(with_timeout 30 "$scratch/tr2$EXE") || { echo "FAIL llvm l3 --triple spy: run"; exit 1; }
                grep -q 'select done' <<<"$out" || { echo "FAIL llvm l3 --triple spy: $out"; exit 1; }
                # feature detection keys off live @sym refs, not string
                # data — printing "rt_sqlite_open" et al must not flip
                # OXL_SQLITE/OXL_NET/OXL_CRYPTO in the clang argv
                cat > "$scratch/strsqlite.oxl" <<'EOF'
package main
fn main() {
    println("rt_sqlite_open rt_sock_connect rt_csrand rt_m_sin")
}
EOF
                : > "$scratch/clangspy.args"
                out=$(LANG_CLANG="$scratch/clangspy" "$OXL" build --target llvm "$scratch/strsqlite.oxl" -o "$scratch/strsqlite$EXE" 2>&1) || { echo "FAIL llvm l3 strsqlite build: $out"; exit 1; }
                if grep -qE -- '-DOXL_(SQLITE|NET|CRYPTO|MATH)|-lsqlite3|-lws2_32|-lbcrypt' "$scratch/clangspy.args"; then
                    echo "FAIL llvm l3: string constant flipped a feature flag: $(cat "$scratch/clangspy.args")"; exit 1
                fi
                out=$(with_timeout 30 "$scratch/strsqlite$EXE") || { echo "FAIL llvm l3 strsqlite: run"; exit 1; }
                grep -q 'rt_sqlite_open' <<<"$out" || { echo "FAIL llvm l3 strsqlite: $out"; exit 1; }
                ;;
        esac
    fi
    # malformed --triple forms are usage errors — an empty, missing,
    # or flag-shaped value must not silently mean "build for host",
    # while a --triple past `--` is the child's own argv
    out=$("$OXL" build --target llvm tests/select.oxl --triple -o "$scratch/x" 2>&1) && { echo "FAIL llvm l3: flag-valued --triple accepted"; exit 1; }
    grep -q -- '--triple needs a target triple' <<<"$out" || { echo "FAIL llvm l3 --triple flag-value msg: $out"; exit 1; }
    out=$("$OXL" build --target llvm tests/select.oxl --triple= -o "$scratch/x" 2>&1) && { echo "FAIL llvm l3: --triple= accepted"; exit 1; }
    grep -q -- '--triple needs a target triple' <<<"$out" || { echo "FAIL llvm l3 --triple= msg: $out"; exit 1; }
    out=$("$OXL" build --target llvm tests/select.oxl -o "$scratch/x" --triple 2>&1) && { echo "FAIL llvm l3: valueless --triple accepted"; exit 1; }
    grep -q -- '--triple needs a target triple' <<<"$out" || { echo "FAIL llvm l3 --triple missing msg: $out"; exit 1; }
    # llvm_gate: box/errors.as fold to descriptor machinery with no
    # LLVM lowering — a clear diagnostic, not an @box call dying at
    # the IR parse
    out=$("$OXL" build tests/errors_as.oxl --target llvm -o "$scratch/x" 2>&1) && { echo "FAIL llvm l3: box accepted"; exit 1; }
    grep -q 'not supported under --target llvm' <<<"$out" || { echo "FAIL llvm l3 box msg: $out"; exit 1; }
    echo "  llvm l3: gate probes ok"
    # a --triple past `--` is the child's own argv — the driver's
    # malformed-value scan and flag_value both stop at the boundary
    out=$("$OXL" run tests/child_args.oxl -- --triple x86_64-pc-win32-msvc 2>&1) || { echo "FAIL child -- args: $out"; exit 1; }
    grep -q 'x86_64-pc-win32-msvc' <<<"$out" || { echo "FAIL llvm l3: -- ate the child's --triple: $out"; exit 1; }
    echo "  llvm l3: child -- boundary ok"
    # wrong-lane flag rejections — errors, not warnings
    out=$("$OXL" build tests/select.oxl --triple x -o "$scratch/x" 2>&1) && { echo "FAIL llvm l3: --triple accepted on native"; exit 1; }
    grep -q -- '--triple needs' <<<"$out" || { echo "FAIL llvm l3 --triple msg: $out"; exit 1; }
    out=$("$OXL" build tests/select.oxl --target js --triple x -o "$scratch/x" 2>&1) && { echo "FAIL llvm l3: --triple accepted on js"; exit 1; }
    out=$("$OXL" build tests/select.oxl --emit-llvm -o "$scratch/x" 2>&1) && { echo "FAIL llvm l3: --emit-llvm accepted on native"; exit 1; }
    grep -q -- '--emit-llvm needs' <<<"$out" || { echo "FAIL llvm l3 --emit-llvm off-lane msg: $out"; exit 1; }
    out=$("$OXL" run tests/select.oxl --target llvm --emit-llvm 2>&1) && { echo "FAIL llvm l3: --emit-llvm accepted on run"; exit 1; }
    grep -q -- "only applies to" <<<"$out" || { echo "FAIL llvm l3 --emit-llvm scope msg: $out"; exit 1; }
    out=$("$OXL" build tests/select.oxl --target llvm --html -o "$scratch/x" 2>&1) && { echo "FAIL llvm l3: --html accepted on llvm"; exit 1; }
    out=$("$OXL" build tests/select.oxl --target bogus -o "$scratch/x" 2>&1) && { echo "FAIL llvm l3: bogus --target accepted"; exit 1; }
    grep -q 'native, js, or llvm' <<<"$out" || { echo "FAIL llvm l3 --target msg: $out"; exit 1; }
    echo "  llvm l3: flag surface ok"
    # pick_clang's named floor error — a stale LANG_CLANG fails fast
    # rather than dying on an IR parse error. POSIX-only: the probe is
    # a shell script, which CreateProcess can't exec on Windows (the
    # version-parse logic itself is platform-neutral)
    case "$(uname -s)" in
        MINGW*|MSYS*|CYGWIN*) ;;
        *)
            printf '#!/bin/sh\necho "clang version 14.0.0 (stale)"\n' > "$scratch/clang14"
            chmod +x "$scratch/clang14"
            out=$(LANG_CLANG="$scratch/clang14" "$OXL" build tests/select.oxl --target llvm -o "$scratch/x" 2>&1) && { echo "FAIL llvm l3: stale clang accepted"; exit 1; }
            grep -q 'clang >= 15' <<<"$out" || { echo "FAIL llvm l3 floor msg: $out"; exit 1; }
            echo "  llvm l3: toolchain floor ok"
            ;;
    esac
else
    echo "  (skipped: clang not installed — the lane's only consumer)"
fi

echo "== llvm lane (l4) =="
# L4 gate: the lane's own fixpoint + cross-lane output parity, plus
# the implicit coverage claim — the llvm lane compiles the *whole*
# toolchain (cmd/oxl + bootstrap/* end-to-end under --target llvm).
#
# IR fixpoint (ADR-0006 one lane over): the C-lane-built product
# driver emits drv1.ll for the driver sources; the same driver
# rebuilt *via --target llvm* (target/oxl-llvm — an in-repo path so
# its exe-walk finds std/ and runtime/) emits drv2.ll; the two must
# be byte-identical. The C-text fixpoint above stays the shared
# regression guard — this is the lane's own determinism claim.
#
# Cross-lane parity: llvm_abi_check plus the conformance whitelist
# are built through BOTH lanes (manual codegen emit + cc/clang, and
# the product driver's --target llvm path is exercised by l3 already)
# and their program output diffed — same runtime, same observable
# behavior, IR instead of C. Where the native build needs the ABI
# shim, tests/llvm_abi_shim.c rides along on both compile lines.
if command -v clang >/dev/null 2>&1; then
    l4libs="$THREAD_FLAG"
    case "$(uname -s)" in
        MINGW*|MSYS*|CYGWIN*) l4libs="-ladvapi32 -lshell32" ;;
    esac
    "$OXL" run bootstrap/cmd/codegen -- --emit llvm cmd/oxl > "$scratch/drv1.ll" || { echo "FAIL llvm l4: drv1 emit"; exit 1; }
    echo "  llvm l4: drv1.ll emitted ($(wc -l < "$scratch/drv1.ll") lines)"
    "$OXL" build cmd/oxl --target llvm -o "target/oxl-llvm$EXE" || { echo "FAIL llvm l4: driver build --target llvm"; exit 1; }
    LLVMOXL="$PWD/target/oxl-llvm$EXE"
    echo "  llvm l4: toolchain compiled end-to-end under --target llvm"
    "$LLVMOXL" run bootstrap/cmd/codegen -- --emit llvm cmd/oxl > "$scratch/drv2.ll" || { echo "FAIL llvm l4: drv2 emit"; exit 1; }
    diff "$scratch/drv1.ll" "$scratch/drv2.ll" >/dev/null || { echo "FAIL llvm l4: IR fixpoint"; diff "$scratch/drv1.ll" "$scratch/drv2.ll" | head -20; exit 1; }
    echo "  llvm l4: IR fixpoint clean"
    # the llvm-built driver is itself a conformance subject: the smoke
    # sections' assertions re-run under it (hello, features, match,
    # methods — same markers as their native sections)
    out=$("$LLVMOXL" run examples/hello.oxl)
    [ "$out" = "hello, world" ] || { echo "FAIL llvm l4 driver hello: $out"; exit 1; }
    out=$("$LLVMOXL" run examples/features.oxl)
    [ "$(tail -1 <<<"$out")" = "done" ] || { echo "FAIL llvm l4 driver features"; exit 1; }
    out=$(with_timeout 60 "$LLVMOXL" run tests/match.oxl)
    grep -q 'match ok' <<<"$out" || { echo "FAIL llvm l4 driver match: $out"; exit 1; }
    out=$(with_timeout 60 "$LLVMOXL" run tests/methods.oxl)
    grep -q 'methods ok' <<<"$out" || { echo "FAIL llvm l4 driver methods: $out"; exit 1; }
    echo "  llvm l4: llvm-built driver smoke ok"
    # cross-lane parity table — one line per corpus file: native-lane
    # binary output vs llvm-lane binary output, byte-diffed. The
    # trap-expectation files are l3's; every file here exits 0.
    for f in select chan_own chanbuf chanbuf_close scope_exit orphan_join defer_order pairfwd susp_closure zero_str match methods fnval d5_qual susp_ownarg spawn_forms iface_susp iface_susp_shim iface_susp_pair iface_susp_nested iface_susp_rewrap iface_susp_prop iface_susp_convdest iface_susp_cancel iface_susp_ownarg vtab_fn closure_mcall closure_fnfield closure_shadow; do
        "$OXL" build "tests/$f.oxl" -o "$scratch/$f-c$EXE" || { echo "FAIL llvm l4 parity $f: native build"; exit 1; }
        "$OXL" build --target llvm "tests/$f.oxl" -o "$scratch/$f-l$EXE" || { echo "FAIL llvm l4 parity $f: llvm build"; exit 1; }
        cout=$(with_timeout 60 "$scratch/$f-c$EXE" 2>&1) || { echo "FAIL llvm l4 parity $f: native run"; exit 1; }
        lout=$(with_timeout 60 "$scratch/$f-l$EXE" 2>&1) || { echo "FAIL llvm l4 parity $f: llvm run"; exit 1; }
        [ "$cout" = "$lout" ] || { echo "FAIL llvm l4 parity $f: $cout vs $lout"; exit 1; }
        echo "  llvm l4 parity: $f ok"
    done
    # conc_ping/conc_scale/select_fair/stdmods_test stay out of the
    # diff table — scheduling/fairness counters and wall-clock prints
    # make their output nondeterministic; l2/l3 already marker-gate
    # them.
    # llvm_abi_check both ways: the shim compiles against rt.h for
    # both emits, so the same probe binary contract holds on either
    # lane — outputs must match byte-for-byte.
    "$OXL" run bootstrap/cmd/codegen -- tests/llvm_abi_check.oxl > "$scratch/abi.c" || { echo "FAIL llvm l4 abi: native emit"; exit 1; }
    "$CC" -O0 -Iruntime "$scratch/abi.c" tests/llvm_abi_shim.c runtime/rt.c $l4libs -o "$scratch/abi-c$EXE" || { echo "FAIL llvm l4 abi: native cc"; exit 1; }
    "$OXL" run bootstrap/cmd/codegen -- --emit llvm tests/llvm_abi_check.oxl > "$scratch/abi-l4.ll" || { echo "FAIL llvm l4 abi: llvm emit"; exit 1; }
    clang -O0 -Iruntime "$scratch/abi-l4.ll" tests/llvm_abi_shim.c runtime/rt.c $l4libs -o "$scratch/abi-l$EXE" || { echo "FAIL llvm l4 abi: clang"; exit 1; }
    # slice.heap prints a live alloc address — mask it before the diff
    cout=$(with_timeout 30 "$scratch/abi-c$EXE" 2>&1 | sed 's/slice.heap=.*/slice.heap=X/') || { echo "FAIL llvm l4 abi: native run"; exit 1; }
    lout=$(with_timeout 30 "$scratch/abi-l$EXE" 2>&1 | sed 's/slice.heap=.*/slice.heap=X/') || { echo "FAIL llvm l4 abi: llvm run"; exit 1; }
    [ "$cout" = "$lout" ] || { echo "FAIL llvm l4 abi parity: $cout vs $lout"; exit 1; }
    grep -q "llvm_abi_check ok" <<<"$lout" || { echo "FAIL llvm l4 abi: $lout"; exit 1; }
    echo "  llvm l4 parity: llvm_abi_check ok"
else
    echo "  (skipped: clang not installed — the lane's only consumer)"
fi

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
# are byte-identical stderr + exit codes (2/2/2). The stage-0 snapshot
# compiles the same driver sources as gen1, so no output scrubbing is
# needed — seed and self are the same program at different generations.
for inv in "" "bogus" "list"; do
    seed_out=$("$SEEDOXL" $inv 2>&1) && seed_rc=0 || seed_rc=$?
    self_out=$("$SELFOXL" $inv 2>&1) && self_rc=0 || self_rc=$?
    if [ "$seed_out" != "$self_out" ] || [ "$seed_rc" != "$self_rc" ]; then
        echo "FAIL driver parity: \`oxl $inv\`"
        echo "-- seed ($seed_rc) --"; printf '%s\n' "$seed_out"
        echo "-- self ($self_rc) --"; printf '%s\n' "$self_out"
        exit 1
    fi
done

# #144: driver diagnostics carry file:line:col — a package-dir build must
# point at the offending file/line, not just print a bare kind+msg.
mkdir -p "$scratch/diagpos"
printf 'package main\nfn main() {}\n' > "$scratch/diagpos/a.oxl"
cat > "$scratch/diagpos/b.oxl" <<'EOF'
package main

fn f() -> int {
    return "s"
}
EOF
diagpos_out=$("$SELFOXL" build "$scratch/diagpos" -o "$scratch/diagposbin" 2>&1 || true)
printf '%s\n' "$diagpos_out" | grep -Eq 'diagpos/b\.oxl:[0-9]+:[0-9]+: error \[type\] expected `int`, found `str`' || { echo "FAIL diag position: $diagpos_out"; exit 1; }

# #145: the `[T, err]` rule is validated at the signature, not only at
# return sites — a `[str, str]` declaration must fail on the second
# member instead of compiling because its only return delegates.
cat > "$scratch/pairsig.oxl" <<'EOF'
package main

fn h() -> [str, err] {
    return "a", nil
}

fn g() -> [str, str] {
    return h()
}

fn main() {}
EOF
pairsig_out=$("$SELFOXL" build "$scratch/pairsig.oxl" -o "$scratch/pairsigbin" 2>&1 || true)
printf '%s\n' "$pairsig_out" | grep -Eq 'pairsig\.oxl:[0-9]+:[0-9]+: error \[type\] multi-return signature must be' || { echo "FAIL pair signature position: $pairsig_out"; exit 1; }
if printf '%s\n' "$pairsig_out" | grep -q 'expected `err`, found `str`'; then
    echo "FAIL pair signature still diagnosed at return site: $pairsig_out"; exit 1
fi

# #131: package-dir args — `oxl test` fans out over every leading dir,
# build/run reject multiples, mixed dir+file lists and stray args are
# loud usage errors (exit 2), and driver flags may interleave between
# dirs. Scratch fixtures keep this out of the tests/ corpus.
mkdir -p "$scratch/mp/a" "$scratch/mp/b"
printf 'package main\nimport "std/testing"\nfn test_a() { testing.expect(1 == 1, "a ok") }\nfn main() {}\n' > "$scratch/mp/a/a_test.oxl"
printf 'package main\nimport "std/testing"\nfn test_b() { testing.expect(2 == 2, "b ok") }\nfn main() {}\n' > "$scratch/mp/b/b_test.oxl"
mp_out=$("$SELFOXL" test "$scratch/mp/a" "$scratch/mp/b" 2>&1) && mp_rc=0 || mp_rc=$?
[ "$mp_rc" = 0 ] || { echo "FAIL multi-dir test rc=$mp_rc"; printf '%s\n' "$mp_out"; exit 1; }
printf '%s' "$mp_out" | grep -q "test_a" || { echo "FAIL multi-dir: pkg a not run"; printf '%s\n' "$mp_out"; exit 1; }
printf '%s' "$mp_out" | grep -q "test_b" || { echo "FAIL multi-dir: pkg b not run"; printf '%s\n' "$mp_out"; exit 1; }
# flags may sit between package dirs
mp_out=$("$SELFOXL" test "$scratch/mp/a" --target c "$scratch/mp/b" 2>&1) && mp_rc=0 || mp_rc=$?
[ "$mp_rc" = 0 ] || { echo "FAIL interleaved-flag test rc=$mp_rc"; printf '%s\n' "$mp_out"; exit 1; }
# build takes exactly one package
"$SELFOXL" build "$scratch/mp/a" "$scratch/mp/b" -o "$scratch/mpbin" >"$scratch/mpb.out" 2>&1 && mp_rc=0 || mp_rc=$?
[ "$mp_rc" = 2 ] || { echo "FAIL multi-dir build rc=$mp_rc (want 2)"; cat "$scratch/mpb.out"; exit 1; }
# a stray non-source arg is a usage error, not silent program argv
"$SELFOXL" test "$scratch/mp/a" "$scratch/mp/nope" >"$scratch/mps.out" 2>&1 && mp_rc=0 || mp_rc=$?
[ "$mp_rc" = 2 ] || { echo "FAIL stray-arg test rc=$mp_rc (want 2)"; cat "$scratch/mps.out"; exit 1; }
# mixing dirs and file lists is a usage error
"$SELFOXL" test "$scratch/mp/a" "$scratch/mp/b/b_test.oxl" >"$scratch/mpm.out" 2>&1 && mp_rc=0 || mp_rc=$?
[ "$mp_rc" = 2 ] || { echo "FAIL mixed-args test rc=$mp_rc (want 2)"; cat "$scratch/mpm.out"; exit 1; }
# a trailing flag with no value is loud, not silently defaulted
"$SELFOXL" build "$scratch/mp/a" -o >"$scratch/mpo.out" 2>&1 && mp_rc=0 || mp_rc=$?
[ "$mp_rc" != 0 ] || { echo "FAIL missing -o value accepted"; cat "$scratch/mpo.out"; exit 1; }
# the diag corpus through the whole driver pipeline (load + check +
# emit + cc): every fixture must fail identically on both drivers —
# same text, same exit code, and neither side may accept
for f in tests/diag/*.oxl; do
    seed_out=$("$SEEDOXL" build "$f" -o "$scratch/drvbin" 2>&1 | sed -E 's/^([A-Za-z]:)?[^:]*:[0-9]+:[0-9]+: //') && seed_rc=0 || seed_rc=$?
    self_out=$("$SELFOXL" build "$f" -o "$scratch/drvbin2" 2>&1 | sed -E 's/^([A-Za-z]:)?[^:]*:[0-9]+:[0-9]+: //') && self_rc=0 || self_rc=$?
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
    seed_out=$("$SEEDOXL" build "$f" -o "$scratch/drvbin" 2>&1 | sed -E 's/^([A-Za-z]:)?[^:]*:[0-9]+:[0-9]+: //') && seed_rc=0 || seed_rc=$?
    self_out=$("$SELFOXL" build "$f" -o "$scratch/drvbin2" 2>&1 | sed -E 's/^([A-Za-z]:)?[^:]*:[0-9]+:[0-9]+: //') && self_rc=0 || self_rc=$?
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
# #136 regression: mkslice-qual must RUN, not just build — the bug
# was a runtime heap miscompile (int64 storage for a struct element)
# that compiles cleanly; only the self driver is run since the seed
# predates the fix.
"$SELFOXL" build tests/mod/mkslice-qual -o "$scratch/mkslicequal" >/dev/null 2>&1 || { echo "FAIL mkslice-qual build"; exit 1; }
"$scratch/mkslicequal" > "$scratch/mkslicequal.out" 2>&1 || { echo "FAIL mkslice-qual run"; cat "$scratch/mkslicequal.out"; exit 1; }
grep -q "mkslice-qual ok" "$scratch/mkslicequal.out" || { echo "FAIL mkslice-qual output"; cat "$scratch/mkslicequal.out"; exit 1; }
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
seed_out=$("$SEEDOXL" build "$scratch/flist/m.oxl" "$scratch/flother/o.oxl" -o "$scratch/flbin" 2>&1 | sed -E 's/^([A-Za-z]:)?[^:]*:[0-9]+:[0-9]+: //') && seed_rc=0 || seed_rc=$?
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
# R1: the descriptor lane is codegen-emitted, so index order, offsets,
# kind codes, and variant metadata must be byte-identical through both
# drivers — the fixture prints the whole table digest
seed_out=$("$SEEDOXL" run tests/desc_parity.oxl 2>&1 | sed -E 's/^([A-Za-z]:)?[^:]*:[0-9]+:[0-9]+: //' | sed -E 's/^([A-Za-z]:)?[^:]*:[0-9]+:[0-9]+: //') && seed_rc=0 || seed_rc=$?
self_out=$("$SELFOXL" run tests/desc_parity.oxl 2>&1 | sed -E 's/^([A-Za-z]:)?[^:]*:[0-9]+:[0-9]+: //' | sed -E 's/^([A-Za-z]:)?[^:]*:[0-9]+:[0-9]+: //') && self_rc=0 || self_rc=$?
# matching failure IS a failure — both runs must exit 0, not just agree
if [ "$seed_rc" != 0 ] || [ "$self_rc" != 0 ]; then
    echo "FAIL tests/desc_parity.oxl native run: seed rc=$seed_rc self rc=$self_rc"
    echo "-- seed --"; printf '%s
' "$seed_out"
    echo "-- self --"; printf '%s
' "$self_out"
    exit 1
fi
if [ "$seed_out" != "$self_out" ] || [ "$seed_rc" != "$self_rc" ]; then
    echo "FAIL driver parity tests/desc_parity.oxl"
    echo "-- seed ($seed_rc) --"; printf '%s
' "$seed_out"
    echo "-- self ($self_rc) --"; printf '%s
' "$self_out"
    exit 1
fi
grep -q 'desc_parity ok' <<<"$self_out" || { echo "FAIL desc_parity output"; printf '%s
' "$self_out"; exit 1; }
# and the js lane rejects every R1 surface identically on both drivers
seed_out=$("$SEEDOXL" build tests/desc_parity.oxl --target js -o "$scratch/descjs" 2>&1 | sed -E 's/^([A-Za-z]:)?[^:]*:[0-9]+:[0-9]+: //') && seed_rc=0 || seed_rc=$?
self_out=$("$SELFOXL" build tests/desc_parity.oxl --target js -o "$scratch/descjs2" 2>&1 | sed -E 's/^([A-Za-z]:)?[^:]*:[0-9]+:[0-9]+: //') && self_rc=0 || self_rc=$?
if [ "$seed_rc" = 0 ] || [ "$self_rc" = 0 ]; then
    echo "FAIL --target js accepted the descriptor lane"; exit 1
fi
if [ "$seed_out" != "$self_out" ] || [ "$seed_rc" != "$self_rc" ]; then
    echo "FAIL driver parity desc --target js"
    echo "-- seed --"; printf '%s
' "$seed_out"
    echo "-- self --"; printf '%s
' "$self_out"
    exit 1
fi
# the descriptor runtime lane — elem_ptr on borrow-qualified slots,
# double-handle value_of loads, reflect handles embedded in pair
# aggregates, and the rt_desc_alloc* overflow guards
seed_out=$("$SEEDOXL" run tests/desc_rt.oxl 2>&1 | sed -E 's/^([A-Za-z]:)?[^:]*:[0-9]+:[0-9]+: //' | sed -E 's/^([A-Za-z]:)?[^:]*:[0-9]+:[0-9]+: //') && seed_rc=0 || seed_rc=$?
self_out=$("$SELFOXL" run tests/desc_rt.oxl 2>&1 | sed -E 's/^([A-Za-z]:)?[^:]*:[0-9]+:[0-9]+: //' | sed -E 's/^([A-Za-z]:)?[^:]*:[0-9]+:[0-9]+: //') && self_rc=0 || self_rc=$?
if [ "$seed_rc" != 0 ] || [ "$self_rc" != 0 ]; then
    echo "FAIL tests/desc_rt.oxl native run: seed rc=$seed_rc self rc=$self_rc"
    echo "-- seed --"; printf '%s
' "$seed_out"
    echo "-- self --"; printf '%s
' "$self_out"
    exit 1
fi
if [ "$seed_out" != "$self_out" ]; then
    echo "FAIL driver parity tests/desc_rt.oxl"
    echo "-- seed --"; printf '%s
' "$seed_out"
    echo "-- self --"; printf '%s
' "$self_out"
    exit 1
fi
grep -q 'desc_rt ok' <<<"$self_out" || { echo "FAIL desc_rt output"; printf '%s
' "$self_out"; exit 1; }
# a local fn value shadowing an intrinsic name is NOT the resolved
# intrinsic — the --target js gate keys on resolved call sites, so the
# shadow must build cleanly on both drivers
printf 'package main\n\nfn add1(x: int) -> int {\n    return x + 1\n}\n\nfn main() {\n    value_of := add1\n    println(itoa(value_of(41)))\n}\n' > "$scratch/jsshadow.oxl"
"$SEEDOXL" build "$scratch/jsshadow.oxl" --target js -o "$scratch/jsshad" >/dev/null 2>&1 || { echo "FAIL --target js shadowed value_of: seed rejected"; exit 1; }
"$SELFOXL" build "$scratch/jsshadow.oxl" --target js -o "$scratch/jsshad2" >/dev/null 2>&1 || { echo "FAIL --target js shadowed value_of: self rejected"; exit 1; }
# R3: typed err payloads — box folds to rt_err_box (heap-copy for
# values, handle move for own) and errors.as folds to rt_err_as; the
# fixture exercises round-trip, exact-descr match, once-only
# consumption, and wrapped-chain walking through both drivers
seed_out=$("$SEEDOXL" run tests/errors_as.oxl 2>&1 | sed -E 's/^([A-Za-z]:)?[^:]*:[0-9]+:[0-9]+: //') && seed_rc=0 || seed_rc=$?
self_out=$("$SELFOXL" run tests/errors_as.oxl 2>&1 | sed -E 's/^([A-Za-z]:)?[^:]*:[0-9]+:[0-9]+: //') && self_rc=0 || self_rc=$?
if [ "$seed_out" != "$self_out" ] || [ "$seed_rc" != "$self_rc" ]; then
    echo "FAIL driver parity tests/errors_as.oxl"
    echo "-- seed ($seed_rc) --"; printf '%s
' "$seed_out"
    echo "-- self ($self_rc) --"; printf '%s
' "$self_out"
    exit 1
fi
grep -q 'errors_as ok' <<<"$self_out" || { echo "FAIL errors_as output"; printf '%s\n' "$self_out"; exit 1; }
if grep -q '(BUG)' <<<"$self_out"; then echo "FAIL errors_as BUG marker"; printf '%s\n' "$self_out"; exit 1; fi
# and the js lane rejects box/errors.as fold sites identically
seed_out=$("$SEEDOXL" build tests/errors_as.oxl --target js -o "$scratch/easjs" 2>&1 | sed 's/^[^:]*:[0-9][0-9]*:[0-9][0-9]*: //') && seed_rc=0 || seed_rc=$?
self_out=$("$SELFOXL" build tests/errors_as.oxl --target js -o "$scratch/easjs2" 2>&1 | sed 's/^[^:]*:[0-9][0-9]*:[0-9][0-9]*: //') && self_rc=0 || self_rc=$?
if [ "$seed_rc" = 0 ] || [ "$self_rc" = 0 ]; then
    echo "FAIL --target js accepted the typed-err lane"; exit 1
fi
if [ "$seed_out" != "$self_out" ] || [ "$seed_rc" != "$self_rc" ]; then
    echo "FAIL driver parity errors_as --target js"
    echo "-- seed --"; printf '%s
' "$seed_out"
    echo "-- self --"; printf '%s
' "$self_out"
    exit 1
fi
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
out=$("$OXL" run tests/closure_mcall.oxl)
[ "$(tail -1 <<<"$out")" = "closure mcall ok" ] || { echo "FAIL closure_mcall: $out"; exit 1; }
out=$("$OXL" run tests/closure_fnfield.oxl)
[ "$(tail -1 <<<"$out")" = "closure fnfield ok" ] || { echo "FAIL closure_fnfield: $out"; exit 1; }
out=$("$OXL" run tests/closure_shadow.oxl)
[ "$(tail -1 <<<"$out")" = "closure shadow ok" ] || { echo "FAIL closure_shadow: $out"; exit 1; }
out=$("$OXL" run tests/zero_str.oxl)
[ "$(tail -1 <<<"$out")" = "zero str ok" ] || { echo "FAIL zero_str: $out"; exit 1; }
out=$("$OXL" run tests/js_ident.oxl)
[ "$(tail -1 <<<"$out")" = "js ident ok" ] || { echo "FAIL js_ident: $out"; exit 1; }
out=$("$OXL" run tests/susp_ownarg.oxl)
[ "$(tail -1 <<<"$out")" = "susp ownarg ok" ] || { echo "FAIL susp_ownarg: $out"; exit 1; }

echo "== susp iface vtable (descriptor ABI) =="
# susp-declared iface methods dispatch through RtSuspDesc slots
# (make/poll/res_off) — sync impls ride ready-shim frames, pair rets
# read through res_off, rewraps forward the inner pair's descriptor,
# and susp reaches callers by declaration through the fixpoint
for t in iface_susp iface_susp_shim iface_susp_pair iface_susp_nested iface_susp_rewrap iface_susp_prop iface_susp_convdest iface_susp_cancel iface_susp_ownarg vtab_fn; do
    out=$("$OXL" run tests/$t.oxl)
    [ "$(tail -1 <<<"$out")" = "${t//_/ } ok" ] || { echo "FAIL $t: $out"; exit 1; }
done
# `susp` on a non-method member is a parse error, not a silently
# dropped op constraint
cat > "$scratch/suspmark.oxl" <<'EOF'
package main
interface I { susp eq }
fn main() {}
EOF
if diag=$("$OXL" build "$scratch/suspmark.oxl" -o "$scratch/suspmark$EXE" 2>&1); then
    echo "FAIL susp-marker: build succeeded: $diag"; exit 1
fi
grep -q "must precede a method signature" <<<"$diag" || { echo "FAIL susp-marker diag: $diag"; exit 1; }
# fmt must reject it too — rewriting `susp eq` to `eq` loses the mark
if "$OXL" fmt "$scratch/suspmark.oxl" >"$scratch/suspmark.out" 2>&1; then
    echo "FAIL susp-marker fmt: accepted"; exit 1
fi
grep -q "must precede a method signature" "$scratch/suspmark.out" || { echo "FAIL susp-marker fmt diag: $(cat "$scratch/suspmark.out")"; exit 1; }
# the marker's edge cases stay valid: `susp` as a method name and
# `susp` ahead of a real signature
cat > "$scratch/suspok.oxl" <<'EOF'
package main
interface I { susp() -> int, susp read() -> int }
struct S { n: int }
fn (s S) susp() -> int { return s.n }
fn (s S) read() -> int { sleep(1); return s.n + 1 }
fn drive(i: I) -> int { return i.susp() + i.read() }
fn main() { s := S{n: 3}; println(itoa(drive(s))) }
EOF
out=$("$OXL" run "$scratch/suspok.oxl")
[ "$out" = "7" ] || { echo "FAIL susp-named method: $out"; exit 1; }

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
# delayed-reply drain (G1): stop fired mid-delay must let the reply
# land or reconcile before pump_fin's sweep — never a dead reply.
"$OXL" build tests/gui_delay_stop.oxl -o "$scratch/gui_delay_stop$EXE" || {
    echo "FAIL gui_delay_stop: compile failed"; exit 1; }
rc=0
out=$(with_timeout 30 "$scratch/gui_delay_stop$EXE") || rc=$?
[ "$rc" -eq 0 ] && [ "$(tail -1 <<<"$out")" = "delay stop ok" ] || {
    echo "FAIL gui_delay_stop: rc=$rc: $out"; exit 1; }
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


echo "== stage0 findings (#102) =="
# snapshot-review compiler bugs: 4-byte UTF-8 decode in fmt, test
# runner exit status, single-eval borrowed call args, whitespace-
# split require upserts, symlink dir walks, and checker index records
# for := decls / assign targets

# fmt canonicalizes char literals to their scalar — 'U+1F600' must
# decode to 128512 (the *64 second payload byte yielded 3520)
printf 'package main\nfn main() {\n    c := '\''\xf0\x9f\x98\x80'\''\n    println(itoa(c))\n}\n' > "$scratch/u8.oxl"
out=$("$OXL" fmt "$scratch/u8.oxl")
grep -q 'c := 128512' <<<"$out" || { echo "FAIL fmt utf8-4byte: $out"; exit 1; }

# `oxl test` must exit nonzero when any test_ fn traps — the runner
# printed FAIL but returned 0 before the exit-status fix
cat > "$scratch/tfail.oxl" <<'EOF'
package main

import "std/testing"

fn test_ok() { testing.expect_eq(1, 1, "fine") }
fn test_bad() { testing.expect_eq(1, 2, "boom") }
EOF
cat > "$scratch/tpass.oxl" <<'EOF'
package main

import "std/testing"

fn test_ok() { testing.expect_eq(1, 1, "fine") }
EOF
rc=0
out=$("$OXL" test "$scratch/tfail.oxl" 2>&1) || rc=$?
[ "$rc" -ne 0 ] || { echo "FAIL test exit status: failing suite exited 0"; exit 1; }
grep -q 'FAIL' <<<"$out" || { echo "FAIL test exit marker: $out"; exit 1; }
"$OXL" test "$scratch/tpass.oxl" > /dev/null 2>&1 || { echo "FAIL test pass rc"; exit 1; }

# own -> mut/ref call args evaluate exactly once: the borrow ledger
# temps the expr instead of embedding it in borrow/call/unborrow
cat > "$scratch/borrow.oxl" <<'EOF'
package main

import "std/testing"

struct Counter { n: int }

let g_n: int = 0

fn mk() -> own Counter {
    g_n = g_n + 1
    return new(Counter{n: 0})
}

fn bump(c: mut Counter) { c.n = c.n + 1 }

fn test_borrow_once() {
    bump(mk())
    testing.expect_eq(g_n, 1, "borrowed arg evaluated once")
}
EOF
"$OXL" test "$scratch/borrow.oxl" > /dev/null 2>&1 || { echo "FAIL borrow single-eval"; exit 1; }
if command -v node >/dev/null 2>&1; then
    rc=0
    "$OXL" test --target js "$scratch/tfail.oxl" > /dev/null 2>&1 || rc=$?
    [ "$rc" -ne 0 ] || { echo "FAIL js test exit status"; exit 1; }
    "$OXL" test --target js "$scratch/borrow.oxl" > /dev/null 2>&1 || { echo "FAIL js borrow single-eval"; exit 1; }
fi

# get: tab-separated require lines upsert in place (split on general
# whitespace like the manifest parser) — pre-fix the version token
# glued to the path appended a duplicate require instead — and a
# symlink inside a sealed cache slot must not hang dir_h1's walk
case "$(uname -s)" in
MINGW*|MSYS*|CYGWIN*) ;;
*)
    w102="$scratch/w102"
    mkdir -p "$w102/dep/util" "$w102/app/app" "$w102/cache"
    ( cd "$w102/dep" && git init -q . && git config user.email t@t && git config user.name t
      printf 'module file://%s/dep\noxl 0.3\n' "$w102" > oxl.mod
      printf 'package util\nfn answer() -> int { return 42 }\n' > util/u.oxl
      git add -A && git commit -qm v1 && git tag v1.0.0
      printf 'package util\nfn answer() -> int { return 43 }\n' > util/u.oxl
      git add -A && git commit -qm v2 && git tag v1.1.0 )
    printf 'module local/app\noxl 0.3\n\nrequire file://%s/dep\tv1.0.0\n' "$w102" > "$w102/app/oxl.mod"
    printf 'package main\nimport "file://%s/dep/util"\n\nfn main() { println("answer=" + itoa(util.answer())) }\n' "$w102" > "$w102/app/app/main.oxl"
    ( cd "$w102/app" && OXLMODCACHE="$w102/cache" "$OXL" get "file://$w102/dep@v1.1.0" ) > "$w102/get" 2>&1 || { echo "FAIL w102 get rc"; cat "$w102/get"; exit 1; }
    # the tab require's version was swapped in place — one require
    # line for dep, now at v1.1.0, no appended duplicate
    [ "$(grep -c "require file://$w102/dep" "$w102/app/oxl.mod")" = 1 ] || { echo "FAIL w102 dup require"; cat "$w102/app/oxl.mod"; exit 1; }
    grep -q "v1.1.0" "$w102/app/oxl.mod" || { echo "FAIL w102 require ver"; cat "$w102/app/oxl.mod"; exit 1; }
    ! grep -q 'v1.0.0' "$w102/app/oxl.mod" || { echo "FAIL w102 stale ver"; cat "$w102/app/oxl.mod"; exit 1; }
    # a symlink inside the sealed slot is skipped by dir_walk — the
    # verify must complete (pre-fix the walk re-read it forever)
    slot102=$(find "$w102/cache" -name '*@v1.1.0' -type d)
    [ -n "$slot102" ] || { echo "FAIL w102 slot missing"; exit 1; }
    chmod -R u+w "$w102/cache" 2>/dev/null
    ln -s /etc/hostname "$slot102/link" 2>/dev/null || ln -s /etc/passwd "$slot102/link"
    ( cd "$w102/app" && export OXLMODCACHE="$w102/cache" && with_timeout 60 "$OXL" mod verify ) > "$w102/vfy" 2>&1 || { echo "FAIL w102 verify (symlink hang?)"; cat "$w102/vfy"; exit 1; }
    grep -q 'all modules verified' "$w102/vfy" || { echo "FAIL w102 verify text"; cat "$w102/vfy"; exit 1; }
    ;;
esac

# lsp index records: := decl names and assign targets resolve as
# locals (hover shows the binding, not the enclosing fn), and rename
# covers the decl + write + read sites. Edit ranges are deduped
# client-side here — the server-side dedupe rides with the lsp
# worker's rename changes.
OXL_WIN102=$(cygpath -w "$OXL" 2>/dev/null || printf '%s' "$OXL")
$PY - "$OXL_WIN102" "$scratch" <<'PYEOF'
import json, pathlib, subprocess, sys
oxl = sys.argv[1]
work = pathlib.Path(sys.argv[2]) / "lsp102"
work.mkdir(parents=True, exist_ok=True)
f = work / "main.oxl"
f.write_text("""package main

fn id[T any](x: T) -> T { return x }

fn helper(p_seed: int) -> int {
    total := p_seed + 1
    total = total * 2
    return total
}

fn main() {
    w := 41
    v := id(w)
    println("v=" + itoa(v))
    println("h=" + itoa(helper(v)))
}
""")
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
uri = f.as_uri(); src = f.read_text()
send({"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}); recv()
send({"jsonrpc":"2.0","method":"initialized","params":{}})
send({"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":uri,"languageId":"oxl","version":1,"text":src}}}); recv()
lines = src.split("\n")
def pos_of(sub):
    for i, l in enumerate(lines):
        j = l.find(sub)
        if j >= 0:
            return {"textDocument":{"uri":uri},"position":{"line":i,"character":j}}
    raise AssertionError("missing " + sub)
def recv_id(i):
    while True:
        m = recv()
        if m.get("id") == i: return m
# hover on the `total :=` decl name — the binding, not fn helper
send({"jsonrpc":"2.0","id":2,"method":"textDocument/hover","params":pos_of("total :=")})
h = recv_id(2)
assert "total: int" in json.dumps(h), h
# hover on the `total =` assign target — a write is still an occurrence
send({"jsonrpc":"2.0","id":3,"method":"textDocument/hover","params":pos_of("total =")})
h = recv_id(3)
assert "total: int" in json.dumps(h), h
# hover on the p_seed param decl
send({"jsonrpc":"2.0","id":4,"method":"textDocument/hover","params":pos_of("p_seed:")})
h = recv_id(4)
assert "p_seed: int" in json.dumps(h), h
# rename total -> tt: decl + assign target + two reads, deduped
send({"jsonrpc":"2.0","id":5,"method":"textDocument/rename","params":{**pos_of("total :="),"newName":"tt"}})
r = recv_id(5)
assert "result" in r and "changes" in r["result"], r
edits = [e for u, es in r["result"]["changes"].items() for e in es]
# the server itself must not emit overlapping replacements — the
# client-side uniq below would hide a duplicate
raw_keys = [(e["range"]["start"]["line"], e["range"]["start"]["character"], e["range"]["end"]["line"], e["range"]["end"]["character"]) for e in edits]
assert len(raw_keys) == len(set(raw_keys)), raw_keys
seen = set()
uniq = []
for e in edits:
    key = (e["range"]["start"]["line"], e["range"]["start"]["character"], e["range"]["end"]["line"], e["range"]["end"]["character"])
    if key not in seen:
        seen.add(key); uniq.append(e)
starts = sorted((e["range"]["start"]["line"], e["range"]["start"]["character"]) for e in uniq)
# decl 5:4, write 6:4, reads 6:12 + 7:11
assert starts == [(5,4),(6,4),(6,12),(7,11)], starts
# rename w -> ww: the generic-call arg `id(w)` must appear exactly
# once — the ty-param inference pass used to record it a second time
send({"jsonrpc":"2.0","id":6,"method":"textDocument/rename","params":{**pos_of("w :="),"newName":"ww"}})
r = recv_id(6)
assert "result" in r and "changes" in r["result"], r
raw = [e for u, es in r["result"]["changes"].items() for e in es]
arg_hits = [e for e in raw if e["range"]["start"]["line"] == 12 and e["range"]["start"]["character"] == 12]
assert len(arg_hits) == 1, raw
send({"jsonrpc":"2.0","method":"exit","params":{}})
print("lsp102 ok")
PYEOF

echo "== lsp didClose invalidation (#102) =="
OXL_WIN102=$(cygpath -w "$OXL" 2>/dev/null || printf '%s' "$OXL")
$PY - "$OXL_WIN102" "$scratch" <<'PYEOF'
import json, pathlib, subprocess, sys
oxl = sys.argv[1]
work = pathlib.Path(sys.argv[2]) / "lsp102close"
work.mkdir(parents=True, exist_ok=True)
fa = work / "a.oxl"
fb = work / "b.oxl"
fa.write_text("""package main

fn helper() -> int {
    return 42
}
""")
fb.write_text("""package main

fn main() {
    x := helper()
    println(x)
}
""")
p = subprocess.Popen([oxl, "lsp"], stdin=subprocess.PIPE, stdout=subprocess.PIPE)
srv_methods = []
def send(m):
    b = json.dumps(m).encode()
    p.stdin.write(b"Content-Length: %d\r\n\r\n" % len(b) + b); p.stdin.flush()
def recv():
    while True:
        h = {}
        while True:
            l = p.stdout.readline().decode().strip()
            if not l: break
            k, v = l.split(":", 1); h[k.strip()] = v.strip()
        m = json.loads(p.stdout.read(int(h["Content-Length"])).decode())
        if "method" in m and "id" in m:
            srv_methods.append(m["method"])
            b = json.dumps({"jsonrpc":"2.0","id":m["id"],"result":{}}).encode()
            p.stdin.write(b"Content-Length: %d\r\n\r\n" % len(b) + b); p.stdin.flush()
            continue
        return m
def recv_id(i):
    while True:
        m = recv()
        if m.get("id") == i: return m
ua = fa.as_uri(); ub = fb.as_uri()
sa = fa.read_text(); sb = fb.read_text()
send({"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}); recv()
send({"jsonrpc":"2.0","method":"initialized","params":{}})
send({"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":ua,"languageId":"oxl","version":1,"text":sa}}})
send({"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":ub,"languageId":"oxl","version":1,"text":sb}}})
def hover_helper():
    send({"jsonrpc":"2.0","id":90,"method":"textDocument/hover","params":{"textDocument":{"uri":ub},"position":{"line":3,"character":10}}})
    return recv_id(90)
h = hover_helper()
assert "fn helper" in json.dumps(h), h
# break the callee in an unsaved overlay — the sibling's hover degrades
send({"jsonrpc":"2.0","method":"textDocument/didChange","params":{"textDocument":{"uri":ua,"version":2},"contentChanges":[{"text":sa.replace("helper", "helperX")}]}})
h = hover_helper()
assert "fn helper" not in json.dumps(h), h
# closing the broken doc must invalidate the stale overlay and rebuild
# the package analysis from disk — hover resolves again
send({"jsonrpc":"2.0","method":"textDocument/didClose","params":{"textDocument":{"uri":ua}}})
h = hover_helper()
assert "fn helper" in json.dumps(h), h
send({"jsonrpc":"2.0","method":"exit","params":{}})
print("lsp102close ok")
PYEOF

echo "== lsp hover/definition =="
# a Windows python can't exec an msys path — hand it the native spelling
OXL_WIN=$(cygpath -w "$OXL" 2>/dev/null || printf '%s' "$OXL")
$PY - "$OXL_WIN" <<'PYEOF'
import json, pathlib, subprocess, sys
oxl = sys.argv[1]
p = subprocess.Popen([oxl, "lsp"], stdin=subprocess.PIPE, stdout=subprocess.PIPE)
srv_methods = []
def send(m):
    b = json.dumps(m).encode()
    p.stdin.write(b"Content-Length: %d\r\n\r\n" % len(b) + b); p.stdin.flush()
def recv():
    while True:
        h = {}
        while True:
            l = p.stdout.readline().decode().strip()
            if not l: break
            k, v = l.split(":", 1); h[k.strip()] = v.strip()
        m = json.loads(p.stdout.read(int(h["Content-Length"])).decode())
        # server->client requests (e.g. client/registerCapability)
        # carry method+id — answer them so the handshake completes
        if "method" in m and "id" in m:
            srv_methods.append(m["method"])
            b = json.dumps({"jsonrpc":"2.0","id":m["id"],"result":{}}).encode()
            p.stdin.write(b"Content-Length: %d\r\n\r\n" % len(b) + b); p.stdin.flush()
            continue
        return m
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

def recv_id(i):
    while True:
        m = recv()
        if m.get("id") == i:
            return m

def u16(t):
    return len(t.encode("utf-16-le")) // 2

# positions on the emoji-bearing line must be UTF-16 units, not code points
sh_col = u16(lines2[i2][:lines2[i2].index("lexlib.lex") + 12])
src_col = u16(lines2[i2][:lines2[i2].index("src)") + 1])

# ---- milestone U: extended capabilities ----
# initialize advertised the full block
send({"jsonrpc":"2.0","id":10,"method":"initialize","params":{"rootUri":"file://" + str(pathlib.Path("bootstrap/cmd/parse").resolve()),"workspaceFolders":[{"uri":"file://" + str(pathlib.Path("bootstrap/cmd/parse").resolve()),"name":"parse"}]}})
init = recv_id(10)
caps = init["result"]["capabilities"]
for k in ["completionProvider","signatureHelpProvider","documentSymbolProvider","documentHighlightProvider","referencesProvider","renameProvider","documentFormattingProvider","semanticTokensProvider","workspace"]:
    assert k in caps, (k, caps)
assert caps["semanticTokensProvider"]["legend"]["tokenTypes"] == ["namespace","type","class","enum","interface","struct","typeParameter","parameter","variable","property","enumMember","event","function","method","macro","keyword","modifier","comment","string","number","regexp","operator","decorator"]
assert caps["textDocumentSync"] == 1

# documentSymbol: fn main is a top-level symbol
send({"jsonrpc":"2.0","id":11,"method":"textDocument/documentSymbol","params":{"textDocument":{"uri":uri}}})
syms = recv_id(11)["result"]
assert any(s["name"] == "main" and s["kind"] == 12 for s in syms), syms

# completion at top level returns package decls + keywords
send({"jsonrpc":"2.0","id":12,"method":"textDocument/completion","params":{"textDocument":{"uri":uri},"position":{"line":0,"character":0}}})
comp = recv_id(12)["result"]["items"]
assert any(c["label"] == "main" for c in comp), comp[:5]
assert any(c["label"] == "fn" for c in comp)

# semanticTokens: full-doc data, 5 ints per token, non-empty
send({"jsonrpc":"2.0","id":13,"method":"textDocument/semanticTokens/full","params":{"textDocument":{"uri":uri}}})
tok = recv_id(13)["result"]["data"]
assert len(tok) > 0 and len(tok) % 5 == 0, tok[:20]

# signatureHelp inside lexlib.lex(src)
send({"jsonrpc":"2.0","id":14,"method":"textDocument/signatureHelp","params":{"textDocument":{"uri":uri},"position":{"line":i2,"character":sh_col}}})
sh = recv_id(14)["result"]
assert len(sh["signatures"]) == 1, sh
assert "lex" in sh["signatures"][0]["label"]

# references + documentHighlight on the `src` local's use site
send({"jsonrpc":"2.0","id":15,"method":"textDocument/references","params":{"textDocument":{"uri":uri},"position":{"line":i2,"character":src_col},"context":{"includeDeclaration":True}}})
refs = recv_id(15)["result"]
assert len(refs) >= 2, refs
send({"jsonrpc":"2.0","id":16,"method":"textDocument/documentHighlight","params":{"textDocument":{"uri":uri},"position":{"line":i2,"character":src_col}}})
hl = recv_id(16)["result"]
assert len(hl) >= 2, hl

# rename src -> source: WorkspaceEdit over decl + uses
send({"jsonrpc":"2.0","id":17,"method":"textDocument/rename","params":{"textDocument":{"uri":uri},"position":{"line":i2,"character":src_col},"newName":"source"}})
rn = recv_id(17)["result"]
assert "changes" in rn, rn
edits = [e for u, es in rn["changes"].items() for e in es]
assert len(edits) >= 2 and all(e["newText"] == "source" for e in edits), edits

# rename src -> ast captures the sibling local: empty edit set + warning
send({"jsonrpc":"2.0","id":18,"method":"textDocument/rename","params":{"textDocument":{"uri":uri},"position":{"line":i2,"character":src_col},"newName":"ast"}})
rn2 = recv_id(18)["result"]
assert all(len(es) == 0 for es in rn2["changes"].values()), rn2

# rename to a keyword or builtin is rejected before any edit is built
send({"jsonrpc":"2.0","id":181,"method":"textDocument/rename","params":{"textDocument":{"uri":uri},"position":{"line":i2,"character":src_col},"newName":"fn"}})
ekw = recv_id(181); assert ekw["error"]["code"] == -32602, ekw
send({"jsonrpc":"2.0","id":182,"method":"textDocument/rename","params":{"textDocument":{"uri":uri},"position":{"line":i2,"character":src_col},"newName":"print"}})
ebi = recv_id(182); assert ebi["error"]["code"] == -32602, ebi

# formatting returns an edit list (canonical file -> empty)
send({"jsonrpc":"2.0","id":19,"method":"textDocument/formatting","params":{"textDocument":{"uri":uri}}})
fmt = recv_id(19)["result"]
assert isinstance(fmt, list), fmt

# didChangeWatchedFiles invalidates the touched package dir
send({"jsonrpc":"2.0","method":"workspace/didChangeWatchedFiles","params":{"changes":[{"uri":"file://" + str(pathlib.Path("bootstrap/lexlib/lexlib.oxl").resolve()),"type":2}]}})
# hover still resolves after invalidation
send({"jsonrpc":"2.0","id":20,"method":"textDocument/hover","params":pos2})
h3 = recv_id(20); assert "fn lexlib.lex" in json.dumps(h3), h3

# hover on a local's binding site shows the local, not the fn sig —
# `ast :=` on the emoji-bearing line; the position is UTF-16 units
ast_col = u16(lines2[i2][:lines2[i2].index("ast :=")])
send({"jsonrpc":"2.0","id":22,"method":"textDocument/hover","params":{"textDocument":{"uri":uri},"position":{"line":i2,"character":ast_col}}})
hb = recv_id(22)["result"]
assert hb["contents"]["value"].startswith("ast:"), hb

# semanticTokens/range returns delta-encoded data for the range only —
# first token is `fn` at the start of the fn main line
fn_line = next(i for i,l in enumerate(lines) if l.startswith("fn main"))
send({"jsonrpc":"2.0","id":23,"method":"textDocument/semanticTokens/range","params":{"textDocument":{"uri":uri},"range":{"start":{"line":fn_line,"character":0},"end":{"line":fn_line+1,"character":0}}}})
tr = recv_id(23)["result"]["data"]
assert len(tr) > 0 and len(tr) % 5 == 0 and tr[0] == fn_line and tr[1] == 0, tr[:10]
# the non-spec bare semanticTokens alias is gone
send({"jsonrpc":"2.0","id":24,"method":"textDocument/semanticTokens","params":{"textDocument":{"uri":uri}}})
eb = recv_id(24); assert eb["error"]["code"] == -32601, eb
# semanticTokensProvider advertises range support
assert caps["semanticTokensProvider"]["range"] == True

# client/registerCapability was sent once after `initialized`
assert srv_methods.count("client/registerCapability") == 1, srv_methods

# unknown method -> -32601, malformed body -> -32700
send({"jsonrpc":"2.0","id":21,"method":"bogus/method","params":{}})
e1 = recv_id(21); assert e1["error"]["code"] == -32601, e1
raw = b"{not json"
p.stdin.write(b"Content-Length: %d" % len(raw) + b"\r\n\r\n" + raw); p.stdin.flush()
e2 = recv(); assert e2["error"]["code"] == -32700, e2
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
    # each file's last-line success marker is grepped — an err-path
    # regression that prints + exits 0 (gui_dom's `run err:` shape)
    # can't pass silently
    for f in conc_ping conc_scale select select_fair chan_own chanbuf chanbuf_close scope_exit orphan_join defer_order pairfwd match methods fnval d5_qual stdmods_test susp_closure closure_mcall closure_fnfield closure_shadow zero_str susp_ownarg iface_susp iface_susp_shim iface_susp_pair iface_susp_nested iface_susp_rewrap iface_susp_prop iface_susp_convdest iface_susp_cancel iface_susp_ownarg vtab_fn gui_mock gui_lifecycle gui_overflow gui_select gui_stress gui_cancel gui_dom gui_delay_stop js_ident; do
        case "$f" in
            conc_ping)      marker='bounces=' ;;
            conc_scale)     marker='done' ;;
            select)         marker='select done' ;;
            select_fair)    marker='select fair ok' ;;
            chan_own)       marker='chan_own done' ;;
            chanbuf)        marker='chanbuf done' ;;
            chanbuf_close)  marker='chanbuf close ok' ;;
            scope_exit)     marker='scope-exit ok' ;;
            orphan_join)    marker='orphan-join ok' ;;
            defer_order)    marker='defer order ok' ;;
            pairfwd)        marker='pairfwd ok' ;;
            match)          marker='match ok' ;;
            methods)        marker='methods ok' ;;
            fnval)          marker='fnval ok' ;;
            d5_qual)        marker='d5 qual ok' ;;
            stdmods_test)   marker='done' ;;
            susp_closure)   marker='susp closure ok' ;;
            closure_mcall)  marker='closure mcall ok' ;;
            closure_fnfield) marker='closure fnfield ok' ;;
            closure_shadow) marker='closure shadow ok' ;;
            zero_str)       marker='zero str ok' ;;
            gui_mock)       marker='done' ;;
            gui_lifecycle)  marker='lifecycle ok' ;;
            gui_overflow)   marker='overflow ok' ;;
            gui_select)     marker='select ok' ;;
            gui_stress)     marker='stress ok' ;;
            gui_cancel)     marker='cancel ok' ;;
            gui_dom)        marker='activated' ;;
            gui_delay_stop) marker='delay stop ok' ;;
            js_ident)       marker='js ident ok' ;;
            susp_ownarg)    marker='susp ownarg ok' ;;
            iface_susp)         marker='iface susp ok' ;;
            iface_susp_shim)    marker='iface susp shim ok' ;;
            iface_susp_pair)    marker='iface susp pair ok' ;;
            iface_susp_nested)  marker='iface susp nested ok' ;;
            iface_susp_rewrap)  marker='iface susp rewrap ok' ;;
            iface_susp_prop)    marker='iface susp prop ok' ;;
            iface_susp_convdest) marker='iface susp convdest ok' ;;
            iface_susp_cancel)  marker='iface susp cancel ok' ;;
            iface_susp_ownarg)  marker='iface susp ownarg ok' ;;
            vtab_fn)            marker='vtab fn ok' ;;
        esac
        out=$(with_timeout 60 "$SELFOXL" run --target js "tests/$f.oxl" 2>&1) || { echo "FAIL js lane $f: $out"; exit 1; }
        grep -q "$marker" <<<"$out" || { echo "FAIL js lane $f marker '$marker': $out"; exit 1; }
    done
    for f in enc_test hash_test regexp_test float_test util_test stdlib_test collections_test enum_test defer_test os_test exec_test net_test flaglog_test extra_testutil term_signal_test; do
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

echo "== toolchain shim + version manager (i60) =="
# offline shim suite: fake installed toolchains, no network. Asserts
# the spec's resolution order (env > .oxl-version > oxl.mod toolchain
# > default), the 127-on-missing contract, and every `oxl toolchain`
# verb staying inside the shim.
tch="$scratch/tchome"; mkdir -p "$tch"
for v in v0.1.0 v0.2.0; do
    mkdir -p "$tch/versions/$v/oxl-toolchain"
    printf '#!/bin/sh\necho "FAKE %s $@"\n' "$v" > "$tch/versions/$v/oxl-toolchain/oxl"
    chmod +x "$tch/versions/$v/oxl-toolchain/oxl"
done
echo v0.1.0 > "$tch/default-version"
# the shim embeds in install.sh — --shim-only extracts it without a download
OXL_HOME="$tch" sh scripts/install.sh --shim-only >/dev/null
SHIM="$tch/bin/oxl"
tcw="$scratch/tcwork"; mkdir -p "$tcw/proj"

# default resolution (bare dir, no config anywhere)
out=$(cd "$tcw" && OXL_HOME="$tch" "$SHIM" check x)
[ "$out" = "FAKE v0.1.0 check x" ] || { echo "FAIL shim default: $out"; exit 1; }
# env beats everything
out=$(cd "$tcw" && OXL_HOME="$tch" OXL_TOOLCHAIN=v0.2.0 "$SHIM" run)
[ "$out" = "FAKE v0.2.0 run" ] || { echo "FAIL shim env: $out"; exit 1; }
# oxl.mod toolchain directive beats default (walk-up from proj/)
printf 'module example.com/m\n\noxl 0.3\ntoolchain v0.2.0\n' > "$tcw/oxl.mod"
out=$(cd "$tcw/proj" && OXL_HOME="$tch" "$SHIM" build)
[ "$out" = "FAKE v0.2.0 build" ] || { echo "FAIL shim directive: $out"; exit 1; }
# .oxl-version beats a NEARER oxl.mod directive — precedence, not proximity:
# the dotfile sits FARTHER up the tree and must still win
mv "$tcw/oxl.mod" "$tcw/proj/oxl.mod"
echo v0.1.0 > "$tcw/.oxl-version"
out=$(cd "$tcw/proj" && OXL_HOME="$tch" "$SHIM" build)
[ "$out" = "FAKE v0.1.0 build" ] || { echo "FAIL shim dotfile-precedence: $out"; exit 1; }
rm "$tcw/.oxl-version"
mv "$tcw/proj/oxl.mod" "$tcw/oxl.mod"
# nearer oxl.mod without a pin shadows an ancestor's directive
mkdir -p "$tcw/proj/inner"
printf 'module example.com/inner\n\noxl 0.3\n' > "$tcw/proj/inner/oxl.mod"
out=$(cd "$tcw/proj/inner" && OXL_HOME="$tch" "$SHIM" build)
[ "$out" = "FAKE v0.1.0 build" ] || { echo "FAIL shim mod-shadow: $out"; exit 1; }
# missing resolved version -> exit 127 with the install hint
rc=0
out=$(cd "$tcw" && OXL_HOME="$tch" OXL_TOOLCHAIN=v9.9.9 "$SHIM" build 2>&1) || rc=$?
[ "$rc" = 127 ] && grep -q "toolchain install v9.9.9" <<<"$out" || {
    echo "FAIL shim missing-127: rc=$rc $out"; exit 1; }
# verbs: list marks the default; use flips it; current names the source
out=$(OXL_HOME="$tch" "$SHIM" toolchain list)
grep -q '^v0.1.0 (default)$' <<<"$out" && grep -q '^v0.2.0$' <<<"$out" || {
    echo "FAIL toolchain list: $out"; exit 1; }
out=$(OXL_HOME="$tch" "$SHIM" toolchain use v0.2.0)
[ "$(cat "$tch/default-version")" = "v0.2.0" ] || { echo "FAIL toolchain use"; exit 1; }
out=$(cd "$tcw/proj/inner" && OXL_HOME="$tch" "$SHIM" toolchain current)
grep -q '^v0.2.0.*default-version' <<<"$out" || { echo "FAIL toolchain current: $out"; exit 1; }
# use --local writes ./.oxl-version; uninstall refuses the default, --force wins
out=$(cd "$tcw/proj" && OXL_HOME="$tch" "$SHIM" toolchain use --local v0.1.0)
[ "$(cat "$tcw/proj/.oxl-version")" = "v0.1.0" ] || { echo "FAIL use --local"; exit 1; }
rc=0
out=$(OXL_HOME="$tch" "$SHIM" toolchain uninstall v0.2.0 2>&1) || rc=$?
[ "$rc" != 0 ] && grep -q "is the default" <<<"$out" || {
    echo "FAIL uninstall-default-guard: rc=$rc $out"; exit 1; }
out=$(OXL_HOME="$tch" "$SHIM" toolchain uninstall v0.2.0 --force)
[ ! -d "$tch/versions/v0.2.0" ] || { echo "FAIL uninstall --force"; exit 1; }
# `version` is a real-binary verb reporting the RELEASE file stamp
# (else dev) — probe it on the actual drivers
out=$("$OXL" version)
grep -qE '^oxl (dev|v[0-9]+\.[0-9]+\.[0-9]+) \(language [0-9]+\.[0-9]+\)$' <<<"$out" || {
    echo "FAIL self version shape: $out"; exit 1; }
out=$("$SEEDOXL" version)
grep -qE '^oxl (dev|v[0-9]+\.[0-9]+\.[0-9]+) \(language [0-9]+\.[0-9]+\)$' <<<"$out" || {
    echo "FAIL seed version shape: $out"; exit 1; }
# RELEASE stamp is picked up beside the exe
cp "$OXL" "$scratch/oxl-stamp$EXE" && echo v7.7.7 > "$scratch/RELEASE"
out=$("$scratch/oxl-stamp$EXE" version)
grep -qE '^oxl v7\.7\.7 \(language [0-9]+\.[0-9]+\)$' <<<"$out" || { echo "FAIL version stamp: $out"; exit 1; }
# a manifest carrying `toolchain` builds clean on both drivers
printf 'module example.com/tc\n\noxl 0.3\ntoolchain v0.9.0\n' > "$tcw/proj/inner/oxl.mod"
printf 'package main\n\nfn main() { println("tc") }\n' > "$tcw/proj/inner/main.oxl"
out=$("$OXL" run "$tcw/proj/inner" 2>&1)
[ "$out" = "tc" ] || { echo "FAIL self toolchain-manifest: $out"; exit 1; }
out=$("$SEEDOXL" run "$tcw/proj/inner" 2>&1)
[ "$out" = "tc" ] || { echo "FAIL seed toolchain-manifest: $out"; exit 1; }
# and `mod tidy` preserves the directive
rm "$tcw/proj/inner/main.oxl"
(cd "$tcw/proj/inner" && "$OXL" mod tidy >/dev/null 2>&1)
grep -q '^toolchain v0.9.0$' "$tcw/proj/inner/oxl.mod" || {
    echo "FAIL tidy preserves toolchain"; cat "$tcw/proj/inner/oxl.mod"; exit 1; }

# unprefixed `toolchain 0.9.0` pins resolve and parse on both drivers
rm -f "$tcw/proj/.oxl-version"
# the --force uninstall above removed v0.2.0 — restore the fake install
mkdir -p "$tch/versions/v0.2.0/oxl-toolchain"
printf '#!/bin/sh\necho "FAKE v0.2.0 $@"\n' > "$tch/versions/v0.2.0/oxl-toolchain/oxl"
chmod +x "$tch/versions/v0.2.0/oxl-toolchain/oxl"
printf 'module example.com/tc2\n\noxl 0.3\ntoolchain 0.2.0\n' > "$tcw/oxl.mod"
rm -f "$tcw/proj/inner/oxl.mod"
out=$(cd "$tcw/proj" && OXL_HOME="$tch" "$SHIM" build)
[ "$out" = "FAKE v0.2.0 build" ] || { echo "FAIL shim unprefixed-directive: $out"; exit 1; }
printf 'module example.com/tc3\n\noxl 0.3\ntoolchain 0.9.0\n' > "$tcw/proj/inner/oxl.mod"
printf 'package main\n\nfn main() { println("tc3") }\n' > "$tcw/proj/inner/main.oxl"
out=$("$OXL" run "$tcw/proj/inner" 2>&1)
[ "$out" = "tc3" ] || { echo "FAIL self unprefixed-toolchain: $out"; exit 1; }
out=$("$SEEDOXL" run "$tcw/proj/inner" 2>&1)
[ "$out" = "tc3" ] || { echo "FAIL seed unprefixed-toolchain: $out"; exit 1; }
rm "$tcw/proj/inner/main.oxl"
(cd "$tcw/proj/inner" && "$OXL" mod tidy >/dev/null 2>&1)
grep -q '^toolchain 0.9.0$' "$tcw/proj/inner/oxl.mod" || {
    echo "FAIL tidy preserves unprefixed pin"; cat "$tcw/proj/inner/oxl.mod"; exit 1; }
# invalid directive is rejected, not silently selected
printf 'module example.com/tc4\n\noxl 0.3\ntoolchain vfoo\n' > "$tcw/oxl.mod"
rc=0
out=$(cd "$tcw/proj" && OXL_HOME="$tch" "$SHIM" build 2>&1) || rc=$?
[ "$rc" != 0 ] && grep -q "invalid toolchain directive" <<<"$out" || {
    echo "FAIL shim bad-directive: rc=$rc $out"; exit 1; }
# `//` is the manifest comment — a trailing note does not break the pin
printf 'module example.com/m\n\noxl 0.3\ntoolchain v0.2.0 // pinned\n' > "$tcw/oxl.mod"
out=$(cd "$tcw/proj" && OXL_HOME="$tch" "$SHIM" build)
[ "$out" = "FAKE v0.2.0 build" ] || { echo "FAIL shim comment-directive: $out"; exit 1; }
# `#` is NOT a manifest comment — trailing tokens make the directive invalid
printf 'module example.com/m\n\noxl 0.3\ntoolchain v0.2.0 # note\n' > "$tcw/oxl.mod"
rc=0
out=$(cd "$tcw/proj" && OXL_HOME="$tch" "$SHIM" build 2>&1) || rc=$?
[ "$rc" != 0 ] && grep -q "invalid toolchain directive" <<<"$out" || {
    echo "FAIL shim hash-directive: rc=$rc $out"; exit 1; }
# a bare `toolchain` line is a malformed directive, not a pin to nothing
printf 'module example.com/m\n\noxl 0.3\ntoolchain\n' > "$tcw/oxl.mod"
rc=0
out=$(cd "$tcw/proj" && OXL_HOME="$tch" "$SHIM" build 2>&1) || rc=$?
[ "$rc" != 0 ] && grep -q "requires a tag" <<<"$out" || {
    echo "FAIL shim bare-directive: rc=$rc $out"; exit 1; }
# two directives in one manifest must die, not silently pick one
printf 'module example.com/m\n\noxl 0.3\ntoolchain v0.1.0\ntoolchain v0.2.0\n' > "$tcw/oxl.mod"
rc=0
out=$(cd "$tcw/proj" && OXL_HOME="$tch" "$SHIM" build 2>&1) || rc=$?
[ "$rc" != 0 ] && grep -q "duplicate toolchain directive" <<<"$out" || {
    echo "FAIL shim dup-directive: rc=$rc $out"; exit 1; }
# a multiline tag can never reach a path — the env/arg trim guards die first
printf 'module example.com/m\n\noxl 0.3\ntoolchain v0.1.0\n' > "$tcw/oxl.mod"
rc=0
out=$(OXL_HOME="$tch" OXL_TOOLCHAIN="$(printf 'v9.9.9\n../x')" "$SHIM" build 2>&1) || rc=$?
[ "$rc" != 0 ] && grep -q "invalid OXL_TOOLCHAIN" <<<"$out" || {
    echo "FAIL shim env-multiline: rc=$rc $out"; exit 1; }
# invalid pins die loudly rather than traversing paths
rc=0
out=$(OXL_HOME="$tch" OXL_TOOLCHAIN="../v0.1.0" "$SHIM" build 2>&1) || rc=$?
[ "$rc" != 0 ] && grep -q "invalid OXL_TOOLCHAIN" <<<"$out" || {
    echo "FAIL shim env-traversal: rc=$rc $out"; exit 1; }
mkdir -p "$scratch/keepme"
rc=0
out=$(OXL_HOME="$tch" "$SHIM" toolchain uninstall "v0.1.0/../../../$scratch/keepme" 2>&1) || rc=$?
[ "$rc" != 0 ] && grep -q "invalid toolchain tag" <<<"$out"     && [ -d "$scratch/keepme" ] || {
    echo "FAIL uninstall-traversal: rc=$rc $out"; exit 1; }
[ -d "$tch/versions/v0.1.0" ] || { echo "FAIL uninstall-traversal removed real dir"; exit 1; }

# the pipeline section resolves via tch2's default-version — clear the
# oxl.mod pin the traversal checks left behind
rm -f "$tcw/oxl.mod"

# file:// release bases hit the same Windows wall as the fetch fixture:
# native curl can't open MSYS-style paths (curl 37), so the install
# pipeline is POSIX-gated — the shim's resolution verbs above are
# offline and already cover the Windows leg.
case "$(uname -s)" in
MINGW*|MSYS*|CYGWIN*) ;;
*)
echo "== i60 install pipeline — file:// release fixture =="
# end-to-end: download -> sha256 verify -> stage -> atomic mv -> verbs.
# OXL_RELEASE_BASE takes file:// so the whole pipeline runs offline.
reldir="$scratch/relfix"; mkdir -p "$reldir/download/v9.9.9" "$reldir/download/v9.9.8"
# mirror asset_os_arch() in scripts/install.sh so the fixture name always matches the request
tch_os=$(uname -s | tr '[:upper:]' '[:lower:]')
case "$tch_os" in mingw*|msys*|cygwin*|windows*) tch_os=windows ;; esac
tch_arch=$(uname -m)
case "$tch_arch" in x86_64|amd64) tch_arch=x86_64 ;; arm64|aarch64) tch_arch=arm64 ;; esac
tch_asset="oxl-toolchain-$tch_os-$tch_arch.tar.gz"
mkdir -p "$reldir/work/oxl-toolchain"
printf '#!/bin/sh\necho "FAKE 9.9.9 $@"\n' > "$reldir/work/oxl-toolchain/oxl"
chmod +x "$reldir/work/oxl-toolchain/oxl"
tar czf "$reldir/download/v9.9.9/$tch_asset" -C "$reldir/work" oxl-toolchain
if have_sum=$(command -v sha256sum 2>/dev/null); then
    (cd "$reldir/download/v9.9.9" && "$have_sum" "$tch_asset" > "$tch_asset.sha256")
elif command -v shasum >/dev/null 2>&1; then
    (cd "$reldir/download/v9.9.9" && shasum -a 256 "$tch_asset" > "$tch_asset.sha256")
fi
# tampered tarball for the verify-or-die path (wrong payload, real sum)
mkdir -p "$reldir/work2/oxl-toolchain"
printf '#!/bin/sh\necho tampered\n' > "$reldir/work2/oxl-toolchain/oxl"
chmod +x "$reldir/work2/oxl-toolchain/oxl"
tar czf "$reldir/download/v9.9.8/$tch_asset" -C "$reldir/work2" oxl-toolchain
printf '%s  %s\n' "0000000000000000000000000000000000000000000000000000000000000000" "$tch_asset" \
    > "$reldir/download/v9.9.8/$tch_asset.sha256"
# atom feed so `latest` resolves offline — newest-first. An extras
# entry leads page one to prove the scan skips non-toolchain tags.
# $reldir/latest must exist for curl's file:// HEAD to succeed; its
# url_effective then falls through to the atom scan.
printf '<feed><entry>releases/tag/extra/v9.9.10</entry><entry>releases/tag/v9.9.9</entry></feed>\n' > "$reldir.atom"
printf 'latest\n' > "$reldir/latest"

tch2="$scratch/tchome2"
OXL_HOME="$tch2" OXL_RELEASE_BASE="file://$reldir" \
    sh scripts/install.sh v9.9.9 >"$scratch/i60-install.log" 2>&1 || {
    echo "FAIL install pipeline:"; cat "$scratch/i60-install.log"; exit 1; }
[ -x "$tch2/versions/v9.9.9/oxl-toolchain/oxl" ] || { echo "FAIL install: no toolchain dir"; exit 1; }
[ "$(cat "$tch2/default-version")" = "v9.9.9" ] || { echo "FAIL install: default-version"; cat "$tch2/default-version"; exit 1; }
! ls -d "$tch2/versions"/.stage.* >/dev/null 2>&1 || { echo "FAIL install: stage dir leaked"; exit 1; }
SHIM2="$tch2/bin/oxl"
# dispatch goes through the shim to the installed toolchain
out=$(cd "$tcw" && OXL_HOME="$tch2" "$SHIM2" run --help)
[ "$out" = "FAKE 9.9.9 run --help" ] || { echo "FAIL pipeline dispatch: $out"; exit 1; }
# verbs: list marks default, default echoes the tag, current names source
out=$(OXL_HOME="$tch2" "$SHIM2" toolchain list)
[ "$out" = "v9.9.9 (default)" ] || { echo "FAIL pipeline list: $out"; exit 1; }
out=$(OXL_HOME="$tch2" "$SHIM2" toolchain default)
[ "$out" = "v9.9.9" ] || { echo "FAIL pipeline default: $out"; exit 1; }
out=$(cd "$tcw" && OXL_HOME="$tch2" "$SHIM2" toolchain current)
case "$out" in v9.9.9*default-version*installed*) ;; *)
    echo "FAIL pipeline current: $out"; exit 1 ;; esac
# `latest` resolves through the atom-feed fallback on file://
out=$(OXL_HOME="$tch2" OXL_RELEASE_BASE="file://$reldir" \
    "$SHIM2" toolchain install latest 2>&1)
grep -q "already installed" <<<"$out" || { echo "FAIL pipeline latest: $out"; exit 1; }
# feed pagination: page one carries only extras tags, the toolchain
# tag lands on page two — file:// cannot carry ?page= so this needs
# a real http base. Gated on python3 like the other lanes.
if command -v "$PY" >/dev/null 2>&1; then
reldir2="$scratch/relfix2"; mkdir -p "$reldir2/download/v9.9.7" "$reldir2/work/oxl-toolchain"
printf '#!/bin/sh\necho "FAKE 9.9.7 $@"\n' > "$reldir2/work/oxl-toolchain/oxl"
chmod +x "$reldir2/work/oxl-toolchain/oxl"
tar czf "$reldir2/download/v9.9.7/$tch_asset" -C "$reldir2/work" oxl-toolchain
if have_sum=$(command -v sha256sum 2>/dev/null); then
    (cd "$reldir2/download/v9.9.7" && "$have_sum" "$tch_asset" > "$tch_asset.sha256")
elif command -v shasum >/dev/null 2>&1; then
    (cd "$reldir2/download/v9.9.7" && shasum -a 256 "$tch_asset" > "$tch_asset.sha256")
fi
printf '<feed><entry>releases/tag/extra/v9.9.10</entry><entry>releases/tag/extra/v9.9.11</entry></feed>\n' > "$reldir2/atom-1.xml"
printf '<feed><entry>releases/tag/v9.9.7</entry></feed>\n' > "$reldir2/atom-2.xml"
printf 'latest\n' > "$reldir2/latest"
cat > "$scratch/relserve.py" <<'PY'
import pathlib, sys, urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
root = pathlib.Path(sys.argv[1]).resolve()
class H(BaseHTTPRequestHandler):
    def _serve(self, head):
        u = urllib.parse.urlparse(self.path)
        path = u.path
        if path.startswith('/releases'):
            path = path[len('/releases'):] or '/'
        if path.endswith('.atom'):
            f = root / ('atom-%s.xml' % urllib.parse.parse_qs(u.query).get('page', ['1'])[0])
        else:
            f = (root / path.lstrip('/')).resolve()
        try:
            ok = f.is_file() and root in f.resolve().parents
        except OSError:
            ok = False
        if not ok:
            self.send_response(404); self.end_headers(); return
        body = f.read_bytes()
        self.send_response(200)
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        if not head:
            self.wfile.write(body)
    def do_GET(self): self._serve(False)
    def do_HEAD(self): self._serve(True)
    def log_message(self, *a): pass
srv = ThreadingHTTPServer(('127.0.0.1', 0), H)
print(srv.server_address[1], flush=True)
srv.serve_forever()
PY
"$PY" "$scratch/relserve.py" "$reldir2" > "$scratch/relserve.port" &
relsrv=$!
for i in 1 2 3 4 5 6 7 8 9 10; do [ -s "$scratch/relserve.port" ] && break; sleep 0.2; done
relport=$(cat "$scratch/relserve.port")
rc=0
out=$(OXL_HOME="$tch2" OXL_RELEASE_BASE="http://127.0.0.1:$relport/releases" \
    "$SHIM2" toolchain install latest 2>&1) || rc=$?
kill "$relsrv" 2>/dev/null || true; wait "$relsrv" 2>/dev/null || true
relsrv=""
[ "$rc" = 0 ] && grep -q "installed v9.9.7" <<<"$out" \
    && [ -x "$tch2/versions/v9.9.7/oxl-toolchain/oxl" ] || {
    echo "FAIL latest pagination: rc=$rc $out"; exit 1; }
fi
# --default forces the pin even when a default exists
echo v9.9.8 > "$tch2/default-version"
OXL_HOME="$tch2" OXL_RELEASE_BASE="file://$reldir" \
    sh scripts/install.sh --default v9.9.9 >>"$scratch/i60-install.log" 2>&1 || {
    echo "FAIL --default install:"; cat "$scratch/i60-install.log"; exit 1; }
[ "$(cat "$tch2/default-version")" = "v9.9.9" ] || { echo "FAIL --default pin"; cat "$tch2/default-version"; exit 1; }
# --shim-only rejects a positional tag instead of silently ignoring it
rc=0
out=$(OXL_HOME="$tch2" sh scripts/install.sh --shim-only v1.2.3 2>&1) || rc=$?
[ "$rc" = 2 ] && grep -q "no effect with --shim-only" <<<"$out" || {
    echo "FAIL shim-only positional guard: rc=$rc $out"; exit 1; }
# OXL_TOOLCHAIN with stray whitespace trims instead of dying
out=$(cd "$tcw" && OXL_HOME="$tch2" OXL_TOOLCHAIN=" v9.9.9 " "$SHIM2" version)
[ "$out" = "FAKE 9.9.9 version" ] || { echo "FAIL env trim: $out"; exit 1; }
# a tampered payload must die at the checksum gate, never install
rc=0
out=$(OXL_HOME="$tch2" OXL_RELEASE_BASE="file://$reldir" \
    "$SHIM2" toolchain install v9.9.8 2>&1) || rc=$?
[ "$rc" != 0 ] && grep -q "sha256 mismatch" <<<"$out" \
    && [ ! -d "$tch2/versions/v9.9.8" ] || {
    echo "FAIL sha256 gate: rc=$rc $out"; ls "$tch2/versions"; exit 1; }
# uninstall guards the default; --force removes it
rc=0
out=$(OXL_HOME="$tch2" "$SHIM2" toolchain uninstall v9.9.9 2>&1) || rc=$?
[ "$rc" != 0 ] && grep -q "is the default" <<<"$out" || {
    echo "FAIL uninstall default-guard: rc=$rc $out"; exit 1; }
out=$(OXL_HOME="$tch2" "$SHIM2" toolchain uninstall v9.9.9 --force 2>&1)
grep -q "removed v9.9.9" <<<"$out" && [ ! -d "$tch2/versions/v9.9.9" ] || {
    echo "FAIL uninstall --force: $out"; exit 1; }
# a non-directory parked at the version path dies before the stage work
mkdir -p "$tch2/versions"; echo x > "$tch2/versions/v9.9.9"
rc=0
out=$(OXL_HOME="$tch2" OXL_RELEASE_BASE="file://$reldir" \
    "$SHIM2" toolchain install v9.9.9 2>&1) || rc=$?
[ "$rc" != 0 ] && grep -q "not a directory" <<<"$out" || {
    echo "FAIL nondir guard: rc=$rc $out"; exit 1; }
rm "$tch2/versions/v9.9.9"
;;
esac


# ---------- editor distribution assets (WI-0015) ----------
echo "== editor assets — syntax + structure checks =="
# sublime-syntax must be valid YAML with the expected scope/extension
if command -v "$PY" >/dev/null 2>&1; then
"$PY" - <<'PYCHK'
import sys
try:
    import yaml
except ImportError:
    sys.exit(0)  # no pyyaml — skip, CI images vary
src = open('editors/sublime/oxl.sublime-syntax').read()
doc = yaml.safe_load(src.split('---', 1)[1])
assert doc['scope'] == 'source.oxl', doc['scope']
assert 'oxl' in doc['file_extensions']
assert 'main' in doc['contexts']
print('sublime-syntax ok')
PYCHK
fi
# grammars must be valid JSON and the vscode copy must stay identical
"$PY" - <<'PYCHK'
import json
a = json.load(open('editors/grammars/oxl.tmLanguage.json'))
b = json.load(open('editors/vscode/syntaxes/oxl.tmLanguage.json'))
assert a == b, 'vscode grammar drifted from editors/grammars'
assert a['scopeName'] == 'source.oxl'
am = json.load(open('editors/grammars/oxl-mod.tmLanguage.json'))
bm = json.load(open('editors/vscode/syntaxes/oxl-mod.tmLanguage.json'))
assert am == bm, 'vscode mod grammar drifted from editors/grammars'
assert am['scopeName'] == 'source.oxl.mod'
print('grammar parity ok')
PYCHK
# nvim lua files must parse; plugin must load headless when nvim exists
if command -v luac >/dev/null 2>&1; then
    for f in editors/nvim/lua/oxl/init.lua editors/nvim/plugin/oxl.lua \
             editors/nvim/ftdetect/oxl.lua editors/nvim/ftplugin/oxl.lua; do
        luac -p "$f" || { echo "FAIL luac -p $f"; exit 1; }
    done
    echo "nvim lua parse ok"
fi
if command -v nvim >/dev/null 2>&1; then
    printf 'fn main() -> int {\n    return 0\n}\n' > "$scratch/ftcheck.oxl"
    out=$(nvim --headless -u NONE \
        --cmd "set rtp+=$PWD/editors/nvim" \
        -c "filetype on" \
        -c "e $scratch/ftcheck.oxl" \
        -c "lua io.write(vim.bo.filetype)" -c "qa!" 2>/dev/null)
    [ "$out" = "oxl" ] || { echo "FAIL nvim filetype: '$out'"; exit 1; }
    echo "nvim filetype ok"
fi
# vscode extension: package.json main must point at the esbuild bundle;
# build it when node+npm are available (soft-skip on bare runners)
if command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1 \
    && [ -f editors/vscode/package-lock.json ]; then
    (cd editors/vscode && npm ci --no-audit --no-fund >/dev/null 2>&1 \
        && node build.mjs >/dev/null 2>&1) || {
        echo "FAIL vscode extension build"; exit 1; }
    node -e 'const j=require("./editors/vscode/package.json");
        if (j.main !== "./dist/extension.js") process.exit(1);
        if (!j.activationEvents.includes("onLanguage:oxl")) process.exit(1);
        const l = j.contributes.languages.find(x => x.id === "oxlmod");
        if (!l || JSON.stringify(l.filenames) !== JSON.stringify(["oxl.mod", "oxl.work"])) process.exit(1);
        const gm = j.contributes.grammars.find(x => x.language === "oxlmod");
        if (!gm || gm.scopeName !== "source.oxl.mod") process.exit(1);'
    grep -q 'vscode-languageclient' editors/vscode/dist/extension.js \
        || { echo "FAIL vsix bundle missing language client"; exit 1; }
    echo "vscode extension bundle ok"
fi

# shiki-oxl package: manifest must keep name/registry/exports stable;
# npm pack must ship exactly the grammar + loader + readme (soft-skip
# without node/npm like the vscode block above)
if command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
    node -e 'const j=require("./editors/grammars/package.json");
        if (j.name !== "@oxidean/shiki-oxl") process.exit(1);
        if (j.publishConfig.registry !== "https://npm.pkg.github.com") process.exit(1);
        if (!j.exports["."] || !j.exports["./grammar.json"]
            || !j.exports["./mod-grammar.json"]) process.exit(1);
        for (const f of ["index.mjs", "oxl.tmLanguage.json",
            "oxl-mod.tmLanguage.json", "README.md"])
            if (!j.files.includes(f)) process.exit(1);'
    packout=$(cd editors/grammars && npm pack --dry-run 2>&1)
    for f in index.mjs oxl.tmLanguage.json oxl-mod.tmLanguage.json README.md package.json; do
        grep -q "$f" <<<"$packout" || { echo "FAIL shiki-oxl pack missing $f"; exit 1; }
    done
    node --input-type=module -e 'import g, { oxlModGrammar as m } from "./editors/grammars/index.mjs";
        if (g.name !== "oxl" || g.scopeName !== "source.oxl") process.exit(1);
        if (!Array.isArray(g.patterns)) process.exit(1);
        if (m.name !== "oxlmod" || m.scopeName !== "source.oxl.mod") process.exit(1);
        if (JSON.stringify(m.aliases) !== JSON.stringify(["oxl.mod", "oxl.work"])) process.exit(1);'
    echo "shiki-oxl package ok"
fi

# install-editor.sh — offline file:// release fixture (POSIX-gated like
# the install.sh pipeline: native curl can't open file:// on Windows)
case "$(uname -s)" in
MINGW*|MSYS*|CYGWIN*) ;;
*)
echo "== install-editor.sh — file:// release fixture =="
iedir="$scratch/iedfix"; mkdir -p "$iedir/download/v9.9.9" "$iedir/expanded_assets"
printf 'fixture vsix\n' > "$iedir/download/v9.9.9/oxl-language.vsix"
printf '%%YAML 1.2\n---\nname: OXL\n' > "$iedir/download/v9.9.9/oxl.sublime-syntax"
tar czf "$iedir/download/v9.9.9/oxl-editor-assets.tar.gz" -C "$iedir" download 2>/dev/null || \
    tar czf "$iedir/download/v9.9.9/oxl-editor-assets.tar.gz" --files-from /dev/null
printf 'oxl-editor-assets oxl-language.vsix oxl.sublime-syntax\n' \
    > "$iedir/expanded_assets/v9.9.9"
# an extras-only release that must be skipped by latest resolution
mkdir -p "$iedir/download/v9.9.10"
printf 'no editor assets here\n' > "$iedir/expanded_assets/v9.9.10"
printf '<feed><entry>releases/tag/v9.9.10</entry><entry>releases/tag/v9.9.9</entry></feed>\n' > "$iedir.atom"
printf 'latest\n' > "$iedir/latest"

# list prints the asset URLs for an explicit tag
out=$(OXL_RELEASE_BASE="file://$iedir" sh scripts/install-editor.sh list v9.9.9)
grep -q "oxl-language.vsix" <<<"$out" && grep -q "nvim-oxl" <<<"$out" \
    || { echo "FAIL ie-list: $out"; exit 1; }

# latest skips the extras release and lands on v9.9.9
out=$(OXL_RELEASE_BASE="file://$iedir" sh scripts/install-editor.sh list)
grep -q "v9.9.9" <<<"$out" || { echo "FAIL ie-latest: $out"; exit 1; }

# bat installs the syntax file into BAT_CONFIG_DIR
batdir="$scratch/batcfg"
out=$(BAT_CONFIG_DIR="$batdir" OXL_RELEASE_BASE="file://$iedir" \
    sh scripts/install-editor.sh bat v9.9.9)
[ -f "$batdir/syntaxs/oxl.sublime-syntax" ] \
    || { echo "FAIL ie-bat: $out"; ls -R "$batdir" 2>/dev/null; exit 1; }

# nvim clones the mirror repo (file:// fixture) into the pack dir — twice,
# to cover both the clone and the fetch/checkout update path
nvimpak="$scratch/nvimpak"
mkdir -p "$scratch/nvimirror"
(
    cd "$scratch/nvimirror"
    git init -q -b main .
    mkdir -p ftdetect lua/oxl syntax plugin ftplugin
    printf 'vim.filetype.add({extension={oxl="oxl"}})\n' > ftdetect/oxl.lua
    printf 'return {}\n' > lua/oxl/init.lua
    printf 'let b:current_syntax="oxl"\n' > syntax/oxl.vim
    printf 'require("oxl").setup()\n' > plugin/oxl.lua
    printf 'vim.bo.commentstring="// %%s"\n' > ftplugin/oxl.lua
    git add -A
    git -c user.name=t -c user.email=t@t commit -qm init
    git tag v9.9.9
)
out=$(OXL_NVIM_REPO="file://$scratch/nvimirror" OXL_NVIM_HOME="$nvimpak/nvim-oxl" \
    OXL_RELEASE_BASE="file://$iedir" sh scripts/install-editor.sh nvim v9.9.9)
[ -f "$nvimpak/nvim-oxl/ftdetect/oxl.lua" ] \
    || { echo "FAIL ie-nvim clone: $out"; exit 1; }
out=$(OXL_NVIM_REPO="file://$scratch/nvimirror" OXL_NVIM_HOME="$nvimpak/nvim-oxl" \
    OXL_RELEASE_BASE="file://$iedir" sh scripts/install-editor.sh nvim v9.9.9)
grep -q "updating" <<<"$out" || { echo "FAIL ie-nvim update path: $out"; exit 1; }

# vscode: a stub `code` bin records the install URL
mkdir -p "$scratch/vscbin"
printf '#!/bin/sh\necho "$@" > "%s/vscode-args"\n' "$scratch" > "$scratch/vscbin/code"
chmod +x "$scratch/vscbin/code"
out=$(PATH="$scratch/vscbin:$PATH" OXL_RELEASE_BASE="file://$iedir" \
    sh scripts/install-editor.sh vscode v9.9.9 code)
grep -q "oxl-language.vsix" "$scratch/vscode-args" \
    || { echo "FAIL ie-vscode: $out $(cat "$scratch/vscode-args" 2>/dev/null)"; exit 1; }
# invalid tag dies
rc=0
OXL_RELEASE_BASE="file://$iedir" sh scripts/install-editor.sh list "bad tag" 2>/dev/null || rc=$?
[ "$rc" != 0 ] || { echo "FAIL ie-tag-validation"; exit 1; }
echo "install-editor.sh ok"
;;
esac

echo "ALL TESTS PASSED"
