import select
import socket
import socketserver
import sys


class Proxy(socketserver.BaseRequestHandler):
    def handle(self):
        data = bytearray()
        while b"\r\n\r\n" not in data and len(data) <= 32768:
            chunk = self.request.recv(1)
            if not chunk:
                return
            data.extend(chunk)
        if b"\r\n\r\n" not in data:
            return
        lines = bytes(data).split(b"\r\n")
        with open(self.server.capture, "ab") as capture:
            capture.write(lines[0] + b"\n")
            for line in lines[1:]:
                if not line:
                    break
                capture.write(line + b"\n")
        parts = lines[0].split()
        if len(parts) != 3 or parts[0] != b"CONNECT":
            self.request.sendall(b"HTTP/1.1 400 Bad Request\r\nContent-Length: 0\r\n\r\n")
            return
        host = parts[1].rsplit(b":", 1)[0].strip(b"[]")
        if host == b"reject.invalid":
            self.request.sendall(b"HTTP/1.1 407 Proxy Authentication Required\r\nContent-Length: 0\r\n\r\n")
            return
        if host == b"badgateway.invalid":
            self.request.sendall(b"HTTP/1.1 502 Bad Gateway\r\nContent-Length: 0\r\n\r\n")
            return
        if host == b"malformed.invalid":
            self.request.sendall(b"not an HTTP response\r\n\r\n")
            return
        if host == b"badcl.invalid":
            self.request.sendall(b"HTTP/1.1 200 Connection Established\r\nContent-Length: 5\r\n\r\n")
            return
        if host == b"badte.invalid":
            self.request.sendall(b"HTTP/1.1 200 Connection Established\r\nTransfer-Encoding: chunked\r\n\r\n")
            return
        if host == b"truncated.invalid":
            self.request.sendall(b"HTTP/1.1 200 Connection")
            return
        if host == b"oversized.invalid":
            self.request.sendall(b"HTTP/1.1 200 Connection Established\r\nX-Pad: " + b"x" * 32768 + b"\r\n\r\n")
            return
        if host == b"cumulative.invalid":
            response = b"HTTP/1.1 100 Continue\r\nX-Pad: " + b"x" * 16380 + b"\r\n\r\n"
            response += b"HTTP/1.1 100 Continue\r\nX-Pad: " + b"x" * 16380 + b"\r\n\r\n"
            response += b"HTTP/1.1 200 Connection Established\r\n\r\n"
            self.request.sendall(response)
            return
        try:
            upstream = socket.create_connection(("127.0.0.1", self.server.origin_port), 5)
        except OSError:
            self.request.sendall(b"HTTP/1.1 502 Bad Gateway\r\nContent-Length: 0\r\n\r\n")
            return
        if host == b"interim.invalid":
            self.request.sendall(b"HTTP/1.1 100 Continue\r\n\r\n")
        self.request.sendall(b"HTTP/1.1 200 Connection Established\r\n\r\n")
        peers = (self.request, upstream)
        try:
            while True:
                readable, _, _ = select.select(peers, [], [], 15)
                if not readable:
                    return
                for source in readable:
                    target = upstream if source is self.request else self.request
                    chunk = source.recv(65536)
                    if not chunk:
                        return
                    target.sendall(chunk)
        except OSError:
            pass
        finally:
            upstream.close()


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


def main():
    port, origin_port, capture = int(sys.argv[1]), int(sys.argv[2]), sys.argv[3]
    with Server(("127.0.0.1", port), Proxy) as server:
        server.origin_port = origin_port
        server.capture = capture
        server.serve_forever()


if __name__ == "__main__":
    main()
