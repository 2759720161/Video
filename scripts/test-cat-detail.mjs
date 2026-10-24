import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { test } from 'node:test';

const read = name => readFileSync(new URL('../entry/src/main/ets/' + name, import.meta.url), 'utf8');
const compile = source => stripTypeScriptTypes(source.replace(/^import .*\r?\n/gm, ''), { mode: 'transform' });
const presentation = compile(read('pages/catvod/CatVodDetailPresentation.ets').replace(/export class /g, 'class '));
const { Presentation, Rows } = new Function(presentation + ';return { Presentation: CatVodDetailPresentation, Rows: CatVodEpisodeRows };')();
const heroColors = compile(read('services/media/HomeHeroColors.ets').replace(/export class /g, 'class '));
const HomeHeroColors = new Function(heroColors + ';return HomeHeroColors;')();
const configuration = compile(read('providers/catvod/CatNodeConfiguration.ets').replace(/export class /g, 'class '));
const CatNodeConfiguration = new Function('url', configuration + ';return CatNodeConfiguration;')({
  URL: class extends URL { static parseURL(value) { return new this(value); } }
});
const source = read('pages/catvod/CatVodDetailPage.ets');
const methods = compile(`class Page { ${source.slice(source.indexOf('  aboutToAppear()'), source.indexOf('  build()'))} }`);
const defer = () => { let resolve; let reject; const promise = new Promise((yes, no) => { resolve = yes; reject = no; }); return { promise, resolve, reject }; };
const episode = n => ({ id: `catvod|v|ep${n}|0`, subtitle: `第 ${n} 集`, variantId: 'a' });
class CatNodeRecommendationError extends Error {}
class CatNodeEmptyDetailError extends Error {}

function setup() {
  const a = [episode(1), episode(2), episode(3)];
  const b = [episode(2), episode(4)].map(item => ({ ...item, variantId: 'b' }));
  const state = { video: { id: 'v', name: '作品', poster: 'https://images.test/v', year: 2026,
    remarks: '全三集', overview: '简介', roads: [{ id: 'a', name: '线路 A' }, { id: 'b', name: '线路 B' }] },
    history: [], historyTask: null, detailTask: null, paletteTask: null, launchTask: null, failLaunch: false,
    useNode: false, detailReads: 0, routeFailure: false };
  const opened = [], toasts = [], routes = [];
  class Provider {
    static defaultRoad(video) { return video.roads[0] ?? null; }
    async getDetail() {
      state.detailReads++; if (state.detailError) throw state.detailError;
      return state.detailTask ? await state.detailTask.promise : state.video;
    }
    episodeItems(_video, id) { return id === 'a' ? a.slice() : b.slice(); }
  }
  class NodeProvider extends Provider { getSiteKey() { return 'baseset'; } }
  const provider = new Provider();
  const nodeProvider = new NodeProvider();
  const dependencies = {
    CatVodProvider: Provider, CatNodeProvider: NodeProvider, CatNodeConfiguration,
    CatNodeRecommendationError, CatNodeEmptyDetailError,
    MediaSearchPresentation: { normalize: value => value.trim().replace(/\s+/g, ' ').slice(0, 255) },
    ProviderRegistry: { get: async () => state.useNode ? nodeProvider : provider },
    CatVodDetailPresentation: Presentation,
    CatVodCodec: { identity: id => id.startsWith('catvod|') ? { videoId: id.split('|')[1] } : null },
    PlaybackHistoryStore: class { async getAll() { return state.historyTask ? await state.historyTask.promise : state.history; } },
    HomeHeroPalette: { resolve: async () => state.paletteTask ? await state.paletteTask.promise : '#7080a0' },
    HomeHeroColors,
    ProviderPlaybackLauncher: { async openWithProvider(_ctx, selectedProvider, item, queue) {
      opened.push({ provider: selectedProvider, item, queue });
      if (state.failLaunch) throw new Error('播放失败');
      if (state.launchTask) await state.launchTask.promise;
    } },
    buildDetailToastOptions: message => ({ message }), $r: name => ({ id: name })
  };
  const Page = new Function(...Object.keys(dependencies), methods + ';return Page;')(...Object.values(dependencies));
  const page = Object.assign(new Page(), {
    sourceId: 'source', videoId: 'v', video: state.video, provider, alive: true, generation: 1,
    selectionRevision: 0, roadId: '', episodes: [], selectedEpisodeId: '',
    loading: false, playing: false, error: '', posterFailed: false, heroSurface: '#f2f2f2', heroTone: '',
    themeBase: 0xfff2f2f2, overviewExpanded: false, openingConfiguration: false,
    openingSearch: false, requestTitle: '', fromSearch: false,
    episodeRows: new Rows(),
    getUIContext: () => ({ getHostContext: () => ({ resourceManager: { getStringSync: id => id } }),
      getPromptAction: () => ({ showToast: options => toasts.push(options.message) }),
      getRouter: () => ({ async pushUrl(options) {
        if (state.routeFailure) throw new Error('cannot open search'); routes.push(options);
      }, async replaceUrl(options) {
        if (state.routeFailure) throw new Error('cannot open configuration'); routes.push(options);
      } }) })
  });
  page.chooseRoad('a');
  return { page, state, opened, toasts, routes, a, b, provider };
}

