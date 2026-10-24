import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { test } from 'node:test';

const read = name => readFileSync(new URL('../entry/src/main/ets/' + name, import.meta.url), 'utf8').replace(/\r\n/g, '\n');
const compile = text => stripTypeScriptTypes(text.replace(/^import .*\r?\n/gm, '').replace(/^export /gm, ''), { mode: 'transform' });
const defer = () => { let resolve; const promise = new Promise(done => { resolve = done; }); return { promise, resolve }; };
const MediaItem = new Function(compile(read('core/media/MediaItem.ets')) + ';return MediaItem;')();

function fixture() {
  const calls = { providers: 0, items: 0, resolves: 0, sessions: [], releases: [], routes: [], logs: [] };
  const state = { current: true, gateProvider: null, gateItem: null, gateResolve: null, missing: false, failResolve: false,
    wrongIdentity: false, routeFailure: false, unavailable: false };
  const Queue = class {
    static normalizePositionMs(value) { return Number.isFinite(value) ? Math.max(0, Math.floor(value)) : 0; }
    static normalizeDurationMs(value) { return this.normalizePositionMs(value); }
    variants = [];
  };
  const item = Object.assign(new MediaItem(), { sourceId: 'cat-a', id: 'episode-a', playable: true, title: '作品',
    variants: [], variantId: 'road', durationMs: 60000, trackSelection: null });
  const provider = { getSourceId: () => 'cat-a', async getItem() {
    calls.items++; if (state.gateItem) await state.gateItem.promise; return state.missing ? null : item;
  }, async resolvePlayback(selected) {
    calls.resolves++; if (state.gateResolve) await state.gateResolve.promise;
    if (state.failResolve) throw new Error('private upstream URL/token');
    return { media: { sourceId: 'cat-a', mediaId: state.wrongIdentity ? 'another' : selected.mediaId }, stream: { url: 'private-stream' } };
  }, createReporterForSession: () => ({}) };
  const dependencies = { MediaItem, PlaybackQueueItem: Queue, ProviderPlaybackResolver: class {},
    ProviderRegistry: { async get() { calls.providers++; if (state.gateProvider) await state.gateProvider.promise;
      return state.unavailable ? null : provider; } },
    PlaybackSessionManager: { getInstance: () => ({ create(...args) { calls.sessions.push(args); return 'session'; },
      release(id) { calls.releases.push(id); } }) }, Logger: class { info(...args) { calls.logs.push(args); } warn(...args) { calls.logs.push(args); } } };
  const Launcher = new Function(...Object.keys(dependencies), compile(read('services/ProviderPlaybackLauncher.ets')) +
    ';return ProviderPlaybackLauncher;')(...Object.values(dependencies));
  const context = { getHostContext: () => ({}), getRouter: () => ({ async pushUrl(route) {
    calls.routes.push(route); if (state.routeFailure) throw new Error('route failed');
  } }) };
  const open = () => Launcher.openById(context, 'cat-a', 'episode-a', 17500, false, () => state.current);
  return { calls, state, Launcher, context, provider, item, open };
}

test('history launch keeps one provider, the selected episode and position through player navigation', async () => {
  const f = fixture(); await f.open();
  assert.equal(f.calls.providers, 1); assert.equal(f.calls.items, 1); assert.equal(f.calls.resolves, 1);
  assert.equal(f.calls.sessions.length, 1);
  assert.equal(f.calls.sessions[0][0].queue[0].positionMs, 17500);
  assert.equal(f.calls.sessions[0][0].queue[0].allowVariantFallback, true);
  assert.deepEqual(f.calls.routes[0], { url: 'pages/player/PlayerPage', params: { sessionId: 'session',
    sourceId: 'cat-a', mediaId: 'episode-a', variantId: 'road', positionMs: 17500 } });
});

test('leaving during provider, history or stream resolution never creates or navigates to a stale player', async () => {
  for (const stage of ['gateProvider', 'gateItem', 'gateResolve']) {
    const f = fixture(); const gate = defer(); f.state[stage] = gate;
    const pending = f.open(); for (let i = 0; i < 6; i++) await Promise.resolve();
    f.state.current = false; gate.resolve();
    await assert.rejects(pending, /播放准备已取消/);
    assert.equal(f.calls.sessions.length, 0, stage); assert.equal(f.calls.routes.length, 0, stage);
  }
});

