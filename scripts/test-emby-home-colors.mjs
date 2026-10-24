import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { test } from 'node:test';

const read = path => readFileSync(new URL('../entry/src/main/ets/' + path, import.meta.url), 'utf8');
const compile = source => stripTypeScriptTypes(source.replace(/^import .*\r?\n/gm, '').replace(/export class /g, 'class '), { mode: 'transform' });
const Colors = new Function(compile(read('services/media/HomeHeroColors.ets')) + '; return HomeHeroColors;')();
const CarouselItem = new Function(compile(read('components/media/carousel/HomeCarouselItem.ets')) + '; return HomeCarouselItem;')();
const source = read('pages/emby/EmbyHomeContent.ets');
const methods = source.slice(source.indexOf('  private hasFeaturedBackground('), source.indexOf('  build()')) +
  source.slice(source.indexOf('  private sectionPosters('), source.indexOf('  private otherResume(')) +
  source.slice(source.indexOf('  private artwork('), source.indexOf('  private openLibrary(')) +
  source.slice(source.indexOf('  onWillApplyTheme('), source.indexOf('  aboutToDisappear('));
const makeClass = (methods, names, values) => new Function(...names, 'HomeHeroSyncTrace', compile(`class Page { ${methods} }`) + '; return Page;')(...values, { palette() {}, applied() {} });
const settle = async () => { await new Promise(resolve => setImmediate(resolve)); };
const item = id => ({ id, name: '作品' + id, seriesName: '', subtitle: () => '2026', type: 'Movie', isFolder: false,
  poster: 'https://server.test/primary/' + id + '?api_key=opaque',
  backdrop: 'https://server.test/backdrop/' + id + '?api_key=opaque' });

function fixture() {
  const tasks = new Map(), requests = [], published = [];
  const palette = new Function('HomeHeroColors', compile(read('services/media/HomeHeroPalette.ets')) + ';return HomeHeroPalette;')(Colors);
  palette.resolve = url => {
    const cached = palette.cache.get(url); if (cached !== undefined) return Promise.resolve(cached);
    if (!tasks.has(url)) {
      requests.push(url);
      let resolve; const promise = new Promise(done => { resolve = done; }); tasks.set(url, { promise, resolve });
    }
    return tasks.get(url).promise.then(color => { palette.cache.set(url, color); return color; });
  };
  const Page = makeClass(methods, ['HomeHeroColors', 'HomeHeroPalette', 'ColorMetrics', '$r', 'HomeCarouselItem'],
    [Colors, palette, { resourceColor: value => value }, id => id, CarouselItem]);
  const values = [item('a'), item('b')];
  const page = Object.assign(new Page(), { source: { id: 'server-a', updatedAt: 123 }, alive: true, isActive: true,
    foreground: true, query: '', error: '', generation: 1, colorRequest: 0, heroTone: '', heroSurface: '',
    themeBase: 0xfff2f2f2, featuredIndex: 0, featuredItemId: '', featuredKey: '',
    featuredProgress: 0, progressReady: false, failedArtwork: new Set(),
    snapshot: { sections: [{ items: values }] }, provider: {
      backdropUrlFor: value => value.backdrop || '', thumbnailUrlFor: value => value.thumbnail || '',
      imageUrlFor: value => value.poster || '' }, onBackgroundChanged: (...args) => published.push(args) });
  return { page, values, tasks, requests, published };
}

test('Emby turntable prefers original authenticated posters and falls back to backdrop images', () => {
  const carousel = source.slice(source.indexOf('  private FeaturedCarousel('), source.indexOf('  private Section('));
  assert.ok(carousel.includes('HomeMediaCarousel({ items: this.carouselItems()'));
  assert.equal(source.includes('CatVodHeroBanner'), false);
  const { page, values } = fixture(); values[1].poster = '';
  const cards = page.carouselItems();
  assert.equal(cards[0].artworkUrl, values[0].poster);
  assert.equal(cards[1].artworkUrl, values[1].backdrop);
  assert.equal(cards[0].title, values[0].name); assert.equal(cards[0].subtitle, '2026');
});

test('Emby section posters exclude the complete carousel across libraries without altering snapshots or selection', () => {
  const { page } = fixture();
  const first = { items: Array.from({ length: 8 }, (_, i) => item(String(i))) };
  const second = { items: [item('0'), item('6'), item('other')] };
  page.snapshot.sections = [first, second];
  const before = page.snapshot.sections.map(section => section.items.slice());
  assert.deepEqual(page.featuredItems().map(value => value.id), ['0', '1', '2', '3', '4', '5']);
  assert.deepEqual(page.sectionPosters(first).map(value => value.id), ['6', '7']);
  assert.deepEqual(page.sectionPosters(second).map(value => value.id), ['6', 'other']);
  page.featuredIndex = 4;
  assert.deepEqual(page.sectionPosters(first).map(value => value.id), ['6', '7']);
  assert.deepEqual(page.snapshot.sections.map(section => section.items), before);
  const allFeatured = { items: first.items.slice(0, 6) };
  assert.deepEqual(page.sectionPosters(allFeatured), []);
  page.provider = null; assert.equal(page.sectionPosters(first), first.items);
});

test('shared card click still starts Emby playback with the original selected item', () => {
  const { page, values } = fixture(); const opened = [];
  page.play = async value => { opened.push(value); };
  page.openFeatured('b'); page.openFeatured('missing');
  assert.deepEqual(opened, [values[1]]);
});

