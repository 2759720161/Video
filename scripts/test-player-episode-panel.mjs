import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { test } from 'node:test';
const read = path => readFileSync(new URL('../entry/src/main/ets/' + path, import.meta.url), 'utf8');
const compile = source => stripTypeScriptTypes(source.replace(/^import .*\r?\n/gm, '').replace(/export /g, ''), { mode: 'transform' });
const QueueItem = new Function(compile(read('core/playback/PlaybackQueueItem.ets')) + ';return PlaybackQueueItem;')();
const Presentation = new Function('PlaybackQueueItem', compile(read('components/player/PlayerEpisodePresentation.ets')) +
  ';return PlayerEpisodePresentation;')(QueueItem);
const source = read('pages/player/PlayerPage.ets');
function method(name) {
  const pattern = new RegExp('  private (?:async )?' + name + '\\(');
  const start = source.search(pattern); assert.ok(start >= 0, name);
  const end = source.indexOf('\n  }', start); return source.slice(start, end + 4);
}
const methods = ['episodePanelTitle', 'openPlaybackQueue', 'closePlaybackQueue', 'selectQueueEpisode',
  'selectQueueVariant', 'selectQueueGroupEpisode', 'currentQueueItem', 'currentPlaybackVariantSources', 'selectPlaybackVariant',
  'playQueueItem', 'handleBackFromPlayer', 'startAutoHideTimer', 'shouldDisablePlayerGestures'].map(method).join('\n');
const deferred = () => { let resolve, reject; const promise = new Promise((ok, fail) => { resolve = ok; reject = fail; });
  return { promise, resolve, reject }; };
const item = (id, subtitle = id) => Object.assign(new QueueItem(), { sourceId: 'source', mediaId: id, title: '作品', subtitle,
  variantId: 'a', variants: [{ id: 'a', name: '线路 A' }, { id: 'b', name: '线路 B' }] });
function fixture() {
  const dialogs = [], updates = [], hud = [], events = [];
  const gate = deferred();
  const controls = { resolve: () => gate.promise, allowed: true };
  const resolver = { resolvePlayback: value => controls.resolve(value), createReporterForSession: () => null };
  const manager = { getResolver: () => resolver, get: () => ({}), update: value => updates.push(value),
    replaceReporter() {}, getReportController: () => null };
  const Harness = new Function('PlaybackQueueItem', 'PlayerEpisodePresentation', 'CustomDialogController',
    'PlayerEpisodePanel', 'buildDetailDialogOptions', 'DialogAlignment', '$r', 'logger',
    'PlaybackOptionsAdapter', 'setTimeout',
    'const $playbackQueue=[], $episodeGroups=[], $currentQueueIndex=0, $episodeSwitching=false, $queuePanelError="";\n' +
    compile('class PlayerPage { static normalizeText(value) { return typeof value === "string" ? value.trim() : ""; }' + methods + '}') +
    ';return PlayerPage;')(QueueItem, Presentation,
      class { constructor(options) { this.options = options; dialogs.push(this); } open() { this.opened = true; }
        close() { this.closed = true; } }, options => options, (_thickness, options) => options,
      { CenterEnd: 'right', Bottom: 'bottom' }, value => ({ id: value }), { warn() {}, info() {} },
      { fromStream: (stream, position) => ({ url: stream.url, position }) }, () => { events.push('timer'); return 1; });
  const page = Object.assign(new Harness(), { isPageAlive: true, pageVisible: true, showPlaybackQueue: false,
    isControlVisible: true, isAnimatingFullscreen: false, hideBottomControlsForFullscreenTransition: false,
    isFullScreen: true, materialThickness: 'thin', episodeDialogGeneration: 0, episodeDialog: null,
    episodeSwitching: false, queuePanelError: '', episodeGroups: [], playbackQueue: [item('one'), item('two')], currentQueueIndex: 0,
    queueResolveToken: 0, sessionId: 'session', session: { media: { sourceId: 'source', mediaId: 'one' } },
    sessionManager: manager, handedToTypeNodePiP: false, positionMs: 12345, durationMs: 60000, speed: 1,
    isPlayerControlActionAllowed: () => controls.allowed, pauseAutoHideTimer: () => events.push('pauseTimer'),
    showControlsWithAutoHide: () => events.push('controls'), toggleFullScreen: () => events.push('rotate'),
    getUIContext: () => ({ getHostContext: () => ({ resourceManager: { getStringSync: value => value } }) }),
    captureCurrentQueueProgress: () => events.push('capture'), saveLocalHistory: async () => events.push('history'),
    normalizeResumePosition: value => value, clearLivePlaybackPosition() {}, setSubtitleMenuSelection() {},
    stopExternalSubtitleClock() {}, clearDanmakuState() {}, withPlaybackIdentity: value => value,
    syncPlaybackSessionMedia() {}, refreshPlaybackQueue: async () => events.push('refresh'),
    showHudText: message => hud.push(message),
    applySession(value) { this.session = value; this.playbackQueue = value.queue; this.currentQueueIndex = value.queueIndex; }
  });
  const next = (id = 'two') => ({ media: { sourceId: 'source', mediaId: id }, stream: { url: 'https://media.invalid/' + id },
    startPositionMs: 0, durationMs: 60000 });
  return { page, dialogs, updates, hud, events, controls, gate, next };
}

