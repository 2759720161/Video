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
const { CatNodeClient, CatNodeSearchUnavailableError, CatNodeRecommendationError, CatNodeEmptyDetailError } = await import('../entry/src/main/ets/providers/catvod/CatNodeClient.ets');
const { CatVodCodec } = await import('../entry/src/main/ets/providers/catvod/CatVodCodec.ets');
const { CatPlaybackPreparationCache } = await import('../entry/src/main/ets/providers/catvod/CatPlaybackPreparationCache.ets');
const { CatNodeRequestControl } = await import('../entry/src/main/ets/providers/catvod/CatNodeRequestControl.ets');
const { http } = await import('./fixtures/catnode-kit.mjs');
const base = 'http://127.0.0.1:34127';

test('runtime failure invalidates prepared metadata and preferred lines before another launch', async () => {
  CatPlaybackPreparationCache.clear(); let reads = 0; const scope = {};
  const load = async () => { reads++; return { id: 'one', name: '作品', roads: [] }; };
  await CatPlaybackPreparationCache.detail(scope, 'runtime-work', 'one', load);
  CatPlaybackPreparationCache.rememberVariant('runtime-episode', 'road');
  CatNodeRuntime.fail(new Error('fixture worker stopped'));
  await CatPlaybackPreparationCache.detail(scope, 'runtime-work', 'one', load);
  assert.equal(reads, 2); assert.equal(CatPlaybackPreparationCache.preferredVariant('runtime-episode'), '');
  CatPlaybackPreparationCache.clear();
});

test('catalog decodes grouped video sources and derives real routes from prefixed config keys', () => {
  const sources = CatNodeRuntime.parseSites(JSON.stringify({ video: { sites: [
    { key: 'nodejs_wexaitiantang', name: '天堂|采集', type: 3, api: '/spider/wexaitiantang/3', ext: '配置' },
    { key: 'nodejs_other', name: '其他', type: 3, api: base + '/spider/other/3', searchable: 0 },
    { key: 'nodejs_off', name: '关闭搜索', type: 3, api: '/spider/off/3', searchable: false },
    { key: 'nodejs_offstring', name: '字符串开关', type: 3, api: '/spider/offstring/3', searchable: '0' },
    { key: 'nodejs_disabled', name: '配置关闭', type: 3, api: '/spider/disabled/3', enable: false },
    { key: 'nodejs_disabled0', name: '数值关闭', type: 3, api: '/spider/disabled0/3', enable: 0 },
    { key: 'nodejs_disabledstring', name: '字符串关闭', type: 3, api: '/spider/disabledstring/3', enable: 'false' },
    { key: 'duplicate', name: '重复', type: 3, api: '/spider/other/3' },
    { key: 'foreign', name: '外部', type: 3, api: 'https://foreign.invalid/spider/foreign/3' }
  ] }, music: { sites: [{ key: 'nodejs_music', name: '音乐', type: 30, api: '/spider/music/30' }] } }), base);
  assert.deepEqual(sources.map(site => site.key), ['wexaitiantang', 'other', 'off', 'offstring']);
  assert.equal(sources[0].ext, '配置');
  assert.equal(sources[0].api, '/spider/wexaitiantang/3');
  assert.equal(sources[1].api, '/spider/other/3');
  assert.deepEqual(sources.map(site => site.searchable), [true, false, false, false]);
});