test('configuration tool replaces the fake media detail without requesting its unsupported WebView bridge', async () => {
  const { page, state, routes } = setup();
  state.useNode = true; page.videoId = 'catnode:baseset:config-center';
  await page.load();
  assert.equal(state.detailReads, 0); assert.equal(page.openingConfiguration, true);
  assert.deepEqual(routes, [{ url: 'pages/catvod/CatNodeConfigurationPage', params: { sourceId: 'source' } }]);
  const failed = setup(); failed.state.useNode = true; failed.state.routeFailure = true;
  failed.page.videoId = 'config-center'; await failed.page.load();
  assert.equal(failed.page.openingConfiguration, false); assert.equal(failed.page.loading, false);
  assert.equal(failed.page.error, 'cannot open configuration');
});

test('a known index from a cached card replaces detail with seeded search; search-origin items never auto-loop', async () => {
  const f = setup(); f.page.requestTitle = '  影片  第一季 '; f.state.detailError = new CatNodeRecommendationError('index');
  await f.page.load();
  assert.deepEqual(f.routes, [{ url: 'pages/home/SearchPage', params: { sourceId: 'source', keyword: '影片 第一季' } }]);
  const search = setup(); search.page.requestTitle = '影片'; search.page.fromSearch = true;
  search.state.detailError = new CatNodeRecommendationError('index');
  await search.page.load(); assert.equal(search.routes.length, 0); assert.equal(search.page.error, 'index');
  await search.page.openSearch();
  assert.deepEqual(search.routes, [{ url: 'pages/home/SearchPage', params: { sourceId: 'source', keyword: '影片' } }]);
});

test('unknown empty detail and real failures preserve retry and only search on explicit action', async () => {
  for (const error of [new CatNodeEmptyDetailError('empty'), new Error('HTTP 500'), new Error('network failed')]) {
    const f = setup(); f.page.requestTitle = '原始标题'; f.state.detailError = error;
    await f.page.load(); assert.equal(f.routes.length, 0); assert.equal(f.page.loading, false);
    assert.equal(f.page.error, error instanceof CatNodeEmptyDetailError ? 'app.string.cat_detail_empty_response' : error.message);
    await f.page.openSearch(); assert.equal(f.routes[0].params.keyword, '原始标题');
  }
});