test('reversing displayed indices preserves queue order and original selection identity', () => {
  for (const length of [0, 1, 2, 73]) {
    const indices = Presentation.indices(length, true);
    assert.equal(indices.length, length); assert.deepEqual(indices.slice().reverse(), Presentation.indices(length, false));
  }
  assert.equal(Presentation.label(item('id', '第 12 集')), '第 12 集');
  assert.equal(Presentation.label(item('id', ' ')), '作品');
});

test('browsing a different episode group does not change playback and highlights only the actual line/media identity', () => {
  const panel = read('components/player/PlayerEpisodePanel.ets');
  const extract = name => {
    const start = panel.indexOf('  private ' + name + '('); assert.ok(start >= 0);
    const brace = panel.indexOf('{', start); let depth = 1, end = brace + 1;
    for (; depth > 0; end++) { if (panel[end] === '{') depth++; if (panel[end] === '}') depth--; }
    return panel.slice(start, end);
  };
  const Panel = new Function(compile('class Panel {' + ['current', 'visibleGroup', 'visibleQueue', 'isPlaying'].map(extract).join('\n') + '}') + ';return Panel;')();
  const active = item('one'), alternate = Object.assign(item('one', '另一线路文件'), { variantId: 'b' });
  const instance = Object.assign(new Panel(), { queue: [active], currentIndex: 0, browsedGroupId: '',
    groups: [{ id: 'a', items: [active] }, { id: 'b', items: [alternate] }] });
  assert.equal(instance.visibleQueue()[0], active); assert.equal(instance.isPlaying(active), true);
  instance.browsedGroupId = 'b'; assert.equal(instance.visibleQueue()[0], alternate);
  assert.equal(instance.isPlaying(alternate), false); assert.equal(instance.current(), active);
  instance.groups = []; assert.equal(instance.visibleQueue(), instance.queue);
});

test('variant requests copy stable identity and progress without mutating the active queue', () => {
  const original = Object.assign(item('one'), { artwork: 'poster', artworkRef: 'ref', durationMs: 60000,
    positionMs: 50, startFromBeginning: true, trackSelection: { audioId: 'audio' } });
  const before = JSON.stringify(original); const copy = Presentation.withVariant(original, 'b', 12345.9);
  assert.equal(JSON.stringify(original), before); assert.equal(copy.mediaId, 'one'); assert.equal(copy.variantId, 'b');
  assert.equal(copy.positionMs, 12345); assert.equal(copy.trackSelection, null); assert.equal(copy.startFromBeginning, false);
  assert.equal(copy.artworkRef, 'ref'); assert.notEqual(copy.variants, original.variants);
});

test('native panel opens on the right or bottom with customStyle disabled and blocks duplicate/hidden actions', () => {
  for (const landscape of [true, false]) {
    const f = fixture(); f.page.isFullScreen = landscape; f.page.openPlaybackQueue(); f.page.openPlaybackQueue();
    assert.equal(f.dialogs.length, 1); assert.equal(f.dialogs[0].options.customStyle, false);
    assert.equal(f.dialogs[0].options.alignment, landscape ? 'right' : 'bottom');
    assert.equal(f.page.showPlaybackQueue, true); assert.equal(f.page.shouldDisablePlayerGestures(), true);
    f.page.startAutoHideTimer(); assert.ok(!f.events.includes('timer'));
  }
  const f = fixture(); f.controls.allowed = false; f.page.openPlaybackQueue(); assert.equal(f.dialogs.length, 0);
});

test('back dismisses the panel before rotating; late dismissal cannot close a reopened panel', () => {
  const f = fixture(); f.page.openPlaybackQueue(); const old = f.dialogs[0];
  assert.equal(f.page.handleBackFromPlayer(), true); assert.equal(old.closed, true); assert.ok(!f.events.includes('rotate'));
  f.page.openPlaybackQueue(); old.options.onDidDisappear();
  assert.equal(f.page.showPlaybackQueue, true); assert.equal(f.page.episodeDialog, f.dialogs[1]);
  f.dialogs[1].options.onDidDisappear(); assert.equal(f.page.showPlaybackQueue, false);
});

