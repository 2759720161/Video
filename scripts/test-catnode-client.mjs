import { registerHooks, stripTypeScriptTypes } from 'node:module';
import { readFileSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';
import { test } from 'node:test';

registerHooks({
  resolve(specifier, context, next) {
    if (specifier.startsWith('@kit.')) return { url: new URL('./fixtures/catnode-kit.mjs', import.meta.url).href, shortCircuit: true };
    if (specifier.startsWith('.') && context.parentURL?.startsWith('file:')) {
      const url = new URL(specifier, context.parentURL);
      if (!url.pathname.endsWith('.ets')) url.pathname += '.ets';
      if (existsSync(fileURLToPath(url))) return { url: url.href, shortCircuit: true };
    }
    return next(specifier, context);
  },
  load(url, context, next) {
    if (url === 'test:catnode-kit') return { format: 'module', source:
      'export const common={}; export const fileIo={}; export const http={}; export const promptAction={};', shortCircuit: true };
    if (url.endsWith('/utils/DetailMaterial.ets')) return { format: 'module', source:
      'export const buildDetailToastOptions = message => ({message});', shortCircuit: true };
    if (url.endsWith('.ets')) return { format: 'module', source:
      stripTypeScriptTypes(readFileSync(new URL(url), 'utf8'), { mode: 'transform' }), shortCircuit: true };
    return next(url, context);
  }
});

const { CatNodeRuntime } = await import('../entry/src/main/ets/providers/catvod/CatNodeRuntime.ets');
const { CatNodeClient } = await import('../entry/src/main/ets/providers/catvod/CatNodeClient.ets');
const { CatVodCodec } = await import('../entry/src/main/ets/providers/catvod/CatVodCodec.ets');
const base = 'http://127.0.0.1:34127';

test('catalog decodes grouped video sources and derives real routes from prefixed config keys', () => {
  const sources = CatNodeRuntime.parseSites(JSON.stringify({ video: { sites: [
    { key: 'nodejs_wexaitiantang', name: '天堂|采集', type: 3, api: '/spider/wexaitiantang/3', ext: '配置' },
    { key: 'nodejs_other', name: '其他', type: 3, api: base + '/spider/other/3' },
    { key: 'duplicate', name: '重复', type: 3, api: '/spider/other/3' },
    { key: 'foreign', name: '外部', type: 3, api: 'https://foreign.invalid/spider/foreign/3' }
  ] }, music: { sites: [{ key: 'nodejs_music', name: '音乐', type: 30, api: '/spider/music/30' }] } }), base);
  assert.deepEqual(sources.map(site => site.key), ['wexaitiantang', 'other']);
  assert.equal(sources[0].ext, '配置');
});

test('opaque play IDs are retained only in full-engine mode', () => {
  const text = JSON.stringify({ list: [{ vod_id: 'one', vod_name: '作品',
    vod_play_from: '云盘', vod_play_url: '第1集$opaque:token' }] });
  assert.equal(CatVodCodec.parse(text).videos[0].roads.length, 0);
  assert.equal(CatVodCodec.parse(text, true).videos[0].roads[0].episodes[0].url, 'opaque:token');
});

async function clientFixture(body) {
  const original = { ensure: CatNodeRuntime.ensure, sites: CatNodeRuntime.sites, request: CatNodeRuntime.request };
  const calls = [];
  let playback = { parse: 0, url: ['原画', 'js2p://_WEB_/spider/test/proxy/session'],
    header: JSON.stringify({ 'User-Agent': 'NodeSourceTest', Referer: 'https://site.invalid/', Cookie: 'session=fixture' }) };
  let session = { baseUrl: () => base };
  CatNodeRuntime.ensure = async () => session;
  CatNodeRuntime.sites = async () => [{ key: 'test', name: '测试', type: 3, ext: { account: 'fixture' } }];
  CatNodeRuntime.request = async (url, value) => {
    calls.push({ url, body: value });
    const route = url.split('/').at(-1);
    if (route === 'init') return '{}';
    if (route === 'home') return JSON.stringify({ class: [{ type_id: 'movie', type_name: '电影' }] });
    if (route === 'play') return JSON.stringify(playback);
    return JSON.stringify({ page: value.page || 1, pagecount: 2,
      list: [{ vod_id: route === 'detail' ? 'another-id' : 'one', vod_name: '作品',
        vod_pic: 'js2p://_WEB_/spider/test/proxy/poster/one',
        vod_play_from: '云盘', vod_play_url: '第1集$opaque:token' }] });
  };
  try {
    await body({ client: new CatNodeClient({}, 'test'), calls, setPlayback: value => { playback = value; },
      restart: () => { session = { baseUrl: () => base }; } });
  } finally { Object.assign(CatNodeRuntime, original); }
}

test('client initializes with source extension, uses default categories and sends opaque IDs to play', async () => {
  await clientFixture(async ({ client, calls }) => {
    const categories = await client.categories();
    assert.equal(categories[0].id, 'movie');
    const page = await client.page('', '', 1);
    assert.equal(page.videos[0].poster, base + '/spider/test/proxy/poster/one');
    assert.equal(calls.find(call => call.url.endsWith('/category')).body.id, 'movie');
    const road = page.videos[0].roads[0];
    const stream = await client.resolve(road, road.episodes[0]);
    assert.equal(stream.url, base + '/spider/test/proxy/session');
    assert.equal(stream.userAgent, 'NodeSourceTest');
    assert.equal(stream.referer, 'https://site.invalid/');
    assert.equal(stream.headers.Cookie, 'session=fixture');
    assert.equal(calls.filter(call => call.url.endsWith('/init')).length, 1);
    assert.deepEqual(calls[0].body.ext, { account: 'fixture' });
    assert.equal(calls.at(-1).body.id, 'opaque:token');
    assert.equal(calls.at(-1).body.flag, '云盘');
  });
});

test('client preserves search pagination and rejects mismatched detail identity', async () => {
  await clientFixture(async ({ client, calls }) => {
    assert.equal((await client.page('', '中文 & 搜索', 2)).page, 2);
    const search = calls.find(call => call.url.endsWith('/search'));
    assert.equal(search.body.wd, '中文 & 搜索'); assert.equal(search.body.page, 2);
    assert.equal(await client.detail('one'), null);
  });
});

test('client initializes its source again after the engine restarts', async () => {
  await clientFixture(async ({ client, calls, restart }) => {
    await client.categories();
    restart();
    await client.page('', '', 1);
    assert.equal(calls.filter(call => call.url.endsWith('/init')).length, 2);
    assert.equal(calls.filter(call => call.url.endsWith('/home')).length, 2);
  });
});

test('shutdown cancels startup and a late failure cannot reject a new startup', async () => {
  const original = { launch: CatNodeRuntime.launch, native: CatNodeRuntime.native };
  const launches = [];
  let stops = 0;
  CatNodeRuntime.native = { stop() { stops++; }, isRunning() { return false; } };
  CatNodeRuntime.launch = () => new Promise((resolve, reject) => launches.push({ resolve, reject }));
  try {
    const first = CatNodeRuntime.ensure({}, 'https://fixture.invalid/index.js.md5');
    await new Promise(resolve => setImmediate(resolve));
    const cancelled = assert.rejects(first, /已停止/);
    await CatNodeRuntime.shutdown();
    await cancelled;
    assert.equal(stops, 1);
    const second = CatNodeRuntime.ensure({}, 'https://fixture.invalid/index.js.md5');
    await new Promise(resolve => setImmediate(resolve));
    launches[0].reject(new Error('obsolete startup failed'));
    await new Promise(resolve => setImmediate(resolve));
    CatNodeRuntime.onEvent(JSON.stringify({ type: 'ready', port: 34127, hostPort: 34128,
      token: 'a'.repeat(48), nodeVersion: 'v24.2.0', wasm: false }));
    assert.equal((await second).port, 34127);
  } finally {
    CatNodeRuntime.fail(new Error('fixture complete'));
    CatNodeRuntime.launch = original.launch;
    CatNodeRuntime.native = original.native;
  }
});

test('new startup waits until the old native worker has actually stopped', async () => {
  const original = { launch: CatNodeRuntime.launch, native: CatNodeRuntime.native, request: CatNodeRuntime.request };
  let running = true;
  let launches = 0;
  const ready = { type: 'ready', port: 34127, hostPort: 34128, token: 'b'.repeat(48) };
  CatNodeRuntime.subscriptionUrl = 'https://fixture.invalid/index.js.md5';
  CatNodeRuntime.onEvent(JSON.stringify(ready));
  CatNodeRuntime.request = async () => '{}';
  CatNodeRuntime.native = { isRunning: () => running,
    stop() { setTimeout(() => { running = false; }, 60); } };
  CatNodeRuntime.launch = async () => {
    assert.equal(running, false);
    launches++;
    CatNodeRuntime.onEvent(JSON.stringify(ready));
  };
  try {
    const stopping = CatNodeRuntime.shutdown();
    const next = CatNodeRuntime.ensure({}, 'https://fixture.invalid/index.js.md5');
    await new Promise(resolve => setImmediate(resolve));
    assert.equal(launches, 0);
    await stopping;
    assert.equal((await next).port, 34127);
    assert.equal(launches, 1);
  } finally {
    CatNodeRuntime.fail(new Error('fixture complete'));
    Object.assign(CatNodeRuntime, original);
  }
});

test('play rejects parser pages with misleading media extensions in their query', async () => {
  await clientFixture(async ({ client, setPlayback }) => {
    const road = { name: '线路' }; const episode = { url: 'opaque' };
    setPlayback({ parse: 1, url: 'https://parser.invalid/?url=https://cdn.invalid/a.m3u8' });
    await assert.rejects(client.resolve(road, episode), /网页解析/);
    setPlayback({ parse: 1, url: 'https://cdn.invalid/a.m3u8?token=one' });
    assert.equal((await client.resolve(road, episode)).url, 'https://cdn.invalid/a.m3u8?token=one');
  });
});

test('play rejects header injection instead of passing it to the native player', async () => {
  await clientFixture(async ({ client, setPlayback }) => {
    setPlayback({ parse: 0, url: 'https://cdn.invalid/a.m3u8', header: { Cookie: 'one\r\nInjected: yes' } });
    await assert.rejects(client.resolve({ name: '线路' }, { url: 'opaque' }), /无效请求头/);
  });
});

test('switching subscription URLs restarts the worker while the same URL reuses it', async () => {
  await CatNodeRuntime.shutdown();
  const original = { launch: CatNodeRuntime.launch, native: CatNodeRuntime.native, request: CatNodeRuntime.request };
  const urls = []; let running = false; let stops = 0;
  CatNodeRuntime.native = { isRunning: () => running, stop() { stops++; running = false; } };
  CatNodeRuntime.request = async () => '{}';
  CatNodeRuntime.launch = async (_context, _generation, address) => {
    assert.equal(running, false); running = true; urls.push(address);
    CatNodeRuntime.onEvent(JSON.stringify({ type: 'ready', port: 34000 + urls.length,
      hostPort: 35000 + urls.length, token: 'c'.repeat(48) }));
  };
  try {
    const a = 'https://one.invalid/index.js.md5'; const b = 'https://two.invalid/index.js.md5';
    const first = await CatNodeRuntime.ensure({}, a);
    assert.equal(await CatNodeRuntime.ensure({}, a), first);
    assert.notEqual(await CatNodeRuntime.ensure({}, b), first);
    assert.notEqual(await CatNodeRuntime.ensure({}, a), first);
    assert.deepEqual(urls, [a, b, a]); assert.equal(stops, 2);
  } finally { await CatNodeRuntime.shutdown(); Object.assign(CatNodeRuntime, original); }
});

test('same video IDs from different spiders remain distinct and history routes to its own spider', async () => {
  const original = { ensure: CatNodeRuntime.ensure, sites: CatNodeRuntime.sites, request: CatNodeRuntime.request };
  const calls = []; const subscription = 'https://fixture.invalid/index.js.md5';
  CatNodeRuntime.ensure = async () => ({ baseUrl: () => base });
  CatNodeRuntime.sites = async () => [{ key: 'a', name: 'A' }, { key: 'b', name: 'B' }];
  CatNodeRuntime.request = async (address, body) => {
    const match = address.match(/\/spider\/([^/]+)\/([^/]+)$/); const key = decodeURIComponent(match[1]);
    calls.push({ key, route: match[2], body });
    if (match[2] === 'init') return '{}';
    if (match[2] === 'play') return JSON.stringify({ url: `https://cdn.invalid/${key}.m3u8`, parse: 0 });
    return JSON.stringify({ class: [{ type_id: 'movie', type_name: '电影' }], page: 1, pagecount: 1,
      list: [{ vod_id: 'same', vod_name: key, vod_play_from: 'line', vod_play_url: '第1集$opaque' }] });
  };
  try {
    const a = new CatNodeClient({}, 'a', subscription); const b = new CatNodeClient({}, 'b', subscription);
    const one = (await a.page('', '', 1)).videos[0]; const two = (await b.page('', '', 1)).videos[0];
    assert.notEqual(one.id, two.id);
    const detail = await a.detail(two.id); assert.equal(detail.name, 'b');
    assert.deepEqual(calls.findLast(call => call.route === 'detail').body.id, ['same']);
    assert.equal((await a.resolve(detail.roads[0], detail.roads[0].episodes[0])).url, 'https://cdn.invalid/b.m3u8');
    const legacy = await new CatNodeClient({}, 'b', subscription, 'a').detail('same');
    assert.equal(legacy.name, 'a'); assert.equal(legacy.id, 'same');
  } finally { Object.assign(CatNodeRuntime, original); }
});
