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

test('captions use only real summary/year/remarks, strip markup and bound long summaries', () => {
  assert.equal(Hero.summary(video('1', { overview: '<p>剧情介绍</p>' })), '剧情介绍');
  assert.deepEqual(Hero.metadata(video('1')), []);
  assert.deepEqual(Hero.metadata(video('1', { year: 2026, remarks: '<b>更新至第12集</b>' })), ['2026', '更新至第12集']);
  const summary = Hero.summary(video('1', { overview: '长'.repeat(100) }));
  assert.equal(summary, '长'.repeat(60) + '…');
});

const content = read('CatVodContent.ets');
const loadMethod = content.slice(content.indexOf('  private async loadPage('), content.indexOf('  private async more('));
const LoadPage = new Function('CatVodHeroPresentation',
  compilePage(loadMethod))(Hero);
function createPage() {
  let result = { page: 1, pageCount: 3, videos: [video('a'), video('b')] };
  const page = Object.assign(new LoadPage(), { generation: 1, alive: true, keyword: '', categoryId: '',
    videos: [], heroVideos: [], heroVersion: 0, page: 0, pageCount: 1, error: '', pageError: '',
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
});

test('a new first page replaces featured items; search/categories and stale responses cannot publish old slides', async () => {
  const f = createPage(); await f.page.loadPage(1, 1);
  f.result({ page: 1, pageCount: 1, videos: [video('new')] });
  await f.page.loadPage(1, 1);
  assert.deepEqual(f.page.heroVideos.map(item => item.id), ['new']);
  f.page.keyword = '搜索'; await f.page.loadPage(1, 1);
  assert.deepEqual(f.page.heroVideos, []);
  f.page.keyword = ''; f.page.categoryId = 'movie'; await f.page.loadPage(1, 1);
  assert.deepEqual(f.page.heroVideos, []);
  f.page.categoryId = ''; f.page.generation = 2;
  await f.page.loadPage(1, 1);
  assert.deepEqual(f.page.heroVideos, []);
});

test('hero visibility is published only for a successful home overview', () => {
  const publish = content.slice(content.indexOf('  private publishNavigation('), content.indexOf('  private async refresh('));
  const visibility = content.slice(content.indexOf('  private showHero('), content.indexOf('  private viewportWidth('));
  const Page = new Function('CatVodHomeNavigation', 'CatNodeProvider',
    compilePage(`${publish} ${visibility}`))(
      CatVodHomeNavigation, class {});
  let navigation;
  const page = Object.assign(new Page(), { embeddedHomeTitle: true, alive: true, isActive: true,
    source: { id: 'sub' }, nodeSites: [], nodeSiteKey: '', provider: null, loading: false, error: '',
    keyword: '', categoryId: '', heroVideos: [video('a')], onNavigationChanged: value => { navigation = value; } });
  page.publishNavigation(); assert.equal(navigation.heroVisible, true);
  for (const [field, value] of [['loading', true], ['error', 'offline'], ['keyword', 'search'], ['categoryId', 'movie'], ['heroVideos', []]]) {
    const previous = page[field]; page[field] = value;
    page.publishNavigation(); assert.equal(navigation.heroVisible, false);
    page[field] = previous;
  }
  page.embeddedHomeTitle = false;
  assert.equal(page.showHero(), false);
});

test('automatic playback pauses offscreen, in the background, on inactive tabs and for one item', () => {
  const text = readFileSync(new URL('../entry/src/main/ets/pages/catvod/CatVodHeroBanner.ets', import.meta.url), 'utf8');
  const methods = text.slice(text.indexOf('  private resetPosition('), text.indexOf('  build()'));
  const Page = new Function(compilePage(methods))();
  const page = Object.assign(new Page(), { isActive: true, foreground: true, visible: true, items: [video('a'), video('b')],
    currentIndex: 1, alive: false, paletteRequest: 0, failedArtwork: new Set() });
  assert.equal(page.canAutoPlay(), true);
  for (const field of ['isActive', 'foreground', 'visible']) {
    page[field] = false; assert.equal(page.canAutoPlay(), false); page[field] = true;
  }
  page.items = [video('a')]; assert.equal(page.canAutoPlay(), false);
  page.resetPosition(); assert.equal(page.currentIndex, 0);
  page.aboutToDisappear(); assert.equal(page.visible, false);
});

test('hero details retain the subscription and namespaced video identity', () => {
  const method = content.slice(content.indexOf('  private detail('), content.indexOf('  private async playHistory('));
  const Page = new Function(compilePage(method))();
  let route;
  const page = Object.assign(new Page(), { source: { id: 'my-subscription' },
    getUIContext: () => ({ getRouter: () => ({ pushUrl: value => { route = value; } }) }) });
  page.detail(video('catnode:site-a:opaque-id'));
  assert.deepEqual(route, { url: 'pages/catvod/CatVodDetailPage',
    params: { sourceId: 'my-subscription', videoId: 'catnode:site-a:opaque-id' } });
});
