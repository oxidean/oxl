#!/usr/bin/env python3
"""Tiny independent RFC 6455 peer used only by tests/run.sh on loopback."""
import base64
import hashlib
import os
import socketserver
import ssl
import struct
import sys
import threading
import time

GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"


def read_exact(sock, n):
    out = bytearray()
    while len(out) < n:
        block = sock.recv(n - len(out))
        if not block:
            raise EOFError("truncated frame")
        out.extend(block)
    return bytes(out)


def read_frame(sock):
    h = read_exact(sock, 2)
    fin, opcode, masked, length = bool(h[0] & 128), h[0] & 15, bool(h[1] & 128), h[1] & 127
    if length == 126:
        length = struct.unpack("!H", read_exact(sock, 2))[0]
    elif length == 127:
        length = struct.unpack("!Q", read_exact(sock, 8))[0]
    if not masked:
        raise AssertionError("client frame was not masked")
    mask = read_exact(sock, 4)
    data = read_exact(sock, length)
    return fin, opcode, bytes(v ^ mask[i & 3] for i, v in enumerate(data))


def send_frame(sock, opcode, data=b"", fin=True):
    first = opcode | (128 if fin else 0)
    n = len(data)
    if n < 126:
        head = bytes((first, n))
    elif n <= 65535:
        head = bytes((first, 126)) + struct.pack("!H", n)
    else:
        head = bytes((first, 127)) + struct.pack("!Q", n)
    sock.sendall(head + data)

def expect_protocol_close(sock):
    if read_frame(sock) != (True, 8, b"\x03\xea"):
        raise AssertionError("client did not send a masked close-1002 frame")


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True
    block_on_close = False

    def __init__(self, address, tls_context=None):
        self.tls_context = tls_context
        super().__init__(address, Handler)

    def get_request(self):
        sock, address = super().get_request()
        if self.tls_context:
            sock = self.tls_context.wrap_socket(sock, server_side=True)
        return sock, address


