import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { test } from 'node:test';

const read = path => readFileSync(new URL('../entry/src/main/ets/' + path, import.meta.url), 'utf8');
const compile = source => stripTypeScriptTypes(source.replace(/^import .*\r?\n/gm, '').replace(/export class /g, 'class '), { mode: 'transform' });
const Colors = new Function(compile(read('services/media/HomeHeroColors.ets')) + '; return HomeHeroColors;')();
const source = read('pages/emby/EmbyHomeContent.ets');
const methods = source.slice(source.indexOf('  private hasFeaturedBackground('), source.indexOf('  build()')) +
  source.slice(source.indexOf('  private featuredItems('), source.indexOf('  private otherResume(')) +
  source.slice(source.indexOf('  private artwork('), source.indexOf('  private openLibrary(')) +
  source.slice(source.indexOf('  onWillApplyTheme('), source.indexOf('  aboutToDisappear('));
const makeClass = (methods, names, values) => new Function(...names, compile(`class Page { ${methods} }`) + '; return Page;')(...values);
const settle = async () => { await new Promise(resolve => setImmediate(resolve)); };
const item = id => ({ id, type: 'Movie', isFolder: false, poster: 'https://server.test/primary/' + id + '?api_key=opaque',
  backdrop: 'https://server.test/backdrop/' + id + '?api_key=opaque' });

function fixture() {
  const tasks = new Map(), requests = [], published = [];
  const palette = { resolve(url) {
    requests.push(url);
    if (!tasks.has(url)) {
      let resolve; const promise = new Promise(done => { resolve = done; }); tasks.set(url, { promise, resolve });
    }
    return tasks.get(url).promise;
  } };
  const Page = makeClass(methods, ['HomeHeroColors', 'HomeHeroPalette', 'ColorMetrics', '$r'],
    [Colors, palette, { resourceColor: value => value }, id => id]);
  const values = [item('a'), item('b')];
  const page = Object.assign(new Page(), { source: { id: 'server-a', updatedAt: 123 }, alive: true, isActive: true,
    foreground: true, query: '', error: '', generation: 1, colorRequest: 0, heroTone: '', heroSurface: '',
    themeBase: 0xfff2f2f2, featuredIndex: 0, featuredItemId: '', featuredKey: '', failedArtwork: new Set(),
    snapshot: { sections: [{ items: values }] }, provider: {
      backdropUrlFor: value => value.backdrop || '', thumbnailUrlFor: value => value.thumbnail || '',
      imageUrlFor: value => value.poster || '' }, onBackgroundChanged: (...args) => published.push(args) });
  return { page, values, tasks, requests, published };
}

