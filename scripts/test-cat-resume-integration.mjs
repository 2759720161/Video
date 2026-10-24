import { registerHooks, stripTypeScriptTypes } from 'node:module';
import { readFileSync, existsSync, mkdirSync, mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';
import { test, beforeEach } from 'node:test';

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
    const stubs = {
      '/utils/DetailMaterial.ets': 'export const buildDetailToastOptions = message => ({message});',
      '/store/MediaSourceStore.ets': 'export class MediaSourceStore {}',
      '/store/PlaybackHistoryStore.ets': 'export class PlaybackHistoryStore { async get() { return null; } }',
      '/core/playback/PlaybackHistoryReporter.ets': 'export class PlaybackHistoryReporter {}'
    };
    for (const [suffix, source] of Object.entries(stubs)) {
      if (url.endsWith(suffix)) return { format: 'module', source, shortCircuit: true };
    }
    if (url.endsWith('.ets')) return { format: 'module', source:
      stripTypeScriptTypes(readFileSync(new URL(url), 'utf8'), { mode: 'transform' }), shortCircuit: true };
    return next(url, context);
  }
});

const { CatNodeRuntime } = await import('../entry/src/main/ets/providers/catvod/CatNodeRuntime.ets');
const { CatNodeProvider } = await import('../entry/src/main/ets/providers/catvod/CatNodeProvider.ets');
const { CatVodCodec } = await import('../entry/src/main/ets/providers/catvod/CatVodCodec.ets');
const { CatPlaybackPreparationCache: Cache } = await import('../entry/src/main/ets/providers/catvod/CatPlaybackPreparationCache.ets');
const { PlaybackQueueItem } = await import('../entry/src/main/ets/core/playback/PlaybackQueueItem.ets');
const { CatStreamProbe } = await import('../entry/src/main/ets/providers/catvod/CatStreamProbe.ets');
beforeEach(() => { CatStreamProbe.check = async () => false; });
const deferred = () => { let resolve; const promise = new Promise(done => { resolve = done; }); return { promise, resolve }; };

test('real Node provider resumes a large multi-episode detail without duplicate init/detail and resolves fresh streams', async () => {
  const original = { ensure: CatNodeRuntime.ensure, sites: CatNodeRuntime.sites, request: CatNodeRuntime.request };
  const source = { id: 'source', providerType: 'catnode', updatedAt: 1,
    configJson: JSON.stringify({ md5Url: 'https://fixture.invalid/index.js.md5', spiderKey: 'directory' }) };
  const calls = [];
  let scope = { baseUrl: () => 'http://127.0.0.1:34127' };
  let ext = 'configuration-a'; let plays = 0;
  CatNodeRuntime.ensure = async () => scope;
  CatNodeRuntime.sites = async () => [{ key: 'directory', api: '/spider/directory/3', name: '目录', ext }];
  CatNodeRuntime.request = async (url, body) => {
    const route = url.split('/').at(-1); calls.push({ route, body });
    if (route === 'init') return '{}';
    if (route === 'detail') return JSON.stringify({ list: [{ vod_id: 'work', vod_name: '作品',
      vod_play_from: '网盘', vod_play_url: Array.from({ length: 12 }, (_, i) =>
        `第${i + 1}集$opaque-${i}-` + 'x'.repeat(26000)).join('#') }] });
    if (route === 'play') return JSON.stringify({ parse: 0, url: `https://media.invalid/stream.m3u8?fresh=${++plays}` });
    throw new Error('unexpected route');
  };
  Cache.clear();
  const count = route => calls.filter(call => call.route === route).length;
  try {
    const first = await CatNodeProvider.create(source, {});
    const detail = await first.getDetail('catnode:directory:work');
    assert.ok(JSON.stringify(detail).length > 256 * 1024);
    const id = CatVodCodec.episodeId(detail.id, detail.roads[0].episodes[0]);
    const resume = async provider => {
      const restored = await provider.getItem(id);
      return provider.resolvePlayback(Object.assign(new PlaybackQueueItem(), { sourceId: source.id,
        mediaId: id, variantId: restored.variantId, positionMs: 642082 }));
    };
    const one = await resume(first);
    const two = await resume(await CatNodeProvider.create(source, {}));
    assert.equal(count('init'), 1); assert.equal(count('detail'), 1); assert.equal(count('play'), 2);
    assert.notEqual(one.stream.url, two.stream.url);
    assert.equal(two.startPositionMs, 642082); assert.equal(two.episodeGroups[0].items.length, 12);
    // A changed runtime must not reuse either the old init route or old detail.
    scope = { baseUrl: () => 'http://127.0.0.1:34127' };
    await resume(await CatNodeProvider.create(source, {}));
    assert.equal(count('init'), 2); assert.equal(count('detail'), 2);
    // Configuration invalidation resets even a client which has already initialized.
    ext = 'configuration-b'; Cache.clear(); await resume(first);
    assert.equal(count('init'), 3); assert.equal(count('detail'), 3);
    assert.deepEqual(calls.filter(call => call.route === 'init').at(-1).body, { ext: 'configuration-b' });
  } finally { Cache.clear(); Object.assign(CatNodeRuntime, original); }
});

