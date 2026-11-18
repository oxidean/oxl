#!/usr/bin/env bash
# scripts/gen_tls_fixtures.sh — mint the checked-in TLS test
# fixtures with openssl. The test suite never execs openssl; these
# fixtures are generated once and committed. Sections so far:
#
#   rsa   tests/fixtures/rsa/ — X3: RSA-4096 RSAPublicKey DER, a
#         message, PKCS#1 v1.5 + PSS signatures over sha256/384/512,
#         plus negative fixtures (raw-pad, odd salt length)
#
#   x509  tests/fixtures/x509/ — X5: a two-root PKI (RSA root CA +
#         Ed25519 root CA) with ECDSA P-256/P-384 intermediates and
#         leaves (RSA, ECDSA, Ed25519 keys; expired, wrong-name,
#         wildcard, sha1-signed, PSS-signed, EKU-restricted, not-a-CA
#         issuer, and untrusted-root chains). X5-review additions:
#         selfsigned.pem (self-signed anchor/leaf), inter_nc.pem
#         (critical nameConstraints — must fail parse), root_sha1.pem
#         + leaf_sha1root.pem (sha1 self-signed anchor still anchors
#         the sha256 chain it signs). roots.pem is the
#         OXL_SSL_CERT_FILE bundle; dir/ is the OXL_SSL_CERT_DIR store
#         (a *.pem + a *.crt + a DER-form *.cer — plain-dir layout,
#         not capath).
#
#   flight tests/tls/ — X6: a live TLS 1.3 handshake against
#         `openssl s_server -www -tls1_3`, captured by
#         tests/tls/capture.oxl running under the freshly built
#         ./target/oxl with the deterministic fixture hook armed.
#         Mints tests/tls/{ca,ca-key,server,server-key}.pem and
#         records the raw server->client wire bytes (server flight,
#         session tickets, the -www status page) in flight.hex,
#         plus a forged KeyUpdate/app-data/close_notify tail the
#         replay asserts consumes and rotates. CA key is committed
#         deliberately: regenerating the flight needs the same PKI.
#
# Usage: gen_tls_fixtures.sh [rsa|x509|flight|all]   — default "all"
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

