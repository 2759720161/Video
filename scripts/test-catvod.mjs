// Run actual ArkTS business logic with platform persistence/network boundaries stubbed.
import { registerHooks, stripTypeScriptTypes } from 'node:module';
import { readFileSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { createServer } from 'node:http';

const hypium = `import assert from 'node:assert/strict';
import { describe, it as test } from 'node:test';
export { describe }; export function it(name, filter, body) { test(name, body); }
export function expect(actual) { return {
assertEqual(expected) { assert.strictEqual(actual, expected); },
assertTrue() { assert.strictEqual(actual, true); }, assertFalse() { assert.strictEqual(actual, false); }
}; }`;

registerHooks({
  resolve(specifier, context, nextResolve) {
    if (specifier === '@ohos/hypium') return { url: 'test:catvod-hypium', shortCircuit: true };
    if (specifier === '@kit.NetworkKit') return { url: 'test:catvod-network', shortCircuit: true };
    if (specifier.startsWith('.') && context.parentURL?.startsWith('file:')) {
      const url = new URL(specifier, context.parentURL);
      if (!url.pathname.endsWith('.ets')) url.pathname += '.ets';
      if (existsSync(fileURLToPath(url))) return { url: url.href, shortCircuit: true };
    }
    return nextResolve(specifier, context);
  },
  load(url, context, nextLoad) {
    if (url === 'test:catvod-hypium') return { format: 'module', source: hypium, shortCircuit: true };
    if (url === 'test:catvod-network') return { format: 'module', source: `
      let created = 0, destroyed = 0;
      export const counts = () => ({ created, destroyed });
      export const http = { RequestMethod: { GET: 'GET' }, HttpDataType: { STRING: 0 },
        createHttp() { created++; return {
          async request(url, options) {
            const response = await fetch(url, { method: options.method, headers: options.header });
            return { responseCode: response.status, result: await response.text() };
          }, destroy() { destroyed++; }
        }; }
      };`, shortCircuit: true };
    if (url.endsWith('/store/PlaybackHistoryStore.ets')) return { format: 'module', source:
      'export class PlaybackHistoryStore { async get() { return null; } async getAll() { return []; } }', shortCircuit: true };
    if (url.endsWith('/core/playback/PlaybackHistoryReporter.ets')) return { format: 'module', source:
      'export class PlaybackHistoryReporter { constructor(media) { this.media = media; } }', shortCircuit: true };
    if (url.endsWith('.ets')) return { format: 'module', source:
      stripTypeScriptTypes(readFileSync(new URL(url), 'utf8'), { mode: 'transform' }), shortCircuit: true };
    return nextLoad(url, context);
  }
});
const { default: tests } = await import('../entry/src/test/CatVod.test.ets');
tests();

const { CatVodClient } = await import('../entry/src/main/ets/providers/catvod/CatVodClient.ets');
const { CatVodSourceConfig } = await import('../entry/src/main/ets/providers/catvod/CatVodSourceConfig.ets');
const { counts } = await import('@kit.NetworkKit');

async function withServer(handler, body) {
  const server = createServer(handler);
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  try { await body(`http://127.0.0.1:${server.address().port}/vod?key=fixture&ac=wrong&pg=99`); }
  finally { server.closeAllConnections(); await new Promise(resolve => server.close(resolve)); }
}

test('collection client sends encoded search, pagination and playback request headers', async () => {
  const requests = [];
  await withServer((req, res) => {
    const url = new URL(req.url, 'http://localhost');
    requests.push({ params: url.searchParams, headers: req.headers });
    res.setHeader('Content-Type', 'application/json');
    const item = { vod_id: '7', vod_name: '作品', vod_play_from: 'A', vod_play_url: '第1集$https://media.invalid/1.m3u8' };
    res.end(JSON.stringify({ page: Number(url.searchParams.get('pg') || 1), pagecount: 3,
      class: [{ type_id: 1, type_name: '电影' }], list: [item] }));
  }, async address => {
    const config = new CatVodSourceConfig();
    config.apiUrl = address; config.userAgent = 'CatVodTest'; config.referer = 'https://site.invalid/';
    const client = new CatVodClient(config);
    assert.equal((await client.categories())[0].id, '1');
    assert.equal((await client.page('电影&1', '中文 & 搜索', 2)).page, 2);
    assert.equal((await client.detail('7')).roads[0].episodes[0].url, 'https://media.invalid/1.m3u8');
    assert.equal(requests[1].params.get('wd'), '中文 & 搜索');
    assert.equal(requests[1].params.get('t'), '电影&1');
    assert.equal(requests[1].params.get('pg'), '2');
    assert.equal(requests[1].params.get('key'), 'fixture');
    assert.equal(requests[2].params.get('ids'), '7');
    assert.ok(requests.every(request => request.headers['user-agent'] === 'CatVodTest' && request.headers.referer === config.referer));
  });
  assert.equal(counts().created, counts().destroyed);
});

test('collection client reports upstream rejection and HTML instead of empty success', async () => {
  await withServer((req, res) => {
    const url = new URL(req.url, 'http://localhost');
    if (url.searchParams.get('wd') === 'blocked') { res.statusCode = 403; res.end('Forbidden'); }
    else res.end('<html>challenge</html>');
  }, async address => {
    const config = new CatVodSourceConfig(); config.apiUrl = address;
    const client = new CatVodClient(config);
    await assert.rejects(client.page('', 'blocked', 1), /HTTP 403/);
    await assert.rejects(client.categories(), /无法读取/);
  });
  assert.equal(counts().created, counts().destroyed);
});
