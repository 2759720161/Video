import { registerHooks, stripTypeScriptTypes } from 'node:module';
import { readFileSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';
import { test } from 'node:test';

registerHooks({
  resolve(specifier, context, next) {
    if (specifier.startsWith('.') && context.parentURL?.startsWith('file:')) {
      const target = new URL(specifier, context.parentURL);
      if (!target.pathname.endsWith('.ets')) target.pathname += '.ets';
      if (existsSync(fileURLToPath(target))) return { url: target.href, shortCircuit: true };
    }
    return next(specifier, context);
  },
  load(url, context, next) {
    if (url.endsWith('.ets')) return { format: 'module', source:
      stripTypeScriptTypes(readFileSync(new URL(url), 'utf8'), { mode: 'transform' }), shortCircuit: true };
    return next(url, context);
  }
});
const { CatVodHeroPresentation: Hero } = await import('../entry/src/main/ets/pages/catvod/CatVodHeroPresentation.ets');
const { CatVodVideo } = await import('../entry/src/main/ets/providers/catvod/CatVodModels.ets');
const { CatVodHomeNavigation } = await import('../entry/src/main/ets/pages/catvod/CatVodHomeNavigation.ets');
const read = name => readFileSync(new URL('../entry/src/main/ets/pages/catvod/' + name, import.meta.url), 'utf8');
const compilePage = methods => stripTypeScriptTypes(`class Page { ${methods} }`, { mode: 'transform' }) + '; return Page;';
const video = (id, extra = {}) => Object.assign(new CatVodVideo(), { id, name: '作品' + id, poster: 'https://image.invalid/' + id }, extra);

test('carousel uses up to six valid posters in source order, skipping duplicates and missing artwork', () => {
  const videos = [video('missing', { poster: '' }), video('empty-name', { name: '' }), video(''),
    video('a'), video('a'), ...Array.from({ length: 9 }, (_, i) => video(String(i)))];
  assert.deepEqual(Hero.select(videos).map(item => item.id), ['a', '0', '1', '2', '3', '4']);
  assert.equal(videos.length, 14);
  assert.deepEqual(Hero.select([]), []);
  assert.deepEqual(Hero.select([video('no-image', { poster: '  ' })]), []);
});

test('posters below the carousel exclude every featured ID without mutating cached or paginated content', () => {
  const items = Array.from({ length: 10 }, (_, i) => video(String(i)));
  const featured = Hero.select(items);
  const before = JSON.stringify(items);
  const restored = items.map(item => Object.assign(new CatVodVideo(), item, { poster: item.poster + '?restored' }));
  assert.deepEqual(Hero.belowHero(restored, featured).map(item => item.id), ['6', '7', '8', '9']);
  assert.equal(JSON.stringify(items), before); assert.equal(featured.length, 6); assert.equal(restored.length, 10);
  assert.deepEqual(Hero.belowHero(featured, featured), []);
  assert.equal(Hero.belowHero(items, []), items);
  const sameTitle = video('other-source:same-title', { name: featured[0].name });
  assert.deepEqual(Hero.belowHero([sameTitle], featured), [sameTitle]);
});

test('captions use only real summary/year/remarks, strip markup and bound long summaries', () => {
  assert.equal(Hero.summary(video('1', { overview: '<p>剧情介绍</p>' })), '剧情介绍');
  assert.deepEqual(Hero.metadata(video('1')), []);
  assert.deepEqual(Hero.metadata(video('1', { year: 2026, remarks: '<b>更新至第12集</b>' })), ['2026', '更新至第12集']);
  const summary = Hero.summary(video('1', { overview: '长'.repeat(100) }));
  assert.equal(summary, '长'.repeat(60) + '…');
});

const content = read('CatVodContent.ets');

test('grid filtering follows the visible category carousel and preserves search or standalone results', () => {
  const start = content.indexOf('  private posterVideos(');
  const display = content.slice(start, content.indexOf('  @Builder', start));
  const visibility = content.slice(content.indexOf('  private showHero('), content.indexOf('  private viewportWidth('));
  const Page = new Function('CatVodHeroPresentation', compilePage(display + visibility))(Hero);
  const videos = [video('catnode:a:1'), video('catnode:b:1'), video('new')];
  const page = Object.assign(new Page(), { videos, heroVideos: [videos[0]], embeddedHomeTitle: true,
    loading: false, error: '', keyword: '', categoryId: 'movie' });
  assert.deepEqual(page.posterVideos().map(item => item.id), ['catnode:b:1', 'new']);
  page.heroVideos = [videos[1]];
  assert.deepEqual(page.posterVideos().map(item => item.id), ['catnode:a:1', 'new']);
  page.keyword = 'search'; assert.equal(page.posterVideos(), videos);
  page.keyword = ''; page.embeddedHomeTitle = false; assert.equal(page.posterVideos(), videos);
  page.embeddedHomeTitle = true; page.heroVideos = []; assert.equal(page.posterVideos(), videos);
});

const loadMethod = content.slice(content.indexOf('  private async loadPage('), content.indexOf('  private async more('));
const LoadPage = new Function('CatVodHeroPresentation',
  compilePage(loadMethod))(Hero);
function createPage() {
  let result = { page: 1, pageCount: 3, videos: [video('a'), video('b')] };
  const page = Object.assign(new LoadPage(), { generation: 1, alive: true, keyword: '', categoryId: '',
    videos: [], heroVideos: [], heroVersion: 0, contentRevision: 0, page: 0, pageCount: 1, error: '', pageError: '',
    provider: { getClient: () => ({ async page() { return result; } }) } });
  return { page, result(value) { result = value; } };
}

test('loading another page preserves the first-page carousel and its current revision', async () => {
  const f = createPage(); await f.page.loadPage(1, 1);
  const featured = f.page.heroVideos;
  f.result({ page: 2, pageCount: 3, videos: [video('c')] });
  await f.page.loadPage(2, 1);
  assert.equal(f.page.heroVideos, featured);
  assert.deepEqual(f.page.heroVideos.map(item => item.id), ['a', 'b']);
  assert.equal(f.page.heroVersion, 1);
  assert.deepEqual(f.page.videos.map(item => item.id), ['a', 'b', 'c']);
  assert.deepEqual(Hero.belowHero(f.page.videos, f.page.heroVideos).map(item => item.id), ['c']);
});

test('each category gets its own first-page slides; searches and stale responses cannot publish old slides', async () => {
  const f = createPage(); await f.page.loadPage(1, 1);
  f.result({ page: 1, pageCount: 1, videos: [video('new')] });
  await f.page.loadPage(1, 1);
  assert.deepEqual(f.page.heroVideos.map(item => item.id), ['new']);
  f.page.keyword = '搜索'; await f.page.loadPage(1, 1);
  assert.deepEqual(f.page.heroVideos, []);
  f.page.keyword = ''; f.page.categoryId = 'movie'; await f.page.loadPage(1, 1);
  assert.deepEqual(f.page.heroVideos.map(item => item.id), ['new']);
  const heroes = f.page.heroVideos;
  f.page.categoryId = ''; f.page.generation = 2;
  await f.page.loadPage(1, 1);
  assert.equal(f.page.heroVideos, heroes);
});

test('hero visibility supports overview and categories but excludes search/loading/error/empty states', () => {
  const publish = content.slice(content.indexOf('  private publishNavigation('), content.indexOf('  private async refresh('));
  const visibility = content.slice(content.indexOf('  private showHero('), content.indexOf('  private viewportWidth('));
  const callback = content.slice(content.indexOf('class CatVodNavigationFrame'));
  const Page = new Function('CatVodHomeNavigation', 'CatNodeProvider', 'CatVodNavigationFrame',
    compilePage(`${publish} ${visibility}`))(
      CatVodHomeNavigation, class {}, new Function('FrameCallback',
        stripTypeScriptTypes(callback, { mode: 'transform' }) + ';return CatVodNavigationFrame;')(class {}));
  const frames = [];
  let navigation;
  const page = Object.assign(new Page(), { embeddedHomeTitle: true, alive: true, isActive: true,
    source: { id: 'sub' }, nodeSites: [], nodeSiteKey: '', provider: null, loading: false, error: '',
    keyword: '', categoryId: '', heroVideos: [video('a')], navigationPending: false, navigationTicket: 0,
    getUIContext: () => ({ postFrameCallback: callback => frames.push(callback) }),
    onNavigationChanged: value => { navigation = value; } });
  const render = () => { for (const frame of frames.splice(0)) frame.onFrame(); };
  page.publishNavigation(); render(); assert.equal(navigation.heroVisible, true);
  page.categoryId = 'movie'; page.publishNavigation(); render(); assert.equal(navigation.heroVisible, true);
  for (const [field, value] of [['loading', true], ['error', 'offline'], ['keyword', 'search'], ['heroVideos', []]]) {
    const previous = page[field]; page[field] = value;
    page.publishNavigation(); render(); assert.equal(navigation.heroVisible, false);
    page[field] = previous;
  }
  page.embeddedHomeTitle = false;
  assert.equal(page.showHero(), false);
});

test('cached proxy artwork changes rebuild retained poster bindings, while unchanged content keeps its key', () => {
  const pending = video('same', { poster: '' });
  const components = new Map();
  const render = items => items.map(item => {
    const key = Hero.posterKey(item);
    if (!components.has(key)) components.set(key, { poster: item.poster, name: item.name });
    return components.get(key);
  });
  const first = render([pending])[0];
  assert.equal(first.poster, '');
  const restored = video('same', { poster: 'http://127.0.0.1:3000/imgProxy?url=poster' });
  const loaded = render([restored])[0];
  assert.notEqual(loaded, first); assert.equal(loaded.poster, restored.poster);
  assert.equal(render([Object.assign(new CatVodVideo(), restored)])[0], loaded);
  assert.notEqual(Hero.posterKey(restored), Hero.posterKey({ ...restored, remarks: '更新至12集' }));
  assert.notEqual(Hero.posterKey(restored), Hero.posterKey({ ...restored, name: '新标题' }));
  assert.match(content, /\(video: CatVodVideo, _index: number\) => CatVodHeroPresentation\.posterKey\(video\)/);
});

test('automatic playback pauses offscreen, in the background, on inactive tabs and for one item', () => {
  const text = readFileSync(new URL('../entry/src/main/ets/components/media/carousel/HomeMediaCarousel.ets', import.meta.url), 'utf8');
  const methods = text.slice(text.indexOf('  private syncItems('), text.indexOf('  build()'));
  const Page = new Function(compilePage(methods))();
  const page = Object.assign(new Page(), { isActive: true, foreground: true, visible: true, items: [video('a'), video('b')],
    currentIndex: 1, touching: false, interactionPaused: false, interactionTimer: -1, interactionTicket: 0, alive: true, syncTrace: { flush() {} } });
  assert.equal(page.canAutoPlay(), true);
  for (const field of ['isActive', 'foreground', 'visible']) {
    page[field] = false; assert.equal(page.canAutoPlay(), false); page[field] = true;
  }
  page.touching = true; assert.equal(page.canAutoPlay(), false); page.touching = false;
  page.items = [video('a')]; assert.equal(page.canAutoPlay(), false);
  page.aboutToDisappear(); assert.equal(page.visible, false);
});

test('Cat display adapter keeps the namespaced ID and real metadata, with a portrait-safe image mode', () => {
  const original = video('catnode:source-a:film-1', { year: 2026, remarks: '<b>更新至12集</b>' });
  const item = Hero.carouselItems([original])[0];
  assert.equal(item.id, original.id); assert.equal(item.title, original.name);
  assert.equal(item.artworkUrl, original.poster);
  assert.equal(item.subtitle, '2026 · 更新至12集');
  const noMeta = Hero.carouselItems([video('plain', { overview: '<p>真实简介</p>' })])[0];
  assert.equal(noMeta.subtitle, '真实简介');
});

class IntentProvider {
  constructor(sites, key = 'index') { this.catalog = sites; this.key = key; }
  sites() { return Promise.resolve(this.catalog); }
  getSiteKey() { return this.key; }
}
function detailFixture(provider = null) {
  const method = content.slice(content.indexOf('  private detail('), content.indexOf('  private async playHistory('));
  const Page = new Function('CatNodeProvider', 'cacheLogger', 'buildDetailToastOptions', '$r', compilePage(method))(
    IntentProvider, { info() {}, warn() {} }, value => value, value => value);
  const routes = [], toasts = [];
  const page = Object.assign(new Page(), { source: { id: 'my-subscription' }, provider,
    alive: true, isActive: true, generation: 1, detailOpening: false, label: value => value,
    getUIContext: () => ({ getRouter: () => ({ pushUrl: value => { routes.push(value); } }),
      getPromptAction: () => ({ showToast: value => toasts.push(value) }) }) });
  return { page, routes, toasts };
}

test('hero details retain the subscription and namespaced video identity', async () => {
  const { page, routes } = detailFixture();
  await page.openDetail(video('catnode:site-a:opaque-id'));
  assert.deepEqual(routes, [{ url: 'pages/catvod/CatVodDetailPage',
    params: { sourceId: 'my-subscription', videoId: 'catnode:site-a:opaque-id', title: '作品catnode:site-a:opaque-id' } }]);
});

test('explicit recommendation cards open seeded search and refreshing the action invalidates a cached card binding', async () => {
  const { page, routes } = detailFixture(); page.source.id = 'subscription';
  const item = video('catnode:index:one', { name: '作品 第一季', searchOnly: true });
  await page.openDetail(item);
  assert.deepEqual(routes, [{ url: 'pages/home/SearchPage', params: { sourceId: 'subscription', keyword: '作品 第一季' } }]);
  assert.notEqual(Hero.posterKey(item), Hero.posterKey({ ...item, searchOnly: false }));
});

test('a cached poster missing intent resolves current directory metadata and routes once directly to search', async () => {
  const { page, routes } = detailFixture(new IntentProvider([{ key: 'index', indexOnly: true }]));
  await page.openDetail(video('catnode:index:cached', { name: '推荐作品' }));
  assert.deepEqual(routes, [{ url: 'pages/home/SearchPage', params: { sourceId: 'my-subscription', keyword: '推荐作品' } }]);
});

test('ordinary directory and catalog lookup failures preserve detail navigation', async () => {
  for (const fail of [false, true]) {
    const provider = new IntentProvider([{ key: 'index', indexOnly: false }]);
    if (fail) provider.sites = async () => { throw new Error('offline'); };
    const { page, routes } = detailFixture(provider);
    await page.openDetail(video('catnode:index:normal'));
    assert.equal(routes.length, 1); assert.equal(routes[0].url, 'pages/catvod/CatVodDetailPage');
  }
});

test('pending directory intent lookup suppresses duplicate clicks and navigation after a scope or source change', async () => {
  for (const change of ['generation', 'source', 'hidden', 'destroyed', 'provider', 'none']) {
    let release; const provider = new IntentProvider([]);
    provider.sites = () => new Promise(resolve => { release = resolve; });
    const { page, routes } = detailFixture(provider);
    const pending = page.openDetail(video('catnode:index:cached'));
    await page.openDetail(video('duplicate')); assert.equal(routes.length, 0);
    if (change === 'generation') page.generation++;
    if (change === 'source') page.source = { id: 'another' };
    if (change === 'hidden') page.isActive = false;
    if (change === 'destroyed') page.alive = false;
    if (change === 'provider') page.provider = new IntentProvider([]);
    release([{ key: 'index', indexOnly: true }]); await pending;
    assert.equal(routes.length, change === 'none' ? 1 : 0);
    assert.equal(page.detailOpening, false);
  }
});

test('failed navigation clears the click guard and allows retry', async () => {
  const { page, routes, toasts } = detailFixture();
  const context = page.getUIContext;
  page.getUIContext = () => ({ ...context(), getRouter: () => ({ pushUrl: async () => { throw new Error('router'); } }) });
  await page.openDetail(video('ordinary')); assert.equal(page.detailOpening, false); assert.equal(toasts.length, 1);
  page.getUIContext = context; await page.openDetail(video('ordinary'));
  assert.equal(routes.length, 1);
});
