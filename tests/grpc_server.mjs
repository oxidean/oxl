// Independent interoperability peer: Node's native HTTP/2 implementation
// plus a small gRPC envelope/status fixture (no oxl H2 or grpc package).
import http2 from 'node:http2';
import fs from 'node:fs';

const port = Number(process.argv[2]);
const tlsPort = Number(process.argv[3]);
const server = http2.createServer();
const frame = (value) => {
  const payload = Buffer.from(value);
  const head = Buffer.alloc(5);
  head.writeUInt32BE(payload.length, 1);
  return Buffer.concat([head, payload]);
};
const parseFrames = (buf) => {
  const messages = [];
  while (buf.length >= 5) {
    const compressed = buf[0];
    const n = buf.readUInt32BE(1);
    if (n > 4 * 1024 * 1024 || buf.length < n + 5) break;
    messages.push({compressed, value: buf.subarray(5, n + 5)});
    buf = buf.subarray(n + 5);
  }
  return {messages, rest: buf};
};

const handle = (stream, headers) => {
  const path = headers[':path'];
  let pending = Buffer.alloc(0);
  const requests = [];
  const response = (status = '0', extra = {}) => {
    if (stream.destroyed) return;
    stream.respond({ ':status': 200, 'content-type': 'application/grpc', 'x-response': 'ready', 'x-request-token': headers['x-token'] ?? '', ...extra }, {waitForTrailers: true});
    stream.on('wantTrailers', () => {
      if (!stream.destroyed) stream.sendTrailers({'grpc-status': status, 'grpc-message': status === '7' ? 'permission%20denied' : '', 'x-finished': 'yes'});
    });
  };
  const send = (value) => stream.write(frame(value));

  if (path === '/svc/malformed') {
    response();
    stream.write(Buffer.from([0, 0, 0, 0, 4, 97]));
    stream.end();
    return;
  }
  if (path === '/svc/compressed-frame') {
    response();
    stream.write(Buffer.from([1, 0, 0, 0, 1, 120]));
    stream.end();
    return;
  }
  if (path === '/svc/oversized') {
    response();
    const h = Buffer.from([0, 0, 64, 0, 1]);
    stream.write(h);
    stream.end();
    return;
  }
  if (path === '/svc/compressed') {
    stream.respond({ ':status': 200, 'content-type': 'application/grpc', 'grpc-encoding': 'gzip' });
    stream.end();
    return;
  }
  if (path === '/svc/http-error') {
    stream.respond({ ':status': 404, 'content-type': 'text/plain' });
    stream.end('not found');
    return;
  }
  if (path === '/svc/bad-content-type') {
    stream.respond({ ':status': 200, 'content-type': 'text/plain' });
    stream.end('not grpc');
    return;
  }
  if (path === '/svc/unknown-status') {
    stream.respond({ ':status': 200, 'content-type': 'application/grpc' }, {waitForTrailers: true});
    stream.on('wantTrailers', () => stream.sendTrailers({'grpc-status': '17', 'grpc-message': 'future%20status'}));
    stream.end();
    return;
  }
  if (path === '/svc/trailers-only') {
    stream.respond({ ':status': 200, 'content-type': 'application/grpc', 'grpc-status': '0' });
    stream.end();
    return;
  }
  if (path === '/svc/delay') {
    setTimeout(() => {
      if (!stream.destroyed) { response(); send('late'); stream.end(); }
    }, 800);
    return;
  }

  if (path === '/svc/bidi' || path === '/svc/bidi-cancel') response();
  stream.on('data', (chunk) => {
    pending = Buffer.concat([pending, chunk]);
    const parsed = parseFrames(pending);
    pending = parsed.rest;
    for (const msg of parsed.messages) {
      if (msg.compressed) { stream.close(http2.constants.NGHTTP2_PROTOCOL_ERROR); return; }
      requests.push(msg.value.toString());
      if (path === '/svc/bidi') send(msg.value.toString());
    }
  });
  stream.on('end', () => {
    if (stream.destroyed) return;
    if (pending.length !== 0) { stream.close(http2.constants.NGHTTP2_PROTOCOL_ERROR); return; }
    if (path === '/svc/bidi') { stream.end(); return; }
    if (path === '/svc/unary') {
      response(); send(requests[0] ?? ''); stream.end();
    } else if (path === '/svc/client-stream') {
      response(); send(requests.join('')); stream.end();
    } else if (path === '/svc/server-stream') {
      response(); send('first'); send('second'); stream.end();
    } else if (path === '/svc/status') {
      response('7', {'x-response': 'denied'}); stream.end();
    } else {
      response(); send(requests[0] ?? ''); stream.end();
    }
  });
};
server.on('stream', handle);
server.listen(port, '127.0.0.1');
const tlsServer = http2.createSecureServer({
  key: fs.readFileSync('tests/tls/server-key.pem'),
  cert: fs.readFileSync('tests/tls/server.pem'),
  ALPNProtocols: ['h2'],
});
tlsServer.on('stream', handle);
tlsServer.listen(tlsPort, '127.0.0.1');