test('Emby colors use the displayed poster URL and publish the same surface to the home page', async () => {
  const { page, tasks, requests, values, published } = fixture();
  page.syncFeaturedColor();
  assert.equal(requests[0], values[0].poster);
  tasks.get(values[0].poster).resolve('#3058b0'); await settle();
  const expected = Colors.surface('#3058b0', 0xfff2f2f2);
  assert.equal(page.heroSurface, expected);
  assert.equal(page.heroBackground(), expected);
  assert.deepEqual(published.at(-1), ['server-a', 123, expected]);
  assert.equal(requests[1], values[1].poster);
});

test('Emby samples a 64px variant of the same image type without changing the visible authenticated artwork', async () => {
  const { page, values } = fixture();
  const imageUrl = (kind, width) => `https://server.test/${kind}?maxWidth=${width}&tag=version&api_key=opaque`;
  page.provider.imageUrlFor = (_item, width) => imageUrl('primary', width);
  page.provider.backdropUrlFor = (_item, width) => imageUrl('backdrop', width);
  page.provider.thumbnailUrlFor = (_item, width) => imageUrl('thumb', width);
  assert.equal(page.heroArtwork(values[0]), imageUrl('primary', 900));
  assert.equal(page.heroPaletteArtwork(values[0]), imageUrl('primary', 64));
  page.featuredItems = () => [values[0]];
  page.provider.imageUrlFor = () => '';
  assert.equal(page.heroArtwork(values[0]), imageUrl('backdrop', 1200));
  assert.equal(page.heroPaletteArtwork(values[0]), imageUrl('backdrop', 64));
  page.provider.backdropUrlFor = () => '';
  assert.equal(page.heroArtwork(values[0]), imageUrl('thumb', 900));
  assert.equal(page.heroPaletteArtwork(values[0]), imageUrl('thumb', 64));
});

test('a delayed previous slide cannot overwrite the current Emby background', async () => {
  const { page, tasks, values, published } = fixture();
  page.syncFeaturedColor(); page.onFeaturedChanged(1);
  tasks.get(values[1].poster).resolve('#a13a20'); await settle();
  const expected = Colors.surface('#a13a20', page.themeBase);
  tasks.get(values[0].poster).resolve('#2040a0'); await settle();
  assert.equal(page.heroSurface, expected);
  assert.ok(published.every(value => value[2] === expected));
});

test('incremental recommendation updates preserve the selected item instead of resetting to page one', async () => {
  const { page, tasks, values } = fixture();
  page.syncFeaturedColor(); page.onFeaturedChanged(1);
  tasks.get(values[1].poster).resolve('#a13a20'); await settle();
  page.snapshot = { sections: [{ items: [item('new'), ...values] }] };
  page.syncFeaturedColor(); await settle();
  assert.equal(page.featuredIndex, 2); assert.equal(page.featuredItemId, 'b');
  page.snapshot = { sections: [{ items: [item('new')] }] };
  page.syncFeaturedColor(); assert.equal(page.featuredIndex, 0); assert.equal(page.featuredItemId, 'new');
});

test('search, lifecycle changes and a failed visible image reject delayed Emby colors', async () => {
  for (const change of [p => { p.query = 'search'; void p.updateFeaturedColor(); },
    p => { p.isActive = false; }, p => { p.foreground = false; }, p => { p.alive = false; },
    p => { p.generation++; }, p => { p.onFeaturedArtworkError(p.featuredItems()[0].poster); }]) {
    const { page, tasks, values, published } = fixture(); page.syncFeaturedColor(); change(page);
    tasks.get(values[0].poster).resolve('#a13a20'); await settle();
    assert.equal(page.heroSurface, ''); assert.ok(published.every(value => value[2] === ''));
  }
});

test('empty lists and artwork failures reset colors; missing posters and backdrops use thumbnails', async () => {
  const f = fixture(); f.values[0].poster = ''; f.values[0].backdrop = ''; f.values[0].thumbnail = 'https://server.test/thumb';
  f.page.syncFeaturedColor(); assert.equal(f.requests[0], 'https://server.test/thumb');
  f.tasks.get('https://server.test/thumb').resolve(''); await settle();
  assert.equal(f.page.heroBackground(), 'app.color.page_background');
  f.page.snapshot = { sections: [] }; f.page.syncFeaturedColor(); await settle();
  assert.deepEqual(f.published.at(-1), ['server-a', 123, '']);
});

test('Emby follows theme changes using the shared stronger tint without another image request', async () => {
  const { page, tasks, values, requests } = fixture(); page.syncFeaturedColor();
  tasks.get(values[0].poster).resolve('#3058b0'); await settle(); const count = requests.length;
  page.onWillApplyTheme({ colors: { backgroundPrimary: { red: 18, green: 18, blue: 18 } } });
  assert.equal(page.heroSurface, Colors.surface('#3058b0', 0xff121212));
  assert.equal(requests.length, count);
});

test('Emby follows forward/reverse swipe progress and an index callback cannot replace an interrupted blend', async () => {
  const { page, values, tasks, requests, published } = fixture(); page.syncFeaturedColor();
  tasks.get(values[0].poster).resolve('#0000ff'); tasks.get(values[1].poster).resolve('#ff0000'); await settle();
  page.onFeaturedProgress(0.5);
  assert.equal(page.heroSurface, Colors.surface('#800080', page.themeBase));
  assert.equal(page.featuredIndex, 0);
  page.onFeaturedProgress(1.8);
  const tone = '#3300cc'; assert.equal(page.heroSurface, Colors.surface(tone, page.themeBase));
  page.onFeaturedChanged(1); await settle();
  assert.equal(page.heroSurface, Colors.surface(tone, page.themeBase));
  const count = requests.length;
  page.onWillApplyTheme({ colors: { backgroundPrimary: { red: 18, green: 18, blue: 18 } } });
  assert.equal(page.heroSurface, Colors.surface(tone, 0xff121212));
  assert.equal(requests.length, count); assert.equal(published.at(-1)[2], page.heroSurface);
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
