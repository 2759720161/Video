import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { test } from 'node:test';

const read = path => readFileSync(new URL('../entry/src/main/ets/' + path, import.meta.url), 'utf8');
const compile = text => stripTypeScriptTypes(text.replace(/^import .*$/gm, '').replace(/^export /gm, ''), { mode: 'transform' });
const models = new Function(compile(read('providers/catvod/CatVodModels.ets')) + ';return {CatVodVideo, CatVodCategory};')();
const artwork = new Function(compile(read('providers/catvod/CatArtwork.ets')) + ';return CatArtwork;')();
class Site { key = ''; name = ''; type = 3; ext = ''; searchable = true; }
const codec = { object: value => value !== null && typeof value === 'object' && !Array.isArray(value) ? value : null,
  text: value => typeof value === 'string' ? value : typeof value === 'number' ? String(value) : '' };
const source = (id = 'cat-a', extra = {}) => ({ id, providerType: 'catnode', updatedAt: 1,
  configJson: '{"spiderKey":"a","token":"source-secret"}', ...extra });

function fixture(data = '[]') {
  let now = 1_000_000;
  const state = { data, failRead: false, failWrite: false, writes: [], keys: [] };
  const preferences = { getInstance: () => ({
    async getStringStrict(key) { state.keys.push(key); if (state.failRead) throw new Error('read failed'); return state.data; },
    async setStringStrict(key, value) {
      if (state.failWrite) throw new Error('write failed'); state.data = value; state.writes.push([key, value]);
    }
  }) };
  const crypto = { createMd: () => {
    const hash = createHash('sha256');
    return { async update({ data }) { hash.update(data); }, async digest() { return { data: new Uint8Array(hash.digest()) }; } };
  } };
  const make = () => new Function('cryptoFramework', 'util', 'MediaSourceInstance', 'CatNodeSite', 'CatVodCategory',
    'CatVodVideo', 'CatVodCodec', 'PreferencesStore', 'Date', 'CatArtwork', compile(read('services/media/CatHomeCache.ets')) +
    ';return {Cache: CatHomeCache, Snapshot: CatHomeSnapshot};')(
    crypto, { TextEncoder: class { encodeInto(value) { return new TextEncoder().encode(value); } } }, class {}, Site,
    models.CatVodCategory, models.CatVodVideo, codec, preferences, { now: () => now }, artwork);
  return { ...make(), state, make, advance: ms => { now += ms; }, snapshot: (overrides = {}) => ({
    key: '', savedAt: now, pageCount: 4, siteKey: 'a', sites: [{ key: 'a', name: '目录甲', type: 3, ext: 'site-secret', searchable: false }],
    categories: [{ id: 'movie', name: '电影' }], videos: [{ id: 'catnode:a:video', name: '影片', poster: 'https://server.test/poster',
      year: 2026, roads: [{ episodes: [{ url: 'https://play.test/private-stream' }] }] }], ...overrides }) };
}

test('home snapshot survives a fresh cache instance and stores display fields without config, site ext or playback URLs', async () => {
  const f = fixture(); await f.Cache.put(source(), f.snapshot());
  const restored = await f.make().Cache.get(source());
  assert.equal(restored.videos[0].id, 'catnode:a:video'); assert.equal(restored.categories[0].name, '电影');
  assert.equal(restored.sites[0].searchable, false); assert.deepEqual(restored.videos[0].roads, []);
  assert.ok(!f.state.data.includes('source-secret') && !f.state.data.includes('site-secret') && !f.state.data.includes('private-stream'));
  assert.ok(f.state.keys.every(key => key === 'cat_home_cache_v1'));
  assert.match(JSON.parse(f.state.data)[0].key, /^[a-f0-9]{64}$/);
});