test('missing items, provider and stream errors remain retryable and diagnostics omit IDs, addresses and secrets', async () => {
  for (const failure of ['unavailable', 'missing', 'failResolve', 'wrongIdentity']) {
    const f = fixture(); f.state[failure] = true; await assert.rejects(f.open());
    assert.equal(f.calls.sessions.length, 0); assert.equal(f.calls.routes.length, 0);
    assert.ok(f.calls.logs.some(args => args[0].includes('history_open_failed')));
    assert.ok(f.calls.logs.every(args => !/private|episode-a|cat-a|http|token/.test(JSON.stringify(args))));
    f.state[failure] = false; await f.open(); assert.equal(f.calls.routes.length, 1);
  }
});

test('failed navigation releases the created session and an ordinary launcher retains default behavior', async () => {
  const f = fixture(); f.state.routeFailure = true; await assert.rejects(f.open(), /route failed/);
  assert.deepEqual(f.calls.releases, ['session']); f.state.routeFailure = false;
  await f.Launcher.openWithProvider(f.context, f.provider, f.item); assert.equal(f.calls.routes.length, 2);
  assert.equal(f.calls.sessions.at(-1)[0].queue[0].allowVariantFallback, false);
});

test('prepared source groups supply the full startup queue without losing the latest resume point or line', () => {
  const f = fixture();
  const selected = { sourceId: 'cat-a', mediaId: 'episode-a', variantId: 'road', positionMs: 17500 };
  const next = { sourceId: 'cat-a', mediaId: 'episode-b', variantId: 'road' };
  const fallback = [selected];
  const session = { episodeGroups: [{ id: 'road', items: [
    { ...selected, positionMs: 0 }, null, [], next, next,
    { ...next, sourceId: 'foreign' }, { ...next, mediaId: 'wrong-line', variantId: 'another' }
  ] }] };
  const queue = f.Launcher.preparedQueue(session, fallback, selected);
  assert.deepEqual(queue, [selected, next]); assert.equal(queue[0], selected);
  assert.equal(f.Launcher.preparedQueue({ episodeGroups: [{ id: 'road', items: [next] }] }, fallback, selected), fallback);
  assert.equal(f.Launcher.preparedQueue({ episodeGroups: [null] }, fallback, selected), fallback);
});

function pageFixture() {
  const source = read('pages/catvod/CatVodContent.ets');
  const start = source.indexOf('  private async playHistory(');
  const method = source.slice(start, source.indexOf('\n}\n', start));
  const calls = { opens: [], toasts: [] }; const state = { gate: null, failure: false };
  const Page = new Function('ProviderPlaybackLauncher', 'buildDetailToastOptions', '$r',
    compile('class Page { ' + method + ' }') + ';return Page;')({ async openById(...args) {
    calls.opens.push(args); if (state.gate) await state.gate.promise; if (state.failure) throw new Error('来源未返回播放地址');
  } }, text => ({ message: text }), text => text);
  const page = Object.assign(new Page(), { alive: true, isActive: true, generation: 1, historyRequest: 0,
    source: { id: 'cat' }, playingHistory: false, historyOpeningId: '', historyError: '', label: text => text,
    getUIContext: () => ({ getPromptAction: () => ({ showToast: options => calls.toasts.push(options.message) }) }) });
  return { page, state, calls };
}

test('history card shows the selected loading state immediately, blocks duplicate clicks, exposes errors and unlocks retry', async () => {
  const f = pageFixture(); const item = { id: 'episode', positionMs: 17000 };
  f.state.gate = defer(); const pending = f.page.playHistory(item);
  assert.equal(f.page.playingHistory, true); assert.equal(f.page.historyOpeningId, item.id);
  await f.page.playHistory(item); assert.equal(f.calls.opens.length, 1);
  f.state.failure = true; f.state.gate.resolve(); await pending;
  assert.equal(f.page.playingHistory, false); assert.equal(f.page.historyOpeningId, '');
  assert.equal(f.page.historyError, '来源未返回播放地址'); assert.equal(f.calls.toasts.length, 1);
  f.state.gate = null; f.state.failure = false; await f.page.playHistory(item); assert.equal(f.page.historyError, '');
  assert.equal(f.calls.opens.length, 2);
});

test('old history errors cannot overwrite a newer page and history navigation guard tracks page activity', async () => {
  const f = pageFixture(); f.state.gate = defer(); const pending = f.page.playHistory({ id: 'old', positionMs: 1000 });
  const canOpen = f.calls.opens[0][5]; assert.equal(canOpen(), true);
  f.page.isActive = false; assert.equal(canOpen(), false); f.page.isActive = true;
  f.page.historyRequest++; f.page.historyOpeningId = 'new'; f.page.playingHistory = true;
  f.state.failure = true; f.state.gate.resolve(); await pending;
  assert.equal(f.page.historyOpeningId, 'new'); assert.equal(f.page.playingHistory, true);
  assert.equal(f.page.historyError, ''); assert.equal(f.calls.toasts.length, 0); assert.equal(canOpen(), false);
});