test('stateless HTTP IDs retain disk fast path; a recovered empty address learns cold preparation', async () => {
  const parent = path.resolve('tmp/resume-restart'); mkdirSync(parent, { recursive: true });
  const root = mkdtempSync(path.join(parent, 'snapshot-fixture-'));
  const original = { ensure: CatNodeRuntime.ensure, sites: CatNodeRuntime.sites, request: CatNodeRuntime.request };
  const source = { id: 'source', providerType: 'catnode', updatedAt: 1,
    configJson: JSON.stringify({ md5Url: 'https://fixture.invalid/index.js.md5', spiderKey: 'directory' }) };
  const calls = []; let revision = 0; let expired = false; let counter = 0;
  const address = () => ({ baseUrl: () => 'http://127.0.0.1:34127', dataRoot: root, bundleSha256: 'a'.repeat(64) });
  let scope = address();
  CatNodeRuntime.ensure = async () => scope;
  CatNodeRuntime.sites = async () => [{ key: 'directory', api: '/spider/directory/3', ext: '' }];
  CatNodeRuntime.request = async (url, body) => {
    const route = url.split('/').at(-1); calls.push({ route, body });
    if (route === 'init') return '{}';
    if (route === 'detail') return JSON.stringify({ list: [{ vod_id: 'work', vod_name: '作品',
      vod_pic: 'http://127.0.0.1:9999/__video_artwork?url=' + encodeURIComponent('https://img2.doubanio.com/a.webp'),
      vod_play_from: 'A$$$B', vod_play_url: `正片$https://share.invalid/a-${revision}$$$正片$https://share.invalid/b-${revision}` }] });
    if (route === 'play') {
      if (expired && body.id.endsWith('-0')) throw new Error('来源请求失败（HTTP 500）：播放地址为空');
      return JSON.stringify({ parse: 0, url: `https://media.invalid/stream.m3u8?fresh=${++counter}` });
    }
    throw new Error('unexpected route');
  };
  Cache.clear();
  try {
    const first = await CatNodeProvider.create(source, {});
    const detail = await first.getDetail('catnode:directory:work');
    const mediaId = CatVodCodec.episodeId(detail.id, detail.roads[0].episodes[0]);
    const request = variantId => Object.assign(new PlaybackQueueItem(), { sourceId: source.id, mediaId, variantId, positionMs: 12000 });
    await first.resolvePlayback(request('B:0'));
    const disk = readFileSync(path.join(root, 'playback-metadata.json'), 'utf8');
    assert.ok(!disk.includes('127.0.0.1')); assert.match(disk, /doubanio/);
    Cache.clear(); scope = address(); // Empty process cache and a new native address identity.
    const restored = await CatNodeProvider.create(source, {});
    const item = await restored.getItem(mediaId); assert.equal(item.variantId, 'B:0');
    assert.equal(calls.filter(call => call.route === 'detail').length, 1);
    const session = await restored.resolvePlayback(request(item.variantId));
    assert.equal(session.startPositionMs, 12000);
    assert.equal(calls.filter(call => call.route === 'init').length, 2, 'native init is never restored from disk');
    assert.equal(calls.filter(call => call.route === 'detail').length, 1);
    assert.notEqual(session.stream.url, 'https://media.invalid/stream.m3u8?fresh=1');
    // A disk-restored opaque token can expire: exactly one fresh read, then resolve again.
    expired = true; revision = 1;
    const repaired = await restored.resolvePlayback(request(item.variantId));
    assert.ok(repaired.stream.url); assert.equal(calls.filter(call => call.route === 'detail').length, 2);
    assert.equal(calls.filter(call => call.route === 'play').at(-1).body.id, 'https://share.invalid/b-1');
    // Recovery is remembered: a new source process prepares live detail before its first play.
    Cache.clear(); scope = address();
    const learned = await CatNodeProvider.create(source, {});
    const beforeLearned = calls.length;
    await learned.resolvePlayback(request('B:0'));
    const learnedCalls = calls.slice(beforeLearned).map(call => call.route);
    assert.ok(learnedCalls.indexOf('detail') < learnedCalls.indexOf('play'));
    assert.equal(learnedCalls.filter(route => route === 'play').length, 1);
    // Login/profile changes isolate persisted snapshots even if source ID is unchanged.
    writeFileSync(path.join(root, 'profile.json'), '{"fixture":"changed-profile"}', 'utf8');
    Cache.clear(); scope = address();
    await (await CatNodeProvider.create(source, {})).getItem(mediaId);
    assert.equal(calls.filter(call => call.route === 'detail').length, 4);
    scope = { ...address(), bundleSha256: 'b'.repeat(64) }; Cache.clear();
    await (await CatNodeProvider.create(source, {})).getItem(mediaId);
    assert.equal(calls.filter(call => call.route === 'detail').length, 5);
  } finally {
    Cache.clear(); Object.assign(CatNodeRuntime, original);
    assert.equal(path.dirname(root), parent); rmSync(root, { recursive: true, force: true });
  }
});

