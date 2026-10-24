import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { test } from 'node:test';
const source = readFileSync(new URL('../entry/src/main/ets/providers/catvod/CatPlaybackPreparationCache.ets', import.meta.url), 'utf8');
function fixture() {
  const clock = { now: 1000000 };
  const Cache = new Function('Date', stripTypeScriptTypes(source.replace(/^import .*\r?\n/gm, '').replace(/export /g, ''),
    { mode: 'transform' }) + ';return CatPlaybackPreparationCache;')({ now: () => clock.now });
  return { Cache, clock, scope: {} };
}
const video = (id = 'work', name = '作品') => ({ id, name, poster: 'loopback-image', roads: [
  { id: 'a', spiderKey: 'spider', name: '网盘', episodes: [{ name: '正片', url: 'opaque' }] }] });
const deferred = () => { let resolve, reject; const promise = new Promise((ok, fail) => { resolve = ok; reject = fail; });
  return { promise, resolve, reject }; };

test('warm details are shared across readers but each consumer receives an independent mutable copy', async () => {
  const { Cache, scope } = fixture(); let reads = 0; const raw = video(); const status = [];
  const load = async () => { reads++; return raw; };
  const first = await Cache.detail(scope, 'source-config-work', 'work', load);
  first.roads[0].episodes[0].url = 'changed';
  const second = await Cache.detail(scope, 'source-config-work', 'work', load, false, value => status.push(value));
  assert.equal(second.roads[0].episodes[0].url, 'opaque'); assert.equal(raw.roads[0].episodes[0].url, 'opaque');
  assert.equal(reads, 1); assert.deepEqual(status, ['hit']);
});

test('concurrent requests coalesce and clones remain isolated', async () => {
  const { Cache, scope } = fixture(); const gate = deferred(); let reads = 0;
  const load = () => { reads++; return gate.promise; };
  const first = Cache.detail(scope, 'key', 'work', load), second = Cache.detail(scope, 'key', 'work', load);
  assert.equal(reads, 1); gate.resolve(video()); const [a, b] = await Promise.all([first, second]);
  a.name = '更改'; assert.equal(b.name, '作品'); assert.notEqual(a, b);
});

test('worker identity, source key and two-minute TTL bound reuse; clock rollback cannot prolong validity', async () => {
  const { Cache, scope, clock } = fixture(); let reads = 0;
  const load = async () => { reads++; return video(); };
  await Cache.detail(scope, 'key', 'work', load); clock.now += 119999;
  await Cache.detail(scope, 'key', 'work', load); assert.equal(reads, 1);
  clock.now++; await Cache.detail(scope, 'key', 'work', load); assert.equal(reads, 2);
  await Cache.detail({}, 'key', 'work', load); assert.equal(reads, 3);
  await Cache.detail(scope, 'another-source', 'work', load); assert.equal(reads, 4);
  clock.now--; await Cache.detail(scope, 'another-source', 'work', load); assert.equal(reads, 5);
});

test('empty, mismatched and failed loads are never cached; failed refresh cannot resurrect older data', async () => {
  const { Cache, scope } = fixture(); let reads = 0; let value = null;
  const load = async () => { reads++; if (value instanceof Error) throw value; return value; };
  for (value of [null, video('other'), video('work', ''), new Error('offline')]) {
    for (let i = 0; i < 2; i++) { if (value instanceof Error) await assert.rejects(Cache.detail(scope, 'key', 'work', load));
      else await Cache.detail(scope, 'key', 'work', load); }
  }
  assert.equal(reads, 8); value = video(); await Cache.detail(scope, 'key', 'work', load);
  value = new Error('refresh failed'); await assert.rejects(Cache.detail(scope, 'key', 'work', load, true));
  value = video('work', '新详情'); assert.equal((await Cache.detail(scope, 'key', 'work', load)).name, '新详情');
});

test('force refresh and invalidation stop late pending reads from repopulating an obsolete cache', async () => {
  for (const clear of [false, true]) {
    const { Cache, scope } = fixture(); const gate = deferred();
    const old = Cache.detail(scope, 'key', 'work', () => gate.promise);
    if (clear) Cache.clear();
    const current = await Cache.detail(scope, 'key', 'work', async () => video('work', '新详情'), !clear);
    gate.resolve(video('work', '旧详情')); await old;
    const retained = await Cache.detail(scope, 'key', 'work', async () => { throw new Error('unexpected reload'); });
    assert.equal(current.name, '新详情'); assert.equal(retained.name, '新详情');
  }
});

test('bounded LRU keeps at most 24 entries and two million characters; oversized details are not retained', async () => {
  const { Cache, scope } = fixture();
  for (let i = 0; i < 24; i++) await Cache.detail(scope, String(i), 'work', async () => video());
  await Cache.detail(scope, '0', 'work', async () => { throw new Error('lost recent item'); });
  await Cache.detail(scope, '24', 'work', async () => video());
  assert.equal(Cache.details.size, 24); assert.equal(Cache.details.has('0'), true); assert.equal(Cache.details.has('1'), false);
  Cache.clear();
  for (let i = 0; i < 20; i++) await Cache.detail(scope, String(i), 'work', async () => ({ ...video(), overview: '长'.repeat(200000) }));
  assert.ok([...Cache.details.values()].reduce((sum, value) => sum + value.json.length, 0) <= 2 * 1024 * 1024);
  const status = [];
  let reads = 0;
  const large = async () => { reads++; return { ...video(), overview: '长'.repeat(312033) }; };
  await Cache.detail(scope, 'large', 'work', large, false, value => status.push(value));
  await Cache.detail(scope, 'large', 'work', large, false, value => status.push(value));
  assert.equal(reads, 1); assert.equal(status.at(-1), 'hit');
  assert.ok(status.some(value => value.startsWith('stored chars=')));
  await Cache.detail(scope, 'huge', 'work', async () => ({ ...video(), overview: '长'.repeat(2 * 1024 * 1024) }),
    false, value => status.push(value));
  assert.equal(Cache.details.has('huge'), false);
  assert.match(status.at(-1), /^not_stored reason=size_limit chars=\d+$/);
});

