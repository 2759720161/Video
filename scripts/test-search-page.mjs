import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { test } from 'node:test';

const read = path => readFileSync(new URL('../entry/src/main/ets/' + path, import.meta.url), 'utf8');
const compile = text => stripTypeScriptTypes(text.replace(/^import .*\r?\n/gm, '').replace(/export /g, ''), { mode: 'transform' });
const presentation = new Function(compile(read('services/media/MediaSearchPresentation.ets')) +
  ';return { Item: MediaSearchItem, Page: MediaSearchPage, Presentation: MediaSearchPresentation };')();
const { Item, Page, Presentation } = presentation;
const item = (id, title = id, year = 0) => Object.assign(new Item(), { id, title, year });
const result = (items, page = 1, pageCount = page) => Object.assign(new Page(), { items, page, pageCount });
const deferred = () => { let resolve, reject; const promise = new Promise((ok, fail) => { resolve = ok; reject = fail; }); return { promise, resolve, reject }; };

class Emby {
  constructor(values = []) { this.values = values; this.requests = []; }
  async searchRaw(word) { this.requests.push(word); return this.values; }
  imageUrlFor(value, width) { return 'https://images.test/' + value.id + '?w=' + width; }
}
class Cat {
  constructor(page) { this.fetch = page; this.requests = []; }
  getClient() { return { page: async (...args) => { this.requests.push(args); return this.fetch(...args); } }; }
}
class NodeCat extends Cat {
  getSiteKey() { return this.key; }
  async sites() { return [{ key: 'a', name: '目录 A' }, { key: 'b', name: '目录 B' },
    { key: 'index', name: '任意推荐目录', indexOnly: true },
    { key: 'off', name: '配置', searchable: false }]; }
  searchClient(key) { return { page: async (...args) => { this.requests.push([key, ...args]); return this.fetch(...args); } }; }
}

test('index metadata excludes recommendation-only directories from playback search without changing the home directory', async () => {
  const backend = new NodeCat(async () => ({ videos: [], page: 1, pageCount: 1 })); backend.key = 'index';
  const session = await open(backend);
  assert.equal(session.canSearch, false); assert.deepEqual(session.scopes.map(site => site.key), ['a', 'b']);
  await assert.rejects(session.search('影片'), /不提供搜索/); assert.equal(backend.requests.length, 0);
  assert.equal(session.forScope('b').canSearch, true); assert.equal(backend.key, 'index');
});
let source = { id: 'source', name: '我的服务', enabled: true }, provider;
const Session = new Function('EmbyProvider', 'CatVodProvider', 'CatNodeProvider', 'MediaSourceStore', 'ProviderRegistry',
  'MediaSearchItem', 'MediaSearchPage', 'MediaSearchPresentation',
  compile(read('services/media/MediaSearchSession.ets')) + ';return MediaSearchSession;')(
  Emby, Cat, NodeCat, { getById: async () => source }, { get: async () => provider }, Item, Page, Presentation);
const open = async value => { provider = value; source = { id: 'source', name: '我的服务', enabled: true }; return Session.open('source', {}); };

const pageSource = read('pages/home/SearchPage.ets');
const lifecycle = pageSource.slice(pageSource.indexOf('  aboutToAppear()'), pageSource.indexOf('  private label('));
const methods = (lifecycle + pageSource.slice(pageSource.indexOf('  private label('), pageSource.indexOf('  private titleOptions(')))
  .replace(/  @Builder\r?\n  private DirectoryMenu\(\): void \{[\s\S]*?\r?\n  \}\r?\n/, '');
class CatNodeSearchUnavailableError extends Error {}
const { Control } = new Function(compile(read('providers/catvod/CatNodeRequestControl.ets')) + ';return { Control: CatNodeRequestControl };')();
const ScopeSelection = new Function(compile(read('services/media/MediaSearchScopeSelection.ets')) + ';return MediaSearchScopeSelection;')();
const { Aggregate, AggregateState, ALL } = new Function('CatNodeSearchUnavailableError', 'CatNodeRequestControl',
  'MediaSearchPresentation', 'MediaSearchScopeSelection', compile(read('services/media/MediaSearchAggregate.ets')) +
  ';return { Aggregate: MediaSearchAggregate, AggregateState: MediaSearchAggregateState, ALL: MEDIA_SEARCH_ALL };')(
  CatNodeSearchUnavailableError, Control, Presentation, ScopeSelection);
function fixture(session = { scopeName: '目录 A', historyKey: 'scope-a', scopes: [], search: async () => result([]) }) {
  const writes = [], toasts = [], routes = [], edges = [], tasks = [], values = new Map(), timers = new Map();
  let timerId = 0;
  const controls = { open: async () => session, writeError: false, writeWait: null, params: {} };
  const preferences = { getString: async (key, fallback) => values.get(key) ?? fallback,
    setStringStrict: async (key, value) => {
      if (controls.writeWait) await controls.writeWait;
      if (controls.writeError) throw new Error('disk'); writes.push([key, value]); values.set(key, value);
    } };
  const Harness = new Function('MediaSearchSession', 'MediaSearchPresentation', 'PreferencesStore', '$r', 'Edge',
    'buildDetailToastOptions', 'buildEmbyDetailRouteParams', 'CatNodeSearchUnavailableError', 'hilog',
    'MediaSearchAggregate', 'MediaSearchAggregateState', 'MEDIA_SEARCH_ALL', 'MediaSearchScopeSelection',
    'setTimeout', 'clearTimeout', stripTypeScriptTypes(`class Harness { ${methods} }`,
      { mode: 'transform' }) + ';return Harness;')({ open: async (...args) => {
        const session = await controls.open(...args); session.scopes ??= []; return session;
      } }, Presentation,
      { getInstance: () => preferences }, id => ({ id }), { Top: 'top' }, message => ({ message }),
      (sourceId, raw, transitionId, artworkUrl) => ({ sourceId, raw, transitionId, artworkUrl }),
      CatNodeSearchUnavailableError, { info() {}, warn() {} }, Aggregate, AggregateState, ALL, ScopeSelection,
      (callback, delay) => { const id = ++timerId; timers.set(id, { callback, delay }); return id; }, id => timers.delete(id));
  const page = Object.assign(new Harness(), { session, sourceId: 'source', generation: 0, initGeneration: 0, alive: true,
    initializing: false, searching: false, paging: false, query: '', submittedQuery: '', items: [], displayedItems: [],
    history: [], historyKey: session?.historyKey ?? '', scopeName: '', scopes: session?.scopes ?? [], page: 0, pageCount: 1, pageError: '', error: '',
    managingHistory: false, order: 'default', listMode: false, measuredWidth: 0, screenWidth: 360, visibleLimit: 60,
    aggregateMode: false, aggregate: null, aggregateState: new AggregateState(), aggregateStopped: false,
    selectedScopeKeys: (session?.scopes ?? []).map(site => site.key), draftScopeKeys: [], scopeFilter: '',
    showScopeSettings: false, scopeSaving: false, scopeSaveError: '',
    showDirectoryMenu: false,
    pageVisible: true, seedTicket: 0, seedTimer: -1, initialSearchPending: false,
    scroller: { scrollEdge: edge => edges.push(edge) },
    getUIContext: () => ({
      getHostContext: () => ({ resourceManager: { getStringSync: id => id } }),
      getPromptAction: () => ({ showToast: options => toasts.push(options.message) }),
      getRouter: () => ({ pushUrl: route => routes.push(route), getParams: () => controls.params }) }) });
  const run = page.runSearch.bind(page);
  page.runSearch = (...args) => { const task = run(...args); tasks.push(task); return task; };
  const fireTimers = () => { for (const [id, timer] of Array.from(timers)) { timers.delete(id); timer.callback(); } };
  return { page, controls, values, writes, toasts, routes, edges, tasks, timers, fireTimers,
    drain: async () => { fireTimers(); await Promise.all(tasks); await Promise.resolve(); } };
}