test('selecting the current item closes without re-resolving or restarting playback', async () => {
  const f = fixture(); f.page.openPlaybackQueue(); await f.page.selectQueueEpisode(0);
  assert.equal(f.page.showPlaybackQueue, false); assert.equal(f.page.queueResolveToken, 0); assert.equal(f.updates.length, 0);
});

test('episode selection serializes requests and commits a valid session before dismissing', async () => {
  const f = fixture(); f.page.openPlaybackQueue(); const run = f.page.selectQueueEpisode(1);
  assert.equal(f.page.episodeSwitching, true); await f.page.selectQueueEpisode(1);
  assert.equal(f.page.queueResolveToken, 1); f.gate.resolve(f.next()); await run;
  assert.equal(f.updates.length, 1); assert.equal(f.page.currentQueueIndex, 1);
  assert.equal(f.page.showPlaybackQueue, false); assert.equal(f.page.episodeSwitching, false);
  assert.deepEqual(f.events.filter(value => ['capture', 'history'].includes(value)), ['capture', 'history']);
});

test('failed or mismatched resolution preserves the current episode and reports an error inside the panel', async () => {
  for (const mismatch of [false, true]) {
    const f = fixture(); f.page.openPlaybackQueue(); const old = f.page.playbackQueue;
    const run = f.page.selectQueueEpisode(1);
    if (mismatch) f.gate.resolve(f.next('other')); else f.gate.reject(new Error('来源请求失败'));
    await run; assert.equal(f.page.playbackQueue, old); assert.equal(f.page.currentQueueIndex, 0);
    assert.equal(f.page.showPlaybackQueue, true); assert.equal(f.updates.length, 0);
    assert.ok(f.page.queuePanelError.length > 0); assert.equal(f.page.episodeSwitching, false);
  }
});

test('line switch failure preserves the active variant, while success commits its copy and refreshes the queue', async () => {
  for (const success of [false, true]) {
    const f = fixture(); f.page.openPlaybackQueue(); const original = f.page.playbackQueue[0];
    const run = f.page.selectQueueVariant('b');
    assert.equal(original.variantId, 'a');
    if (success) f.gate.resolve(f.next('one')); else f.gate.reject(new Error('线路不可用'));
    await run; assert.equal(original.variantId, 'a');
    assert.equal(f.page.playbackQueue[0].variantId, success ? 'b' : 'a');
    assert.equal(f.events.includes('refresh'), success);
  }
});

test('unknown lines and stale page resolution cannot alter the current playback', async () => {
  const f = fixture(); f.page.openPlaybackQueue(); await f.page.selectQueueVariant('invented');
  assert.equal(f.page.queueResolveToken, 0);
  const run = f.page.selectQueueEpisode(1); f.page.isPageAlive = false; f.page.queueResolveToken++;
  f.gate.resolve(f.next()); await run; assert.equal(f.updates.length, 0);
});

test('another line can expose differently named episodes and commits its own complete queue only after selection succeeds', async () => {
  const f = fixture(); f.page.openPlaybackQueue();
  const alternate = [Object.assign(item('alternate-one', '原画版本'), { variantId: 'b' }),
    Object.assign(item('alternate-two', '另一版本'), { variantId: 'b' })];
  f.page.episodeGroups = [{ id: 'b', name: '另一线路', items: alternate }];
  const oldQueue = f.page.playbackQueue; const run = f.page.selectQueueGroupEpisode('b', 1);
  assert.equal(f.page.playbackQueue, oldQueue); assert.equal(f.page.currentQueueIndex, 0);
  f.gate.resolve(f.next('alternate-two')); await run;
  assert.equal(f.page.playbackQueue.length, 2); assert.equal(f.page.playbackQueue[0].mediaId, 'alternate-one');
  assert.equal(f.page.playbackQueue[1].variantId, 'b'); assert.equal(f.page.currentQueueIndex, 1);
});

test('failed group playback and wrong-source groups preserve playback and provider-mutated requests never alter active items', async () => {
  const f = fixture(); f.page.openPlaybackQueue(); const original = f.page.playbackQueue[0];
  f.controls.resolve = async value => { value.variantId = 'mutated'; throw new Error('来源不可用'); };
  f.page.episodeGroups = [{ id: 'a', items: [original, item('another')] }];
  await f.page.selectQueueGroupEpisode('a', 1);
  assert.equal(original.variantId, 'a'); assert.equal(f.page.episodeGroups[0].items[1].variantId, 'a');
  assert.equal(f.page.currentQueueIndex, 0); assert.equal(f.updates.length, 0);
  f.page.episodeGroups = [{ id: 'foreign', items: [Object.assign(item('foreign'), { sourceId: 'other' })] }];
  await f.page.selectQueueGroupEpisode('foreign', 0); assert.equal(f.updates.length, 0);
});
