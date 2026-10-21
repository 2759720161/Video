import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { test } from 'node:test';

const read = path => readFileSync(new URL('../entry/src/main/ets/' + path, import.meta.url), 'utf8');
const compile = source => stripTypeScriptTypes(source.replace(/^import .*\r?\n/gm, '').replace(/export class /g, 'class '), { mode: 'transform' });
const colorsSource = read('services/media/HomeHeroColors.ets');
const Colors = new Function(compile(colorsSource) + '; return HomeHeroColors;')();
const pageClass = (methods, names = [], values = []) => new Function(...names,
  compile(`class Page { ${methods} }`) + '; return Page;')(...values);

const rgb = color => [1, 3, 5].map(index => parseInt(color.slice(index, index + 2), 16));
const luminance = color => rgb(color).map(value => {
  const c = value / 255; return c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4;
}).reduce((total, value, index) => total + value * [0.2126, 0.7152, 0.0722][index], 0);
const contrast = (a, b) => (Math.max(luminance(a), luminance(b)) + 0.05) / (Math.min(luminance(a), luminance(b)) + 0.05);

test('page tint follows the artwork hue and keeps normal text readable in both themes', () => {
  const light = Colors.surface('#0000ff', 0xfff2f2f2);
  const dark = Colors.surface('#0000ff', 0xff121212);
  assert.ok(rgb(light)[2] > rgb(light)[0]);
  assert.ok(rgb(dark)[2] > rgb(dark)[0]);
  for (const color of ['#ff0000', '#00ff00', '#0000ff', '#ffffff', '#000000', '#999999', '#f37d21']) {
    assert.ok(contrast(Colors.surface(color, 0xfff2f2f2), '#182431') >= 4.5, color);
    assert.ok(contrast(Colors.surface(color, 0xff121212), '#e5e5e5') >= 4.5, color);
  }
  assert.equal(Colors.surface('invalid', 0xff121212), '');
  assert.equal(Colors.surface('', 0xff121212), '');
  assert.equal(Colors.surface('#0000ff', 0), '');
});

test('colored covers produce a visible page tint, including muted warm covers', () => {
  for (const base of [0xfff2f2f2, 0xff121212]) {
    for (const color of ['#ff0000', '#00ff00', '#0000ff']) {
      const channels = rgb(Colors.surface(color, base));
      assert.ok(Math.max(...channels) - Math.min(...channels) >= 70, color);
    }
    const warm = rgb(Colors.surface('#8b6d4f', base));
    assert.ok(warm[0] - warm[2] >= 24);
  }
  for (const base of [0xffffffff, 0xfff2f2f2, 0xff121212, 0xff000000]) {
    const dark = (base & 255) < 128;
    for (const color of ['#ffffff', '#000000', '#ffff00', '#00ffff', '#ff00ff']) {
      assert.ok(contrast(Colors.surface(color, base), dark ? '#e5e5e5' : '#182431') >= 4.5);
    }
  }
});

const paletteSource = read('services/media/HomeHeroPalette.ets');
function paletteFixture() {
  const state = { requests: [], destroyed: 0, decoded: 0, pixelReleased: 0, sourceReleased: 0,
    status: 200, body: new ArrayBuffer(8), fail: '', gate: null, topColors: [],
    color: { red: 18, green: 52, blue: 86, alpha: 255 } };
  const http = { RequestMethod: { GET: 'GET' }, HttpDataType: { ARRAY_BUFFER: 'arraybuffer' },
    createHttp: () => {
      if (state.fail === 'create') throw new Error('network module unavailable');
      return { async request(url, options) {
      state.requests.push({ url, options });
      if (state.gate) await state.gate;
      if (state.fail === 'network') throw new Error('offline');
      return { responseCode: state.status, result: state.body };
    }, destroy() { state.destroyed++; if (state.fail === 'destroy') throw new Error('already closed'); } }; } };
  const image = { createImageSource() { return { async createPixelMap(options) {
    state.decoded++; assert.deepEqual(options.desiredSize, { width: 64, height: 64 });
    if (state.fail === 'decode') throw new Error('not an image');
    return { async release() { state.pixelReleased++; } };
  }, async release() { state.sourceReleased++; } }; } };
  const effectKit = { async createColorPicker() { return { getTopProportionColors(count) {
    assert.equal(count, 5);
    if (state.fail === 'top-colors') throw new Error('color regions unavailable');
    return state.topColors;
  }, async getMainColor() {
    if (state.fail === 'picker') throw new Error('unsupported image');
    return state.color;
  } }; } };
  const Palette = new Function('http', 'image', 'effectKit', compile(paletteSource) + '; return HomeHeroPalette;')(http, image, effectKit);
  return { state, Palette };
}