test('history parser accepts text only, normalizes whitespace and caps unique entries at twenty', () => {
  assert.deepEqual(Presentation.history('bad json'), []);
  assert.deepEqual(Presentation.history('{}'), []);
  assert.deepEqual(Presentation.history(JSON.stringify([null, 2, {}, '', '  三  体 ', '三 体', '流浪地球'])), ['三 体', '流浪地球']);
  let history = [];
  for (let index = 0; index < 30; index++) history = Presentation.remember(history, '词' + index);
  assert.equal(history.length, 20);
  assert.equal(Presentation.remember(history, ' 词15 ')[0], '词15');
  assert.equal(Presentation.remember(history, '词15').filter(value => value === '词15').length, 1);
});

test('seeded search waits for saved single-directory preferences and never changes the home scope', async () => {
  const backend = new NodeCat(async () => ({ videos: [], page: 1, pageCount: 1 })); backend.key = 'index';
  const f = fixture(await open(backend));
  f.values.set(f.page.scopePreferenceKey(), 'b');
  f.page.query = '  影片 第一季 '; f.page.initialSearchPending = true;
  await f.page.initialize(); await f.drain();
  assert.equal(f.page.aggregateMode, false); assert.equal(f.page.session.scopeKey, 'b');
  assert.deepEqual(backend.requests, [['b', '', '影片 第一季', 1]]); assert.equal(backend.key, 'index');
  assert.equal(f.page.initialSearchPending, false);
  assert.ok(!f.writes.some(([key]) => [f.page.scopePreferenceKey(), f.page.scopeSelectionPreferenceKey()].includes(key)));
});

test('route keyword is normalized as plain text and malformed parameters never create a seeded query', () => {
  const method = pageSource.slice(pageSource.indexOf('  aboutToAppear()'), pageSource.indexOf('  aboutToDisappear()'));
  const SeedPage = new Function('MediaSearchPresentation', stripTypeScriptTypes(`class SeedPage { ${method} }`) + ';return SeedPage;')(Presentation);
  for (const [keyword, expected] of [['  影片\n 第一季  ', '影片 第一季'], [{ title: '影片' }, ''], [null, '']]) {
    let calls = 0;
    const page = Object.assign(new SeedPage(), { sourceId: '',
      getUIContext: () => ({ getRouter: () => ({ getParams: () => ({ sourceId: 'source', keyword }) }) }),
      initialize() { calls++; } });
    page.aboutToAppear(); assert.equal(page.query, expected); assert.equal(page.initialSearchPending, expected.length > 0);
    assert.equal(page.sourceId, 'source'); assert.equal(calls, 1);
  }
});

test('seeded aggregation uses only the saved subset and an explicit empty subset never expands', async () => {
  for (const subset of [['b'], []]) {
    const backend = new NodeCat(async () => ({ videos: [], page: 1, pageCount: 1 })); backend.key = 'index';
    const f = fixture(await open(backend));
    f.values.set(f.page.scopePreferenceKey(), ALL);
    f.values.set(f.page.scopeSelectionPreferenceKey(), JSON.stringify(subset));
    f.page.query = '影片'; f.page.initialSearchPending = true;
    await f.page.initialize(); await f.drain();
    assert.equal(f.page.aggregateMode, true); assert.deepEqual(f.page.selectedScopeKeys, subset);
    assert.deepEqual(backend.requests.map(args => args[0]), subset);
    if (!subset.length) assert.equal(f.page.error, 'app.string.media_search_scope_minimum');
    assert.ok(!f.writes.some(([key]) => key === f.page.scopeSelectionPreferenceKey()));
  }
});

test('seed on an unsupported saved single scope keeps the keyword and asks for a directory without enabling aggregation', async () => {
  const backend = new NodeCat(async () => ({ videos: [], page: 1, pageCount: 1 })); backend.key = 'index';
  const f = fixture(await open(backend)); f.values.set(f.page.scopePreferenceKey(), 'index');
  f.page.query = '影片'; f.page.initialSearchPending = true;
  await f.page.initialize(); await f.drain();
  assert.equal(f.page.aggregateMode, false); assert.equal(f.page.query, '影片');
  assert.equal(f.page.error, 'app.string.media_search_directory_unavailable'); assert.equal(backend.requests.length, 0);
  assert.equal(f.writes.length, 0);
});

test('typing while scope initialization is pending cancels automatic seed submission', async () => {
  const f = fixture(); const gate = deferred(); f.controls.open = () => gate.promise;
  f.page.query = '推荐影片'; f.page.initialSearchPending = true;
  const task = f.page.initialize(); f.page.editQuery('用户输入');
  gate.resolve({ scopeName: 'scope', historyKey: 'history', scopes: [], search: async () => result([]) });
  await task; await f.drain();
  assert.equal(f.page.query, '用户输入'); assert.equal(f.page.submittedQuery, ''); assert.equal(f.tasks.length, 0);
});

test('seed waits for page visibility and dispatches once without transition or frame callbacks', async () => {
  const f = fixture(); f.page.query = '影片'; f.page.initialSearchPending = true;
  f.page.pageVisible = false;
  await f.page.initialize(); assert.equal(f.timers.size, 0);
  f.page.onPageShow(); assert.equal(f.tasks.length, 0); assert.equal(f.timers.size, 1);
  await f.drain(); assert.equal(f.tasks.length, 1); assert.equal(f.page.submittedQuery, '影片');
  f.page.onPageShow(); await f.drain();
  assert.equal(f.tasks.length, 1);
});

test('visible page still waits for restored settings and session before automatic submission', async () => {
  const f = fixture(); const gate = deferred(); f.controls.open = () => gate.promise;
  f.page.query = '影片'; f.page.initialSearchPending = true;
  const task = f.page.initialize(); f.page.onPageShow();
  assert.equal(f.timers.size, 0); assert.equal(f.tasks.length, 0);
  gate.resolve({ scopeName: 'scope', historyKey: 'history', scopes: [], search: async () => result([]) });
  await task; assert.equal(f.timers.size, 1); assert.equal(f.tasks.length, 0);
  await f.drain(); assert.equal(f.tasks.length, 1);
});