test('index intent survives disk cache and artwork restoration without changing item identity', async () => {
  const f = fixture(); const snapshot = f.snapshot();
  snapshot.sites[0].indexOnly = true; snapshot.videos[0].searchOnly = true;
  await f.Cache.put(source(), snapshot);
  const restored = await f.make().Cache.get(source());
  assert.equal(restored.sites[0].indexOnly, true); assert.equal(restored.videos[0].searchOnly, true);
  const video = f.Cache.artwork(restored)[0];
  assert.equal(video.id, snapshot.videos[0].id); assert.equal(video.searchOnly, true);
  restored.videos[0].searchOnly = false;
  assert.equal(f.Cache.artwork(restored)[0].searchOnly, true);
});

test('fresh cached protected-domain images prepare the current runtime and recover without reloading categories', async () => {
  const f = fixture();
  const url = 'https://img2.doubanio.com/view/photo/s_ratio_poster/public/a.webp';
  await f.Cache.put(source(), f.snapshot({ videos: [{ id: 'a', name: '作品', poster: url }] }));
  const restored = await f.make().Cache.get(source());
  assert.ok(f.Cache.fresh(restored)); assert.equal(f.Cache.needsProxy(restored), true);
  assert.equal(f.Cache.artwork(restored)[0].poster, '');
  const image = f.Cache.artwork(restored, 'http://127.0.0.1:43001')[0].poster;
  assert.equal(new URL(image).searchParams.get('url'), url);
  assert.equal(new URL(image).pathname, '/__video_artwork');
  assert.equal(f.Cache.rebaseArtwork(image, 'http://127.0.0.1:43002'), image.replace(':43001', ':43002'));
  assert.equal(restored.videos[0].poster, url);
});

test('native collection cache retains its direct images without requiring a node subscription', async () => {
  const f = fixture();
  const url = 'https://img2.doubanio.com/view/photo/s_ratio_poster/public/a.webp';
  const cached = f.snapshot({ siteKey: '', videos: [{ id: 'a', name: '作品', poster: url }] });
  assert.equal(f.Cache.needsProxy(cached), false);
  assert.equal(f.Cache.artwork(cached)[0].poster, url);
  cached.siteKey = 'directory'; cached.videos[0].poster = url.replace('https:', '');
  assert.equal(f.Cache.needsProxy(cached), true);
  assert.match(f.Cache.artwork(cached, 'http://127.0.0.1:43001')[0].poster, /__video_artwork/);
});

test('source, configuration, directory, provider type and revision identities cannot share a home snapshot', async () => {
  const f = fixture(); await f.Cache.put(source(), f.snapshot());
  for (const changed of [source('cat-b'), source('cat-a', { updatedAt: 2 }), source('cat-a', { providerType: 'catvod' }),
    source('cat-a', { configJson: '{"spiderKey":"b"}' })]) assert.equal(await f.Cache.get(changed), null);
  assert.notEqual(await f.Cache.identity(source()), await f.Cache.identity(source('cat-b')));
});

test('six-hour freshness expires exactly, while stale display data is retained for up to seven days', async () => {
  const f = fixture(); await f.Cache.put(source(), f.snapshot());
  f.advance(f.Cache.FRESH_MS - 1); assert.equal(f.Cache.fresh(await f.Cache.get(source())), true);
  f.advance(1); const stale = await f.Cache.get(source()); assert.ok(stale); assert.equal(f.Cache.fresh(stale), false);
  f.advance(7 * 24 * 60 * 60 * 1000 - f.Cache.FRESH_MS + 1); assert.equal(await f.Cache.get(source()), null);
});

test('corrupt, oversized, invalid and implausibly future cache entries are ignored', async () => {
  for (const data of ['bad-json', '{}', '[null]', 'x'.repeat(1024 * 1024 + 1)]) {
    assert.equal(await fixture(data).Cache.get(source()), null);
  }
  const f = fixture();
  for (const invalid of [f.snapshot({ pageCount: -1 }), f.snapshot({ savedAt: 0 }), f.snapshot({ savedAt: 2_000_000 }),
    f.snapshot({ videos: null }), f.snapshot({ categories: {} })]) await f.Cache.put(source(), invalid);
  assert.equal(f.state.writes.length, 0);
});