test('palette shares concurrent requests, reuses colors and releases all native resources', async () => {
  const { state, Palette } = paletteFixture();
  let release; state.gate = new Promise(resolve => { release = resolve; });
  const a = Palette.resolve('https://images.test/a');
  const b = Palette.resolve('https://images.test/a');
  release();
  assert.deepEqual(await Promise.all([a, b]), ['#123456', '#123456']);
  assert.equal(await Palette.resolve('https://images.test/a'), '#123456');
  assert.equal(state.requests.length, 1);
  assert.equal(state.requests[0].options.maxLimit, 5 * 1024 * 1024);
  assert.deepEqual([state.destroyed, state.pixelReleased, state.sourceReleased], [1, 1, 1]);
  await Palette.resolve('https://images.test/b');
  assert.equal(state.requests.length, 2);
  assert.equal(await Palette.resolve('file:///private/cover'), '');
});

test('palette prefers the first substantial colored region over a gray image average', async () => {
  const { state, Palette } = paletteFixture();
  state.color = { red: 128, green: 128, blue: 128, alpha: 255 };
  state.topColors = [null, { red: 248, green: 248, blue: 248, alpha: 255 },
    { red: 250, green: 80, blue: 30, alpha: 0 }, { red: 15, green: 2, blue: 2, alpha: 255 },
    { red: 48, green: 88, blue: 176, alpha: 255 }];
  assert.equal(await Palette.resolve('https://images.test/colored'), '#3058b0');
  assert.deepEqual([state.destroyed, state.pixelReleased, state.sourceReleased], [1, 1, 1]);
});

test('neutral artwork and unavailable region analysis retain the main-color fallback', async () => {
  const { state, Palette } = paletteFixture();
  state.color = { red: 128, green: 128, blue: 128, alpha: 255 };
  state.topColors = [null, { red: 245, green: 245, blue: 245, alpha: 255 }];
  assert.equal(await Palette.resolve('https://images.test/neutral'), '#808080');
  state.fail = 'top-colors';
  assert.equal(await Palette.resolve('https://images.test/no-regions'), '#808080');
});

test('network, HTTP, image and picker failures fall back safely and remain retryable', async () => {
  for (const failure of ['create', 'network', 'http', 'empty', 'decode', 'picker', 'transparent']) {
    const { state, Palette } = paletteFixture();
    state.fail = failure;
    if (failure === 'http') state.status = 403;
    if (failure === 'empty') state.body = new ArrayBuffer(0);
    if (failure === 'transparent') state.color.alpha = 0;
    assert.equal(await Palette.resolve('https://images.test/' + failure), '', failure);
    assert.equal(state.destroyed, failure === 'create' ? 0 : 1, failure);
    assert.equal(state.sourceReleased, state.decoded ? 1 : 0, failure);
    assert.equal(state.pixelReleased, ['picker', 'transparent'].includes(failure) ? 1 : 0, failure);
    state.fail = ''; state.status = 200; state.body = new ArrayBuffer(8); state.color.alpha = 255;
    assert.equal(await Palette.resolve('https://images.test/' + failure), '#123456', failure);
  }
  const { state, Palette } = paletteFixture(); state.fail = 'destroy';
  assert.equal(await Palette.resolve('https://images.test/destroy'), '#123456');
});

test('palette cache is bounded and evicted covers can be resolved again', async () => {
  const { state, Palette } = paletteFixture();
  for (let i = 0; i < 34; i++) await Palette.resolve('https://images.test/' + i);
  assert.equal(Palette.cache.size, 32);
  await Palette.resolve('https://images.test/33'); assert.equal(state.requests.length, 34);
  await Palette.resolve('https://images.test/0'); assert.equal(state.requests.length, 35);
});

function bannerFixture() {
  const source = read('pages/catvod/CatVodHeroBanner.ets');
  const methods = source.slice(source.indexOf('  aboutToAppear()'), source.indexOf('  build()'));
  const tasks = new Map(), output = [];
  const Palette = { resolve(url) {
    if (!tasks.has(url)) {
      let resolve; const promise = new Promise(done => { resolve = done; });
      tasks.set(url, { promise, resolve });
    }
    return tasks.get(url).promise;
  } };
  const Banner = pageClass(methods, ['HomeHeroPalette'], [Palette]);
  const banner = Object.assign(new Banner(), { alive: false, visible: true, isActive: true, foreground: true,
    paletteRequest: 0, version: 1, currentIndex: 0, failedArtwork: new Set(),
    items: [{ poster: 'a' }, { poster: 'b' }], onColorChanged: color => output.push(color) });
  return { banner, output, tasks };
}
const settle = async () => { await new Promise(resolve => setImmediate(resolve)); };