test('programmatic same-value search-field changes during creation and scope layout preserve the seeded search', async () => {
  const f = fixture(); f.page.query = '影片'; f.page.initialSearchPending = true;
  f.page.editQuery('影片'); assert.equal(f.page.initialSearchPending, true);
  await f.page.initialize(); f.page.onPageShow();
  f.page.editQuery('影片'); f.page.editQuery('影片');
  await f.drain(); assert.equal(f.tasks.length, 1); assert.equal(f.page.submittedQuery, '影片');
});

test('hidden page ignores stale timer callbacks then resumes the seed only once', async () => {
  const f = fixture(); f.page.query = '影片'; f.page.initialSearchPending = true;
  await f.page.initialize(); f.page.onPageShow(); const stale = [...f.timers.values()][0].callback;
  f.page.onPageHide(); stale(); await f.drain();
  assert.equal(f.tasks.length, 0); assert.equal(f.page.initialSearchPending, true);
  f.page.onPageShow(); await f.drain(); assert.equal(f.tasks.length, 1);
  f.page.onPageHide(); f.page.onPageShow(); await f.drain();
  assert.equal(f.tasks.length, 1);
});

test('destroying a page cancels delayed automatic search', async () => {
  const f = fixture(); f.page.query = '影片'; f.page.initialSearchPending = true;
  await f.page.initialize(); f.page.onPageShow(); const stale = [...f.timers.values()][0].callback;
  f.page.aboutToDisappear(); stale(); await f.drain();
  assert.equal(f.tasks.length, 0); assert.equal(f.timers.size, 0); assert.equal(f.page.alive, false);
});

test('manual edits and submission invalidate queued seed dispatch without a duplicate request', async () => {
  for (const action of ['edit', 'submit']) {
    const f = fixture(); f.page.query = '影片'; f.page.initialSearchPending = true;
    await f.page.initialize(); assert.equal(f.timers.size, 1);
    if (action === 'edit') f.page.editQuery('其他影片'); else f.page.search('影片');
    await f.drain(); assert.equal(f.tasks.length, action === 'submit' ? 1 : 0);
    assert.equal(f.page.initialSearchPending, false);
  }
});

test('retry initialization invalidates earlier queued tasks and submits through the replacement session', async () => {
  const requests = [];
  const f = fixture(); f.page.query = '影片'; f.page.initialSearchPending = true;
  await f.page.initialize();
  f.controls.open = async () => ({ scopeName: 'replacement', historyKey: 'new-history', scopes: [],
    search: async word => { requests.push(word); return result([]); } });
  await f.page.initialize(); await f.drain();
  assert.equal(f.tasks.length, 1); assert.deepEqual(requests, ['影片']);
});

test('failed initialization keeps seed available for retry and never searches a missing session', async () => {
  const f = fixture(); f.page.query = '影片'; f.page.initialSearchPending = true;
  const restore = f.controls.open; f.controls.open = async () => { throw new Error('offline'); };
  await f.page.initialize(); await f.drain();
  assert.equal(f.tasks.length, 0); assert.equal(f.page.initialSearchPending, true);
  f.controls.open = restore; await f.page.initialize(); await f.drain();
  assert.equal(f.tasks.length, 1); assert.equal(f.page.initialSearchPending, false);
});

test('responsive poster rows fit their container without a trailing gap at phone and tablet widths', () => {
  for (const width of [240, 280, 320, 360, 390, 430, 600, 720, 840, 1200, 1600, NaN, 0]) {
    const effective = Presentation.width(width), columns = Presentation.columns(width), card = Presentation.cardWidth(width);
    assert.ok(columns >= 2 && columns <= 6);
    const occupied = columns * card + 12 * (columns - 1);
    assert.ok(occupied <= effective - 40 + 0.00001 && effective - 40 - occupied < 0.061);
    assert.ok(card >= 90);
  }
});

test('sorting keeps raw source order intact and unknown years behind known years; merging deduplicates opaque IDs', () => {
  const original = [item('b', 'Beta', 0), item('a', 'Alpha', 2024), item('c', 'Gamma', 2026)];
  assert.deepEqual(Presentation.sorted(original, 'title').map(value => value.id), ['a', 'b', 'c']);
  assert.deepEqual(Presentation.sorted(original, 'year').map(value => value.id), ['c', 'a', 'b']);
  assert.deepEqual(Presentation.sorted(original, 'default'), original);
  assert.deepEqual(original.map(value => value.id), ['b', 'a', 'c']);
  assert.deepEqual(Presentation.merge(original, [item('a'), item('catnode:source:x%3Ay'), item('', 'invalid'), item('bad', '')])
    .map(value => value.id), ['b', 'a', 'c', 'catnode:source:x%3Ay']);
});

test('Emby adapter preserves original items and identical artwork for detail navigation', async () => {
  const raw = { id: 'episode', name: '原作品', productionYear: 2026, overview: '简介', subtitle: () => '第 3 集', seriesId: 'show', seasonId: 'season' };
  const backend = new Emby([raw]); const session = await open(backend);
  const page = await session.search('  三  体 ');
  assert.deepEqual(backend.requests, ['三 体']); assert.equal(page.items[0].embyItem, raw);
  assert.equal(page.items[0].artworkUrl, 'https://images.test/episode?w=360');
  assert.equal(page.pageCount, 1); assert.equal(session.scopeName, '我的服务');
  await assert.rejects(session.search('x', 2));
});

test('Cat adapter searches the selected directory, preserves namespaced IDs and validates pagination', async () => {
  const backend = new NodeCat(async (_category, _word, page) => ({ page, pageCount: 3,
    videos: [{ id: 'catnode:b:opaque%3Aid', name: '同名作品', year: 2025, remarks: '更新至 12 集', overview: '简介', poster: 'https://image.test/a' }] }));
  backend.key = 'b'; const session = await open(backend); const page = await session.search('影片', 2);
  assert.deepEqual(backend.requests, [['', '影片', 2]]); assert.equal(session.scopeName, '目录 B');
  assert.equal(page.items[0].id, 'catnode:b:opaque%3Aid'); assert.equal(page.items[0].subtitle, '2025 · 更新至 12 集');
  assert.equal(page.page, 2); assert.equal(page.pageCount, 3); assert.equal(page.items[0].embyItem, null);
  backend.fetch = async () => ({ page: 1, pageCount: 10, videos: [] });
  await assert.rejects(session.search('影片', 2), /分页/);
});

test('scope keys isolate sources and Cat directories without storing a subscription address', async () => {
  const backend = new NodeCat(async () => ({ page: 1, pageCount: 1, videos: [] }));
  backend.key = 'a'; const a = await open(backend);
  backend.key = 'b'; const b = await open(backend);
  source = { id: 'other', name: '另一服务', enabled: true }; const other = await Session.open('other', {});
  assert.notEqual(a.historyKey, b.historyKey); assert.notEqual(b.historyKey, other.historyKey);
  assert.equal(a.historyKey.includes('https:'), false);
});