gen_x509() {
    local outdir=tests/fixtures/x509
    local work
    work=$(mktemp -d)
    trap 'rm -rf "$work"' RETURN
    mkdir -p "$outdir/dir"

    # extension blocks: CAs are critical-CA:keyCertSign with SKID;
    # leaves are critical-CA:FALSE + digitalSignature + serverAuth +
    # SKID/AKID (the AKID=keyid vs issuer SKID pairing exercises the
    # tightened link rule)
    cat > "$work/ca.cnf" <<'EOF'
basicConstraints=critical,CA:TRUE,pathlen:1
keyUsage=critical,keyCertSign,cRLSign
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid
EOF
    cat > "$work/ca_eku.cnf" <<'EOF'
basicConstraints=critical,CA:TRUE
keyUsage=critical,keyCertSign,cRLSign
extendedKeyUsage=clientAuth
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid
EOF
    cat > "$work/leaf.cnf" <<'EOF'
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature
extendedKeyUsage=serverAuth
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid
EOF
    cat > "$work/leaf_badeku.cnf" <<'EOF'
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature
extendedKeyUsage=clientAuth
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid
EOF
    # critical nameConstraints — outside the processed critical set,
    # so parse_cert must reject it outright (err_der)
    cat > "$work/ca_nc.cnf" <<'EOF'
basicConstraints=critical,CA:TRUE
keyUsage=critical,keyCertSign,cRLSign
nameConstraints=critical,permitted;DNS:example.com
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid
EOF

    # --- keys -------------------------------------------------------
    # RSA-2048 keeps verify fast; roots/intermediates mix RSA, ECDSA
    # P-256/P-384 and Ed25519 so every accepted signature scheme and
    # SPKI family appears in a real chain
    openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "$work/root.key" 2>/dev/null
    openssl genpkey -algorithm ED25519 -out "$work/root_ed.key" 2>/dev/null
    openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out "$work/inter.key" 2>/dev/null
    openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-384 -out "$work/inter384.key" 2>/dev/null
    openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out "$work/inter_eku.key" 2>/dev/null
    openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "$work/leaf.key" 2>/dev/null
    openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out "$work/leaf_ec.key" 2>/dev/null
    openssl genpkey -algorithm ED25519 -out "$work/leaf_ed.key" 2>/dev/null
    openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "$work/notca.key" 2>/dev/null
    openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "$work/rogue.key" 2>/dev/null
    openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "$work/inter_nc.key" 2>/dev/null
    openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "$work/selfsigned.key" 2>/dev/null
    openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "$work/root_sha1.key" 2>/dev/null

    # --- roots (self-signed anchors) --------------------------------
    for r in root root_ed rogue; do
        case $r in
            root)    subj="/CN=Oxl Test Root CA" ;;
            root_ed) subj="/CN=Oxl Test Ed25519 Root CA" ;;
            rogue)   subj="/CN=Oxl Untrusted Root CA" ;;
        esac
        openssl req -x509 -new -key "$work/$r.key" -sha256 -days 3650 \
            -subj "$subj" \
            -addext "basicConstraints=critical,CA:TRUE" \
            -addext "keyUsage=critical,keyCertSign,cRLSign" \
            -addext "subjectKeyIdentifier=hash" \
            -out "$work/$r.pem"
    done

    # --- intermediates, signed by the RSA root -----------------------
    csr() { openssl req -new -key "$work/$1.key" -subj "$2" -out "$work/$1.csr"; }
    # issue <csr> <cacert> <cakey> <days> <md> <out> [sigopt...]
    issue() {
        local csrfile=$1 cacert=$2 cakey=$3 days=$4 md=$5 out=$6
        shift 6
        # md "" means the key's own default digest (ed25519 has none)
        openssl x509 -req -in "$csrfile" -CA "$cacert" -CAkey "$cakey" \
            -CAcreateserial -days "$days" ${md:+$md} "$@" -out "$work/$out"
    }
    csr inter    "/CN=Oxl Test P256 Intermediate CA"
    csr inter384 "/CN=Oxl Test P384 Intermediate CA"
    csr inter_eku "/CN=Oxl Test ClientAuth Intermediate CA"
    csr notca    "/CN=Oxl Not A CA"
    issue "$work/inter.csr" "$work/root.pem" "$work/root.key" 3650 -sha256 inter.pem \
        -extfile "$work/ca.cnf"
    issue "$work/inter384.csr" "$work/root.pem" "$work/root.key" 3650 -sha384 inter384.pem \
        -extfile "$work/ca.cnf"
    issue "$work/inter_eku.csr" "$work/root.pem" "$work/root.key" 3650 -sha256 inter_eku.pem \
        -extfile "$work/ca_eku.cnf"
    # notca is an end-entity cert whose key still signs leaf_badca —
    # openssl issues through any cert+key pair regardless of cA
    issue "$work/notca.csr" "$work/root.pem" "$work/root.key" 3650 -sha256 notca.pem \
        -extfile "$work/leaf.cnf"
    # a CA carrying a *critical* nameConstraints — outside the
    # processed critical set, so parse_cert must reject it (err_der)
    csr inter_nc "/CN=Oxl Test NameConstraints CA"
    issue "$work/inter_nc.csr" "$work/root.pem" "$work/root.key" 3650 -sha256 inter_nc.pem \
        -extfile "$work/ca_nc.cnf"

    # --- leaves ------------------------------------------------------
    # leafext <name> — leaf.cnf plus a per-cert subjectAltName
    leafext() { cat "$work/leaf.cnf" > "$work/x_$1.cnf"; printf 'subjectAltName=%s\n' "$2" >> "$work/x_$1.cnf"; }
    csr leaf "/CN=www.example.com"
    leafext leaf "DNS:www.example.com"
    issue "$work/leaf.csr" "$work/inter.pem" "$work/inter.key" 3650 -sha256 leaf.pem \
        -extfile "$work/x_leaf.cnf"
    csr leaf_ec "/CN=www.example.com"
    leafext leaf_ec "DNS:www.example.com"
    issue "$work/leaf_ec.csr" "$work/inter384.pem" "$work/inter384.key" 3650 -sha384 leaf_ec.pem \
        -extfile "$work/x_leaf_ec.cnf"
    csr leaf_ed "/CN=www.example.com"
    leafext leaf_ed "DNS:www.example.com"
    issue "$work/leaf_ed.csr" "$work/root_ed.pem" "$work/root_ed.key" 3650 "" leaf_ed.pem \
        -extfile "$work/x_leaf_ed.cnf"

    # RSA-PSS-signed leaf: signatureAlgorithm rsassaPss (sha256/mgf1)
    csr leaf "/CN=www.example.com"
    issue "$work/leaf.csr" "$work/root.pem" "$work/root.key" 3650 -sha256 leaf_pss.pem \
        -extfile "$work/x_leaf.cnf" \
        -sigopt rsa_padding_mode:pss -sigopt rsa_pss_saltlen:digest

    # IP-SAN leaf: exercises match_hostname's ip_addrs leg — v4 dotted
    # quad plus a v6 literal the canonical form compresses
    csr leaf "/CN=www.example.com"
    leafext leaf_ip "IP:10.0.0.9,IP:fd00::1,DNS:ip.example.com"
    issue "$work/leaf.csr" "$work/inter.pem" "$work/inter.key" 3650 -sha256 leaf_ip.pem \
        -extfile "$work/x_leaf_ip.cnf"

    # genuinely expired leaf: openssl ca carries arbitrary validity
    # windows; the fixture's window is 2020→2021, dead by any clock
    mkdir -p "$work/cadb/newcerts"
    touch "$work/cadb/index.txt"
    echo 2000 > "$work/cadb/serial"
    cat > "$work/expired_ca.cnf" <<EOF
