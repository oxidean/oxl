#!/usr/bin/env python3
"""Tiny adversarial TLS peer for deterministic negotiation negatives.

This is test-only: it reads a ClientHello and returns a TLS 1.2
ServerHello carrying DOWNGRD\\x01, then an alert for the pinned-client
case. It never completes authentication or sends application data.
"""
import socket
import sys


def exact(conn, size):
    data = bytearray()
    while len(data) < size:
        part = conn.recv(size - len(data))
        if not part:
            raise EOFError("peer closed early")
        data.extend(part)
    return bytes(data)


def u24(n):
    return bytes((n >> 16 & 255, n >> 8 & 255, n & 255))


def handshake(typ, body):
    return bytes((typ,)) + u24(len(body)) + body


def record(typ, body):
    return bytes((typ, 3, 3)) + len(body).to_bytes(2, "big") + body


def server_hello(session_id, malformed=False):
    random = bytes(24) + b"DOWNGRD\x01"
    # Initial secure-renegotiation and EMS echoes.
    exts = b"\x00\x17\x00\x00\xff\x01\x00\x01\x00"
    body = (
        b"\x03\x03"
        + random
        + bytes((len(session_id),))
        + session_id
        + b"\xc0\x2f"
        + (b"\x01" if malformed else b"\x00")
        + len(exts).to_bytes(2, "big")
        + exts
    )
    return record(22, handshake(2, body))


def main():
    port = int(sys.argv[1])
    mode = sys.argv[2]
    with socket.socket() as listener:
        listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        listener.bind(("127.0.0.1", port))
        listener.listen(1)
        print("READY", flush=True)
        conn, _ = listener.accept()
        with conn:
            conn.settimeout(8)
            header = exact(conn, 5)
            frag = exact(conn, int.from_bytes(header[3:5], "big"))
            if header[0] != 22 or not frag or frag[0] != 1:
                raise ValueError("expected ClientHello record")
            chlen = int.from_bytes(frag[1:4], "big")
            if chlen + 4 != len(frag):
                raise ValueError("fragmented ClientHello is unexpected in test")
            body = frag[4:]
            if len(body) < 35:
                raise ValueError("short ClientHello")
            sidlen = body[34]
            session_id = body[35 : 35 + sidlen]
            malformed = mode == "malformed"
            conn.sendall(server_hello(session_id, malformed))
            if mode == "pinned":
                # Reaching this alert proves the pinned TLS 1.2 client
                # did not abort merely because the random has a sentinel.
                conn.sendall(record(21, b"\x02\x28"))
            try:
                conn.recv(64)
            except (socket.timeout, ConnectionError):
                pass
            conn.close()


if __name__ == "__main__":
    main()