test('search directory selection creates an isolated client without changing the home provider', async () => {
  const backend = new NodeCat(async (_category, _word, page) => ({ page, pageCount: 2,
    videos: [{ id: 'catnode:b:opaque', name: '作品', year: 0, remarks: '', overview: '', poster: '' }] }));
  backend.key = 'a'; const initial = await open(backend); const selected = initial.forScope('b');
  assert.equal(backend.getSiteKey(), 'a'); assert.equal(initial.scopeKey, 'a');
  assert.equal(selected.scopeKey, 'b'); assert.equal(selected.scopeName, '目录 B');
  assert.deepEqual(selected.scopes.map(site => site.key), ['a', 'b']);
  assert.notEqual(initial.historyKey, selected.historyKey);
  await selected.search('影片'); assert.deepEqual(backend.requests, [['b', '', '影片', 1]]);
  assert.throws(() => selected.forScope('off')); assert.throws(() => selected.forScope('missing'));
  assert.equal(selected.forScope('b'), selected);
  const returned = selected.forScope('a'); await returned.search('影片');
  assert.deepEqual(backend.requests.at(-1), ['a', '', '影片', 1]);
  assert.equal(backend.key, 'a');
});

test('empty-object search stubs show an actionable directory message; other failures stay distinct', async () => {
  const f = fixture({ scopes: [], search: async () => { throw new CatNodeSearchUnavailableError(); } });
  f.page.search('三体'); await f.drain();
  assert.equal(f.page.error, 'app.string.media_search_directory_unavailable');
  f.page.session = { search: async () => { throw new Error('network'); } };
  f.page.search('三体'); await f.drain(); assert.equal(f.page.error, 'app.string.media_search_failed');
});

test('switching directories cancels stale results, loads separate history, persists choice and repeats the query', async () => {
  const slow = deferred(); const backend = new NodeCat(async () => slow.promise); backend.key = 'a';
  const session = await open(backend); const f = fixture(session);
  f.values.set(session.forScope('b').historyKey, JSON.stringify(['目录B历史']));
  f.page.query = '三体'; f.page.search('三体');
  backend.fetch = async () => ({ page: 1, pageCount: 1,
    videos: [{ id: 'catnode:b:one', name: '新结果', year: 0, remarks: '', overview: '', poster: '' }] });
  await f.page.changeScope('b');
  slow.resolve({ page: 1, pageCount: 1, videos: [{ id: 'old', name: '旧结果' }] });
  await f.drain();
  assert.equal(f.page.scopeName, '目录 B'); assert.deepEqual(f.page.items.map(value => value.id), ['catnode:b:one']);
  assert.deepEqual(f.page.history, ['三体', '目录B历史']); assert.equal(f.page.searching, false);
  assert.ok(f.writes.some(([key, value]) => key === 'media_search_directory_v1:source' && value === 'b'));
  assert.equal(backend.getSiteKey(), 'a');
  const count = backend.requests.length; await f.page.changeScope('b'); await f.page.changeScope('off');
  assert.equal(backend.requests.length, count);
});

test('remembered search directories restore without overriding the home directory; removed ones fall back', async () => {
  const backend = new NodeCat(async () => ({ page: 1, pageCount: 1, videos: [] })); backend.key = 'a';
  const session = await open(backend); const f = fixture(session);
  f.values.set('media_search_directory_v1:source', 'b');
  f.values.set(session.forScope('b').historyKey, JSON.stringify(['B历史']));
  await f.page.initialize();
  assert.equal(f.page.scopeName, '目录 B'); assert.deepEqual(f.page.history, ['B历史']); assert.equal(backend.key, 'a');
  f.values.set('media_search_directory_v1:source', 'off'); await f.page.initialize();
  assert.equal(f.page.scopeName, '目录 A'); assert.equal(f.page.session.scopeKey, 'a');
});

test('leaving during directory history loading cannot start another search', async () => {
  const backend = new NodeCat(async () => ({ page: 1, pageCount: 1, videos: [] })); backend.key = 'a';
  const session = await open(backend); const f = fixture(session); const slow = deferred();
  const originalGet = f.values.get.bind(f.values);
  f.values.get = key => key === session.forScope('b').historyKey ? slow.promise : originalGet(key);
  f.page.query = '三体'; const switching = f.page.changeScope('b');
  f.page.alive = false; f.page.initGeneration++; f.page.cancelSearch(); slow.resolve('[]');
  await switching; await f.drain(); assert.equal(backend.requests.length, 0);
});

test('disabled and unsupported sources cannot open a search session; blank queries do not call a provider', async () => {
  source = { id: 'source', name: 'x', enabled: false }; await assert.rejects(Session.open('source', {}));
  source.enabled = true; provider = {}; await assert.rejects(Session.open('source', {}));
  const backend = new Emby(); const session = await open(backend);
  assert.deepEqual((await session.search('   ')).items, []); assert.deepEqual(backend.requests, []);
  await assert.rejects(session.search('x', 0));
});

test('editing is local, explicit submission queries once and duplicate submission does not restart a pending request', async () => {
  const request = deferred(); const calls = [];
  const f = fixture({ historyKey: 'scope', search: (...args) => { calls.push(args); return request.promise; } });
  f.page.editQuery('三体'); assert.deepEqual(calls, []);
  f.page.search(' 三体 '); f.page.search('三体');
  assert.equal(calls.length, 1); assert.deepEqual(f.edges, ['top']);
  request.resolve(result([item('a')])); await f.drain();
  assert.equal(f.page.items[0].id, 'a'); assert.equal(f.page.history[0], '三体');
  assert.equal(f.page.searching, false);
});

test('blank submission clears results without issuing a request', () => {
  const f = fixture({ historyKey: 'scope', search: () => { throw new Error('must not request'); } });
  f.page.items = [item('a')]; f.page.search('  ');
  assert.equal(f.page.items.length, 0); assert.equal(f.page.submittedQuery, ''); assert.equal(f.page.searching, false);
});

test('new input and a newer query reject older responses, including their history writes and busy-state changes', async () => {
  const first = deferred(), second = deferred(); let call = 0;
  const f = fixture({ historyKey: 'scope', search: () => ++call === 1 ? first.promise : second.promise });
  f.page.search('old'); f.page.editQuery('new'); f.page.search('new');
  first.resolve(result([item('old')])); await f.tasks[0];
  assert.equal(f.page.items.length, 0); assert.equal(f.page.searching, true); assert.equal(f.page.history.length, 0);
  second.resolve(result([item('new')])); await f.drain();
  assert.deepEqual(f.page.items.map(value => value.id), ['new']); assert.deepEqual(f.page.history, ['new']);
});

