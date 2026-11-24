import fs from "node:fs";
import http2 from "node:http2";
import https from "node:https";
import http from "node:http";

const h2cPort = Number(process.argv[2]);
const h2tlsPort = Number(process.argv[3]);
const h1tlsPort = Number(process.argv[4]);
const h1Port = Number(process.argv[5]);
const key = fs.readFileSync("tests/tls/server-key.pem");
const cert = fs.readFileSync("tests/tls/server.pem");
const respond = (stream, headers) => {
  if (headers[":path"] === "/stall") return;
  if (headers[":path"] === "/goaway-accepted") {
    stream.session.goaway(0, stream.id);
    stream.respond({ ":status": 200, "content-type": "text/plain" });
    stream.end("accepted");
    return;
  }
  stream.respond({ ":status": 200, "content-type": "text/plain" }, { waitForTrailers: true });
  stream.on("wantTrailers", () => stream.sendTrailers({ "x-check": "done" }));
  stream.end("abc");
};
const h2c = http2.createServer();
h2c.on("stream", respond);
h2c.listen(h2cPort, "127.0.0.1");
const h2tls = http2.createSecureServer({ key, cert, allowHTTP1: true, ALPNProtocols: ["h2", "http/1.1"] });
h2tls.on("stream", respond);
h2tls.listen(h2tlsPort, "127.0.0.1");
const h1tls = https.createServer({ key, cert, ALPNProtocols: ["http/1.1"] }, (_req, res) => res.end("http/1.1"));
h1tls.listen(h1tlsPort, "127.0.0.1");

const h1 = http.createServer((_req, res) => res.end("http/1.1"));
h1.listen(h1Port, "127.0.0.1");