test('late index response, missing titles and inactive pages cannot launch search', async () => {
  const late = setup(); late.page.requestTitle = '影片'; late.state.detailTask = defer();
  const task = late.page.load(); await Promise.resolve();
  late.page.alive = false; late.page.generation++;
  late.state.detailTask.reject(new CatNodeRecommendationError('index')); await task;
  assert.equal(late.routes.length, 0);
  const empty = setup(); empty.state.detailError = new CatNodeRecommendationError('index');
  await empty.page.load(); assert.equal(empty.routes.length, 0);
  empty.page.alive = false; empty.page.requestTitle = '影片'; await empty.page.openSearch();
  assert.equal(empty.routes.length, 0);
});

test('search navigation failure leaves detail retryable and can be retried', async () => {
  const f = setup(); f.page.requestTitle = '影片'; f.state.detailError = new CatNodeRecommendationError('index');
  f.state.routeFailure = true; await f.page.load();
  assert.equal(f.page.error, 'app.string.cat_detail_search_failed'); assert.equal(f.page.openingSearch, false);
  f.state.routeFailure = false; await f.page.openSearch(); assert.equal(f.routes[0].params.keyword, '影片');
});

test('manual search double taps dispatch once and playback or missing titles cannot navigate', async () => {
  const f = setup(); await Promise.all([f.page.openSearch(), f.page.openSearch()]);
  assert.equal(f.routes.length, 1); assert.equal(f.page.openingSearch, false);
  f.page.playing = true; await f.page.openSearch(); assert.equal(f.routes.length, 1);
  f.page.playing = false; f.page.video = null; f.page.requestTitle = ''; await f.page.openSearch();
  assert.equal(f.routes.length, 1);
});

test('hero height remains bounded and metadata uses only actual supplied values', () => {
  for (const width of [240, 360, 600, 840, 1320, 0, NaN]) {
    const height = Presentation.heroHeight(width, 24);
    assert.ok(height >= 424 && height <= 644);
  }
  assert.equal(Presentation.metadata({ year: 2026, remarks: ' 全十集 ' }), '2026 · 全十集');
  assert.equal(Presentation.metadata({ year: 0, remarks: '' }), '');
  assert.equal(Presentation.alpha('#aabbcc', '00'), '#00aabbcc');
  assert.equal(Presentation.alpha('#aabbcc', 'EE'), '#EEaabbcc');
  assert.equal(Presentation.alpha('invalid', '00'), '#00000000');
});