test('clearing input, leaving or replacing a session prevents late results from resurfacing', async () => {
  for (const cancel of [page => page.editQuery(''), page => { page.alive = false; page.cancelSearch(); }, page => { page.session = {}; }]) {
    const request = deferred(); const f = fixture({ historyKey: 'scope', search: () => request.promise });
    f.page.search('old'); cancel(f.page); request.resolve(result([item('late')])); await f.drain();
    assert.equal(f.page.items.length, 0); assert.equal(f.page.history.length, 0);
  }
});

test('Cat continuation requests are serialized, merge unique results and reapply the current sort', async () => {
  const more = deferred(), requests = [];
  const f = fixture({ historyKey: 'scope', search: (word, page) => {
    requests.push([word, page]); return page === 1 ? Promise.resolve(result([item('a', 'Alpha', 2024)], 1, 2)) : more.promise;
  } });
  f.page.search('作品'); await f.drain(); f.page.setOrder('year'); f.page.more(); f.page.more();
  assert.deepEqual(requests, [['作品', 1], ['作品', 2]]);
  more.resolve(result([item('a', 'Alpha', 2024), item('b', 'Beta', 2026)], 2, 2)); await f.drain();
  assert.deepEqual(f.page.items.map(value => value.id), ['a', 'b']);
  assert.deepEqual(f.page.displayedItems.map(value => value.id), ['b', 'a']);
  f.page.more(); assert.equal(requests.length, 2);
});

test('pagination failures retain existing results, retry the same page and never overwrite first-page errors', async () => {
  let attempts = 0;
  const f = fixture({ historyKey: 'scope', search: async (_word, page) => {
    if (page === 1) return result([item('a')], 1, 2);
    if (++attempts === 1) throw new Error('timeout'); return result([item('b')], 2, 2);
  } });
  f.page.search('影片'); await f.drain(); f.page.more(); await f.drain();
  assert.equal(f.page.error, ''); assert.ok(f.page.pageError.endsWith('media_search_page_failed'));
  assert.equal(f.page.items[0].id, 'a'); assert.equal(f.page.page, 1); assert.equal(f.page.paging, false);
  f.page.more(); await f.drain(); assert.equal(f.page.page, 2); assert.equal(f.page.pageError, '');
});

test('first-page failures expose retry state without recording a successful search', async () => {
  const f = fixture({ historyKey: 'scope', search: async () => { throw new Error('failed'); } });
  f.page.search('影片'); await f.drain();
  assert.ok(f.page.error.endsWith('media_search_failed')); assert.equal(f.page.history.length, 0); assert.equal(f.page.searching, false);
});

test('history management filters locally, persists snapshots and reports failed writes without discarding results', async () => {
  const f = fixture(); f.page.history = ['三体', '三体 第二季', '流浪地球']; f.page.query = '三体';
  assert.deepEqual(f.page.filteredHistory(), ['三体', '三体 第二季']);
  f.page.removeHistory('三体'); f.page.clearHistory(); await Promise.resolve();
  assert.deepEqual(JSON.parse(f.writes[0][1]), ['三体 第二季', '流浪地球']); assert.equal(f.writes[1][1], '[]');
  f.controls.writeError = true; f.page.items = [item('a')]; f.page.rememberSearch('作品'); await Promise.resolve();
  assert.ok(f.toasts[0].endsWith('media_search_history_failed')); assert.equal(f.page.items[0].id, 'a');
});

test('initialization restores scoped history, migrates legacy Emby history and does not resurrect a cleared scope', async () => {
  const session = { scopeName: '我的 Emby', historyKey: 'scope', isEmby: true };
  const f = fixture(session); f.values.set('emby_search_history', '["旧记录"]');
  await f.page.initialize(); assert.equal(f.page.scopeName, '我的 Emby'); assert.deepEqual(f.page.history, ['旧记录']);
  assert.equal(f.writes[0][0], 'scope');
  f.values.set('scope', '[]'); await f.page.initialize(); assert.deepEqual(f.page.history, []);
});

test('a late initialization cannot replace a newer scope or a page that was left', async () => {
  const old = deferred(); const f = fixture(null);
  f.controls.open = () => old.promise; const pending = f.page.initialize();
  f.controls.open = async () => ({ scopeName: '新目录', historyKey: 'new' }); await f.page.initialize();
  old.resolve({ scopeName: '旧目录', historyKey: 'old' }); await pending;
  assert.equal(f.page.scopeName, '新目录'); assert.equal(f.page.historyKey, 'new');
  const late = deferred(); f.controls.open = () => late.promise; const leaving = f.page.initialize();
  f.page.alive = false; f.page.initGeneration++; late.resolve({ scopeName: '离页', historyKey: 'late' }); await leaving;
  assert.equal(f.page.scopeName, '');
});

test('Cat history does not inherit Emby keywords, and initialization failure can be retried', async () => {
  const f = fixture({ scopeName: '猫源目录', historyKey: 'cat-scope', isEmby: false });
  f.values.set('emby_search_history', '["Emby 专用关键词"]');
  f.controls.open = async () => { throw new Error('offline'); };
  await f.page.initialize(); assert.equal(f.page.session, null); assert.equal(f.page.initializing, false);
  assert.ok(f.page.error.endsWith('media_search_connect_failed'));
  f.controls.open = async () => ({ scopeName: '猫源目录', historyKey: 'cat-scope', isEmby: false });
  await f.page.initialize(); assert.deepEqual(f.page.history, []); assert.equal(f.page.scopeName, '猫源目录');
  assert.equal(f.page.error, '');
});

test('reinitialization hides old-scope results and invalidates a search still in flight', async () => {
  const pending = deferred(); const f = fixture({ historyKey: 'old', search: () => pending.promise });
  f.page.search('旧关键词'); f.page.items = [item('previous')]; f.page.displayedItems = f.page.items;
  f.controls.open = async () => ({ scopeName: '新目录', historyKey: 'new', isEmby: false });
  await f.page.initialize(); pending.resolve(result([item('late')])); await f.drain();
  assert.deepEqual(f.page.items, []); assert.deepEqual(f.page.displayedItems, []);
  assert.equal(f.page.submittedQuery, ''); assert.equal(f.page.historyKey, 'new');
});

test('artwork reset ignores failures arriving from an earlier image URL', () => {
  const source = read('components/media/SearchResultCard.ets');
  const methods = source.slice(source.indexOf('  private resetArtwork'), source.indexOf('  @Builder'));
  const Card = new Function(stripTypeScriptTypes(`class Card { ${methods} }`, { mode: 'transform' }) + ';return Card;')();
  const card = Object.assign(new Card(), { artworkUrl: 'old', failed: true });
  card.artworkUrl = 'new'; card.resetArtwork(); card.artworkFailed('old'); assert.equal(card.failed, false);
  card.artworkFailed('new'); assert.equal(card.failed, true);
});