async function protocolFixture(variant, body) {
  const original = { ensure: CatNodeRuntime.ensure, sites: CatNodeRuntime.sites, create: http.createHttp };
  const calls = [];
  let session = { baseUrl: () => base };
  let activeVariant = variant;
  let initFailure = null;
  let destroyed = 0;
  const sites = CatNodeRuntime.parseSites(JSON.stringify({ video: { sites: [
    { key: 'nodejs_tgchannel', name: '「盘」TG搜', type: 3, api: '/spider/tgchannel/3', ext: { fixture: 'extension' } }
  ] } }), base);
  CatNodeRuntime.ensure = async () => session;
  CatNodeRuntime.sites = async () => sites;
  http.createHttp = () => ({
    async request(address, options) {
      const path = new URL(address).pathname;
      const params = JSON.parse(options.extraData);
      calls.push({ path, params });
      assert.equal(options.method, 'POST');
      if (initFailure && path.endsWith('/init')) {
        if (initFailure instanceof Error) throw initFailure;
        return { responseCode: initFailure.status, result: JSON.stringify(initFailure.body) };
      }
      const prefix = '/spider/tgchannel' + (activeVariant === 'typed' ? '/3/' : '/');
      if (!path.startsWith(prefix) || path.substring(prefix.length).includes('/')) {
        return { responseCode: 404, result: JSON.stringify({ message: 'Route POST:' + path + ' not found',
          ...(activeVariant === 'untyped-coded' ? { code: 'FST_ERR_NOT_FOUND' } : {}) }) };
      }
      const route = path.substring(prefix.length);
      let result = {};
      if (route === 'home') result = { class: [{ type_id: 'channel', type_name: '频道' }] };
      if (['category', 'search', 'detail'].includes(route)) result = { page: 1, pagecount: 1, list: [
        { vod_id: 'video', vod_name: '作品', vod_play_from: '线路', vod_play_url: '第1集$opaque' }
      ] };
      if (route === 'play') result = { parse: 0, url: 'https://example.invalid/video.m3u8' };
      return { responseCode: 200, result: JSON.stringify(result) };
    },
    destroy() { destroyed++; }
  });
  try {
    await body({ client: new CatNodeClient({}, 'tgchannel', 'https://fixture.invalid/index.js.md5'), calls,
      failInit: value => { initFailure = value; },
      restart: next => { activeVariant = next; session = { baseUrl: () => base }; },
      assertReleased: () => assert.equal(destroyed, calls.length) });
  } finally { CatNodeRuntime.ensure = original.ensure; CatNodeRuntime.sites = original.sites; http.createHttp = original.create; }
}

for (const variant of ['typed', 'untyped', 'untyped-coded']) {
  test(`${variant} spider uses one negotiated prefix for home, category, search, detail and playback`, async () => {
    await protocolFixture(variant, async ({ client, calls, assertReleased }) => {
      assert.equal((await client.categories())[0].name, '频道');
      const video = (await client.page('', '', 1)).videos[0];
      assert.equal(video.id, 'catnode:tgchannel:video');
      assert.equal((await client.page('', 'keyword', 1)).videos[0].id, video.id);
      const detail = await client.detail(video.id);
      assert.equal(detail.id, video.id);
      assert.equal((await client.resolve(detail.roads[0], detail.roads[0].episodes[0])).url, 'https://example.invalid/video.m3u8');
      assert.deepEqual(calls[0].params, { ext: { fixture: 'extension' } });
      const prefix = '/spider/tgchannel' + (variant === 'typed' ? '/3/' : '/');
      const actual = calls.slice(variant === 'typed' ? 0 : 1);
      assert.deepEqual(actual.map(call => call.path), ['init', 'home', 'category', 'search', 'detail', 'play'].map(route => prefix + route));
      if (variant !== 'typed') assert.equal(calls[0].path, '/spider/tgchannel/3/init');
      assertReleased();
    });
  });
}

test('a restarted engine negotiates routes again instead of retaining the old prefix', async () => {
  await protocolFixture('untyped', async ({ client, calls, restart }) => {
    await client.categories();
    restart('typed');
    calls.length = 0;
    await client.categories();
    assert.deepEqual(calls.map(call => call.path), ['/spider/tgchannel/3/init', '/spider/tgchannel/3/home']);
    // The cleared call log excludes the first engine's three released requests.
  });
});

test('independent clients reuse a negotiated route; configuration invalidation also resets an existing client', async () => {
  CatPlaybackPreparationCache.clear();
  await protocolFixture('untyped', async ({ client, calls, assertReleased }) => {
    await client.categories();
    const next = new CatNodeClient({}, 'tgchannel', 'https://fixture.invalid/index.js.md5');
    await next.categories();
    assert.deepEqual(calls.map(call => call.path), ['/spider/tgchannel/3/init', '/spider/tgchannel/init',
      '/spider/tgchannel/home', '/spider/tgchannel/home']);
    CatPlaybackPreparationCache.clear();
    await next.categories();
    assert.deepEqual(calls.slice(-3).map(call => call.path), ['/spider/tgchannel/3/init',
      '/spider/tgchannel/init', '/spider/tgchannel/home']);
    assertReleased();
  });
  CatPlaybackPreparationCache.clear();
});