test('opaque cold resume primes detail before play and joins an in-flight home warmup from another provider', async () => {
  const parent = path.resolve('tmp/resume-cold-prime'); mkdirSync(parent, { recursive: true });
  const root = mkdtempSync(path.join(parent, 'prime-fixture-'));
  const original = { ensure: CatNodeRuntime.ensure, sites: CatNodeRuntime.sites, request: CatNodeRuntime.request };
  const source = { id: 'source', providerType: 'catnode', updatedAt: 1,
    configJson: JSON.stringify({ md5Url: 'https://fixture.invalid/index.js.md5', spiderKey: 'directory' }) };
  const address = () => ({ baseUrl: () => 'http://127.0.0.1:34127', dataRoot: root, bundleSha256: 'a'.repeat(64), ready: false });
  let scope = address(); let gate = null; const started = deferred(); const calls = []; let failedPlays = 0;
  CatNodeRuntime.ensure = async () => scope;
  CatNodeRuntime.sites = async () => [{ key: 'directory', api: '/spider/directory/3', ext: '' }];
  CatNodeRuntime.request = async (url, body) => {
    const route = url.split('/').at(-1); calls.push(route);
    if (route === 'init') return '{}';
    if (route === 'detail') {
      if (gate) { started.resolve(); await gate.promise; }
      scope.ready = true;
      return JSON.stringify({ list: [{ vod_id: 'work', vod_name: '作品', vod_play_from: '原画',
        vod_pic: 'https://images.invalid/a.jpg', vod_play_url: '正片$opaque-runtime-dependent-id' }] });
    }
    if (route === 'play') {
      if (!scope.ready) { failedPlays++; throw new Error('HTTP 500：播放地址为空'); }
      assert.equal(body.id, 'opaque-runtime-dependent-id');
      return '{"url":"https://media.invalid/current.mp4","parse":0}';
    }
    throw new Error('unexpected route');
  };
  Cache.clear();
  try {
    const seed = await CatNodeProvider.create(source, {});
    const detail = await seed.getDetail('catnode:directory:work');
    const mediaId = CatVodCodec.episodeId(detail.id, detail.roads[0].episodes[0]);
    Cache.clear(); scope = address(); gate = deferred();
    const home = await CatNodeProvider.create(source, {});
    const warm = home.prepareResume(mediaId);
    await started.promise;
    assert.equal(calls.filter(route => route === 'play').length, 0, 'warmup must never resolve playback');
    const clicked = await CatNodeProvider.create(source, {});
    const playback = clicked.resolvePlayback(Object.assign(new PlaybackQueueItem(), { sourceId: source.id,
      mediaId, variantId: detail.roads[0].id, positionMs: 13200 }));
    gate.resolve(); const [, session] = await Promise.all([warm, playback]);
    assert.equal(calls.filter(route => route === 'detail').length, 2, 'one seed read and one coalesced cold preparation');
    assert.equal(calls.filter(route => route === 'init').length, 2);
    assert.equal(calls.filter(route => route === 'play').length, 1); assert.equal(failedPlays, 0);
    assert.equal(session.startPositionMs, 13200);
    await clicked.resolvePlayback(Object.assign(new PlaybackQueueItem(), { sourceId: source.id,
      mediaId, variantId: detail.roads[0].id }));
    assert.equal(calls.filter(route => route === 'detail').length, 2, 'warm opens must not prime again');
    let current = false;
    await home.prepareResume(mediaId, () => current);
    assert.equal(calls.filter(route => route === 'detail').length, 2);
  } finally {
    Cache.clear(); Object.assign(CatNodeRuntime, original);
    assert.equal(path.dirname(root), parent); rmSync(root, { recursive: true, force: true });
  }
});

