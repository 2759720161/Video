import { registerHooks, stripTypeScriptTypes } from 'node:module';
import { existsSync, readFileSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { createServer } from 'node:http';
import assert from 'node:assert/strict';
import { test } from 'node:test';

registerHooks({
  resolve(specifier, context, next) {
    if (specifier.startsWith('@kit.')) return { url: new URL('./fixtures/catnode-kit.mjs', import.meta.url).href, shortCircuit: true };
    if (specifier.startsWith('.') && context.parentURL?.startsWith('file:')) {
      const value = new URL(specifier, context.parentURL);
      if (!value.pathname.endsWith('.ets')) value.pathname += '.ets';
      if (existsSync(fileURLToPath(value))) return { url: value.href, shortCircuit: true };
    }
    return next(specifier, context);
  },
  load(url, context, next) {
    if (url.endsWith('.ets')) return { format: 'module', source:
      stripTypeScriptTypes(readFileSync(new URL(url), 'utf8'), { mode: 'transform' }), shortCircuit: true };
    return next(url, context);
  }
});
const { CatNodeSubscription, CatNodeSubscriptionCodec, CatNodeSubscriptionStage } = await import('../entry/src/main/ets/providers/catvod/CatNodeSubscription.ets');
const { http, buffer } = await import('./fixtures/catnode-kit.mjs');
const md5 = bytes => createHash('md5').update(bytes).digest('hex');

test('subscription URL derives the script path without changing the query', () => {
  assert.equal(CatNodeSubscriptionCodec.scriptUrl(' HTTPS://example.com/cat/index.js.md5?key=a%2Fb '),
    'https://example.com/cat/index.js?key=a%2Fb');
  for (const url of ['', 'file:///index.js.md5', 'https://user:secret@example.com/index.js.md5',
    'https://example.com/index.js.md5#part', 'https://example.com/index.js', 'https://example.com/a\n/index.js.md5']) {
    assert.throws(() => CatNodeSubscriptionCodec.normalizeUrl(url));
  }
});
test('checksum accepts plain hex and md5sum format while rejecting malformed results', () => {
  assert.equal(CatNodeSubscriptionCodec.parseMd5('A'.repeat(32) + '\n'), 'a'.repeat(32));
  assert.equal(CatNodeSubscriptionCodec.parseMd5('a'.repeat(32) + '  index.js'), 'a'.repeat(32));
  for (const text of ['x'.repeat(32), '<html>error</html>', 'a'.repeat(32) + '\n' + 'b'.repeat(32)]) {
    assert.throws(() => CatNodeSubscriptionCodec.parseMd5(text));
  }
});

async function fixture(body) {
  const parent = path.resolve(tmpdir());
  const root = mkdtempSync(path.join(parent, 'cat-subscription-'));
  const bytes = Buffer.from("module.exports={start:async()=>{},stop:async()=>{}}; // 中文\n");
  const state = { bytes, checksum: md5(bytes), checksumStatus: 200, scriptRequests: 0, queries: [] };
  const server = createServer((request, response) => {
    state.queries.push(request.url);
    if (request.url.startsWith('/a/index.js.md5')) { response.writeHead(state.checksumStatus); response.end(state.checksum); }
    else if (request.url.startsWith('/a/index.js')) { state.scriptRequests++; response.end(state.bytes); }
    else response.writeHead(404).end();
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const address = `http://127.0.0.1:${server.address().port}/a/index.js.md5?key=fixture`;
  let closed = false;
  const close = async () => { if (!closed) { closed = true; server.closeAllConnections(); await new Promise(resolve => server.close(resolve)); } };
  try { await body({ context: { filesDir: root }, state, address, close }); }
  finally {
    await close();
    const resolved = path.resolve(root);
    assert.ok(resolved.startsWith(parent + path.sep));
    rmSync(resolved, { recursive: true, force: true });
  }
}

test('downloads exact bytes, checks MD5 and reuses an unchanged verified cache', async () => fixture(async ({ context, state, address }) => {
  const first = await CatNodeSubscription.prepare(context, address);
  assert.deepEqual(readFileSync(path.join(first.root, 'program', first.file)), state.bytes);
  assert.equal(first.md5, state.checksum);
  assert.equal((await CatNodeSubscription.prepare(context, address)).sha256, first.sha256);
  assert.equal(state.scriptRequests, 1);
  assert.ok(state.queries.includes('/a/index.js?key=fixture'));
}));

test('changed digest updates atomically and a mismatch keeps the previous manifest intact', async () => fixture(async ({ context, state, address }) => {
  const first = await CatNodeSubscription.prepare(context, address);
  const manifest = path.join(first.root, 'bundle.json');
  const old = readFileSync(manifest, 'utf8');
  state.checksum = 'f'.repeat(32);
  await assert.rejects(CatNodeSubscription.prepare(context, address), /MD5 校验失败/);
  assert.equal(readFileSync(manifest, 'utf8'), old);
  state.bytes = Buffer.from('module.exports={updated:true}'); state.checksum = md5(state.bytes);
  const updated = await CatNodeSubscription.prepare(context, address);
  assert.notEqual(updated.file, first.file);
  assert.equal(JSON.parse(readFileSync(manifest, 'utf8')).file, updated.file);
}));

test('offline uses a rechecked cache, but HTTP errors and malformed checksums are not hidden', async () => fixture(async ({ context, state, address, close }) => {
  const cached = await CatNodeSubscription.prepare(context, address);
  state.checksumStatus = 404;
  await assert.rejects(CatNodeSubscription.prepare(context, address), /HTTP 404/);
  state.checksumStatus = 200; state.checksum = 'invalid';
  await assert.rejects(CatNodeSubscription.prepare(context, address), /有效的 MD5/);
  await close();
  assert.equal((await CatNodeSubscription.prepare(context, address)).sha256, cached.sha256);
  writeFileSync(path.join(cached.root, 'program', cached.file), 'corrupted');
  await assert.rejects(CatNodeSubscription.prepare(context, address));
}));

test('different subscription URLs have separate program and profile roots', async () => fixture(async ({ context, address }) => {
  const first = await CatNodeSubscription.prepare(context, address);
  const second = await CatNodeSubscription.prepare(context, address + '&another=1');
  assert.notEqual(first.root, second.root);
}));

test('reports checksum, download and verification stages; unchanged cache skips script stages', async () => fixture(async ({ context, address }) => {
  const first = [];
  await CatNodeSubscription.prepare(context, address, stage => first.push(stage));
  assert.deepEqual(first, [CatNodeSubscriptionStage.CHECKING, CatNodeSubscriptionStage.DOWNLOADING,
    CatNodeSubscriptionStage.VERIFYING]);
  const cached = [];
  await CatNodeSubscription.prepare(context, address, stage => cached.push(stage));
  assert.deepEqual(cached, [CatNodeSubscriptionStage.CHECKING]);
}));

test('a failed checksum never reports a script download', async () => fixture(async ({ context, state, address }) => {
  const stages = [];
  state.checksumStatus = 403;
  await assert.rejects(CatNodeSubscription.prepare(context, address, stage => stages.push(stage)), /HTTP 403/);
  assert.deepEqual(stages, [CatNodeSubscriptionStage.CHECKING]);
  assert.equal(state.scriptRequests, 0);
}));

test('native network error objects preserve their error code and release the request', async () => fixture(async ({ context, address }) => {
  const original = http.createHttp;
  let destroyed = 0;
  http.createHttp = () => ({
    async request() { throw { code: 2300006, message: 'Could not resolve host' }; },
    destroy() { destroyed++; }
  });
  try {
    await assert.rejects(CatNodeSubscription.prepare(context, address), /错误码 2300006.*Could not resolve host/);
    assert.equal(destroyed, 1);
  } finally { http.createHttp = original; }
}));

test('pooled Harmony Buffer offsets cannot break URL hashing before the first download', async () => fixture(async ({ context, address, state }) => {
  const original = buffer.from;
  // Harmony Buffer.buffer exports its bytes, while byteOffset still describes
  // the original memory pool. This differs from Node's shared backing store.
  buffer.from = (value, encoding) => {
    const bytes = Buffer.from(value, encoding);
    if (typeof value !== 'string') return bytes;
    return {
      length: bytes.length, byteOffset: 8,
      buffer: bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.length),
      toString: encoding => bytes.toString(encoding)
    };
  };
  try {
    const result = await CatNodeSubscription.prepare(context, address);
    const expectedIdentity = createHash('sha256').update(CatNodeSubscriptionCodec.normalizeUrl(address), 'utf8').digest('hex');
    assert.equal(path.basename(result.root), expectedIdentity);
    assert.equal(state.scriptRequests, 1);
    assert.deepEqual(readFileSync(path.join(result.root, 'program', result.file)), state.bytes);
  } finally { buffer.from = original; }
}));