test('first slide publishes its color, but a slow previous slide cannot overwrite the current one', async () => {
  const { banner, output, tasks } = bannerFixture();
  banner.aboutToAppear(); tasks.get('a').resolve('#0000ff'); await settle();
  assert.deepEqual(output, ['#0000ff']);
  banner.changeSlide(1); tasks.get('b').resolve('#ff0000'); await settle();
  assert.deepEqual(output, ['#0000ff', '#ff0000']);
  const f = bannerFixture();
  f.banner.aboutToAppear(); f.banner.changeSlide(1);
  f.tasks.get('b').resolve('#ff0000'); await settle();
  f.tasks.get('a').resolve('#0000ff'); await settle();
  assert.deepEqual(f.output, ['#ff0000']);
});

test('old revisions, inactive/background pages and disposed banners reject delayed colors', async () => {
  for (const change of [b => { b.version++; }, b => { b.isActive = false; b.onActivityChanged(); },
    b => { b.foreground = false; b.onActivityChanged(); }, b => b.aboutToDisappear()]) {
    const { banner, tasks, output } = bannerFixture();
    banner.aboutToAppear(); change(banner);
    tasks.get('a').resolve('#0000ff'); await settle();
    assert.deepEqual(output, []);
  }
});

test('failed current artwork resets the background and blocks an earlier palette result', async () => {
  const { banner, tasks, output } = bannerFixture();
  banner.aboutToAppear(); banner.artworkFailed('a');
  tasks.get('a').resolve('#0000ff'); await settle();
  assert.deepEqual(output, ['']);
  banner.artworkFailed('b'); assert.deepEqual(output, ['']);
});

test('home background uses only a valid color from the current successful Cat overview', () => {
  const source = read('pages/home/HomePage.ets');
  const method = source.slice(source.indexOf('  private homeBackground('), source.indexOf('  private catTitleSites('));
  const Home = pageClass(method, ['$r'], [name => name]);
  const page = Object.assign(new Home(), { selectedId: 'sub', loading: false, error: '', isCatSource: () => true,
    selectedSource: () => ({ providerType: 'catnode' }),
    catNavigation: { sourceId: 'sub', heroVisible: true, heroSurface: '#ece5e1' } });
  assert.equal(page.homeBackground(true), '#ece5e1');
  assert.equal(page.homeBackground(false), '#ece5e1');
  for (const change of [() => { page.catNavigation.sourceId = 'old'; }, () => { page.catNavigation.heroVisible = false; },
    () => { page.catNavigation.heroSurface = 'invalid'; }, () => { page.loading = true; },
    () => { page.error = 'offline'; }, () => { page.isCatSource = () => false; }]) {
    page.catNavigation = { sourceId: 'sub', heroVisible: true, heroSurface: '#ece5e1' };
    page.loading = false; page.error = ''; page.isCatSource = () => true; change();
    assert.equal(page.homeBackground(true), 'app.color.home_bg_top');
    assert.equal(page.homeBackground(false), 'app.color.page_background');
  }
});

test('theme changes recompute the current tint and propagate the same opaque surface to home and slide', () => {
  const source = read('pages/catvod/CatVodContent.ets');
  const themeMethod = source.slice(source.indexOf('  onWillApplyTheme('), source.indexOf('  aboutToDisappear('));
  const toneMethods = source.slice(source.indexOf('  private setHeroColor('), source.indexOf('  @Builder', source.indexOf('  private setHeroColor(')));
  const Page = pageClass(themeMethod + toneMethods, ['HomeHeroColors', 'ColorMetrics', '$r'],
    [Colors, { resourceColor: value => value }, name => name]);
  let published = 0;
  const page = Object.assign(new Page(), { alive: true, isActive: true, heroColor: '', themeBase: 0, heroSurface: '',
    showHero: () => true, publishNavigation: () => { published++; } });
  page.onWillApplyTheme({ colors: { backgroundPrimary: { red: 242, green: 242, blue: 242 } } });
  page.setHeroColor('#0000ff'); const light = page.heroSurface;
  assert.equal(page.heroBackground(), light);
  page.onWillApplyTheme({ colors: { backgroundPrimary: { red: 18, green: 18, blue: 18 } } });
  assert.notEqual(page.heroSurface, light);
  assert.equal(page.heroBackground(), page.heroSurface);
  page.setHeroColor(''); assert.equal(page.heroBackground(), 'app.color.page_background');
  page.showHero = () => false; page.setHeroColor('#ff0000'); assert.equal(page.heroSurface, '');
  assert.ok(published >= 4);
});
