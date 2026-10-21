import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import http from 'node:http';
import { setImmediate } from 'node:timers/promises';

// Exercise the actual patched dependency, rather than a copy of the replacement.
assert.equal(typeof WebAssembly, 'undefined', 'Run this probe with --jitless');
const source = process.argv[2];
assert.ok(source, 'Pass the patched deps/undici/undici.js path');
const undici = createRequire(import.meta.url)(source);
assert.equal(new undici.Headers({ test: 'ok' }).get('test'), 'ok');
const form = new undici.FormData();
form.append('value', 'ok');
assert.equal(form.get('value'), 'ok');
assert.equal(new undici.Request('http://127.0.0.1/').method, 'GET');
await setImmediate(); // Eager parser rejection would terminate this process.

const server = http.createServer((_request, response) => response.end('native-http-ok'));
try {
  await new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', resolve);
  });
  const url = `http://127.0.0.1:${server.address().port}`;
  await assert.rejects(undici.fetch(url), error => error.cause instanceof ReferenceError &&
    error.cause.message.includes('WebAssembly'));
  const value = await new Promise((resolve, reject) => {
    http.get(url, response => {
      const chunks = [];
      response.on('data', chunk => chunks.push(chunk));
      response.on('end', () => resolve(Buffer.concat(chunks).toString('utf8')));
      response.on('error', reject);
    }).on('error', reject);
  });
  assert.equal(value, 'native-http-ok');
  console.log('Headers/FormData/Request load without WASM; fetch rejects explicitly; native HTTP succeeds.');
} finally {
  server.closeAllConnections();
  await new Promise(resolve => server.close(resolve));
}