test('init negotiation coalesces readers, expires and isolates runtime and configuration', async () => {
  const { Cache, scope, clock } = fixture(); let reads = 0; const status = [];
  const gate = deferred(); const load = () => { reads++; return gate.promise; };
  const first = Cache.initialize(scope, 'config', load, value => status.push(value));
  const joined = Cache.initialize(scope, 'config', load, value => status.push(value));
  gate.resolve('/spider/work');
  assert.deepEqual(await Promise.all([first, joined]), ['/spider/work', '/spider/work']);
  assert.equal(reads, 1); assert.deepEqual(status, ['miss', 'joined']);
  await Cache.initialize(scope, 'config', load, value => status.push(value)); assert.equal(status.at(-1), 'hit');
  clock.now += 120000; await Cache.initialize(scope, 'config', load); assert.equal(reads, 2);
  await Cache.initialize({}, 'config', load); await Cache.initialize(scope, 'another-config', load);
  assert.equal(reads, 4);
  clock.now--; await Cache.initialize(scope, 'another-config', load); assert.equal(reads, 5);
});

test('failed init is retryable and invalidation prevents late init from replacing a new negotiation', async () => {
  const { Cache, scope } = fixture(); let reads = 0;
  await assert.rejects(Cache.initialize(scope, 'config', async () => { reads++; throw new Error('offline'); }));
  assert.equal(await Cache.initialize(scope, 'config', async () => { reads++; return '/good'; }), '/good');
  assert.equal(reads, 2);
  const gate = deferred(); const old = Cache.initialize(scope, 'pending', () => gate.promise);
  const revision = Cache.revision(); Cache.clear(); assert.equal(Cache.revision(), revision + 1);
  await Cache.initialize(scope, 'pending', async () => '/new'); gate.resolve('/old'); await old;
  assert.equal(await Cache.initialize(scope, 'pending', async () => { throw new Error('unexpected'); }), '/new');
  for (let i = 0; i < 80; i++) await Cache.initialize(scope, String(i), async () => '/path');
  assert.equal(Cache.initializations.size, 64);
});

test('preferred lines expire, have bounded memory and are cleared with configuration/runtime invalidation', () => {
  const { Cache, clock } = fixture();
  Cache.rememberVariant('source-config-episode', 'road'); assert.equal(Cache.preferredVariant('source-config-episode'), 'road');
  assert.equal(Cache.preferredVariant('other-config-episode'), ''); clock.now += 30 * 60 * 1000;
  assert.equal(Cache.preferredVariant('source-config-episode'), '');
  for (let i = 0; i < 80; i++) Cache.rememberVariant(String(i), 'road');
  assert.equal(Cache.variants.size, 64); Cache.clear(); assert.equal(Cache.preferredVariant('79'), '');
});

test('disk provenance survives memory reuse and joined loads so expired opaque IDs can be refreshed', async () => {
  const { Cache, scope } = fixture(); const gate = deferred(); const firstStatus = [], joinedStatus = [], hitStatus = [];
  const load = async report => { await gate.promise; report('disk_hit'); return video(); };
  const first = Cache.detail(scope, 'key', 'work', load, false, value => firstStatus.push(value));
  const joined = Cache.detail(scope, 'key', 'work', load, false, value => joinedStatus.push(value));
  gate.resolve(); await Promise.all([first, joined]);
  await Cache.detail(scope, 'key', 'work', load, false, value => hitStatus.push(value));
  assert.ok(firstStatus.includes('disk_hit')); assert.ok(joinedStatus.includes('disk_hit'));
  assert.deepEqual(hitStatus, ['disk_hit']);
  await Cache.detail(scope, 'key', 'work', async () => video(), true);
  const fresh = []; await Cache.detail(scope, 'key', 'work', load, false, value => fresh.push(value));
  assert.deepEqual(fresh, ['hit']);
});

test('live-detail upgrade joins network work and never accepts a completed disk snapshot', async () => {
  const { Cache, scope } = fixture(); const diskGate = deferred(); let networkReads = 0;
  const disk = Cache.detail(scope, 'key', 'work', async report => { await diskGate.promise; report('disk_hit'); return video(); });
  const network = async () => { networkReads++; return video('work', '当前运行环境'); };
  const first = Cache.detail(scope, 'key', 'work', network, false, () => {}, true);
  const second = Cache.detail(scope, 'key', 'work', network, false, () => {}, true);
  diskGate.resolve(); await disk;
  const live = await Promise.all([first, second]);
  assert.equal(networkReads, 1); assert.ok(live.every(value => value.name === '当前运行环境'));
  assert.equal((await Cache.detail(scope, 'key', 'work', network, false, () => {}, true)).name, '当前运行环境');
  assert.equal(networkReads, 1);
});

test('live-detail readiness is scoped to the actual worker, bounded, and invalidated with configuration', () => {
  const { Cache, scope } = fixture();
  Cache.markLiveDetail(scope, 'work'); assert.equal(Cache.hasLiveDetail(scope, 'work'), true);
  assert.equal(Cache.hasLiveDetail({}, 'work'), false);
  for (let i = 0; i < 80; i++) Cache.markLiveDetail(scope, String(i));
  assert.equal(Cache.liveDetails.size, 64);
  Cache.clear(); assert.equal(Cache.hasLiveDetail(scope, '79'), false);
});
