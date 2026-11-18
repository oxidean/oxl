#!/usr/bin/env python3
# tests/tls/cookie_server.py — synthetic TLS 1.3 server that answers
# a ClientHello with a *cookie-only* HelloRetryRequest, then completes
# the handshake. Fixture-generator only: gen_tls_fixtures.sh's `cookie`
# section runs it so tests/tls/capture.oxl can record
# flight_cookie.hex. The suite never execs python — it replays the
# committed bytes.
#
# openssl s_server cannot emit a TLS cookie HRR (-stateless is DTLS),
# so this does the server side of the key schedule itself: ECDHE over
# the client's original x25519 share, HKDF-SHA256 transcript schedule,
# AES-128-GCM-SHA256 flight, ECDSA-P256 CertificateVerify.
#
#   cookie_server.py <port> <chain.pem> <key.pem>
#
# The cookie is echoed back by the client in CH2 — the server aborts
# if it is not, so the captured fixture also pins cookie echo.

import socket, sys, struct, hashlib, hmac as hmac_mod
from cryptography.hazmat.primitives.asymmetric.x25519 import (
    X25519PrivateKey, X25519PublicKey)
from cryptography.hazmat.primitives.asymmetric.ec import (
    ECDSA, SECP256R1)
from cryptography.hazmat.primitives.serialization import (
    load_pem_private_key, Encoding, PublicFormat)
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives import hashes
from cryptography.x509 import load_pem_x509_certificate

HRR_MAGIC = bytes.fromhex(
    "cf21ad74e59a6111be1d8c021e65b891c2a211167abb8c5e079e09e2c8a8339c")
COOKIE = b"oxl-x6-cookie-only-hrr-fixture!!"   # 31 bytes
G_X25519 = 29
SUITE = 0x1301          # TLS_AES_128_GCM_SHA256
SIGALG = 0x0403         # ecdsa_secp256r1_sha256
HLEN = 32

def hkdf_extract(salt, ikm):
    return hmac_mod.new(salt, ikm, hashlib.sha256).digest()

def hkdf_expand_label(secret, label, ctx, n):
    hkdf_label = struct.pack(">H", n) + bytes([6 + len(label)]) + \
        b"tls13 " + label + bytes([len(ctx)]) + ctx
    # HKDF-Expand, single block is always enough for n<=255
    return hmac_mod.new(secret, hkdf_label + b"\x01",
                        hashlib.sha256).digest()[:n]

def derive_secret(secret, label, transcript):
    return hkdf_expand_label(secret, label,
                             hashlib.sha256(transcript).digest(), HLEN)

def key_iv(secret):
    return (hkdf_expand_label(secret, b"key", b"", 16),
            hkdf_expand_label(secret, b"iv", b"", 12))

def nonce(iv, seq):
    return iv[:-8] + bytes(a ^ b for a, b in
                           zip(iv[-8:], seq.to_bytes(8, "big")))

def hs_msg(ty, body):
    return bytes([ty]) + len(body).to_bytes(3, "big") + body

def record(typ, payload, ver=0x0303):
    return bytes([typ]) + ver.to_bytes(2, "big") + \
        len(payload).to_bytes(2, "big") + payload

def sealed_record(aead, key, iv, seq, inner_typ, content):
    inner = content + bytes([inner_typ])
    hdr = b"\x17\x03\x03" + (len(inner) + 16).to_bytes(2, "big")
    ct = aead.encrypt(nonce(iv, seq), inner, hdr)
    return hdr + ct

def recvn(sock, n):
    buf = b""
    while len(buf) < n:
        chunk = sock.recv(n - len(buf))
        if not chunk:
            raise ConnectionError("eof")
        buf += chunk
    return buf

def read_records(sock):
    """Return list of (type, payload) for every record available,
    blocking until at least one arrives."""
    out = []
    hdr = recvn(sock, 5)
    out.append((hdr[0], recvn(sock, int.from_bytes(hdr[3:5], "big"))))
    sock.settimeout(0.05)
    try:
        while True:
            hdr = recvn(sock, 5)
            out.append((hdr[0],
                        recvn(sock, int.from_bytes(hdr[3:5], "big"))))
    except (socket.timeout, ConnectionError):
        pass
    sock.settimeout(15)
    return out

def hs_payloads(records):
    """Concatenate handshake-record payloads into a message stream."""
    return b"".join(p for t, p in records if t == 22)

def take_hs(stream):
    ty = stream[0]
    ln = int.from_bytes(stream[1:4], "big")
    return stream[:4 + ln], stream[4 + ln:]

def parse_ch(raw):
    """Return (session_id, key_shares, cookie_echo)."""
    b = raw[4:]
    pos = 2 + 32
    sidlen = b[pos]; pos += 1
    sid = b[pos:pos + sidlen]; pos += sidlen
    cslen = int.from_bytes(b[pos:pos + 2], "big"); pos += 2 + cslen
    cmplen = b[pos]; pos += 1 + cmplen
    elen = int.from_bytes(b[pos:pos + 2], "big"); pos += 2
    end = pos + elen
    shares, cookie = {}, None
    while pos < end:
        et = int.from_bytes(b[pos:pos + 2], "big")
        ed = int.from_bytes(b[pos + 2:pos + 4], "big")
        d = b[pos + 4:pos + 4 + ed]
        pos += 4 + ed
        if et == 51:  # key_share
            p = 2  # client_shares vector len
            while p < len(d):
                g = int.from_bytes(d[p:p + 2], "big")
                kl = int.from_bytes(d[p + 2:p + 4], "big")
                shares[g] = d[p + 4:p + 4 + kl]
                p += 4 + kl
        elif et == 44:  # cookie
            cl = int.from_bytes(d[0:2], "big")
            cookie = d[2:2 + cl]
    return sid, shares, cookie