[ ca ]
default_ca = cadef
[ cadef ]
database = $work/cadb/index.txt
new_certs_dir = $work/cadb/newcerts
certificate = $work/inter.pem
private_key = $work/inter.key
serial = $work/cadb/serial
default_md = sha256
policy = pol
x509_extensions = exts
default_days = 365
[ pol ]
commonName = supplied
[ exts ]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = serverAuth
subjectAltName = DNS:www.example.com
EOF
    openssl ca -batch -config "$work/expired_ca.cnf" \
        -startdate 20200101000000Z -enddate 20210101000000Z \
        -in "$work/leaf.csr" -out "$work/leaf_expired.pem" >/dev/null 2>&1

    # wrong-name and wildcard leaves
    csr leaf "/CN=www.wrong-name.example"
    leafext leaf_wrongname "DNS:www.wrong-name.example"
    issue "$work/leaf.csr" "$work/inter.pem" "$work/inter.key" 3650 -sha256 leaf_wrongname.pem \
        -extfile "$work/x_leaf_wrongname.cnf"
    csr leaf "/CN=*.example.com"
    leafext leaf_wildcard "DNS:*.example.com"
    issue "$work/leaf.csr" "$work/inter.pem" "$work/inter.key" 3650 -sha256 leaf_wildcard.pem \
        -extfile "$work/x_leaf_wildcard.cnf"

    # sha1-signed leaf (issuer = RSA root): sig_alg is outside the
    # acceptance set — verify must hard-fail err_alg even though the
    # signature itself is cryptographically valid
    csr leaf "/CN=www.example.com"
    issue "$work/leaf.csr" "$work/root.pem" "$work/root.key" 3650 -sha1 leaf_sha1.pem \
        -extfile "$work/x_leaf.cnf"

    # EKU-restricted CA chain: inter_eku is a CA whose EKU vouches
    # clientAuth only — a leaf under it fails err_eku
    csr leaf "/CN=www.example.com"
    issue "$work/leaf.csr" "$work/inter_eku.pem" "$work/inter_eku.key" 3650 -sha256 leaf_eku.pem \
        -extfile "$work/x_leaf.cnf"
    # leaf_badeku carries clientAuth (not serverAuth) itself
    cat "$work/leaf_badeku.cnf" > "$work/x_badeku.cnf"
    printf 'subjectAltName=%s\n' "DNS:www.example.com" >> "$work/x_badeku.cnf"
    issue "$work/leaf.csr" "$work/inter.pem" "$work/inter.key" 3650 -sha256 leaf_badeku.pem \
        -extfile "$work/x_badeku.cnf"

    # not-a-CA issuer: leaf_badca's issuer is notca (cA=false) — the
    # link matches by name but the CA-worthiness check must reject
    csr leaf "/CN=www.example.com"
    issue "$work/leaf.csr" "$work/notca.pem" "$work/notca.key" 3650 -sha256 leaf_badca.pem \
        -extfile "$work/x_leaf.cnf"

    # untrusted-root chain: a fully well-formed chain that anchors to
    # a root the store doesn't contain
    csr leaf "/CN=www.example.com"
    issue "$work/leaf.csr" "$work/rogue.pem" "$work/rogue.key" 3650 -sha256 leaf_rogue.pem \
        -extfile "$work/x_leaf.cnf"

    # self-signed anchor that doubles as its own leaf — with
    # digitalSignature in KU it also passes the leaf checks, so
    # verify(S, [], Roots{S}) pins the anchor-terminates-path rule
    openssl req -x509 -new -key "$work/selfsigned.key" -sha256 -days 3650 \
        -subj "/CN=Oxl Test Self-Signed CA" \
        -addext "basicConstraints=critical,CA:TRUE" \
        -addext "keyUsage=critical,digitalSignature,keyCertSign,cRLSign" \
        -addext "subjectKeyIdentifier=hash" \
        -addext "authorityKeyIdentifier=keyid" \
        -out "$work/selfsigned.pem"

    # sha1 self-signed root — its own sig_alg is outside the
    # acceptance set, yet store membership still lets it anchor the
    # sha256-signed leaf it issues (the anchor exemption)
    openssl req -x509 -new -key "$work/root_sha1.key" -sha1 -days 3650 \
        -subj "/CN=Oxl Test SHA1 Root CA" \
        -addext "basicConstraints=critical,CA:TRUE" \
        -addext "keyUsage=critical,keyCertSign,cRLSign" \
        -addext "subjectKeyIdentifier=hash" \
        -out "$work/root_sha1.pem"
    csr leaf "/CN=www.example.com"
    issue "$work/leaf.csr" "$work/root_sha1.pem" "$work/root_sha1.key" 3650 -sha256 leaf_sha1root.pem \
        -extfile "$work/x_leaf.cnf"

    # --- publish -----------------------------------------------------
    for f in root root_ed rogue inter inter384 inter_eku inter_nc notca \
             leaf leaf_ec leaf_ed leaf_pss leaf_expired leaf_wrongname \
             leaf_wildcard leaf_sha1 leaf_eku leaf_badeku leaf_badca \
             leaf_rogue leaf_ip selfsigned root_sha1 leaf_sha1root; do
        cp "$work/$f.pem" "$outdir/$f.pem"
    done
    # DER forms for the parse tests (PEM covers the same content, but
    # parse_cert's raw-DER path wants a DER file to read)
    openssl x509 -in "$work/root.pem" -outform DER -out "$outdir/root.der"
    openssl x509 -in "$work/leaf.pem" -outform DER -out "$outdir/leaf.der"
    # the env-override fixtures: a one-file bundle and a scan dir —
    # the .cer entry is DER-form, exercising pem_of_file's raw-cert
    # fallback inside the dir walk
    cat "$work/root.pem" "$work/root_ed.pem" > "$outdir/roots.pem"
    cp "$work/root.pem" "$outdir/dir/root.pem"
    cp "$work/root_ed.pem" "$outdir/dir/root_ed.crt"
    openssl x509 -in "$work/selfsigned.pem" -outform DER -out "$outdir/dir/selfsigned.cer"
    # a non-certificate block mixed in proves parse_pem's skip rule —
    # a PUBLIC KEY block (no secret material) ahead of a real cert
    openssl pkey -in "$work/root.key" -pubout > "$outdir/mixed.pem"
    cat "$work/root_ed.pem" >> "$outdir/mixed.pem"

    openssl version > tests/fixtures/OPENSSL-VERSION
    echo "gen_tls_fixtures: wrote $outdir ($(cat tests/fixtures/OPENSSL-VERSION))"
}