test('a failed shared initialization is not retained by either client', async () => {
  await protocolFixture('typed', async ({ client, calls, failInit }) => {
    failInit(new Error('connection reset'));
    await assert.rejects(client.categories());
    failInit(null);
    await new CatNodeClient({}, 'tgchannel', 'https://fixture.invalid/index.js.md5').categories();
    await client.categories();
    assert.equal(calls.filter(call => call.path.endsWith('/init')).length, 2);
  });
});

test('cancellable search init remains independent of shared playback initialization', async () => {
  await protocolFixture('typed', async ({ client, calls }) => {
    await client.categories();
    const control = new CatNodeRequestControl();
    const search = new CatNodeClient({}, 'tgchannel', 'https://fixture.invalid/index.js.md5', '', control);
    await search.page('', 'query', 1);
    assert.equal(calls.filter(call => call.path.endsWith('/init')).length, 2);
    await new CatNodeClient({}, 'tgchannel', 'https://fixture.invalid/index.js.md5').categories();
    assert.equal(calls.filter(call => call.path.endsWith('/init')).length, 2);
  });
});

test('route negotiation never hides upstream 404, init failures, transport errors or a different missing route', async () => {
  const missing = 'Route POST:/spider/tgchannel/3/init not found';
  for (const failure of [
    { status: 404, body: { message: 'upstream content not found' } },
    { status: 404, body: { message: 'Route POST:/spider/other/3/init not found' } },
    { status: 404, body: { message: missing, code: 'UPSTREAM_ERROR' } },
    { status: 404, body: { message: 'Route GET:/spider/tgchannel/3/init not found' } },
    { status: 500, body: { message: missing } },
    { status: 401, body: { message: 'login required' } },
    new Error('connection reset')
  ]) {
    await protocolFixture('typed', async ({ client, calls, failInit, assertReleased }) => {
      failInit(failure);
      await assert.rejects(client.categories());
      assert.deepEqual(calls.map(call => call.path), ['/spider/tgchannel/3/init']);
      assertReleased();
    });
  }
});

test('search distinguishes the real Douban empty-object stub from a valid empty result', async () => {
  const original = { ensure: CatNodeRuntime.ensure, sites: CatNodeRuntime.sites, request: CatNodeRuntime.request };
  let response = '{}';
  CatNodeRuntime.ensure = async () => ({ baseUrl: () => base });
  CatNodeRuntime.sites = async () => [{ key: 'douban', name: '豆瓣|首页', ext: '' }];
  CatNodeRuntime.request = async address => address.endsWith('/init') ? '{}' : response;
  try {
    const client = new CatNodeClient({}, 'douban');
    await assert.rejects(client.page('', '三体', 1), CatNodeSearchUnavailableError);
    response = JSON.stringify('{}');
    await assert.rejects(client.page('', '三体', 1), CatNodeSearchUnavailableError);
    response = JSON.stringify({ page: 1, pagecount: 1, list: [] });
    assert.equal((await client.page('', '三体', 1)).videos.length, 0);
    response = JSON.stringify({ message: 'upstream failed' });
    await assert.rejects(client.page('', '三体', 1), error => !(error instanceof CatNodeSearchUnavailableError));
  } finally { Object.assign(CatNodeRuntime, original); }
});

test('index capability is parsed from metadata rather than directory names and marks browse items for search', async () => {
  const original = { ensure: CatNodeRuntime.ensure, sites: CatNodeRuntime.sites, request: CatNodeRuntime.request };
  const sites = CatNodeRuntime.parseSites(JSON.stringify({ video: { sites: [
    { name: '任意推荐目录', api: '/spider/index/3', type: 3, indexs: 1 },
    { name: '豆瓣', api: '/spider/playable/3', type: 3, indexs: 0 }
  ] } }), base);
  assert.equal(sites[0].indexOnly, true); assert.equal(sites[1].indexOnly, false);
  const calls = [];
  CatNodeRuntime.ensure = async () => ({ baseUrl: () => base });
  CatNodeRuntime.sites = async () => sites;
  CatNodeRuntime.request = async address => {
    const route = address.split('/').at(-1); calls.push(route);
    if (route === 'init') return '{}';
    return JSON.stringify({ class: [{ type_id: 't1', type_name: '热播' }], list: [{ vod_id: 'id', vod_name: '影片' }] });
  };
  try {
    const client = new CatNodeClient({}, 'index', 'https://fixture.invalid/index.js.md5');
    const result = await client.page('', '', 1);
    assert.equal(result.videos[0].searchOnly, true);
    await assert.rejects(client.detail(result.videos[0].id), CatNodeRecommendationError);
    await assert.rejects(client.page('', '影片', 1), CatNodeSearchUnavailableError);
    assert.ok(!calls.includes('detail') && !calls.includes('search'));
  } finally { Object.assign(CatNodeRuntime, original); }
});

