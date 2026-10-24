// Exercise the actual lifecycle and request handlers; native layout is not simulated.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { test } from 'node:test';

const source = readFileSync(new URL('../entry/src/main/ets/pages/catvod/CatVodContent.ets', import.meta.url), 'utf8').replace(/\r\n/g, '\n');
const methods = source.slice(source.indexOf('  aboutToAppear()'), source.indexOf('  build()'));
const hero = source.slice(source.indexOf('  private showHero()'), source.indexOf('  @Builder\n  private SourceHeader()'));
const callback = source.slice(source.indexOf('class CatVodNavigationFrame'));
const pageClass = stripTypeScriptTypes(`class Page { ${methods}\n${hero} }\n${callback}`, { mode: 'transform' });
const deferred = () => { let resolve; const promise = new Promise(done => { resolve = done; }); return { promise, resolve }; };
const frameQueues = new Set();
const tick = async () => {
  for (let i = 0; i < 20; i++) {
    await Promise.resolve();
    for (const frames of frameQueues) for (const frame of frames.splice(0)) frame.onFrame();
  }
};
class Navigation {}
class Provider {}
class NodeProvider extends Provider {}
class Snapshot {}
class VodPage { page = 1; pageCount = 1; videos = []; }

function setup(active = true) {
  const calls = { registry: 0, sites: 0, categories: 0, pages: [], history: 0, scroll: 0, cacheReads: 0, cacheWrites: [], warms: [] };
  const state = { pageGate: null, categoryGate: null, historyGate: null, fail: false, failHistory: false, empty: false,
    history: [], frameUri: '', frameGate: null, cache: null, categoryCaches: new Map(), cacheFresh: true, cacheGate: null, proxyGate: null,
    contentRect: { x: 0, y: 0, width: 360, height: 10000 }, unbound: false, failPage: false, pageResult: null,
    sites: [{ key: 'a', name: '目录甲' }], siteKey: 'a', warmGate: null, failWarm: false };
  const provider = new NodeProvider();
  const client = {
    async categories() {
      calls.categories++; if (state.categoryGate) await state.categoryGate.promise;
      if (state.fail) throw new Error('catalog failed');
      return [{ id: 'action', name: '动作片' }];
    },
    async page(category, keyword, number) {
      calls.pages.push({ category, keyword, number });
      const gate = state.pageGate; if (gate) await gate.promise;
      if (state.failPage) throw new Error('next page failed');
      if (state.pageResult) return state.pageResult;
      return { page: number, pageCount: 4, videos: state.empty ? [] : [{ id: `movie-${category}-${number}`, poster: 'poster' }] };
    }
  };
  Object.assign(provider, {
    async sites() { calls.sites++; return state.sites; },
    getSiteKey() { return state.siteKey; }, getClient() { return client; },
    async getResumeItems() {
      calls.history++; const gate = state.historyGate;
      if (gate) return gate.promise;
      if (state.failHistory) throw new Error('history failed');
      return state.history;
    },
    async selectSite(key) { state.siteKey = key; },
    async cachedArtworkBase() { return state.proxyGate ? state.proxyGate.promise : 'http://127.0.0.1:2000'; },
    async prepareResume(id, current) {
      calls.warms.push({ id, current });
      if (state.warmGate) await state.warmGate.promise;
      if (state.failWarm) throw new Error('warm failed');
    }
  });
  NodeProvider.fromCachedSites = () => provider;
  Provider.fromSource = async () => provider;
  const cache = {
    async get(source, category = '') {
      calls.cacheReads++; if (state.cacheGate) await state.cacheGate.promise;
      return category ? state.categoryCaches.get(category) ?? null : state.cache;
    },
    async put(source, value) { calls.cacheWrites.push(structuredClone(value)); },
    fresh: () => state.cacheFresh,
    needsProxy: value => value.videos.some(item => item.poster.startsWith('http://127.0.0.1:')),
    rebaseArtwork: (value = '', base = '') => /^http:\/\/127\.0\.0\.1:\d+\//.test(value) ?
      (base ? value.replace(/^http:\/\/127\.0\.0\.1:\d+/, base) : '') : value,
    artwork: (value, base = '') => value.videos.map(item => ({ ...item,
      poster: /^http:\/\/127\.0\.0\.1:\d+\//.test(item.poster) ? (base ? item.poster.replace(/^http:\/\/127\.0\.0\.1:\d+/, base) : '') : item.poster }))
  };
  const Page = new Function('ProviderRegistry', 'CatVodProvider', 'CatNodeProvider', 'CatVodHomeNavigation',
    'CatVodHeroPresentation', 'HomeHeroSyncTrace', 'HomeHeroColors', 'Edge', 'buildDetailToastOptions', '$r', 'FrameCallback',
    'CatHomeCache', 'CatHomeSnapshot', 'CatVodPage', 'cacheLogger', 'ResumeFrameStore',
    pageClass + ';return Page;')(
    { async get() { calls.registry++; return provider; } }, Provider, NodeProvider, Navigation,
    { select: items => items.slice() }, { applied() {} }, { surface: color => color }, { Top: 0 }, value => value, value => value, class {},
    cache, Snapshot, VodPage, { info() {}, warn() {} }, { async resolve() { return state.frameGate ? state.frameGate.promise : state.frameUri; } });
  const published = [], frames = [], routes = []; frameQueues.add(frames);
  const page = Object.assign(new Page(), {
    isActive: active, alive: false, generation: 0, resumeGeneration: 0, refreshPending: true, startupPending: true, refreshing: false,
    navigationPending: false, navigationTicket: 0, contentRevision: 0, artworkSnapshot: null, artworkGeneration: -1,
    paginationPending: false, paginationTicket: 0, viewportHeight: 0,
    embeddedHomeTitle: true, source: { id: 'cat-a', providerType: 'catnode', updatedAt: 1 }, playingHistory: false,
    historyRequest: 0, historyOpeningId: '', historyError: '', resumeWarmKey: '',
    categories: [], videos: [], heroVideos: [], heroVersion: 0, heroColor: '', heroSurface: '',
    resume: [], categoryId: '', query: '', keyword: '', page: 0, pageCount: 1, loading: true,
    paging: false, error: '', pageError: '', nodeSites: [], nodeSiteKey: '', showSites: false, provider: null,
    scroller: { offset: 0, scrollEdge() { calls.scroll++; this.offset = 0; },
      getItemRect(index) {
        assert.equal(index, 1); if (state.unbound) throw new Error('unbound');
        return typeof state.contentRect === 'function' ? state.contentRect(page) : state.contentRect;
      } },
    onNavigationChanged: value => published.push(value), onHeroSurfaceChanged() {},
    getUIContext() { return { postFrameCallback: callback => frames.push(callback),
      getHostContext: () => ({ resourceManager: { getStringSync: () => '更新失败，已保留上次的首页内容' } }),
      getPromptAction: () => ({ showToast() {} }),
      getRouter: () => ({ async pushUrl(options) { routes.push(options); } }) }; }
  });
  return { page, calls, state, published, frames, routes, render: () => { for (const frame of frames.splice(0)) frame.onFrame(); } };
}

test('standalone configuration selection opens the tool while retaining media and cache state', async () => {
  const { page, state, routes } = setup(); state.sites.push({ key: 'baseset', name: '配置|中心' });
  page.aboutToAppear(); await tick(); const videos = page.videos; const selected = page.nodeSiteKey;
  await page.chooseNodeSite('baseset');
  assert.equal(page.nodeSiteKey, selected); assert.equal(page.videos, videos); assert.equal(state.siteKey, selected);
  assert.deepEqual(routes, [{ url: 'pages/catvod/CatNodeConfigurationPage', params: { sourceId: page.source.id } }]);
});
const activate = (page, value) => { page.isActive = value; page.onActiveChanged(); };

test('visible home warms only its most recent history item once without blocking display or navigation', async () => {
  const f = setup(); f.state.history = [{ id: 'recent', poster: '' }, { id: 'older', poster: '' }];
  f.state.warmGate = deferred(); f.page.aboutToAppear(); await tick();
  assert.equal(f.page.loading, false); assert.equal(f.page.resume.length, 2);
  assert.deepEqual(f.calls.warms.map(value => value.id), ['recent']);
  assert.equal(f.calls.warms[0].current(), true);
  await f.page.refreshResume(); assert.equal(f.calls.warms.length, 1);
  activate(f.page, false); assert.equal(f.calls.warms[0].current(), false);
  f.state.warmGate.resolve(); await tick();
  assert.equal(f.page.resumeWarmKey, '');
  activate(f.page, true); await tick(); assert.equal(f.calls.warms.length, 2);
  assert.equal(f.calls.registry, 1, 'warmup must not reconstruct the home catalog');
});

test('warmup failures remain silent and can retry; inactive, playing and empty states do not start work', async () => {
  const f = setup(); f.page.aboutToAppear(); await tick();
  const provider = f.page.provider; const entries = [{ id: 'recent' }];
  f.state.failWarm = true; f.page.warmRecentResume(provider, entries, f.page.generation); await tick();
  assert.equal(f.page.resumeWarmKey, ''); assert.equal(f.page.error, '');
  f.state.failWarm = false; f.page.warmRecentResume(provider, entries, f.page.generation); await tick();
  assert.equal(f.calls.warms.length, 2);
  f.page.resumeWarmKey = ''; f.page.playingHistory = true;
  f.page.warmRecentResume(provider, entries, f.page.generation); assert.equal(f.calls.warms.length, 2);
  f.page.playingHistory = false; f.page.isActive = false;
  f.page.warmRecentResume(provider, entries, f.page.generation); assert.equal(f.calls.warms.length, 2);
  f.page.isActive = true;
  f.page.warmRecentResume(provider, [], f.page.generation); assert.equal(f.calls.warms.length, 2);
});

test('repeated service/settings round trips retain catalog, pagination, hero and scroll position', async () => {
  const { page, calls, published, state } = setup();
  page.aboutToAppear(); await tick();
  await page.more();
  const videos = page.videos, heroes = page.heroVideos, version = page.heroVersion;
  page.heroColor = '#123456'; page.heroSurface = '#234567'; page.scroller.offset = 420;
  for (let i = 0; i < 4; i++) {
    page.showSites = true; activate(page, false); assert.equal(page.showSites, false);
    state.history = [{ id: `resume-${i}` }]; activate(page, true); await tick();
    assert.equal(page.loading, false); assert.equal(page.videos, videos); assert.equal(page.heroVideos, heroes);
    assert.equal(page.heroVersion, version); assert.equal(page.page, 2); assert.equal(page.scroller.offset, 420);
    assert.equal(page.heroSurface, '#234567'); assert.equal(page.heroColor, '#123456');
    assert.equal(page.resume[0].id, `resume-${i}`);
    assert.equal(published.at(-1).heroSurface, '#234567');
  }
  assert.equal(calls.registry, 1); assert.equal(calls.sites, 1); assert.equal(calls.categories, 1);
  assert.equal(calls.pages.length, 2); assert.equal(calls.scroll, 0);
});

test('activation before mount does not fetch; an initially hidden page loads once when first shown', async () => {
  const { page, calls } = setup(false);
  activate(page, true); assert.equal(calls.registry, 0);
  activate(page, false); page.aboutToAppear(); await tick(); assert.equal(calls.registry, 0);
  activate(page, true); activate(page, true); await tick();
  assert.equal(calls.categories, 1); assert.equal(calls.pages.length, 1); assert.equal(page.page, 1);
});

test('a first-page request can finish while hidden without restarting it on return', async () => {
  const { page, calls, state, published } = setup();
  state.pageGate = deferred(); page.aboutToAppear(); await tick();
  assert.equal(calls.pages.length, 1); const generation = page.generation;
  activate(page, false); activate(page, true); await tick();
  assert.equal(calls.pages.length, 1); assert.equal(page.loading, true);
  activate(page, false); const count = published.length;
  state.pageGate.resolve(); await tick();
  assert.equal(page.generation, generation); assert.equal(page.page, 1); assert.equal(page.loading, false);
  assert.equal(published.length, count, 'hidden data must not publish into the active title');
  activate(page, true); await tick(); assert.equal(calls.pages.length, 1);
  assert.equal(published.at(-1).loading, false);
});

test('a pending next page completes across tab changes without losing or duplicating results', async () => {
  const { page, calls, state } = setup(); page.aboutToAppear(); await tick();
  state.pageGate = deferred(); const pending = page.more(); await tick();
  activate(page, false); activate(page, true); await tick();
  assert.equal(page.paging, true); assert.equal(calls.pages.length, 2);
  state.pageGate.resolve(); await pending;
  assert.equal(page.paging, false); assert.equal(page.page, 2); assert.equal(page.videos.length, 2);
});

test('manual refresh requested while hidden is deferred and processed once on return', async () => {
  const { page, calls } = setup(); page.aboutToAppear(); await tick();
  activate(page, false); await page.refresh(); await page.refresh();
  assert.equal(calls.pages.length, 1); assert.equal(page.refreshPending, true);
  activate(page, true); activate(page, true); await tick();
  assert.equal(calls.pages.length, 2); assert.equal(page.refreshPending, false);
  await page.refresh(); assert.equal(calls.pages.length, 3, 'visible explicit refresh remains available');
});

test('category changes still fetch the chosen first page and survive subsequent tab switches', async () => {
  const { page, calls } = setup(); page.aboutToAppear(); await tick();
  page.choose('action'); await tick();
  assert.equal(page.categoryId, 'action'); assert.equal(page.heroVideos[0].id, 'movie-action-1');
  assert.equal(page.showHero(), true);
  assert.deepEqual(calls.pages.at(-1), { category: 'action', keyword: '', number: 1 });
  activate(page, false); activate(page, true); await tick();
  assert.equal(calls.pages.length, 2); assert.equal(page.categoryId, 'action');
});

test('an initial failure is retained on return and the existing explicit retry recovers', async () => {
  const { page, calls, state } = setup(); state.fail = true; page.aboutToAppear(); await tick();
  assert.equal(page.error, 'catalog failed'); assert.equal(page.loading, false);
  activate(page, false); activate(page, true); await tick();
  assert.equal(calls.categories, 1); assert.equal(page.error, 'catalog failed');
  state.fail = false; await page.refresh(); assert.equal(page.error, ''); assert.equal(page.page, 1);
});

test('a failed directory preserves the valid catalog and switching directories can recover without recreating the subscription', async () => {
  const { page, state, published } = setup();
  state.sites.push({ key: 'b', name: '目录乙' }); state.fail = true;
  page.aboutToAppear(); await tick();
  assert.equal(page.error, 'catalog failed'); assert.equal(page.loading, false);
  assert.ok(page.provider instanceof NodeProvider);
  assert.equal(page.nodeSiteKey, 'a'); assert.equal(page.nodeSites.length, 2);
  assert.equal(published.at(-1).loading, false); assert.equal(published.at(-1).sites.length, 2);
  assert.ok(published.at(-1).provider instanceof NodeProvider);
  state.fail = false;
  await page.chooseNodeSite('b'); await tick();
  assert.equal(page.error, ''); assert.equal(page.nodeSiteKey, 'b'); assert.equal(page.page, 1);
  assert.ok(page.videos.length > 0); assert.equal(published.at(-1).selectedKey, 'b');
});

test('removal invalidates in-flight work, and reappearance retries without an old result overwriting it', async () => {
  const { page, calls, state } = setup(); const old = deferred(); state.pageGate = old;
  page.aboutToAppear(); await tick(); page.aboutToDisappear();
  assert.equal(page.refreshPending, true); assert.equal(page.loading, false);
  state.pageGate = null; page.aboutToAppear(); await tick();
  const videos = page.videos, version = page.heroVersion;
  old.resolve(); await tick();
  assert.equal(calls.pages.length, 2); assert.equal(page.videos, videos); assert.equal(page.heroVersion, version);
  assert.equal(page.loading, false); assert.equal(page.refreshing, false);
});

test('history failures and out-of-order history responses cannot reset or replace home content', async () => {
  const { page, state } = setup(); page.aboutToAppear(); await tick(); const videos = page.videos;
  const older = deferred(); state.historyGate = older;
  const first = page.refreshResume();
  const newer = deferred(); state.historyGate = newer;
  const second = page.refreshResume();
  newer.resolve([{ id: 'new' }]); await second;
  older.resolve([{ id: 'old' }]); await first;
  assert.equal(page.resume[0].id, 'new');
  state.historyGate = null; state.failHistory = true;
  activate(page, false); activate(page, true); await tick();
  assert.equal(page.resume[0].id, 'new'); assert.equal(page.videos, videos); assert.equal(page.error, '');
});

test('a removed page ignores delayed history updates', async () => {
  const { page, state } = setup(); page.aboutToAppear(); await tick();
  state.historyGate = deferred(); const pending = page.refreshResume();
  page.aboutToDisappear(); state.historyGate.resolve([{ id: 'stale' }]); await pending;
  assert.deepEqual(page.resume, []);
});

test('Cat resume prefers a saved exit frame and ignores stale frame lookups while keeping provider artwork', async () => {
  const { page, state } = setup(); page.aboutToAppear(); await tick();
  state.history = [{ id: 'saved', positionMs: 17000, poster: 'original-cover', backdrop: '' }];
  state.frameUri = 'file:///exit-frame.jpg'; await page.refreshResume();
  assert.equal(page.resume[0].backdrop, 'file:///exit-frame.jpg'); assert.equal(page.resume[0].poster, 'original-cover');
  state.history = [{ id: 'old', positionMs: 5000, poster: 'old-cover' }]; state.frameGate = deferred();
  const first = page.refreshResume(); await tick(); const old = state.frameGate;
  state.frameGate = null; state.frameUri = '';
  state.history = [{ id: 'new', positionMs: 9000, poster: 'new-cover', backdrop: '' }];
  await page.refreshResume(); old.resolve('file:///old-frame.jpg'); await first;
  assert.equal(page.resume[0].id, 'new'); assert.equal(page.resume[0].poster, 'new-cover'); assert.equal(page.resume[0].backdrop, '');
});

test('history and exit-frame notifications update retained home immediately without resetting catalog, carousel or scroll', async () => {
  const { page, state, calls } = setup();
  state.history = [{ id: 'watched', positionMs: 2240, poster: 'original', backdrop: '' }];
  page.aboutToAppear(); await tick();
  const videos = page.videos, slides = page.heroVideos, revision = page.heroVersion;
  const requests = calls.pages.length, categories = calls.categories;
  page.scroller.offset = 640;
  state.history = [{ id: 'watched', positionMs: 8000, poster: 'original', backdrop: '' }];
  page.onPlaybackHistoryChanged(); await tick();
  assert.equal(page.resume[0].positionMs, 8000); assert.equal(page.resume[0].backdrop, '');
  state.frameUri = 'file:///new-exit-frame.jpg';
  page.onPlaybackHistoryChanged(); await tick();
  assert.equal(page.resume[0].backdrop, state.frameUri); assert.equal(page.resume[0].positionMs, 8000);
  assert.equal(page.videos, videos); assert.equal(page.heroVideos, slides); assert.equal(page.heroVersion, revision);
  assert.equal(page.scroller.offset, 640); assert.equal(calls.pages.length, requests); assert.equal(calls.categories, categories);
});

test('hidden and disposed home ignore history notifications and activation reads the latest progress and frame', async () => {
  const { page, state, calls } = setup(); page.aboutToAppear(); await tick();
  activate(page, false); const requests = calls.history;
  state.history = [{ id: 'watched', positionMs: 22280, poster: 'original' }]; state.frameUri = 'file:///latest.jpg';
  page.onPlaybackHistoryChanged(); await tick(); assert.equal(calls.history, requests);
  activate(page, true); await tick();
  assert.equal(page.resume[0].positionMs, 22280); assert.equal(page.resume[0].backdrop, state.frameUri);
  page.aboutToDisappear(); const disposed = calls.history;
  page.onPlaybackHistoryChanged(); await tick(); assert.equal(calls.history, disposed);
});

test('a late progress lookup cannot replace the frame published by a later history notification', async () => {
  const { page, state } = setup(); page.aboutToAppear(); await tick();
  const older = deferred(); state.historyGate = older;
  page.onPlaybackHistoryChanged(); await tick();
  state.historyGate = null; state.history = [{ id: 'watched', positionMs: 21640, poster: 'original' }];
  state.frameUri = 'file:///latest-frame.jpg'; page.onPlaybackHistoryChanged(); await tick();
  older.resolve([{ id: 'watched', positionMs: 7320, poster: 'original' }]); await tick();
  assert.equal(page.resume[0].positionMs, 21640); assert.equal(page.resume[0].backdrop, state.frameUri);
});

test('a successful empty response is cached instead of being mistaken for an unloaded page', async () => {
  const { page, calls, state } = setup(); state.empty = true; page.aboutToAppear(); await tick();
  assert.equal(page.page, 1); assert.deepEqual(page.videos, []);
  activate(page, false); activate(page, true); await tick();
  assert.equal(calls.pages.length, 1); assert.equal(page.loading, false);
});

test('a retained instance that reappears after completion keeps its data without a full refresh', async () => {
  const { page, calls } = setup(); page.aboutToAppear(); await tick();
  const videos = page.videos; page.scroller.offset = 300;
  page.aboutToDisappear(); page.aboutToAppear(); await tick();
  assert.equal(page.videos, videos); assert.equal(page.scroller.offset, 300);
  assert.equal(calls.pages.length, 1); assert.equal(page.loading, false);
});

test('navigation publications avoid writes during parent render and coalesce to the latest completed state', () => {
  const { page, published, frames, render } = setup();
  let rendering = true;
  page.onNavigationChanged = value => { assert.equal(rendering, false); published.push(value); };
  page.alive = true; page.refreshPending = false; page.page = 1; page.loading = true;
  page.onActiveChanged();
  page.loading = false; page.heroVideos = [{ id: 'featured' }]; page.heroSurface = '#123456';
  page.publishNavigation(); page.publishNavigation();
  assert.equal(published.length, 0); assert.equal(frames.length, 1);
  rendering = false; render();
  assert.equal(published.length, 1); assert.equal(published[0].loading, false);
  assert.equal(published[0].heroVisible, true); assert.equal(published[0].heroSurface, '#123456');
});

test('old queued navigation cannot publish after hiding/removal or consume a new activation publication', () => {
  const { page, published, frames, render } = setup();
  page.alive = true; page.refreshPending = false; page.loading = false;
  page.publishNavigation(); const old = frames.shift();
  activate(page, false); activate(page, true);
  assert.equal(page.navigationPending, true);
  old.onFrame(); assert.equal(published.length, 0); assert.equal(page.navigationPending, true);
  render(); assert.equal(published.length, 1);
  page.publishNavigation(); page.aboutToDisappear(); render();
  assert.equal(published.length, 1);
});

const cachedHome = (poster = 'https://server.test/poster') => ({
  savedAt: Date.now(), pageCount: 3, categoryId: '', siteKey: 'a', sites: [{ key: 'a', name: '目录甲' }],
  categories: [{ id: 'action', name: '动作片' }], videos: [{ id: 'cached', name: '上次首页', poster }]
});

test('fresh persisted home bypasses registry, directories, categories and first-page network on cold start', async () => {
  const { page, calls, state } = setup(); state.cache = cachedHome(); page.aboutToAppear(); await tick();
  assert.equal(page.videos[0].id, 'cached'); assert.equal(page.loading, false); assert.equal(page.page, 1);
  assert.equal(calls.cacheReads, 1); assert.equal(calls.registry, 0); assert.equal(calls.sites, 0);
  assert.equal(calls.categories, 0); assert.equal(calls.pages.length, 0); assert.equal(calls.history, 1);
  activate(page, false); activate(page, true); await tick(); assert.equal(calls.cacheReads, 1);
});

test('stale home appears before refresh completes and a failed refresh preserves it atomically', async () => {
  const { page, state, calls } = setup(); state.cache = cachedHome(); state.cacheFresh = false;
  state.categoryGate = deferred(); state.fail = true; page.aboutToAppear(); await tick();
  assert.equal(page.videos[0].id, 'cached'); assert.equal(page.loading, false);
  const categories = page.categories; state.categoryGate.resolve(); await tick();
  assert.equal(page.videos[0].id, 'cached'); assert.equal(page.categories, categories);
  assert.equal(page.error, ''); assert.equal(page.refreshing, false); assert.equal(calls.cacheWrites.length, 0);
});

test('successful stale refresh, explicit refresh and categories save first pages; searches do not cache', async () => {
  const { page, state, calls } = setup(); state.cache = cachedHome(); state.cacheFresh = false;
  page.aboutToAppear(); await tick();
  assert.equal(page.videos[0].id, 'movie--1'); assert.equal(calls.cacheWrites.length, 1);
  await page.refresh(); assert.equal(calls.cacheWrites.length, 2);
  page.choose('action'); await tick(); assert.equal(calls.cacheWrites.length, 3);
  assert.equal(calls.cacheWrites.at(-1).categoryId, 'action');
  page.query = '关键词'; page.search(); await tick(); assert.equal(calls.cacheWrites.length, 3);
});

test('cached local proxy covers are blank until rebased to this process without querying home', async () => {
  const { page, state, calls } = setup(); state.cache = cachedHome('http://127.0.0.1:1000/imgProxy?url=poster');
  state.proxyGate = deferred(); page.aboutToAppear(); await tick(); assert.equal(page.videos[0].poster, '');
  state.proxyGate.resolve('http://127.0.0.1:3000'); await tick();
  assert.equal(page.videos[0].poster, 'http://127.0.0.1:3000/imgProxy?url=poster');
  assert.equal(calls.pages.length, 0); assert.equal(calls.categories, 0);
});

test('late disk reads and proxy startup cannot replace data after source/page removal', async () => {
  const first = setup(); first.state.cache = cachedHome(); first.state.cacheGate = deferred();
  first.page.aboutToAppear(); first.page.aboutToDisappear(); first.state.cacheGate.resolve(); await tick();
  assert.deepEqual(first.page.videos, []); assert.equal(first.calls.registry, 0);
  const second = setup(); second.state.cache = cachedHome('http://127.0.0.1:1000/poster'); second.state.proxyGate = deferred();
  second.page.aboutToAppear(); await tick(); second.page.aboutToDisappear();
  second.state.proxyGate.resolve('http://127.0.0.1:4000'); await tick(); assert.equal(second.page.videos[0].poster, '');
});

test('cached category first pages restore their own carousel without a catalog request', async () => {
  const { page, state, calls } = setup(); state.cache = cachedHome();
  state.categoryCaches.set('action', { ...cachedHome(), categoryId: 'action',
    videos: [{ id: 'cached-action', name: '动作影片', poster: 'https://server.test/action' }] });
  page.aboutToAppear(); await tick(); page.choose('action'); await tick();
  assert.equal(page.videos[0].id, 'cached-action'); assert.equal(page.heroVideos[0].id, 'cached-action');
  assert.equal(page.showHero(), true); assert.equal(calls.pages.length, 0);
  page.choose(''); await tick();
  assert.equal(page.videos[0].id, 'cached'); assert.equal(page.heroVideos[0].id, 'cached');
  assert.equal(calls.pages.length, 0);
});

test('proxy completion repairs current category posters without navigation or array identity assumptions', async () => {
  const { page, state, calls, published } = setup(); state.cache = cachedHome();
  state.categoryCaches.set('action', { ...cachedHome('http://127.0.0.1:1000/poster'), categoryId: 'action' });
  page.aboutToAppear(); await tick(); state.proxyGate = deferred(); page.choose('action'); await tick();
  assert.equal(page.videos[0].poster, '');
  // ArkUI @State observation may wrap arrays; reference identity is not a content revision.
  page.videos = new Proxy(page.videos.slice(), {});
  state.proxyGate.resolve('http://127.0.0.1:3000'); await tick();
  assert.equal(page.videos[0].poster, 'http://127.0.0.1:3000/poster');
  assert.equal(published.at(-1).heroVisible, true); assert.equal(calls.pages.length, 0);
});

test('loading more while cached proxy startup is pending preserves appended pages and first-page hero', async () => {
  const { page, state } = setup(); state.cache = cachedHome('http://127.0.0.1:1000/poster');
  state.proxyGate = deferred(); page.aboutToAppear(); await tick();
  await page.more(); assert.equal(page.page, 2); const revision = page.contentRevision;
  state.proxyGate.resolve('http://127.0.0.1:3000'); await tick();
  assert.equal(page.page, 2); assert.equal(page.contentRevision, revision);
  assert.deepEqual(page.videos.map(item => item.id), ['cached', 'movie--2']);
  assert.equal(page.videos[0].poster, 'http://127.0.0.1:3000/poster');
  assert.deepEqual(page.heroVideos.map(item => item.id), ['cached']);
});

test('late overview proxy startup cannot replace a newly selected category carousel', async () => {
  const { page, state } = setup(); state.cache = cachedHome('http://127.0.0.1:1000/poster');
  state.proxyGate = deferred(); page.aboutToAppear(); await tick();
  page.choose('action'); await tick();
  const videos = page.videos, heroes = page.heroVideos;
  state.proxyGate.resolve('http://127.0.0.1:3000'); await tick();
  assert.equal(page.categoryId, 'action'); assert.equal(page.videos, videos); assert.equal(page.heroVideos, heroes);
  assert.equal(page.heroVideos[0].id, 'movie-action-1');
});

test('a stale cached page with failed refresh still finishes preparing its proxy posters', async () => {
  const { page, state, calls } = setup(); state.cache = cachedHome('http://127.0.0.1:1000/poster');
  state.cacheFresh = false; state.fail = true; state.proxyGate = deferred();
  page.aboutToAppear(); await tick(); assert.equal(page.loading, false);
  state.proxyGate.resolve('http://127.0.0.1:3000'); await tick();
  assert.equal(page.videos[0].poster, 'http://127.0.0.1:3000/poster');
  assert.equal(page.error, ''); assert.equal(calls.cacheWrites.length, 0);
});

test('history proxy artwork is prepared before publishing and late preparation cannot replace newer history', async () => {
  const { page, state } = setup(); page.aboutToAppear(); await tick();
  state.history = [{ id: 'old', poster: 'http://127.0.0.1:1000/poster', backdrop: 'http://127.0.0.1:1000/backdrop' }];
  state.proxyGate = deferred(); const pending = page.refreshResume(); await tick();
  state.history = [{ id: 'new', poster: 'https://server.test/new', backdrop: '' }];
  await page.refreshResume();
  state.proxyGate.resolve('http://127.0.0.1:3000'); await pending;
  assert.equal(page.resume[0].id, 'new');
  state.history = [{ id: 'rebased', poster: 'http://127.0.0.1:1000/poster', backdrop: 'http://127.0.0.1:1000/backdrop' }];
  await page.refreshResume();
  assert.equal(page.resume[0].poster, 'http://127.0.0.1:3000/poster');
  assert.equal(page.resume[0].backdrop, 'http://127.0.0.1:3000/backdrop');
});

test('unfinished proxy preparation resumes when a retained page reappears after removal', async () => {
  const { page, state, calls } = setup(); state.cache = cachedHome('http://127.0.0.1:1000/poster');
  state.proxyGate = deferred(); page.aboutToAppear(); await tick();
  assert.equal(page.videos[0].poster, ''); page.aboutToDisappear();
  state.proxyGate.resolve('http://127.0.0.1:3000'); await tick();
  assert.equal(page.videos[0].poster, '');
  page.aboutToAppear(); await tick();
  assert.equal(page.videos[0].poster, 'http://127.0.0.1:3000/poster');
  assert.equal(page.artworkSnapshot, null); assert.equal(calls.pages.length, 0);
});

test('a failed manual refresh does not cancel pending cached poster restoration permanently', async () => {
  const { page, state } = setup(); state.cache = cachedHome('http://127.0.0.1:1000/poster');
  state.proxyGate = deferred(); page.aboutToAppear(); await tick();
  state.fail = true; await page.refresh();
  state.proxyGate.resolve('http://127.0.0.1:3000'); await tick();
  assert.equal(page.videos[0].poster, 'http://127.0.0.1:3000/poster'); assert.equal(page.error, '');
});

test('near-bottom checks coalesce per frame and serialize the next request without resetting hero or scroll', async () => {
  const { page, calls, state } = setup(); page.aboutToAppear(); await tick(); page.viewportHeight = 800;
  state.contentRect.height = 1201; page.queuePaginationCheck(); await tick(); assert.equal(calls.pages.length, 1);
  state.contentRect.height = 1200; state.pageGate = deferred();
  const heroes = page.heroVideos; page.scroller.offset = 900;
  for (let i = 0; i < 30; i++) page.queuePaginationCheck();
  await tick(); assert.equal(calls.pages.length, 2); assert.equal(page.paging, true);
  for (let i = 0; i < 30; i++) page.queuePaginationCheck();
  await tick(); assert.equal(calls.pages.length, 2);
  state.contentRect.height = 4000; state.pageGate.resolve(); await tick();
  assert.equal(page.page, 2); assert.equal(page.paging, false); assert.equal(page.heroVideos, heroes);
  assert.equal(page.scroller.offset, 900); assert.equal(calls.pages.length, 2);
});

test('short visible content fills the preload window then stops once native geometry grows beyond it', async () => {
  const { page, calls, state } = setup(); page.viewportHeight = 800;
  state.contentRect = page => ({ x: 0, y: 0, width: 360, height: page.videos.length * 600 + 100 });
  page.aboutToAppear(); await tick();
  assert.equal(page.page, 2); assert.equal(calls.pages.length, 2); assert.equal(page.videos.length, 2);
});

test('paging failures preserve content and block automatic retries until the explicit retry succeeds', async () => {
  const { page, calls, state } = setup(); page.aboutToAppear(); await tick(); page.viewportHeight = 800;
  state.contentRect.height = 1000; state.failPage = true; const original = page.videos;
  page.queuePaginationCheck(); await tick(); assert.equal(page.pageError, 'next page failed');
  assert.equal(page.page, 1); assert.equal(page.videos, original);
  for (let i = 0; i < 20; i++) { page.queuePaginationCheck(); await tick(); }
  assert.equal(calls.pages.length, 2);
  state.failPage = false; state.contentRect.height = 4000; await page.more(); await tick();
  assert.equal(page.pageError, ''); assert.equal(page.page, 2); assert.equal(calls.pages.length, 3);
});

test('queued pagination cannot run after hiding or a category switch, and reactivation checks current geometry', async () => {
  const { page, calls, state } = setup(); page.aboutToAppear(); await tick(); page.viewportHeight = 800;
  state.contentRect.height = 1000; page.queuePaginationCheck(); activate(page, false); await tick();
  assert.equal(calls.pages.length, 1); await page.more(); assert.equal(calls.pages.length, 1);
  state.contentRect.height = 4000; activate(page, true); await tick(); assert.equal(calls.pages.length, 1);
  state.contentRect.height = 1000; page.queuePaginationCheck();
  state.contentRect.height = 4000; page.choose('action'); await tick();
  assert.deepEqual(calls.pages.map(item => item.category), ['', 'action']); assert.equal(page.categoryId, 'action');
  page.queuePaginationCheck(); page.aboutToDisappear(); await tick(); assert.equal(calls.pages.length, 2);
});

test('invalid native geometry is ignored and a later layout check can recover', async () => {
  const { page, calls, state } = setup(); page.aboutToAppear(); await tick(); page.viewportHeight = 800;
  for (const rect of [{ y: 0, height: 0 }, { y: NaN, height: 200 }, { y: 0, height: Infinity }]) {
    state.contentRect = rect; page.queuePaginationCheck(); await tick();
  }
  state.unbound = true; page.queuePaginationCheck(); await tick(); assert.equal(calls.pages.length, 1);
  state.unbound = false; state.contentRect = { y: 0, height: 1000 }; state.pageGate = deferred();
  page.queuePaginationCheck(); await tick(); assert.equal(calls.pages.length, 2);
  state.contentRect.height = 4000; state.pageGate.resolve(); await tick(); assert.equal(page.page, 2);
});

test('empty and duplicate-only next pages terminate automatic paging instead of draining a bogus page count', async () => {
  for (const duplicate of [false, true]) {
    const { page, calls, state } = setup(); page.aboutToAppear(); await tick();
    const first = page.videos.slice(); page.viewportHeight = 800; state.contentRect.height = 1000;
    state.pageResult = { page: 2, pageCount: 9999, videos: duplicate ? first : [] };
    page.queuePaginationCheck(); await tick();
    assert.equal(page.page, 2); assert.equal(page.pageCount, 2); assert.deepEqual(page.videos, first);
    page.queuePaginationCheck(); await tick(); assert.equal(calls.pages.length, 2);
    assert.equal(page.pageError, '');
  }
});

test('list scrolling and layout events trigger checks; the footer keeps only progress, retry and end state', () => {
  assert.ok(source.includes('.onDidScroll(() => this.queuePaginationCheck())'));
  assert.ok(source.includes('.onReachEnd(() => this.queuePaginationCheck())'));
  const footer = source.slice(source.indexOf('  private PageFooter()'), source.indexOf('  private CategoryButton('));
  assert.equal(footer.includes("$r('app.string.catvod_load_more')"), false);
  assert.ok(footer.includes("$r('app.string.catvod_loading_more')"));
  assert.ok(footer.includes("$r('app.string.cat_home_retry')"));
});