test('cached source proxy is rebound and validated after restart; direct fallback and fresh resolution remain available', async () => {
  const parent = path.resolve('tmp/resume-stream-cache'); mkdirSync(parent, { recursive: true });
  const root = mkdtempSync(path.join(parent, 'stream-fixture-'));
  const original = { ensure: CatNodeRuntime.ensure, sites: CatNodeRuntime.sites, request: CatNodeRuntime.request };
  const source = { id: 'source', providerType: 'catnode', updatedAt: 1,
    configJson: JSON.stringify({ md5Url: 'https://fixture.invalid/index.js.md5', spiderKey: 'directory' }) };
  const address = port => ({ baseUrl: () => 'http://127.0.0.1:' + port, dataRoot: root, bundleSha256: 'a'.repeat(64) });
  let scope = address(1111); let mode = 'ticket'; let probes = 0; const calls = [];
  const payload = Buffer.from(JSON.stringify({ url: 'https://media.invalid/upstream.mp4',
    headers: { Cookie: 'fixture-cookie', 'User-Agent': 'fixture-agent' }, createdAt: Date.now() })).toString('base64url');
  CatNodeRuntime.ensure = async () => scope;
  CatNodeRuntime.sites = async () => [{ key: 'directory', api: '/spider/directory/3', ext: '' }];
  CatNodeRuntime.request = async url => {
    const route = url.split('/').at(-1); calls.push(route);
    if (route === 'init') return '{}';
    if (route === 'detail') return JSON.stringify({ list: [{ vod_id: 'work', vod_name: '作品',
      vod_pic: 'https://images.invalid/a.jpg', vod_play_from: '原画', vod_play_url: '正片$opaque-id' }] });
    if (route === 'play') {
      if (mode === 'unavailable') throw new Error('HTTP 500：播放地址为空');
      return JSON.stringify({ parse: 0, url: mode === 'ticket' ?
        scope.baseUrl() + '/spider/directory/3/proxy/runtime/old-uuid?pst=' + payload :
        'https://media.invalid/fresh-' + calls.filter(value => value === 'play').length + '.mp4' });
    }
    throw new Error('unexpected route');
  };
  const count = route => calls.filter(value => value === route).length;
  Cache.clear();
  try {
    const first = await CatNodeProvider.create(source, {});
    const detail = await first.getDetail('catnode:directory:work');
    const mediaId = CatVodCodec.episodeId(detail.id, detail.roads[0].episodes[0]);
    const request = () => Object.assign(new PlaybackQueueItem(), { sourceId: source.id, mediaId,
      variantId: detail.roads[0].id, positionMs: 13200 });
    await first.resolvePlayback(request()); assert.equal(count('play'), 1);
    const disk = readFileSync(path.join(root, 'playback-streams.json'), 'utf8');
    assert.ok(!disk.includes('127.0.0.1') && !disk.includes(':1111'));
    Cache.clear(); scope = address(2222); mode = 'unavailable';
    const restarted = await CatNodeProvider.create(source, {});
    await restarted.prepareResume(mediaId);
    assert.equal(count('detail'), 1, 'warmup should recognize an available stream and skip costly live preparation');
    CatStreamProbe.check = async stream => {
      probes++; assert.match(stream.url, /^http:\/\/127\.0\.0\.1:2222\/spider\/directory\/3\/proxy\//);
      assert.deepEqual(stream.headers, {}); return true;
    };
    const hit = await restarted.resolvePlayback(request());
    assert.equal(hit.stream.reused, true); assert.equal(hit.startPositionMs, 13200);
    assert.equal(count('init'), 1); assert.equal(count('detail'), 1); assert.equal(count('play'), 1); assert.equal(probes, 1);
    assert.ok(hit.episodeGroups[0].items.length > 0);
    assert.match(hit.stream.url, /^http:\/\/127\.0\.0\.1:2222\//);
    // A source that cannot recover its proxy route still has a validated direct path.
    CatStreamProbe.check = async stream => {
      probes++;
      if (stream.url.startsWith('http://127.0.0.1:')) return false;
      assert.equal(stream.url, 'https://media.invalid/upstream.mp4');
      assert.equal(stream.headers.Cookie, 'fixture-cookie'); return true;
    };
    const direct = await restarted.resolvePlayback(request());
    assert.equal(direct.stream.url, 'https://media.invalid/upstream.mp4');
    assert.equal(probes, 3); assert.equal(count('play'), 1);
    // A rejected cache must return to one normal live resolution.
    CatStreamProbe.check = async () => { probes++; return false; }; mode = 'fresh';
    const fresh = await restarted.resolvePlayback(request());
    assert.equal(fresh.stream.reused, false); assert.match(fresh.stream.url, /fresh-2\.mp4$/);
    assert.equal(count('init'), 2); assert.equal(count('detail'), 2); assert.equal(count('play'), 2);
    const before = probes;
    const forced = await restarted.resolvePlayback(Object.assign(request(), { bypassStreamCache: true }));
    assert.match(forced.stream.url, /fresh-3\.mp4$/); assert.equal(probes, before, 'forced refresh must never return the rejected cache');
    // Changed login state cannot hit the previous account's stream.
    writeFileSync(path.join(root, 'profile.json'), '{"fixture":"different-login"}', 'utf8');
    Cache.clear(); scope = address(3333);
    await (await CatNodeProvider.create(source, {})).resolvePlayback(request());
    assert.equal(probes, before); assert.equal(count('play'), 4);
  } finally {
    Cache.clear(); Object.assign(CatNodeRuntime, original);
    assert.equal(path.dirname(root), parent); rmSync(root, { recursive: true, force: true });
  }
});