test('unmarked empty detail is distinguishable without treating malformed or failed responses as recommendations', async () => {
  await clientFixture(async ({ client }) => {
    const request = CatNodeRuntime.request; let response = '{}';
    CatNodeRuntime.request = async (address, body) => address.endsWith('/detail') ? response : request(address, body);
    for (const value of ['{}', JSON.stringify('{}')]) {
      response = value; await assert.rejects(client.detail('one'), CatNodeEmptyDetailError);
    }
    response = '{"list":[]}'; assert.equal(await client.detail('one'), null);
    for (const value of ['bad-json', '{"message":"upstream failed"}', 'null']) {
      response = value;
      await assert.rejects(client.detail('one'), error => !(error instanceof CatNodeEmptyDetailError) && !(error instanceof CatNodeRecommendationError));
    }
    CatNodeRuntime.request = async address => {
      if (address.endsWith('/detail')) throw new Error('HTTP 500'); return '{}';
    };
    await assert.rejects(client.detail('one'), /HTTP 500/);
  });
});

test('cancelling a directory destroys only its HTTP request once and rejects its pending response', async () => {
  const create = http.createHttp; let created = 0, destroyed = 0, rejectRequest;
  http.createHttp = () => {
    created++;
    return { request: () => new Promise((_resolve, reject) => { rejectRequest = reject; }),
      destroy() { destroyed++; rejectRequest(new Error('request cancelled')); } };
  };
  try {
    const control = new CatNodeRequestControl();
    const pending = CatNodeRuntime.request(base + '/spider/a/search', { wd: 'word' }, '', control);
    const rejected = assert.rejects(pending, /cancelled/); control.cancel(); await rejected;
    assert.equal(created, 1); assert.equal(destroyed, 1); control.cancel(); assert.equal(destroyed, 1);
    await assert.rejects(CatNodeRuntime.request(base + '/spider/a/search', {}, '', control), /停止/);
    assert.equal(created, 1);
  } finally { http.createHttp = create; }
});

test('finished HTTP requests unregister cancellation and cancellation cannot accept a late successful response', async () => {
  const create = http.createHttp; let destroyed = 0, resolveRequest;
  http.createHttp = () => ({ request: () => Promise.resolve({ responseCode: 200, result: '{}' }), destroy() { destroyed++; } });
  try {
    const control = new CatNodeRequestControl();
    assert.equal(await CatNodeRuntime.request(base + '/spider/a/search', {}, '', control), '{}');
    control.cancel(); assert.equal(destroyed, 1);
    http.createHttp = () => ({ request: () => new Promise(resolve => { resolveRequest = resolve; }), destroy() { destroyed++; } });
    const cancelled = new CatNodeRequestControl();
    const pending = CatNodeRuntime.request(base + '/spider/a/search', {}, '', cancelled);
    const rejected = assert.rejects(pending, /停止/); cancelled.cancel();
    resolveRequest({ responseCode: 200, result: '{}' }); await rejected; assert.equal(destroyed, 2);
  } finally { http.createHttp = create; }
});

test('HTTP errors retain the upstream code and message, release the request and redact remote secrets', async () => {
  const create = http.createHttp; let destroyed = 0;
  http.createHttp = () => ({ request: async () => ({ responseCode: 500, result: JSON.stringify({
    statusCode: 500, code: 'ECONNRESET', error: 'Internal Server Error',
    message: 'Remote reset https://example.invalid/api?token=secret\nAuthorization: Bearer confidential'
  }) }), destroy() { destroyed++; } });
  try {
    await assert.rejects(CatNodeRuntime.request(base + '/spider/a/home', { filter: true }), error => {
      assert.match(error.message, /HTTP 500，ECONNRESET/);
      assert.match(error.message, /Remote reset/);
      assert.doesNotMatch(error.message, /secret|confidential|example\.invalid|Bearer|\n/);
      return true;
    });
    assert.equal(destroyed, 1);
  } finally { http.createHttp = create; }
});