test('detail navigation retains original Cat IDs and original Emby metadata, artwork and transition identity', () => {
  const f = fixture(); const cat = item('catnode:site:opaque%3Aid'); f.page.openItem(cat, '');
  assert.deepEqual(f.routes[0], { url: 'pages/catvod/CatVodDetailPage',
    params: { sourceId: 'source', videoId: cat.id, title: cat.title, fromSearch: true } });
  const emby = item('episode'); emby.embyItem = { id: 'episode', seriesId: 'show', seasonId: 'season' }; emby.artworkUrl = 'authenticated artwork';
  f.page.openItem(emby, 'shared-artwork');
  assert.equal(f.routes[1].params.raw, emby.embyItem); assert.equal(f.routes[1].params.artworkUrl, emby.artworkUrl);
  assert.equal(f.routes[1].params.transitionId, 'shared-artwork');
});

test('both home search actions open the registered shared search page; standalone browsing remains registered', () => {
  const home = read('pages/home/HomePage.ets');
  const start = home.indexOf('  private handleSearchAction()');
  const logic = home.slice(start, home.indexOf('  private selectableSources()', start));
  const Home = new Function(stripTypeScriptTypes(`class Home { ${logic} }`, { mode: 'transform' }) + ';return Home;')();
  for (const type of ['emby', 'catvod', 'catnode']) {
    const routes = [];
    const control = Object.assign(new Home(), { selectedId: 'current', selectedSource: () => ({ providerType: type }),
      getUIContext: () => ({ getRouter: () => ({ pushUrl: value => routes.push(value) }) }) });
    control.handleSearchAction(); assert.deepEqual(routes, [{ url: 'pages/home/SearchPage', params: { sourceId: 'current' } }]);
  }
  const routes = JSON.parse(readFileSync(new URL('../entry/src/main/resources/base/profile/main_pages.json', import.meta.url), 'utf8'));
  assert.ok(routes.src.includes('pages/home/SearchPage')); assert.ok(routes.src.includes('pages/catvod/CatVodBrowserPage'));
});

function aggregateSession(keys, fetch) {
  const calls = [];
  const session = { scopes: keys.map(key => ({ key, name: key })), scopeKey: keys[0], scopeName: keys[0],
    historyKey: 'single-history',
    forScope(key, control) { return { search: async (word, page) => { calls.push({ key, word, page, control }); return fetch(key, word, page, control); } }; } };
  return { session, calls };
}

test('aggregate streams four concurrent directories, preserves source identities and skips unsupported stubs', async () => {
  const waiting = new Map(), snapshots = []; let active = 0, peak = 0;
  const f = aggregateSession(['a', 'b', 'c', 'd', 'e', 'f'], async key => {
    active++; peak = Math.max(peak, active); const request = deferred(); waiting.set(key, request);
    try { return await request.promise; } finally { active--; }
  });
  const run = new Aggregate(f.session, '  三体 '); const task = run.round(state => snapshots.push(state));
  assert.equal(f.calls.length, 4); assert.equal(snapshots.length, 1);
  waiting.get('a').resolve(result([item('catnode:a:same')]));
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(f.calls.length, 5); assert.equal(snapshots.at(-1).items[0].id, 'catnode:a:same');
  waiting.get('b').resolve(result([item('catnode:b:same')]));
  await new Promise(resolve => setImmediate(resolve));
  waiting.get('c').reject(new CatNodeSearchUnavailableError()); waiting.get('d').reject(new Error('offline'));
  waiting.get('e').resolve(result([])); waiting.get('f').resolve(result([]));
  const state = await task;
  assert.equal(peak, 4); assert.equal(state.completed, 6); assert.equal(state.total, 6);
  assert.equal(state.unavailable, 1); assert.equal(state.failed, 1); assert.equal(state.succeeded, 4);
  assert.deepEqual(state.items.map(value => value.id), ['catnode:a:same', 'catnode:b:same']);
  assert.ok(f.calls.every(value => value.word === '三体' && value.page === 1));
  assert.ok(state.hasMore);
});

test('aggregate continuation retries failed pages, keeps prior items and only advances directories with more results', async () => {
  const attempts = new Map(); const f = aggregateSession(['a', 'b', 'c', 'd'], async (key, _word, page) => {
    attempts.set(key, (attempts.get(key) ?? 0) + 1);
    if (key === 'c') throw new CatNodeSearchUnavailableError();
    if (key === 'd' && attempts.get(key) === 1) throw new Error('temporary');
    if (key === 'a') return result([item('catnode:a:first'), ...(page > 1 ? [item('catnode:a:second')] : [])], page, 2);
    return result([item(`catnode:${key}:one`)], page, 1);
  });
  const run = new Aggregate(f.session, '三体'); await run.round(() => {});
  const state = await run.round(() => {});
  assert.deepEqual(f.calls.slice(4).map(value => [value.key, value.page]), [['a', 2], ['d', 1]]);
  assert.equal(state.failed, 0); assert.equal(state.unavailable, 1); assert.equal(state.hasMore, false);
  assert.deepEqual(state.items.map(value => value.id), ['catnode:a:first', 'catnode:b:one', 'catnode:a:second', 'catnode:d:one']);
});

test('aggregate deadlines cancel request controls, release slots and retain healthy results', async () => {
  const aborted = []; const f = aggregateSession(['slow', 'ok'], async (key, _word, page, control) => {
    if (key === 'ok') return result([item('catnode:ok:one')], page, page);
    control.onCancel(() => aborted.push(key)); return new Promise(() => {});
  });
  const run = new Aggregate(f.session, '三体', 10); const state = await run.round(() => {});
  assert.deepEqual(aborted, ['slow']); assert.equal(state.completed, 2); assert.equal(state.failed, 1);
  assert.equal(state.items[0].id, 'catnode:ok:one'); assert.equal(state.succeeded, 1);
});

test('aggregate cancellation stops active clients and queued work; late results cannot publish', async () => {
  const waiting = deferred(), snapshots = [];
  const f = aggregateSession(['a', 'b', 'c', 'd', 'e'], () => waiting.promise);
  const run = new Aggregate(f.session, '三体'); const task = run.round(state => snapshots.push(state));
  run.cancel(); const state = await task;
  assert.equal(f.calls.length, 4); assert.ok(f.calls.every(value => value.control.cancelled));
  assert.equal(state.hasMore, false); assert.equal(state.items.length, 0);
  waiting.resolve(result([item('late')])); await new Promise(resolve => setImmediate(resolve));
  assert.equal(snapshots.length, 1); assert.equal(run.snapshot().items.length, 0);
  await run.round(() => { throw new Error('cancelled job published'); });
});

test('aggregate duplicate rounds, blank queries and zero directories do not duplicate requests', async () => {
  const waiting = deferred(); const f = aggregateSession(['a'], () => waiting.promise);
  const run = new Aggregate(f.session, '三体'); const task = run.round(() => {});
  await run.round(() => {}); assert.equal(f.calls.length, 1); waiting.resolve(result([])); await task;
  await run.round(() => {}); assert.equal(f.calls.length, 1);
  await new Aggregate(f.session, '   ').round(() => {}); assert.equal(f.calls.length, 1);
  assert.equal((await new Aggregate(aggregateSession([], () => {}).session, '词').round(() => {})).hasMore, false);
});

