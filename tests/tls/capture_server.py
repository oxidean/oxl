#!/usr/bin/env python3
# tests/tls/capture_server.py — plaintext HTTP stub that appends the
# request head of every connection to a file and answers 200.
# Suite-side interop stub: redirect_server.py 302s here so the test
# can assert which headers crossed the scheme hop. Loops until killed
# (run.sh owns the lifecycle) — the readiness probe's empty connect
# just records an empty head.
#
#   capture_server.py <port> <outfile>

import socket, sys

def main():
    port, outfile = int(sys.argv[1]), sys.argv[2]
    ls = socket.socket()
    ls.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    ls.bind(("127.0.0.1", port))
    ls.listen(4)
    while True:
        conn, _ = ls.accept()
        try:
            conn.settimeout(5)
            buf = b""
            while b"\r\n\r\n" not in buf:
                chunk = conn.recv(65536)
                if not chunk:
                    break
                buf += chunk
            with open(outfile, "ab") as f:
                f.write(buf)
            conn.sendall(b"HTTP/1.1 200 OK\r\nContent-Length: 8\r\n"
                         b"Connection: close\r\n\r\ncaptured")
        except Exception:
            pass
        finally:
            conn.close()

if __name__ == "__main__":
    main()