test('HTTP error extraction tolerates malformed bodies and bounds remote error text', () => {
  for (const body of ['', '<html>bad gateway</html>', 'null', '[]', '"upstream failed"']) {
    assert.equal(CatNodeRuntime.responseError(502, body).message, '来源请求失败（HTTP 502）');
  }
  const error = CatNodeRuntime.responseError(500, JSON.stringify({ message: 'x'.repeat(2000), code: '<invalid>' }));
  assert.equal(error.message, '来源请求失败（HTTP 500）：' + 'x'.repeat(240));
});

test('client cancellation during initialization prevents a subsequent spider search request', async () => {
  const original = { ensure: CatNodeRuntime.ensure, sites: CatNodeRuntime.sites, request: CatNodeRuntime.request };
  let resolveEnsure, requests = 0;
  CatNodeRuntime.ensure = () => new Promise(resolve => { resolveEnsure = resolve; });
  CatNodeRuntime.sites = async () => [{ key: 'a', name: 'A', ext: '' }];
  CatNodeRuntime.request = async () => { requests++; return '{}'; };
  try {
    const control = new CatNodeRequestControl(); const client = new CatNodeClient({}, 'a', '', '', control);
    const pending = client.page('', 'word', 1); const rejected = assert.rejects(pending, /停止/);
    control.cancel(); resolveEnsure({ baseUrl: () => base }); await rejected;
    assert.equal(requests, 0);
  } finally { Object.assign(CatNodeRuntime, original); }
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

test('single detail missing an ID inherits the requested opaque identity only at the detail boundary', async () => {
  await clientFixture(async ({ client, calls }) => {
    const request = CatNodeRuntime.request;
    let response;
    CatNodeRuntime.request = async (address, body) => address.endsWith('/detail') ? JSON.stringify(response) : request(address, body);
    for (const mode of ['absent', 'null', 'empty', 'spaces']) {
      const item = { vod_name: '单条详情', vod_play_from: '云盘', vod_play_url: '正片$opaque:token' };
      if (mode !== 'absent') item.vod_id = { null: null, empty: '', spaces: '  ' }[mode];
      response = { list: [item] };
      const video = await client.detail('folder/id:中文?x=1');
      assert.equal(video.id, 'folder/id:中文?x=1'); assert.equal(video.name, '单条详情');
      assert.equal(video.roads[0].episodes[0].url, 'opaque:token');
      assert.equal(Object.hasOwn(item, 'vod_id'), mode !== 'absent');
    }
    assert.equal(calls.filter(call => call.url.endsWith('/init')).length, 1);
    assert.equal(CatVodCodec.parse(JSON.stringify({ list: [{ vod_name: '列表条目' }] }), true).videos.length, 0);
  });
});

test('detail identity fallback preserves numeric IDs and rejects explicit mismatches and invalid ID types', async () => {
  await clientFixture(async ({ client }) => {
    const request = CatNodeRuntime.request; let id;
    CatNodeRuntime.request = async (address, body) => address.endsWith('/detail') ?
      JSON.stringify({ list: [{ vod_id: id, vod_name: '作品' }] }) : request(address, body);
    for (const value of ['other', 2, false, [], {}]) {
      id = value; assert.equal(await client.detail('one'), null);
    }
    id = 0; assert.equal((await client.detail('0')).id, '0');
  });
});

test('missing ID in multiple, malformed, untitled or empty details cannot create a requested work', async () => {
  await clientFixture(async ({ client }) => {
    const request = CatNodeRuntime.request; let response;
    CatNodeRuntime.request = async (address, body) => address.endsWith('/detail') ? JSON.stringify(response) : request(address, body);
    for (const list of [[], [null], [[]], ['text'], [42], [{ vod_name: '' }], [{}],
      [{ vod_name: '甲' }, { vod_name: '乙' }], [{ vod_name: '甲' }, { vod_id: 'other', vod_name: '乙' }]]) {
      response = { list }; assert.equal(await client.detail('one'), null);
    }
    response = { list: [{ vod_name: '无请求 ID' }] }; assert.equal(await client.detail(''), null);
    response = { code: 0, msg: '来源拒绝', list: [{ vod_name: '失败' }] };
    await assert.rejects(client.detail('one'), /来源拒绝/);
  });
});

test('subscription detail fallback retains the actual directory namespace, request ID and playback routing', async () => {
  await clientFixture(async () => {
    const calls = []; const request = CatNodeRuntime.request;
    CatNodeRuntime.sites = async () => ['a', 'b'].map(key => ({ key, name: key, type: 3, ext: '' }));
    CatNodeRuntime.request = async (address, body) => {
      const route = address.split('/').at(-1); calls.push({ address, route, body });
      if (route === 'detail') return JSON.stringify(JSON.stringify({ list: [{ vod_name: '跨目录详情',
        vod_play_from: '网盘', vod_play_url: '正片$opaque' }] }));
      return request(address, body);
    };
    const client = new CatNodeClient({}, 'a', 'https://fixture.invalid/index.js.md5');
    const rawId = '目录/中文:1?key=value';
    const id = 'catnode:b:' + encodeURIComponent(rawId);
    const video = await client.detail(id);
    assert.equal(video.id, id); assert.equal(video.roads[0].spiderKey, 'b');
    assert.deepEqual(calls.find(call => call.route === 'detail').body.id, [rawId]);
    await client.resolve(video.roads[0], video.roads[0].episodes[0]);
    assert.ok(calls.find(call => call.route === 'play').address.includes('/spider/b/play'));
    const historical = await new CatNodeClient({}, 'a', 'https://fixture.invalid/index.js.md5', 'b').detail(rawId);
    assert.equal(historical.id, rawId); assert.equal(historical.roads[0].spiderKey, 'b');
  });
});

test('Douban category can read filters.u and keep its own default instead of failing before requesting works', async () => {
  await clientFixture(async ({ client, calls }) => {
    const request = CatNodeRuntime.request;
    CatNodeRuntime.request = async (address, body) => {
      if (address.endsWith('/category')) {
        // LeeCatPaw reads body.filters.u directly, then supplies this default.
        const route = body.filters.u || 'movie/hot_gaia';
        const result = JSON.parse(await request(address, body));
        result.list[0].vod_name = route;
        return JSON.stringify(result);
      }
      return request(address, body);
    };
    for (const page of [1, 2]) {
      const result = await client.page('t1', '', page);
      assert.equal(result.videos[0].name, 'movie/hot_gaia');
      assert.equal(result.page, page);
    }
    for (const call of calls.filter(call => call.url.endsWith('/category'))) {
      assert.deepEqual(call.body.filters, {});
      assert.deepEqual(call.body.extend, {});
      assert.equal(call.body.filter, true);
      assert.equal(call.body.id, 't1');
    }
  });
});

test('category adapters reading extend continue to work when filters is also provided', async () => {
  await clientFixture(async ({ client }) => {
    const request = CatNodeRuntime.request;
    CatNodeRuntime.request = async (address, body) => {
      if (address.endsWith('/category')) {
        const sort = body.extend.sort || 'adapter-default';
        const result = JSON.parse(await request(address, body));
        result.list[0].vod_name = sort;
        return JSON.stringify(result);
      }
      return request(address, body);
    };
    assert.equal((await client.page('movie', '', 1)).videos[0].name, 'adapter-default');
  });
});

test('artwork normalization applies across catalog identities and preserves existing source image proxies', async () => {
  await clientFixture(async ({ client }) => {
    const request = CatNodeRuntime.request;
    let poster = 'https://img3.doubanio.com/view/photo/s_ratio_poster/public/a.webp';
    CatNodeRuntime.request = async (address, body) => {
      const result = JSON.parse(await request(address, body));
      if (result.list) result.list[0].vod_pic = poster;
      return JSON.stringify(result);
    };
    const protectedImage = (await client.page('movie', '', 1)).videos[0].poster;
    assert.equal(new URL(protectedImage).origin, base);
    assert.equal(new URL(protectedImage).searchParams.get('url'), poster);
    poster = 'js2p://_WEB_/source-image?key=opaque';
    assert.equal((await client.page('movie', '', 1)).videos[0].poster, base + '/source-image?key=opaque');
    poster = '//images.example/poster.webp';
    assert.equal((await client.page('movie', '', 1)).videos[0].poster, 'https://images.example/poster.webp');
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