test('serialized concurrent writes retain distinct sources and enforce entry and total size bounds', async () => {
  const f = fixture();
  await Promise.all(Array.from({ length: 10 }, (_, i) => f.Cache.put(source(`cat-${i}`), f.snapshot())));
  assert.equal(JSON.parse(f.state.data).length, 8);
  assert.equal(await f.Cache.get(source('cat-0')), null); assert.ok(await f.Cache.get(source('cat-9')));
  assert.ok(f.state.data.length <= 1024 * 1024);
  const videos = Array.from({ length: 80 }, (_, i) => ({ id: String(i), name: '电影', poster: 'x'.repeat(8000) }));
  await f.Cache.put(source('large-a'), f.snapshot({ videos })); await f.Cache.put(source('large-b'), f.snapshot({ videos }));
  assert.ok(f.state.data.length <= 1024 * 1024); assert.ok(await f.Cache.get(source('large-b')));
});

test('failed storage never blocks home, overwrites unread data, or poisons subsequent writes', async () => {
  const f = fixture(); await f.Cache.put(source(), f.snapshot()); const original = f.state.data;
  f.state.failRead = true; assert.equal(await f.Cache.get(source()), null);
  await f.Cache.put(source('b'), f.snapshot()); assert.equal(f.state.data, original);
  f.state.failRead = false; f.state.failWrite = true; await f.Cache.put(source('c'), f.snapshot());
  assert.equal(f.state.data, original); f.state.failWrite = false;
  await f.Cache.put(source('d'), f.snapshot()); assert.ok(await f.Cache.get(source('d')));
});

test('snapshot writes capture immutable first-page data before later UI mutations', async () => {
  const f = fixture(); const value = f.snapshot(); const pending = f.Cache.put(source(), value);
  value.videos[0].name = 'later mutation'; value.categories.length = 0;
  await pending; const restored = await f.Cache.get(source());
  assert.equal(restored.videos[0].name, '影片'); assert.equal(restored.categories.length, 1);
});

test('proxy poster URLs rebase to the current runtime without changing external artwork or video identities', () => {
  const f = fixture(); const value = f.snapshot({ videos: [
    { id: 'a', poster: 'http://127.0.0.1:1000/imgProxy?url=https%3A%2F%2Fimage.test%2Fa' },
    { id: 'b', poster: 'https://external.test/poster' }] });
  assert.equal(f.Cache.needsProxy(value), true);
  assert.equal(f.Cache.artwork(value)[0].poster, '');
  const rebased = f.Cache.artwork(value, 'http://127.0.0.1:2222');
  assert.equal(rebased[0].poster, 'http://127.0.0.1:2222/imgProxy?url=https%3A%2F%2Fimage.test%2Fa');
  assert.equal(rebased[1].poster, value.videos[1].poster); assert.equal(rebased[0].id, 'a');
  assert.equal(value.videos[0].poster.startsWith('http://127.0.0.1:1000'), true);
});

test('empty successful first pages persist, and unbounded arrays are cropped to display limits', async () => {
  const f = fixture(); await f.Cache.put(source(), f.snapshot({ videos: [] }));
  assert.deepEqual((await f.Cache.get(source())).videos, []);
  await f.Cache.put(source(), f.snapshot({ videos: Array.from({ length: 220 }, (_, i) => ({ id: String(i), name: '片名' })) }));
  assert.equal((await f.Cache.get(source())).videos.length, 200);
  assert.equal(f.Cache.fresh(await f.Cache.get(source())), false, 'cropped first pages must refresh to recover omitted records');
});