test('page restores aggregate choice with separate history and defaults fresh Cat sessions to aggregation', async () => {
  const backend = new NodeCat(async () => ({ page: 1, pageCount: 1, videos: [] })); backend.key = 'a';
  const session = await open(backend); const f = fixture(session);
  f.values.set(f.page.aggregateHistoryKey(), JSON.stringify(['聚合历史']));
  await f.page.initialize();
  assert.equal(f.page.aggregateMode, true); assert.equal(f.page.scopeName, 'app.string.media_search_aggregate');
  assert.deepEqual(f.page.history, ['聚合历史']); assert.equal(backend.key, 'a');
  assert.deepEqual(f.page.scopeMenu().map(value => value.value), ['目录 A', '目录 B']);
  await f.page.changeScope('b'); assert.equal(f.page.aggregateMode, false); assert.equal(f.page.scopeName, '目录 B');
  await f.page.changeScope(ALL); assert.equal(f.page.aggregateMode, true);
  assert.equal(f.values.get(f.page.scopePreferenceKey()), ALL); await f.page.initialize();
  assert.equal(f.page.aggregateMode, true); assert.deepEqual(f.page.history, ['聚合历史']);
});

test('page shows progressive aggregate results, stops cleanly and isolates the next query', async () => {
  const old = deferred(); const f = aggregateSession(['a', 'b'], async (key, word) => {
    if (word === '旧词' && key === 'b') return old.promise;
    return result([item(`catnode:${key}:${word}`)]);
  });
  const p = fixture(f.session); p.page.aggregateMode = true;
  p.page.search('旧词'); await new Promise(resolve => setImmediate(resolve));
  assert.equal(p.page.searching, true); assert.equal(p.page.items.length, 1);
  p.page.stopAggregate(); assert.equal(p.page.searching, false); assert.equal(p.page.aggregateStopped, true);
  const oldRun = p.page.aggregate; assert.equal(oldRun.snapshot().hasMore, false);
  p.page.search('新词'); old.resolve(result([item('late')])); await p.drain();
  assert.equal(p.page.aggregateStopped, false); assert.equal(p.page.searching, false);
  assert.deepEqual(p.page.items.map(value => value.id), ['catnode:a:新词', 'catnode:b:新词']);
  assert.equal(p.page.aggregateState.succeeded, 2);
});

test('page aggregate more serializes rounds and failed-source retries preserve results', async () => {
  let fail = true; const f = aggregateSession(['a', 'b'], async (key, _word, page) => {
    if (key === 'b' && fail) throw new Error('offline');
    return result([item(`catnode:${key}:${page}`)], page, key === 'a' ? 2 : 1);
  });
  const p = fixture(f.session); p.page.aggregateMode = true; p.page.search('词'); await p.drain();
  assert.equal(p.page.aggregateState.failed, 1); assert.equal(p.page.items.length, 1);
  fail = false; p.page.more(); p.page.more(); await p.drain();
  assert.deepEqual(f.calls.map(value => [value.key, value.page]), [['a', 1], ['b', 1], ['a', 2], ['b', 1]]);
  assert.equal(p.page.aggregateState.failed, 0); assert.equal(p.page.items.length, 3); assert.equal(p.page.paging, false);
});

test('large result sets expand in bounded visible batches while sorting and original identities remain intact', () => {
  const f = fixture(); f.page.items = Array.from({ length: 150 }, (_, index) => item(String(index)));
  f.page.displayedItems = f.page.items.slice(); assert.equal(f.page.visibleResults().length, 60);
  f.page.revealResults(); assert.equal(f.page.visibleResults().length, 120);
  f.page.revealResults(); assert.equal(f.page.visibleResults().length, 150);
  f.page.editQuery('换词'); assert.equal(f.page.visibleLimit, 60); assert.equal(f.page.visibleResults().length, 0);
});

test('scope selection defaults once, reconciles stale keys and never silently broadens an explicit selection', () => {
  const scopes = [{ key: 'a', name: 'A' }, { key: 'b', name: 'B' }, { key: 'off', searchable: false }];
  assert.deepEqual(ScopeSelection.decode('', scopes), ['a', 'b']);
  assert.deepEqual(ScopeSelection.decode('["b","a","b","missing",5,null,"off"]', scopes), ['a', 'b']);
  for (const saved of ['[]', '{}', 'invalid', '["removed"]']) assert.deepEqual(ScopeSelection.decode(saved, scopes), []);
  assert.deepEqual(ScopeSelection.decode('["b"]', [...scopes, { key: 'new' }]), ['b']);
  assert.deepEqual(ScopeSelection.normalize(['b', 'b'], [...scopes, { key: 'b' }]), ['b']);
  assert.ok(ScopeSelection.equal(['a'], ['a'])); assert.ok(!ScopeSelection.equal(['a'], ['b']));
});

test('aggregate searches only the captured selected subset; an explicit empty scope cannot mean all', async () => {
  const f = aggregateSession(['a', 'b', 'c'], async (key, _word, page) => result([item(`catnode:${key}:one`)], page));
  const keys = ['b', 'b', 'missing']; const run = new Aggregate(f.session, '三体', 12000, keys);
  keys.push('a'); const state = await run.round(() => {});
  assert.deepEqual(f.calls.map(value => value.key), ['b']); assert.equal(state.total, 1);
  const empty = await new Aggregate(f.session, '三体', 12000, []).round(() => {});
  assert.equal(empty.total, 0); assert.equal(f.calls.length, 1); assert.equal(empty.hasMore, false);
});

test('scope panel edits a draft, retains hidden selections during filtering and discards cancelled edits', () => {
  const f = fixture(aggregateSession(['alpha', 'beta'], async () => result([])).session);
  f.page.selectedScopeKeys = ['alpha']; let cancelled = 0; f.page.aggregate = { cancel() { cancelled++; } };
  f.page.openScopeSettings(); assert.equal(f.page.showScopeSettings, true);
  f.page.scopeFilter = ' BETA '; assert.deepEqual(f.page.filteredScopeChoices().map(site => site.key), ['beta']);
  f.page.toggleDraftScope('beta'); assert.deepEqual(f.page.draftScopeKeys, ['alpha', 'beta']);
  assert.deepEqual(f.page.selectedScopeKeys, ['alpha']);
  f.page.toggleDraftScope('unknown'); assert.deepEqual(f.page.draftScopeKeys, ['alpha', 'beta']);
  f.page.selectAllScopes(false); assert.deepEqual(f.page.draftScopeKeys, []);
  f.page.selectAllScopes(true); assert.deepEqual(f.page.draftScopeKeys, ['alpha', 'beta']);
  f.page.showScopeSettings = false; f.page.openScopeSettings();
  assert.deepEqual(f.page.draftScopeKeys, ['alpha']); assert.equal(f.page.scopeFilter, '');
  assert.equal(cancelled, 0); assert.equal(f.writes.length, 0);
});