# gen_flight captures a real TLS 1.3 server flight from openssl
# s_server and commits the raw inbound bytes plus the throw-away PKI
# that makes the handshake verify. The suite only replays the bytes;
# it never execs openssl.
gen_flight() {
    local outdir=tests/tls
    local oxl="${OXL:-./target/oxl}"
    [ -x "$oxl" ] || { echo "gen_tls_fixtures: $oxl not built (run ./scripts/stage0.sh)" >&2; exit 1; }
    mkdir -p "$outdir"
    local work
    work=$(mktemp -d)
    trap 'rm -rf "$work"' RETURN

    # PKI: ECDSA P-256 CA -> leaf with both SAN shapes the client
    # dials (IP:127.0.0.1 is what server_name carries; DNS:localhost
    # documents the name side). ECDSA leaf pins the
    # ecdsa_secp256r1_sha256 CertificateVerify path.
    openssl ecparam -name prime256v1 -genkey -noout -out "$work/ca.key"
    openssl req -x509 -new -key "$work/ca.key" -sha256 -days 3650 \
        -subj "/CN=Oxl TLS X6 Test CA" \
        -addext "basicConstraints=critical,CA:TRUE" \
        -addext "keyUsage=critical,keyCertSign,cRLSign" \
        -addext "subjectKeyIdentifier=hash" \
        -out "$work/ca.pem"
    openssl ecparam -name prime256v1 -genkey -noout -out "$work/server.key"
    openssl req -new -key "$work/server.key" -subj "/CN=localhost" \
        -out "$work/server.csr"
    cat > "$work/leaf.cnf" <<'CNF'
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature
extendedKeyUsage=serverAuth
subjectAltName=DNS:localhost,IP:127.0.0.1
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid
CNF
    openssl x509 -req -in "$work/server.csr" -CA "$work/ca.pem" \
        -CAkey "$work/ca.key" -CAcreateserial -days 3650 -sha256 \
        -extfile "$work/leaf.cnf" -out "$work/server.pem"
    # s_server serves the leaf followed by every cert in -cert_chain
    cat "$work/server.pem" "$work/ca.pem" > "$work/server_chain.pem"

    local port="${TLS_FIXTURE_PORT:-24433}"
    openssl s_server -accept "$port" \
        -cert "$work/server_chain.pem" -key "$work/server.key" \
        -tls1_3 -www -naccept 8 -quiet \
        >"$work/s_server.log" 2>&1 &
    local srv=$!
    # wait for the listener
    local i
    for i in $(seq 1 50); do
        kill -0 "$srv" 2>/dev/null || break
        (exec 3<>"/dev/tcp/127.0.0.1/$port") 2>/dev/null && { exec 3>&- 3<&-; break; }
        sleep 0.1
    done

    "$oxl" run tests/tls/capture.oxl -- "$port" "$work/ca.pem" "$work/flight.hex"
    kill "$srv" 2>/dev/null || true
    wait "$srv" 2>/dev/null || true

    cp "$work/ca.pem" "$outdir/ca.pem"
    cp "$work/ca.key" "$outdir/ca-key.pem"
    cp "$work/server_chain.pem" "$outdir/server.pem"
    cp "$work/server.key" "$outdir/server-key.pem"
    cp "$work/flight.hex" "$outdir/flight.hex"
    openssl version > "$outdir/OPENSSL-VERSION"
    echo "gen_tls_fixtures: wrote $outdir ($(cat "$outdir/OPENSSL-VERSION"), $(wc -c < "$outdir/flight.hex") hex chars)"
}

case "${1:-all}" in
    rsa) gen_rsa ;;
    x509) gen_x509 ;;
    flight) gen_flight ;;
    all) gen_rsa; gen_x509; gen_flight ;;
    *) echo "usage: gen_tls_fixtures.sh [rsa|x509|flight|all]" >&2; exit 2 ;;
esac
