#!/usr/bin/env python3
# tests/tls/redirect_server.py — TLS 1.3 stub that answers every HTTP
# request with a fixed 302 redirect. Suite-side interop stub (not a
# fixture generator): run.sh's openssl gate runs it live so
# test_https_redirect_noleak can watch a real scheme downgrade.
#
# s_server cannot emit a redirect, and the oxl TLS server is parked —
# a python ssl stub is the only way to produce a *TLS* 302.
#
#   redirect_server.py <chain.pem> <key.pem> <port> <location>
#
# Accepts until killed (run.sh owns the lifecycle); every connection
# gets one response then close.

import socket, ssl, sys

def main():
    chain, key, port, location = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4]
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.load_cert_chain(chain, key)
    ls = socket.socket()
    ls.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    ls.bind(("127.0.0.1", port))
    ls.listen(8)
    body = ("HTTP/1.1 302 Found\r\n"
            "Location: %s\r\n"
            "Content-Length: 0\r\n"
            "Connection: close\r\n\r\n" % location).encode()
    while True:
        conn, _ = ls.accept()
        try:
            tls_conn = ctx.wrap_socket(conn, server_side=True)
            try:
                tls_conn.recv(65536)
                tls_conn.sendall(body)
            finally:
                # unwrap() sends close_notify before the TCP close —
                # plain close() would trip the client's truncation
                # fail-loud path, which is the correct behavior but
                # not what this stub is for
                try:
                    tls_conn.unwrap()
                except Exception:
                    pass
                tls_conn.close()
        except Exception:
            conn.close()

if __name__ == "__main__":
    main()
