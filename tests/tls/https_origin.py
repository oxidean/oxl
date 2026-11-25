import socketserver
import ssl
import sys


class Origin(socketserver.BaseRequestHandler):
    def handle(self):
        try:
            conn = self.server.context.wrap_socket(self.request, server_side=True)
        except ssl.SSLError:
            return
        conn.settimeout(10)
        data = bytearray()
        try:
            while b"\r\n\r\n" not in data and len(data) <= 32768:
                chunk = conn.recv(1)
                if not chunk:
                    return
                data.extend(chunk)
            if b"\r\n\r\n" not in data:
                return
            body = b"proxy origin ok"
            conn.sendall(b"HTTP/1.1 200 OK\r\nContent-Length: " + str(len(body)).encode() + b"\r\nConnection: close\r\n\r\n" + body)
            try:
                conn.unwrap()
            except (OSError, ssl.SSLError):
                pass
        except (OSError, ssl.SSLError):
            pass
        finally:
            conn.close()


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


def main():
    port, cert, key = int(sys.argv[1]), sys.argv[2], sys.argv[3]
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(cert, key)
    with Server(("127.0.0.1", port), Origin) as server:
        server.context = context
        server.serve_forever()


if __name__ == "__main__":
    main()