test('applying a subset persists before cancelling the old run and searches only the confirmed directories', async () => {
  const slow = deferred(); const f = aggregateSession(['a', 'b'], async key => {
    if (key === 'a') return slow.promise;
    return result([item('catnode:b:confirmed')]);
  });
  const p = fixture(f.session); p.page.aggregateMode = true; p.page.selectedScopeKeys = ['a'];
  p.page.search('三体'); p.page.openScopeSettings(); p.page.toggleDraftScope('a'); p.page.toggleDraftScope('b');
  await p.page.applyScopeSelection(); slow.resolve(result([item('catnode:a:late')])); await p.drain();
  assert.deepEqual(p.page.selectedScopeKeys, ['b']); assert.equal(p.page.showScopeSettings, false);
  assert.deepEqual(f.calls.map(value => value.key), ['a', 'b']); assert.ok(f.calls[0].control.cancelled);
  assert.deepEqual(p.page.items.map(value => value.id), ['catnode:b:confirmed']);
  assert.equal(p.values.get(p.page.scopeSelectionPreferenceKey()), '["b"]');
});

test('failed scope saves preserve active settings and draft for retry; empty or unchanged drafts never dispatch', async () => {
  const f = fixture(aggregateSession(['a', 'b'], async () => result([])).session);
  f.page.selectedScopeKeys = ['a']; f.page.openScopeSettings(); f.page.draftScopeKeys = ['b'];
  f.controls.writeError = true; await f.page.applyScopeSelection();
  assert.deepEqual(f.page.selectedScopeKeys, ['a']); assert.deepEqual(f.page.draftScopeKeys, ['b']);
  assert.equal(f.page.scopeSaveError, 'app.string.media_search_scope_save_failed'); assert.ok(f.page.showScopeSettings);
  assert.equal(f.page.scopeSaving, false);
  f.controls.writeError = false; await f.page.applyScopeSelection(); assert.deepEqual(f.page.selectedScopeKeys, ['b']);
  f.page.openScopeSettings(); f.page.draftScopeKeys = []; await f.page.applyScopeSelection();
  assert.equal(f.page.scopeSaveError, 'app.string.media_search_scope_minimum'); assert.ok(f.page.showScopeSettings);
  const writes = f.writes.length; f.page.draftScopeKeys = ['b']; await f.page.applyScopeSelection();
  assert.equal(f.writes.length, writes); assert.equal(f.page.showScopeSettings, false); assert.equal(f.tasks.length, 0);
});

test('switch preserves last single directory and configured aggregate scope across reopening', async () => {
  const backend = new NodeCat(async () => ({ page: 1, pageCount: 1, videos: [] })); backend.key = 'a';
  const session = await open(backend); const f = fixture(session);
  f.values.set(f.page.scopePreferenceKey(), ALL); f.values.set(f.page.singleScopePreferenceKey(), 'b');
  f.values.set(f.page.scopeSelectionPreferenceKey(), '["a"]');
  await f.page.initialize(); assert.equal(f.page.aggregateMode, true); assert.equal(f.page.session.scopeKey, 'b');
  assert.deepEqual(f.page.selectedScopeKeys, ['a']);
  f.page.setAggregation(false); await new Promise(resolve => setImmediate(resolve));
  assert.equal(f.page.aggregateMode, false); assert.equal(f.page.scopeName, '目录 B');
  assert.deepEqual(f.page.selectedScopeKeys, ['a']);
  f.page.setAggregation(true); await new Promise(resolve => setImmediate(resolve));
  await f.page.initialize(); assert.equal(f.page.aggregateMode, true); assert.equal(f.page.session.scopeKey, 'b');
  assert.deepEqual(f.page.selectedScopeKeys, ['a']); assert.equal(backend.key, 'a');
});

test('stale or empty saved aggregate scopes block queries instead of searching every directory', async () => {
  const backend = new NodeCat(async () => ({ page: 1, pageCount: 1, videos: [] })); backend.key = 'a';
  const f = fixture(await open(backend)); f.values.set(f.page.scopeSelectionPreferenceKey(), '["removed"]');
  await f.page.initialize(); assert.deepEqual(f.page.selectedScopeKeys, []);
  f.page.search('三体'); await f.drain(); assert.equal(backend.requests.length, 0);
  assert.equal(f.page.error, 'app.string.media_search_scope_minimum');
  assert.equal(f.page.searching, false); assert.equal(f.page.scopeSelectionPreferenceKey().includes('https:'), false);
  f.page.sourceId = 'another'; assert.equal(f.page.scopeSelectionPreferenceKey(), 'media_search_aggregate_scope_v1:another');
});

test('double apply is serialized and leaving during persistence cannot restart a search', async () => {
  const f = fixture(aggregateSession(['a', 'b'], async () => result([])).session);
  f.page.selectedScopeKeys = ['a']; f.page.aggregateMode = true; f.page.query = '三体';
  f.page.openScopeSettings(); f.page.draftScopeKeys = ['b']; const write = deferred(); f.controls.writeWait = write.promise;
  const first = f.page.applyScopeSelection(); assert.equal(f.page.scopeSaving, true);
  await f.page.applyScopeSelection(); f.page.setAggregation(false); assert.equal(f.page.aggregateMode, true);
  f.page.alive = false; f.page.initGeneration++; f.page.cancelSearch(); write.resolve(); await first;
  assert.equal(f.writes.length, 1); assert.equal(f.tasks.length, 0); assert.deepEqual(f.page.selectedScopeKeys, ['a']);
});

test('directory menu is controlled only by its capsule and cannot open during aggregation or unavailable states', () => {
  const f = fixture(aggregateSession(['a', 'b'], async () => result([])).session);
  f.page.toggleDirectoryMenu(); assert.equal(f.page.showDirectoryMenu, true);
  f.page.toggleDirectoryMenu(); assert.equal(f.page.showDirectoryMenu, false);
  for (const key of ['aggregateMode', 'initializing', 'scopeSaving']) {
    f.page[key] = true; f.page.toggleDirectoryMenu(); assert.equal(f.page.showDirectoryMenu, false); f.page[key] = false;
  }
  f.page.alive = false; f.page.toggleDirectoryMenu(); assert.equal(f.page.showDirectoryMenu, false);
  f.page.alive = true; f.page.scopes = []; f.page.toggleDirectoryMenu(); assert.equal(f.page.showDirectoryMenu, false);
});

test('directory selection, switching to aggregation and reinitialization close controlled menus', async () => {
  const backend = new NodeCat(async () => ({ page: 1, pageCount: 1, videos: [] })); backend.key = 'a';
  const f = fixture(await open(backend));
  f.page.toggleDirectoryMenu(); f.page.scopeMenu()[0].action();
  assert.equal(f.page.showDirectoryMenu, false); assert.equal(f.writes.length, 0);
  f.page.toggleDirectoryMenu(); await f.page.changeScope(ALL); assert.equal(f.page.showDirectoryMenu, false);
  f.page.showDirectoryMenu = true; await f.page.initialize(); assert.equal(f.page.showDirectoryMenu, false);
});
