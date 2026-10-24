import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { test } from 'node:test';

const read = name => readFileSync(new URL('../entry/src/main/ets/' + name, import.meta.url), 'utf8').replaceAll('\r\n', '\n');
const source = read('pages/local/ContinueWatchingPage.ets');
const cat = read('pages/catvod/CatVodContent.ets');
const method = (text, name) => {
  const start = text.search(new RegExp('^  (?:private )?(?:async )?' + name + '\\(', 'm'));
  assert.ok(start >= 0, name);
  return text.slice(start, text.indexOf('\n  }', start) + 4);
};
const compile = text => stripTypeScriptTypes(text, { mode: 'transform' });
const pure = text => compile(text.replace(/^import .*\n/gm, '').replace(/^export /gm, ''));
const Scope = new Function(pure(read('providers/catvod/CatVodModels.ets')) + '\n' +
  pure(read('providers/catvod/CatVodCodec.ets')) + '\n' + pure(read('providers/catvod/CatPlaybackHistoryScope.ets')) +
  ';return CatPlaybackHistoryScope;')();
const scopedId = key => 'catvod|' + encodeURIComponent('catnode:' + encodeURIComponent(key) + ':work') + '|episode|0';
const deferred = () => { let resolve; const promise = new Promise(done => { resolve = done; }); return { promise, resolve }; };
const record = (sourceId, mediaId, lastPlayedAt = 1) => ({ sourceId, mediaId, key: sourceId + ':' + mediaId,
  positionMs: 10000, durationMs: 60000, completed: false, artworkUrl: '', lastPlayedAt, remoteRecordId: 1 });

function fixture() {
  const state = { all: [], gate: null, frame: 'file://exit-frame.jpg', launches: [], removed: [], toasts: [], params: {}, sourceType: 'catvod' };
  const ctx = { getHostContext: () => ({ resourceManager: { getStringSync: id => id } }),
    getPromptAction: () => ({ showToast: value => state.toasts.push(value) }) };
  const body = ['aboutToAppear', 'reloadHistory', 'isCompleted', 'removeMissingSelections', 'exitEditMode',
    'buildHistoryTitleBarOptions', 'openRecord', 'handleRecordTap', 'toggleSelect', 'isSelected', 'deleteSelectedRecords']
    .map(name => method(source, name)).join('\n');
  const Page = new Function('MediaSourceStore', 'ResumeFrameStore', 'getContext', 'logger', 'ProviderPlaybackLauncher',
    'buildTitleBarOptions', '$r', 'router', 'COMPLETED_THRESHOLD', 'CatPlaybackHistoryScope', 'CatNodeSubscriptionCodec',
    compile('class Page {\n' + body + '\n}\n') + ';return Page;')(
    { async getAll() { return [{ id: 'cat', name: '猫源订阅', enabled: true, providerType: state.sourceType, configJson: '{}' }, { id: 'disabled', enabled: false },
      { id: 'other', name: '其他来源', enabled: true }]; } },
    { async resolve() { return state.frame; } }, () => ctx.getHostContext(), { warn() {} },
    { async openById(...args) { state.launches.push(args); if (state.gate) await state.gate.promise; } },
    title => ({ title }), name => ({ id: name }), { getParams: () => state.params }, 0.995, Scope,
    { decode: text => JSON.parse(text) });
  const page = Object.assign(new Page(), { appRdbReady: true, resumeLayout: true, sourceFilter: 'cat', records: [],
    reloadGeneration: 0, sourceNames: {}, spiderFilter: '', scopeName: '', selectedIds: [], isEditMode: false, openingRecordKey: '',
    historyLoading: true, hdsMaterialLevel: 'regular', getUIContext: () => ctx,
    historyRepository: { async getAll() { return state.all; }, async resolveArtwork(items) {
      for (const item of items) item.artworkUrl = 'https://poster.invalid/a.jpg';
    } }, unifiedHistoryStore: { async deleteById(id) { state.removed.push(id); } }
  });
  return { page, state };
}

test('cat arrow opens the source-scoped resume layout and serializes repeated navigation', async () => {
  const Open = new Function('buildDetailToastOptions', '$r', compile('class Open {\n' +
    method(cat, 'openContinueWatching') + '\n}\n') + ';return Open;')(value => value, value => value);
  const gate = deferred(); const routes = [];
  const opener = Object.assign(new Open(), { source: { id: 'cat', name: '猫源订阅', providerType: 'catnode' },
    nodeSiteKey: 'site-a', nodeSites: [{ key: 'site-a', name: '目录 A' }], playingHistory: false, openingHistoryPage: false,
    getUIContext: () => ({ getRouter: () => ({ async pushUrl(route) { routes.push(route); await gate.promise; } }) }) });
  const first = opener.openContinueWatching(); await opener.openContinueWatching();
  assert.deepEqual(routes, [{ url: 'pages/local/ContinueWatchingPage',
    params: { view: 'continue', sourceId: 'cat', spiderKey: 'site-a', scopeName: '目录 A' } }]);
  gate.resolve(); await first; assert.equal(opener.openingHistoryPage, false);
});