class Handler(socketserver.BaseRequestHandler):
    def handle(self):
        sock = self.request
        try:
            sock.settimeout(3)
            req = bytearray()
            while b"\r\n\r\n" not in req and len(req) < 16384:
                chunk = sock.recv(2048)
                if not chunk:
                    return
                req.extend(chunk)
            if len(req) >= 16384:
                raise AssertionError("request headers too large")
            head = bytes(req).split(b"\r\n\r\n", 1)[0].decode("ascii")
            lines = head.split("\r\n")
            path = lines[0].split(" ")[1]
            headers = {}
            for line in lines[1:]:
                name, value = line.split(":", 1)
                headers.setdefault(name.strip().lower(), []).append(value.strip())
            key = headers["sec-websocket-key"][0]
            accept = base64.b64encode(hashlib.sha1((key + GUID).encode()).digest()).decode()
            mode = path.lstrip("/")
            if mode == "bad-status":
                sock.sendall(b"HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n")
                return
            status = "HTTP/1.1 101" if mode == "empty-reason" else "HTTP/1.1 101 Switching Protocols"
            response = [status, "Upgrade: websocket", "Connection: keep-alive, Upgrade"]
            if mode == "missing-upgrade":
                response.remove("Upgrade: websocket")
            if mode == "missing-connection":
                response.remove("Connection: keep-alive, Upgrade")
            response.append("Sec-WebSocket-Accept: " + ("bad" if mode == "bad-accept" else accept))
            if mode == "duplicate-upgrade":
                response.append("Upgrade: websocket")
            if mode == "missing-accept":
                response = [x for x in response if not x.lower().startswith("sec-websocket-accept:")]
            if mode == "duplicate-accept":
                response.append("Sec-WebSocket-Accept: " + accept)
            protocol = "not-offered" if mode == "bad-protocol" else "echo.v1"
            if mode != "missing-protocol":
                response.append("Sec-WebSocket-Protocol: " + protocol)
            sock.sendall(("\r\n".join(response) + "\r\n\r\n").encode())
            if mode.startswith("bad-") or mode == "missing-accept" or mode == "missing-upgrade" or mode == "missing-connection" or mode == "duplicate-accept" or mode == "duplicate-upgrade":
                return
            if mode == "timeout":
                time.sleep(1)
                return
            if mode == "extended":
                send_frame(sock, 1, b"e" * 126)
                return
            if mode == "length64":
                frame = read_frame(sock)
                if frame != (True, 2, bytes(i & 255 for i in range(65536))):
                    raise AssertionError("64-bit frame length/payload mismatch")
                close = read_frame(sock)
                if close[1] != 8:
                    raise AssertionError("missing close after 64-bit frame")
                send_frame(sock, 8, close[2])
                return
            if mode == "masked":
                sock.sendall(b"\x81\x81\x00\x00\x00\x00x")
                expect_protocol_close(sock)
                return
            if mode == "masked-small-limit":
                sock.sendall(b"\x81\x81\x00\x00\x00\x00x")
                expect_protocol_close(sock)
                return
            if mode == "ping-small-limit":
                # legal ping larger than the client's configured max_frame:
                # control frames must be exempt from the message limit
                send_frame(sock, 9, b"pongme")
                pong = read_frame(sock)
                if pong != (True, 10, b"pongme"):
                    raise AssertionError("missing pong for legal ping: %r" % (pong,))
                send_frame(sock, 1, b"x")
                close = read_frame(sock)
                if close[1] != 8:
                    raise AssertionError("missing close response")
                send_frame(sock, 8, close[2])
                return
            if mode == "reserved-opcode":
                sock.sendall(b"\x83\x00")
                expect_protocol_close(sock)
                return
            if mode == "bad-utf8":
                sock.sendall(b"\x81\x01\xff")
                expect_protocol_close(sock)
                return
            if mode == "bad-control":
                sock.sendall(b"\x09\x00")
                expect_protocol_close(sock)
                return
            if mode == "bad-close-code":
                send_frame(sock, 8, b"\x03\xed")  # 1005 is forbidden on wire
                expect_protocol_close(sock)
                return
            if mode == "bad-close-length":
                send_frame(sock, 8, b"\x00")
                expect_protocol_close(sock)
                return
            if mode == "oversize":
                send_frame(sock, 2, b"123456789")
                expect_protocol_close(sock)
                return
            if mode == "nonminimal":
                sock.sendall(b"\x82\x7e\x00\x01x")
                expect_protocol_close(sock)
                return
            if mode == "huge-length":
                sock.sendall(b"\x82\x7f\x80\x00\x00\x00\x00\x00\x00\x00")
                expect_protocol_close(sock)
                return
            if mode == "long-control":
                sock.sendall(b"\x89\x7e\x00\x7e" + b"x" * 126)
                expect_protocol_close(sock)
                return
            if mode == "unexpected-continuation":
                send_frame(sock, 0, b"x")
                expect_protocol_close(sock)
                return
            if mode == "new-during-fragment":
                send_frame(sock, 1, b"first", fin=False)
                send_frame(sock, 2, b"other")
                expect_protocol_close(sock)
                return
            if mode == "fragment-overflow":
                send_frame(sock, 1, b"12345", fin=False)
                send_frame(sock, 0, b"6789")
                expect_protocol_close(sock)
                return
            if mode == "ok" and self.server.tls_context:
                send_frame(sock, 1, b"secure")
                send_frame(sock, 8, struct.pack("!H", 1000))
                fin, op, data = read_frame(sock)
                if op != 8 or len(data) < 2:
                    raise AssertionError("client did not answer close")
                return
            if mode == "ok":
                first = read_frame(sock)
                second = read_frame(sock)
                if first != (True, 1, b"hello"):
                    raise AssertionError("unexpected text frame: %r" % (first,))
                if second != (True, 2, b"\x00\xff"):
                    raise AssertionError("unexpected binary frame: %r" % (second,))
                third = read_frame(sock)
                if third != (True, 2, bytes(i & 255 for i in range(130))):
                    raise AssertionError("unexpected 16-bit frame: %r" % (third[:2],))
                fragments = [read_frame(sock) for _ in range(8)]
                if fragments[0][1] != 2 or fragments[0][0] or any(f[1] != 0 for f in fragments[1:-1]) or not fragments[-1][0]:
                    raise AssertionError("invalid outgoing fragmentation")
                if b"".join(f[2] for f in fragments) != bytes(i & 255 for i in range(65536)):
                    raise AssertionError("fragmented 64-bit payload mismatch")
                client_ping = read_frame(sock)
                if client_ping != (True, 9, b"client-ping"):
                    raise AssertionError("unexpected client ping: %r" % (client_ping,))
                send_frame(sock, 10, b"client-ping")
                send_frame(sock, 1, b"frag", fin=False)
                send_frame(sock, 9, b"p")
                send_frame(sock, 0, b"mented")
                pong = read_frame(sock)
                if pong != (True, 10, b"p"):
                    raise AssertionError("missing pong: %r" % (pong,))
                close = read_frame(sock)
                if close[1] != 8:
                    raise AssertionError("missing close response")
                send_frame(sock, 8, close[2])
        except (EOFError, ConnectionError, OSError, ssl.SSLError):
            pass
        except Exception as exc:  # surfaced by a sentinel consumed by the test harness
            with open(os.environ["OXL_WS_ERRORS"], "a", encoding="utf-8") as f:
                f.write(repr(exc) + "\n")


def main():
    ports_path = sys.argv[1]
    tls_context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    tls_context.load_cert_chain("tests/tls/server.pem", "tests/tls/server-key.pem")
    ws = Server(("127.0.0.1", 0))
    wss = Server(("127.0.0.1", 0), tls_context)
    with open(ports_path, "w", encoding="ascii") as f:
        f.write("%d %d\n" % (ws.server_address[1], wss.server_address[1]))
    for server in (ws, wss):
        threading.Thread(target=server.serve_forever, daemon=True).start()
    threading.Event().wait()


if __name__ == "__main__":
    main()
