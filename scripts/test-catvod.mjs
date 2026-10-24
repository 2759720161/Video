// Run actual ArkTS business logic with platform persistence/network boundaries stubbed.
import { registerHooks, stripTypeScriptTypes } from 'node:module';
import { readFileSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';
import { test, beforeEach } from 'node:test';
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
    if (specifier === '@kit.PerformanceAnalysisKit') return { url: 'test:catvod-performance', shortCircuit: true };
    if (specifier.startsWith('.') && context.parentURL?.startsWith('file:')) {
      const url = new URL(specifier, context.parentURL);
      if (!url.pathname.endsWith('.ets')) url.pathname += '.ets';
      if (existsSync(fileURLToPath(url))) return { url: url.href, shortCircuit: true };
    }
    return nextResolve(specifier, context);
  },
  load(url, context, nextLoad) {
    if (url === 'test:catvod-hypium') return { format: 'module', source: hypium, shortCircuit: true };
    if (url === 'test:catvod-performance') return { format: 'module', source:
      'export const hilog = { info() {}, warn() {}, error() {}, debug() {} };', shortCircuit: true };
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
const { CatVodProvider } = await import('../entry/src/main/ets/providers/catvod/CatVodProvider.ets');
const { CatVodCodec } = await import('../entry/src/main/ets/providers/catvod/CatVodCodec.ets');
const { PlaybackQueueItem } = await import('../entry/src/main/ets/core/playback/PlaybackQueueItem.ets');
const { CatPlaybackPreparationCache } = await import('../entry/src/main/ets/providers/catvod/CatPlaybackPreparationCache.ets');
class CachedProvider extends CatVodProvider {
  usesPreparationCache() { return true; }
  preparationScope() { return Promise.resolve(this.scopeEpoch ?? CatPlaybackPreparationCache.defaultScope); }
}
beforeEach(() => CatPlaybackPreparationCache.clear());

test('playback session supplies complete episode groups even when another road uses different episode names', async () => {
  const video = CatVodCodec.parse(JSON.stringify({ list: [{ vod_id: 'work', vod_name: '作品',
    vod_play_from: '夸克$$$UC', vod_play_url: '第1集$https://media.invalid/a1.mp4#第2集$https://media.invalid/a2.mp4$$$原画文件$https://media.invalid/b.mp4'
  }] })).videos[0];
  const provider = new CatVodProvider({ id: 'cat' }, { detail: async () => video }, new CatVodSourceConfig());
  const first = video.roads[0];
  const request = Object.assign(new PlaybackQueueItem(), { sourceId: 'cat',
    mediaId: CatVodCodec.episodeId(video.id, first.episodes[0]), variantId: first.id });
  const session = await provider.resolvePlayback(request);
  assert.deepEqual(session.episodeGroups.map(group => [group.name, group.items.length]), [['夸克', 2], ['UC', 1]]);
  assert.equal(request.variants.length, 1, 'current-episode variants cannot represent the differently named road');
  const other = session.episodeGroups[1].items[0];
  assert.equal(other.subtitle, '原画文件'); assert.equal(other.sourceId, 'cat'); assert.equal(other.variantId, video.roads[1].id);
  const switched = await provider.resolvePlayback(other);
  assert.equal(switched.stream.url, 'https://media.invalid/b.mp4'); assert.equal(switched.media.mediaId, other.mediaId);
  assert.equal(switched.episodeGroups.length, 2);
});

test('history preparation shares scoped details across provider instances while explicit refresh reads a new snapshot', async () => {
  let reads = 0; let revision = 0;
  const client = { async detail(id) {
    reads++;
    return CatVodCodec.parse(JSON.stringify({ list: [{ vod_id: id, vod_name: '作品', vod_play_from: 'A',
      vod_play_url: '第1集$https://media.invalid/' + id + '.m3u8?r=' + revision }] })).videos[0];
  } };
  const provider = new CachedProvider({ id: 'cat' }, client, new CatVodSourceConfig());
  const id = 'catvod|a|%E7%AC%AC1%E9%9B%86|0';
  const restored = await provider.getItem(id);
  const queue = Object.assign(new PlaybackQueueItem(), { sourceId: 'cat', mediaId: restored.id,
    variantId: restored.variantId, positionMs: 17000 });
  revision++; await provider.getDetail('a', true);
  const expired = await provider.resolvePlayback(queue);
  assert.equal(reads, 2); assert.match(expired.stream.url, /a\.m3u8\?r=1$/); assert.equal(expired.startPositionMs, 17000);
  await provider.getItem('catvod|b|%E7%AC%AC1%E9%9B%86|0');
  revision++; const other = await provider.resolvePlayback(queue);
  assert.equal(reads, 3); assert.match(other.stream.url, /a\.m3u8\?r=1$/);
  const again = new CachedProvider({ id: 'cat' }, client, new CatVodSourceConfig());
  const repeat = await again.resolvePlayback(queue);
  assert.equal(reads, 3); assert.match(repeat.stream.url, /a\.m3u8\?r=1$/);
});

function cachedFixture() {
  let reads = 0;
  const state = { revision: 0, removeB: false, plays: 0, mode: 'ok' };
  const client = { async detail(id) {
    reads++;
    return CatVodCodec.parse(JSON.stringify({ list: [{ vod_id: id, vod_name: '作品',
      vod_play_from: state.removeB ? 'A' : 'A$$$B',
      vod_play_url: '正片$https://media.invalid/a-' + state.revision + '.mp4' +
        (state.removeB ? '' : '$$$正片$https://media.invalid/b-' + state.revision + '.mp4') }] })).videos[0];
  } };
  const source = { id: 'cached', providerType: 'catnode', configJson: 'configuration-a', updatedAt: 1 };
  const provider = new CachedProvider(source, client, new CatVodSourceConfig());
  provider.resolveEpisode = async (_road, episode) => {
    state.plays++;
    if (state.mode === 'stale' && episode.url.endsWith('-0.mp4')) throw new Error('HTTP 410 file expired');
    if (state.mode === 'server') throw new Error('HTTP 500');
    if (state.mode === 'expired') throw new Error('HTTP 410');
    return { url: episode.url + '?fresh=' + state.plays };
  };
  return { provider, source, client, state, reads: () => reads,
    id: 'catvod|work|%E6%AD%A3%E7%89%87|0' };
}

test('large detail metadata survives the history item-to-resolve chain and another provider instance', async () => {
  const f = cachedFixture(); let reads = 0;
  const original = f.client.detail;
  f.client.detail = async id => {
    reads++; const detail = await original(id);
    detail.overview = '长简介'.repeat(110000);
    assert.ok(JSON.stringify(detail).length > 256 * 1024);
    return detail;
  };
  const restored = await f.provider.getItem(f.id);
  const request = Object.assign(new PlaybackQueueItem(), { sourceId: f.source.id, mediaId: f.id,
    variantId: restored.variantId, positionMs: 642082 });
  const session = await f.provider.resolvePlayback(request);
  const next = new CachedProvider(f.source, f.client, new CatVodSourceConfig());
  await next.getItem(f.id);
  assert.equal(reads, 1); assert.equal(session.startPositionMs, 642082);
  assert.equal(f.state.plays, 1); assert.equal(session.episodeGroups.length, 2);
});

test('warm resume reuses detail across opens but parses a fresh stream and remembers the selected eligible line', async () => {
  const f = cachedFixture(); const detail = await f.provider.getDetail('work');
  const request = Object.assign(new PlaybackQueueItem(), { sourceId: f.source.id, mediaId: f.id,
    variantId: detail.roads[1].id, positionMs: 17000 });
  const first = await f.provider.resolvePlayback(request);
  const again = new CachedProvider(f.source, f.client, new CatVodSourceConfig());
  again.resolveEpisode = f.provider.resolveEpisode;
  const restored = await again.getItem(f.id); assert.equal(restored.variantId, detail.roads[1].id);
  const second = await again.resolvePlayback(Object.assign(new PlaybackQueueItem(), { sourceId: f.source.id,
    mediaId: f.id, variantId: restored.variantId, positionMs: 32000 }));
  assert.equal(f.reads(), 1); assert.equal(f.state.plays, 2);
  assert.notEqual(first.stream.url, second.stream.url); assert.equal(second.startPositionMs, 32000);
  await again.refreshQueue(second); assert.equal(f.reads(), 1);
  f.state.removeB = true; await again.getDetail('work', true);
  assert.equal((await again.getItem(f.id)).variantId, 'A:0');
});

test('source identity, saved configuration version and worker epoch isolate prepared metadata', async () => {
  const f = cachedFixture(); await f.provider.getDetail('work');
  await new CachedProvider({ ...f.source }, f.client, new CatVodSourceConfig()).getDetail('work');
  assert.equal(f.reads(), 1);
  for (const change of [{ id: 'another' }, { configJson: 'configuration-b' }, { updatedAt: 2 }]) {
    await new CachedProvider({ ...f.source, ...change }, f.client, new CatVodSourceConfig()).getDetail('work');
  }
  f.provider.scopeEpoch = {}; await f.provider.getDetail('work'); assert.equal(f.reads(), 5);
});

test('expired metadata gets one fresh-detail retry while HTTP 500 is not burdened with another detail request', async () => {
  for (const mode of ['stale', 'expired', 'server']) {
    CatPlaybackPreparationCache.clear(); const f = cachedFixture();
    const detail = await f.provider.getDetail('work'); f.state.revision = 1; f.state.mode = mode;
    const request = Object.assign(new PlaybackQueueItem(), { sourceId: f.source.id, mediaId: f.id,
      variantId: detail.roads[0].id });
    if (mode === 'stale') assert.match((await f.provider.resolvePlayback(request)).stream.url, /a-1/);
    else await assert.rejects(f.provider.resolvePlayback(request));
    assert.equal(f.reads(), mode === 'server' ? 1 : 2);
    assert.equal(f.state.plays, mode === 'server' ? 1 : 2);
  }
});

test('only history permits one same-episode fallback on an empty address; explicit line and unrelated errors stay unchanged', async () => {
  for (const allow of [false, true]) {
    CatPlaybackPreparationCache.clear(); const f = cachedFixture();
    const detail = await f.provider.getDetail('work'); let attempts = 0;
    f.provider.resolveEpisode = async road => {
      attempts++; if (road.id === 'A:0') throw new Error('HTTP 500：播放地址为空');
      return { url: 'https://media.invalid/fallback.mp4' };
    };
    const item = Object.assign(new PlaybackQueueItem(), { sourceId: f.source.id, mediaId: f.id,
      variantId: detail.roads[0].id, allowVariantFallback: allow, positionMs: 23000 });
    if (!allow) await assert.rejects(f.provider.resolvePlayback(item), /播放地址为空/);
    else {
      const session = await f.provider.resolvePlayback(item);
      assert.equal(item.variantId, 'B:0'); assert.equal(session.startPositionMs, 23000);
      assert.equal(session.media.mediaId, f.id); assert.equal(session.media.subtitle, '正片');
    }
    assert.equal(attempts, allow ? 2 : 1); assert.equal(f.reads(), 1);
  }
  for (const error of ['HTTP 500', '请登录', 'HTTP 403']) {
    const f = cachedFixture(); let attempts = 0;
    f.provider.resolveEpisode = async () => { attempts++; throw new Error(error); };
    const item = Object.assign(new PlaybackQueueItem(), { sourceId: f.source.id, mediaId: f.id,
      variantId: 'A:0', allowVariantFallback: true });
    await assert.rejects(f.provider.resolvePlayback(item)); assert.equal(attempts, 1);
  }
});

test('empty-address recovery never scans more than one alternative or substitutes a differently named episode', async () => {
  for (const matching of [false, true]) {
    CatPlaybackPreparationCache.clear(); const f = cachedFixture();
    const original = f.client.detail;
    f.client.detail = async id => {
      const detail = await original(id);
      if (!matching) detail.roads[1].episodes[0].name = '另一集';
      else detail.roads.push({ ...detail.roads[1], id: 'C:0' });
      return detail;
    };
    let attempts = 0;
    f.provider.resolveEpisode = async () => { attempts++; throw new Error('播放地址为空'); };
    const item = Object.assign(new PlaybackQueueItem(), { sourceId: f.source.id, mediaId: f.id,
      variantId: 'A:0', allowVariantFallback: true });
    await assert.rejects(f.provider.resolvePlayback(item), /播放地址为空/);
    assert.equal(attempts, matching ? 2 : 1);
  }
});

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
