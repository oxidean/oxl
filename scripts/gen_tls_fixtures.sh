#!/usr/bin/env bash
# scripts/gen_tls_fixtures.sh — mint the checked-in TLS test
# fixtures with openssl. The test suite never execs openssl; these
# fixtures are generated once and committed. Sections so far:
#
#   rsa   tests/fixtures/rsa/ — X3: RSA-4096 RSAPublicKey DER, a
#         message, PKCS#1 v1.5 + PSS signatures over sha256/384/512,
#         plus negative fixtures (raw-pad, odd salt length)
#
# (X5's x509 bundle and X6's `flight` capture append sections here.)
#
# Usage: gen_tls_fixtures.sh [rsa|all]   — default "all"
# The openssl version is recorded in tests/fixtures/OPENSSL-VERSION
# so a future regeneration can tell what minted the fixtures.
set -euo pipefail
cd "$(dirname "$0")/.."

command -v openssl >/dev/null 2>&1 || { echo "gen_tls_fixtures: openssl not found" >&2; exit 1; }

# hexfile dumps stdin as one lower-case hex line — od is POSIX, xxd
# is not guaranteed on minimal images
hexfile() { od -An -tx1 -v | tr -d ' \n'; echo; }

gen_rsa() {
    local outdir=tests/fixtures/rsa
    local work
    work=$(mktemp -d)
    trap 'rm -rf "$work"' RETURN
    mkdir -p "$outdir"

    openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:4096 \
        -out "$work/rsa4096.pem" 2>/dev/null
    # RSAPublicKey ::= SEQUENCE { INTEGER n, INTEGER e } — the exact
    # DER shape rsa.parse_pub_key (and an SPKI BIT STRING) carries
    openssl rsa -in "$work/rsa4096.pem" -RSAPublicKey_out -outform DER 2>/dev/null \
        | hexfile > "$outdir/pub4096.hex"
    printf 'oxl tls x3 fixture message\n' > "$work/msg.bin"
    hexfile < "$work/msg.bin" > "$outdir/msg.hex"

    local h
    for h in sha256 sha384 sha512; do
        # PKCS#1 v1.5 with DigestInfo wrapping — `openssl dgst` form
        openssl dgst -"$h" -sign "$work/rsa4096.pem" -out "$work/sig.bin" "$work/msg.bin"
        hexfile < "$work/sig.bin" > "$outdir/sig_v15_$h.hex"
        # PSS, salt length = hash length (the TLS 1.3 pin), MGF1 = h
        openssl dgst -"$h" -sign "$work/rsa4096.pem" \
            -sigopt rsa_padding_mode:pss -sigopt rsa_mgf1_md:"$h" \
            -sigopt rsa_pss_saltlen:digest \
            -out "$work/sig.bin" "$work/msg.bin"
        hexfile < "$work/sig.bin" > "$outdir/sig_pss_$h.hex"
    done

    # negative fixture: structurally valid v1.5 padding over a raw
    # 32-byte digest — no DigestInfo, so T can never match; verify
    # must reject. pkeyutl refuses pad-without-digest; rsautl -sign
    # is the (deprecated but present) raw PKCS#1 type-1 padder.
    openssl dgst -sha256 -binary -out "$work/digest.bin" "$work/msg.bin"
    openssl rsautl -sign -inkey "$work/rsa4096.pem" -in "$work/digest.bin"         -out "$work/sig.bin" 2>/dev/null
    hexfile < "$work/sig.bin" > "$outdir/sig_rawpad.hex"

    # negative fixture: PSS with a non-standard 20-byte salt — the
    # salt-recovering path accepts it, a pinned saltlen must reject
    openssl dgst -sha256 -sign "$work/rsa4096.pem" \
        -sigopt rsa_padding_mode:pss -sigopt rsa_mgf1_md:sha256 \
        -sigopt rsa_pss_saltlen:20 \
        -out "$work/sig.bin" "$work/msg.bin"
    hexfile < "$work/sig.bin" > "$outdir/sig_pss_salt20.hex"

    openssl version > tests/fixtures/OPENSSL-VERSION
    echo "gen_tls_fixtures: wrote $outdir ($(cat tests/fixtures/OPENSSL-VERSION))"
}

case "${1:-all}" in
    rsa) gen_rsa ;;
    all) gen_rsa ;;
    *) echo "usage: gen_tls_fixtures.sh [rsa|all]" >&2; exit 2 ;;
esac