test('cached provider construction is local, validates the saved directory, and only proxy preparation starts runtime', async () => {
  const text = read('providers/catvod/CatNodeProvider.ets');
  const methods = text.slice(text.indexOf('  static fromCachedSites('), text.indexOf('  getSiteKey()'));
  let starts = 0;
  const Provider = new Function('CatNodeSubscriptionCodec', 'CatNodeClient', 'CatNodeRuntime', compile(`class CatNodeProvider {
    constructor(source, client, context, config) { this.nodeContext=context; this.nodeConfig=config; this.client=client; }
    ${methods} }`) + ';return CatNodeProvider;')(
    { decode: json => ({ legacySpiderKey: '', ...JSON.parse(json) }), normalizeUrl: url => new URL(url).href },
    class { constructor(context, key) { this.key = key; } },
    { async ensure() { starts++; return { baseUrl: () => 'http://127.0.0.1:4000' }; } });
  const config = { configJson: '{"md5Url":"https://source.test/index.js.md5","spiderKey":"a"}' };
  const provider = Provider.fromCachedSites(config, {}, [{ key: 'a' }], 'a');
  assert.equal(starts, 0); assert.equal(provider.client.key, 'a');
  assert.throws(() => Provider.fromCachedSites(config, {}, [{ key: 'b' }], 'b'), /变化/);
  assert.equal(await provider.cachedArtworkBase(), 'http://127.0.0.1:4000'); assert.equal(starts, 1);
});

test('category snapshots remain isolated from overview and other categories after a cold restart', async () => {
  const f = fixture();
  await f.Cache.put(source(), f.snapshot());
  await f.Cache.put(source(), f.snapshot({ categoryId: 'movie', videos: [{ id: 'm', name: '电影', poster: 'movie' }] }));
  await f.Cache.put(source(), f.snapshot({ categoryId: 'comedy', videos: [{ id: 'c', name: '喜剧', poster: 'comedy' }] }));
  const { Cache } = f.make();
  assert.equal((await Cache.get(source())).videos[0].id, 'catnode:a:video');
  assert.equal((await Cache.get(source(), 'movie')).videos[0].poster, 'movie');
  assert.equal((await Cache.get(source(), 'comedy')).categoryId, 'comedy');
  assert.equal(await Cache.get(source(), 'unknown'), null);
});

test('legacy overview keys and snapshots without categoryId remain readable', async () => {
  const f = fixture();
  const legacyKey = createHash('sha256').update(JSON.stringify([
    source().id, source().providerType, source().updatedAt, source().configJson])).digest('hex');
  assert.equal(await f.Cache.identity(source()), legacyKey);
  f.state.data = JSON.stringify([{ ...f.snapshot(), key: legacyKey }]);
  assert.equal((await f.Cache.get(source())).categoryId, '');
  assert.equal(await f.Cache.get(source(), 'movie'), null);
});

test('visiting many categories evicts older category snapshots before the cold-start overview', async () => {
  const f = fixture(); await f.Cache.put(source(), f.snapshot());
  for (let i = 0; i < 12; i++) await f.Cache.put(source(), f.snapshot({ categoryId: `category-${i}` }));
  assert.equal(JSON.parse(f.state.data).length, 8);
  assert.ok(await f.make().Cache.get(source()));
  assert.equal(await f.Cache.get(source(), 'category-0'), null);
  assert.ok(await f.Cache.get(source(), 'category-11'));
});

test('history artwork rebasing handles poster/backdrop paths and preserves external URLs', () => {
  const f = fixture();
  assert.equal(f.Cache.rebaseArtwork(''), '');
  assert.equal(f.Cache.rebaseArtwork('http://127.0.0.1:1000/backdrop?a=1'), '');
  assert.equal(f.Cache.rebaseArtwork('http://127.0.0.1:1000/backdrop?a=1', 'http://127.0.0.1:2000'),
    'http://127.0.0.1:2000/backdrop?a=1');
  assert.equal(f.Cache.rebaseArtwork('https://server.test/a'), 'https://server.test/a');
});