test('catalogs within a subscription remain isolated from one another and from Emby records', async () => {
  const { page, state } = fixture(); page.spiderFilter = '目录 A'; state.sourceType = 'catnode';
  state.all = [record('cat', scopedId('目录 A')), record('cat', scopedId('目录 B')),
    record('other', scopedId('目录 A')), record('other', 'emby-video'), record('cat', 'catvod|old-work|episode|0')];
  await page.reloadHistory();
  assert.equal(page.records.length, 1); assert.equal(page.records[0].mediaId, scopedId('目录 A'));
  assert.equal(Scope.matches('catvod|old-work|episode|0', '目录 A', '目录 A'), true);
  assert.equal(Scope.matches('catvod|old-work|episode|0', '目录 B', '目录 A'), false);
  assert.equal(Scope.matches('catvod|catnode%3A%25ZZ%3Awork|episode|0', '目录 A'), false);
});

test('missing source or Node catalog scope never falls back to a merged resume list', async () => {
  const { page, state } = fixture(); state.all = [record('cat', scopedId('a')), record('other', 'emby-video')];
  page.sourceFilter = ''; await page.reloadHistory(); assert.equal(page.records.length, 0);
  page.sourceFilter = 'cat'; state.sourceType = 'catnode'; await page.reloadHistory(); assert.equal(page.records.length, 0);
});

test('Node provider filters its catalog before applying the home-card limit', async () => {
  const items = [{ id: scopedId('b') }, { id: scopedId('a') }, { id: scopedId('a') }];
  const Parent = class { async getResumeItems() { return items; } };
  const Provider = new Function('Parent', 'CatPlaybackHistoryScope',
    compile('class Provider extends Parent {\n' + method(read('providers/catvod/CatNodeProvider.ets'), 'getResumeItems') +
      '\n}\n') + ';return Provider;')(Parent, Scope);
  const provider = Object.assign(new Provider(), { getSiteKey: () => 'a', nodeConfig: { legacySpiderKey: '' } });
  assert.deepEqual(await provider.getResumeItems(1), [items[1]]);
  assert.equal((await provider.getResumeItems()).length, 2);
});

test('resume list uses all unfinished records from the selected enabled source and prefers exit frames', async () => {
  const { page, state } = fixture();
  state.all = [record('cat', 'older', 1), record('other', 'hidden', 5), record('disabled', 'hidden', 6),
    { ...record('cat', 'finished', 8), completed: true }, record('cat', 'newer', 3)];
  await page.reloadHistory();
  assert.deepEqual(page.records.map(item => item.mediaId), ['newer', 'older']);
  assert.equal(page.records[0].artworkUrl, state.frame); assert.equal(page.sourceNames.cat, '猫源订阅');
  assert.equal(page.historyLoading, false);
  state.frame = ''; await page.reloadHistory(); assert.equal(page.records[0].artworkUrl, 'https://poster.invalid/a.jpg');
});

test('ordinary history route keeps other enabled sources and completed records', async () => {
  const { page, state } = fixture(); page.resumeLayout = false;
  state.all = [record('cat', 'one'), record('other', 'two'), { ...record('cat', 'three'), completed: true }];
  await page.reloadHistory(); assert.equal(page.records.length, 3);
  assert.equal(page.buildHistoryTitleBarOptions().content.title.mainTitle, '播放历史');
});

test('resume toolbar enters selective deletion; it never clears another source history', async () => {
  const { page, state } = fixture(); state.all = [record('cat', 'one'), record('other', 'two')];
  await page.reloadHistory(); const toolbar = page.buildHistoryTitleBarOptions();
  assert.equal(toolbar.content.title.mainTitle, 'app.string.continue_watching_title');
  assert.equal(toolbar.content.menu.value[0].content.icon.id, 'sys.symbol.trash');
  toolbar.content.menu.value[0].content.action(); assert.equal(page.isEditMode, true);
  page.handleRecordTap(page.records[0]); assert.equal(state.launches.length, 0);
  await page.deleteSelectedRecords(); assert.deepEqual(state.removed, [1]); assert.equal(page.records.length, 0);
});

test('resume opens the stored source, episode and position once while preparation is pending', async () => {
  const { page, state } = fixture(); const item = record('cat', 'episode'); state.gate = deferred();
  const first = page.openRecord(item); await page.openRecord(item);
  assert.equal(state.launches.length, 1); assert.deepEqual(state.launches[0].slice(1), ['cat', 'episode', 10000, false]);
  state.gate.resolve(); await first; assert.equal(page.openingRecordKey, '');
});