test('ordinary poster gradient reaches the exact theme surface before the image edge', () => {
  const alpha = color => parseInt(color.slice(1, 3), 16) / 255;
  const channels = color => [1, 3, 5].map(offset => parseInt(color.slice(offset, offset + 2), 16));
  for (const surface of ['#f2f2f2', '#121212', '#000000', '#ffffff', '#a8c4de']) {
    const stops = Presentation.posterGradient(surface);
    assert.equal(stops[0][1], 0); assert.equal(stops.at(-1)[1], 1);
    for (let i = 0; i < stops.length; i++) {
      const [color, position] = stops[i];
      assert.match(color, /^#[0-9a-f]{8}$/i);
      assert.equal(color.slice(3).toLowerCase(), surface.slice(1));
      assert.ok(position >= 0 && position <= 1);
      if (i) {
        assert.ok(position > stops[i - 1][1]);
        assert.ok(alpha(color) >= alpha(stops[i - 1][0]));
      }
      if (position <= 0.24) assert.equal(alpha(color), 0);
    }
    const opaqueTail = stops.findIndex(([color]) => alpha(color) === 1);
    assert.ok(stops[opaqueTail][1] <= 0.9, 'finish fading before the physical clipping edge');
    for (const poster of ['#000000', '#ffffff', '#ff0000', '#00ff00', '#0000ff']) {
      const base = channels(surface), image = channels(poster);
      for (const [color] of stops.slice(opaqueTail)) {
        const amount = alpha(color);
        const overlay = channels('#' + color.slice(3));
        const composed = image.map((value, index) => value * (1 - amount) + overlay[index] * amount);
        assert.deepEqual(composed, base, `${poster} must converge exactly to ${surface}`);
      }
    }
  }
});

test('lazy single-column rows preserve every episode and canonical order across empty, odd and long catalogs', () => {
  const rows = new Rows();
  for (const count of [0, 1, 2, 3, 10, 1001]) {
    const items = Array.from({ length: count }, (_, index) => episode(index + 1));
    for (const descending of [false, true]) {
      rows.replace(items, descending);
      assert.equal(rows.totalCount(), count);
      const actual = Array.from({ length: rows.totalCount() }, (_, index) => rows.getData(index)).flatMap(row => row.items);
      assert.deepEqual(actual, descending ? items.slice().reverse() : items);
      assert.equal(items[0]?.id, count ? episode(1).id : undefined);
      if (count) assert.equal(rows.rowOf(actual.at(-1).id), rows.totalCount() - 1);
    }
  }
  assert.equal(rows.rowOf('missing'), -1);
});

test('lazy reload listeners register once, unregister and receive replacement events', () => {
  const rows = new Rows(); let calls = 0;
  const listener = { onDataReloaded: () => calls++ };
  rows.registerDataChangeListener(listener); rows.registerDataChangeListener(listener);
  rows.replace([episode(1)], false); assert.equal(calls, 1);
  rows.unregisterDataChangeListener(listener); rows.replace([], false); assert.equal(calls, 1);
});

test('road switching retains matching episode identity and otherwise selects the canonical first episode', () => {
  const { page, a, b } = setup();
  page.selectedEpisodeId = a[1].id; page.chooseRoad('b');
  assert.equal(page.selectedEpisodeId, b[0].id); assert.equal(page.primaryItem().variantId, 'b');
  page.selectedEpisodeId = b[1].id; page.chooseRoad('a');
  assert.equal(page.selectedEpisodeId, a[0].id);
  assert.equal(page.episodeRows.getData(0).items[0].id, a[0].id);
  page.chooseRoad('missing'); assert.equal(page.episodes.length, 0); assert.equal(page.primaryItem(), null);
});

test('primary playback uses the selected episode and original provider queue', async () => {
  const { page, a, opened } = setup();
  page.selectedEpisodeId = a[1].id;
  await page.playPrimary(); assert.equal(opened[0].item, a[1]); assert.deepEqual(opened[0].queue, a);
});

test('preparing playback blocks duplicate launches and road changes, then failures unlock the page', async () => {
  const { page, state, opened, toasts } = setup(); state.launchTask = defer();
  const playing = page.playPrimary();
  assert.equal(page.playing, true); page.chooseRoad('b'); await page.playPrimary();
  assert.equal(opened.length, 1); assert.equal(page.roadId, 'a');
  state.launchTask.resolve(); await playing; assert.equal(page.playing, false);
  state.launchTask = null; state.failLaunch = true; await page.playPrimary();
  assert.equal(page.playing, false); assert.deepEqual(toasts, ['播放失败']);
});

test('history restores only a matching source, video and available episode', async () => {
  const { page, state, a } = setup();
  state.history = [{ sourceId: 'other', mediaId: a[2].id }, { sourceId: 'source', mediaId: 'catvod|other|ep1|0' },
    { sourceId: 'source', mediaId: a[1].id }];
  await page.restoreSelection(page.generation); assert.equal(page.selectedEpisodeId, a[1].id);
});

test('late history cannot replace a newer road selection, playback selection or disposed page', async () => {
  for (const change of [f => f.page.chooseRoad('b'), f => f.page.playPrimary(), f => f.page.aboutToDisappear()]) {
    const f = setup(); f.state.historyTask = defer();
    const restore = f.page.restoreSelection(f.page.generation);
    await change(f); const selected = f.page.selectedEpisodeId;
    f.state.historyTask.resolve([{ sourceId: 'source', mediaId: f.a[2].id }]); await restore;
    assert.equal(f.page.selectedEpisodeId, selected);
  }
});

test('palette failures are contained and obsolete colors cannot tint a changed, failed or disposed poster', async () => {
  for (const change of [f => { f.page.video = { ...f.page.video, poster: 'other' }; },
    f => { f.page.posterFailed = true; }, f => f.page.aboutToDisappear()]) {
    const f = setup(); f.state.paletteTask = defer();
    const resolve = f.page.resolvePalette(f.page.video.poster, f.page.generation);
    change(f); f.state.paletteTask.resolve('#ffaa00'); await resolve;
    assert.equal(f.page.heroSurface, '#f2f2f2');
  }
  const f = setup(); f.state.paletteTask = defer();
  const resolve = f.page.resolvePalette(f.page.video.poster, f.page.generation);
  f.state.paletteTask.reject(new Error('image unavailable')); await resolve;
  assert.equal(f.page.heroSurface, '#f2f2f2');
});

test('pending, invalid and failed poster tones use the actual theme instead of an empty background', async () => {
  const f = setup();
  for (const base of [0xfff2f2f2, 0xff121212, 0xff000000, 0xffffffff]) {
    f.page.themeBase = base;
    const fallback = '#' + (base & 0xffffff).toString(16).padStart(6, '0');
    for (const tone of ['', 'invalid']) {
      f.page.applyHeroTone(tone);
      assert.equal(f.page.heroSurface, fallback);
    }
    f.page.applyHeroTone('#7080a0');
    assert.equal(f.page.heroSurface, HomeHeroColors.surface('#7080a0', base));
    f.page.applyHeroTone('');
    assert.equal(f.page.heroSurface, fallback);
    f.state.paletteTask = defer();
    const pending = f.page.resolvePalette(f.page.video.poster, f.page.generation);
    assert.equal(f.page.heroSurface, fallback);
    f.state.paletteTask.resolve(''); await pending;
    assert.equal(f.page.heroSurface, fallback);
  }
});

test('detail loading ignores a response after page disposal and recovers after an unavailable video', async () => {
  const f = setup(); f.page.video = null; f.state.detailTask = defer();
  const load = f.page.load(); await Promise.resolve(); f.page.aboutToDisappear();
  f.state.detailTask.resolve(f.state.video); await load; assert.equal(f.page.video, null);
  const g = setup(); g.state.video = null; await g.page.load();
  assert.equal(g.page.loading, false); assert.ok(g.page.error.length > 0);
});

test('material episode controls restore controlled selection and suppress repeated pending actions', () => {
  const action = read('pages/catvod/CatVodDetailAction.ets');
  const methods = action.slice(action.indexOf('  aboutToAppear()'), action.indexOf('  build()'));
  const callback = action.slice(action.indexOf('class CatVodDetailActionReset'));
  const Control = new Function('FrameCallback', compile(`class Control { ${methods} }\n${callback}`) + ';return Control;')(class {});
  const frames = []; let calls = 0;
  const control = Object.assign(new Control(), { alive: false, pending: false, resetTicket: 0,
    selected: true, toggled: false, actionEnabled: true, busy: false,
    getUIContext: () => ({ postFrameCallback: frame => frames.push(frame) }), onAction: () => calls++ });
  control.aboutToAppear(); assert.equal(control.toggled, true);
  control.toggled = false; control.changed(); control.changed();
  assert.equal(calls, 1); assert.equal(frames.length, 1);
  frames.shift().onIdle(); assert.equal(control.toggled, true); assert.equal(control.pending, false);
  control.changed(); const stale = frames.shift();
  control.aboutToDisappear(); control.selected = false; control.aboutToAppear();
  control.changed(); stale.onIdle(); assert.equal(control.pending, true);
  frames.shift().onIdle(); assert.equal(control.pending, false); assert.equal(control.toggled, false);
  const previous = calls;
  control.busy = true; control.changed(); control.busy = false; control.actionEnabled = false; control.changed();
  assert.equal(calls, previous); assert.equal(frames.length, 0);
});