test('Emby keeps its full-image carousel, indicators, sizing and click-to-play behavior', () => {
  const carousel = source.slice(source.indexOf('  private FeaturedCarousel('), source.indexOf('  private Section('));
  assert.equal((carousel.match(/Image\(this.artwork\(item, true\)/g) || []).length, 2);
  assert.ok(carousel.includes('.objectFit(ImageFit.Cover).blur(14).opacity(0.72)'));
  assert.ok(carousel.includes('.objectFit(ImageFit.Cover).opacity(0.9)'));
  assert.ok(carousel.includes("Text('精选推荐')"));
  assert.ok(carousel.includes('this.featuredTopPadding()'));
  assert.ok(carousel.includes('this.featuredBottomPadding()'));
  assert.ok(carousel.includes(".width('calc(100% + '"));
  assert.ok(carousel.includes('if (item.isFolder) this.openDetail(item); else void this.play(item)'));
  assert.ok(carousel.includes('.interval(5000)'));
  assert.ok(carousel.includes('.duration(500).itemSpace(0)'));
  assert.ok(carousel.includes('index === this.featuredIndex ? 20 : 8'));
  assert.equal(source.includes('CatVodHeroBanner'), false);
});

test('Emby colors use the displayed backdrop URL and publish the same surface to the home page', async () => {
  const { page, tasks, requests, values, published } = fixture();
  page.syncFeaturedColor();
  assert.equal(requests[0], values[0].backdrop);
  tasks.get(values[0].backdrop).resolve('#3058b0'); await settle();
  const expected = Colors.surface('#3058b0', 0xfff2f2f2);
  assert.equal(page.heroSurface, expected);
  assert.equal(page.heroBackground(), expected);
  assert.deepEqual(published.at(-1), ['server-a', 123, expected]);
  assert.equal(requests[1], values[1].backdrop);
});

test('a delayed previous slide cannot overwrite the current Emby background', async () => {
  const { page, tasks, values, published } = fixture();
  page.syncFeaturedColor(); page.onFeaturedChanged(1);
  tasks.get(values[1].backdrop).resolve('#a13a20'); await settle();
  const expected = Colors.surface('#a13a20', page.themeBase);
  tasks.get(values[0].backdrop).resolve('#2040a0'); await settle();
  assert.equal(page.heroSurface, expected);
  assert.ok(published.every(value => value[2] === expected));
});

test('incremental recommendation updates preserve the selected item instead of resetting to page one', async () => {
  const { page, tasks, values } = fixture();
  page.syncFeaturedColor(); page.onFeaturedChanged(1);
  tasks.get(values[1].backdrop).resolve('#a13a20'); await settle();
  page.snapshot = { sections: [{ items: [item('new'), ...values] }] };
  page.syncFeaturedColor(); await settle();
  assert.equal(page.featuredIndex, 2); assert.equal(page.featuredItemId, 'b');
  page.snapshot = { sections: [{ items: [item('new')] }] };
  page.syncFeaturedColor(); assert.equal(page.featuredIndex, 0); assert.equal(page.featuredItemId, 'new');
});

test('search, lifecycle changes and a failed visible image reject delayed Emby colors', async () => {
  for (const change of [p => { p.query = 'search'; void p.updateFeaturedColor(); },
    p => { p.isActive = false; }, p => { p.foreground = false; }, p => { p.alive = false; },
    p => { p.generation++; }, p => { p.onFeaturedArtworkError(p.featuredItems()[0].backdrop); }]) {
    const { page, tasks, values, published } = fixture(); page.syncFeaturedColor(); change(page);
    tasks.get(values[0].backdrop).resolve('#a13a20'); await settle();
    assert.equal(page.heroSurface, ''); assert.ok(published.every(value => value[2] === ''));
  }
});

test('empty lists and artwork failures fall back; missing backdrops use the original thumbnail/primary fallback', async () => {
  const f = fixture(); f.values[0].backdrop = ''; f.values[0].thumbnail = 'https://server.test/thumb';
  f.page.syncFeaturedColor(); assert.equal(f.requests[0], 'https://server.test/thumb');
  f.tasks.get('https://server.test/thumb').resolve(''); await settle();
  assert.equal(f.page.heroBackground(), 'app.color.page_background');
  f.page.snapshot = { sections: [] }; f.page.syncFeaturedColor(); await settle();
  assert.deepEqual(f.published.at(-1), ['server-a', 123, '']);
});

test('Emby follows theme changes using the shared stronger tint without another image request', async () => {
  const { page, tasks, values, requests } = fixture(); page.syncFeaturedColor();
  tasks.get(values[0].backdrop).resolve('#3058b0'); await settle(); const count = requests.length;
  page.onWillApplyTheme({ colors: { backgroundPrimary: { red: 18, green: 18, blue: 18 } } });
  assert.equal(page.heroSurface, Colors.surface('#3058b0', 0xff121212));
  assert.equal(requests.length, count);
});

test('home ignores old Emby server/configuration callbacks and clears the tint for searches or other services', () => {
  const home = read('pages/home/HomePage.ets');
  const methods = home.slice(home.indexOf('  private homeBackground('), home.indexOf('  private catTitleSites('));
  const Page = makeClass(methods, ['$r'], [value => value]);
  const page = Object.assign(new Page(), { source: { id: 'server-a', updatedAt: 123, providerType: 'emby' },
    selectedSource() { return this.source; }, selectedId: 'server-a', isActive: true, loading: false, error: '',
    isCatSource: () => false, embyBackgroundSource: '', embyBackgroundUpdatedAt: 0, embyBackgroundColor: '' });
  page.onEmbyBackgroundChanged('server-a', 123, '#d1c4af');
  assert.equal(page.homeBackground(false), '#d1c4af');
  page.onEmbyBackgroundChanged('server-b', 123, '#ffaabb');
  page.onEmbyBackgroundChanged('server-a', 122, '#ffaabb');
  assert.equal(page.homeBackground(false), '#d1c4af');
  page.isActive = false; page.onEmbyBackgroundChanged('server-a', 123, '#ffaabb');
  assert.equal(page.embyBackgroundColor, '#d1c4af'); page.isActive = true;
  page.onEmbyBackgroundChanged('server-a', 123, '');
  assert.equal(page.homeBackground(false), 'app.color.page_background');
  page.onEmbyBackgroundChanged('server-a', 123, '#d1c4af'); page.source.providerType = 'webdav';
  assert.equal(page.homeBackground(false), 'app.color.page_background');
});