def sh_body(random, sid, exts):
    return b"\x03\x03" + random + bytes([len(sid)]) + sid + \
        SUITE.to_bytes(2, "big") + b"\x00" + \
        len(exts).to_bytes(2, "big") + exts

def ext(ty, body):
    return ty.to_bytes(2, "big") + len(body).to_bytes(2, "big") + body

def main():
    port, chainf, keyf = int(sys.argv[1]), sys.argv[2], sys.argv[3]
    pem = open(chainf, "rb").read()
    certs_der = [load_pem_x509_certificate(
        blk + b"-----END CERTIFICATE-----").public_bytes(Encoding.DER)
        for blk in pem.split(b"-----END CERTIFICATE-----")
        if b"-----BEGIN CERTIFICATE-----" in blk]
    key = load_pem_private_key(open(keyf, "rb").read(), password=None)

    ls = socket.socket()
    ls.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    ls.bind(("127.0.0.1", port))
    ls.listen(1)
    conn, _ = ls.accept()
    conn.settimeout(15)

    # ---- CH1 ----
    recs = read_records(conn)
    stream = hs_payloads(recs)
    ch1, stream = take_hs(stream)
    assert ch1[0] == 1, "expected client_hello"
    sid, shares, _ = parse_ch(ch1)
    assert G_X25519 in shares, "no x25519 share in CH1"

    # ---- HRR: cookie only, no key_share demand ----
    hrr_exts = ext(43, b"\x03\x04") + ext(44, len(COOKIE).to_bytes(2, "big") + COOKIE)
    hrr = hs_msg(2, sh_body(HRR_MAGIC, sid, hrr_exts))
    conn.sendall(record(22, hrr))

    # ---- CH2 (+ compat CCS) ----
    recs = read_records(conn)
    stream = hs_payloads(recs)
    ch2, stream = take_hs(stream)
    assert ch2[0] == 1, "expected client_hello#2"
    sid2, shares2, cookie2 = parse_ch(ch2)
    assert sid2 == sid, "CH2 session id changed"
    assert cookie2 == COOKIE, "cookie not echoed in CH2"
    assert G_X25519 in shares2, "x25519 share missing in CH2"

    # ---- ECDHE + key schedule ----
    srv_sk = X25519PrivateKey.generate()
    srv_pk = srv_sk.public_key().public_bytes(
        Encoding.Raw, PublicFormat.Raw)
    shared = srv_sk.exchange(X25519PublicKey.from_public_bytes(
        shares2[G_X25519]))

    # transcript after HRR: message_hash(CH1) + HRR + CH2 ...
    t = hs_msg(254, hashlib.sha256(ch1).digest()) + hrr + ch2

    sh2_exts = ext(43, b"\x03\x04") + ext(
        51, G_X25519.to_bytes(2, "big") + len(srv_pk).to_bytes(2, "big") + srv_pk)
    sh2 = hs_msg(2, sh_body(__import__("os").urandom(32), sid, sh2_exts))
    t += sh2
    conn.sendall(record(22, sh2))
    conn.sendall(record(20, b"\x01", ver=0x0303))

    early = hkdf_extract(b"\x00" * HLEN, b"\x00" * HLEN)
    hs_secret = hkdf_extract(derive_secret(early, b"derived", b""), shared)
    c_hs = derive_secret(hs_secret, b"c hs traffic", t)
    s_hs = derive_secret(hs_secret, b"s hs traffic", t)
    s_key, s_iv = key_iv(s_hs)

    aead = AESGCM(s_key)
    seq = 0
    def send_hs(ty, body):
        nonlocal seq, t
        m = hs_msg(ty, body)
        t += m
        conn.sendall(sealed_record(aead, s_key, s_iv, seq, 22, m))
        seq += 1

    send_hs(8, b"\x00\x00")                                   # EE
    cert_list = b"".join(
        len(d).to_bytes(3, "big") + d + b"\x00\x00"
        for d in certs_der)
    send_hs(11, b"\x00" + len(cert_list).to_bytes(3, "big") + cert_list)
    cv_content = b"\x20" * 64 + b"TLS 1.3, server CertificateVerify" + \
        b"\x00" + hashlib.sha256(t).digest()
    sig = key.sign(cv_content, ECDSA(hashes.SHA256()))
    send_hs(15, SIGALG.to_bytes(2, "big") +
            len(sig).to_bytes(2, "big") + sig)
    fin_key = hkdf_expand_label(s_hs, b"finished", b"", HLEN)
    vd = hmac_mod.new(fin_key, hashlib.sha256(t).digest(),
                      hashlib.sha256).digest()
    send_hs(20, vd)

    # app traffic secrets: transcript now includes server Finished
    master = hkdf_extract(derive_secret(hs_secret, b"derived", b""),
                          b"\x00" * HLEN)
    s_ap = derive_secret(master, b"s ap traffic", t)
    ap_key, ap_iv = key_iv(s_ap)

    # page immediately — the client reads it after its own Finished
    page = (b"HTTP/1.0 200 ok\r\ncontent-type: text/plain\r\n\r\n"
            b"oxl x6 cookie-hrr fixture page\n")
    aead_ap = AESGCM(ap_key)
    conn.sendall(sealed_record(aead_ap, ap_key, ap_iv, 0, 23, page))

    # drain the client flight + GET + close_notify until it hangs up
    try:
        while conn.recv(8192):
            pass
    except (socket.timeout, ConnectionError):
        pass
    conn.close()
    ls.close()
    print("cookie_server: handshake completed, cookie echoed", flush=True)

if __name__ == "__main__":
    main()
