import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { test } from 'node:test';

const read = path => readFileSync(new URL('../entry/src/main/ets/' + path, import.meta.url), 'utf8');
const compile = source => stripTypeScriptTypes(source.replace(/^import .*\r?\n/gm, '').replace(/export class /g, 'class '), { mode: 'transform' });
const colorsSource = read('services/media/HomeHeroColors.ets');
const Colors = new Function(compile(colorsSource) + '; return HomeHeroColors;')();
const ImageTone = new Function(compile(read('services/media/HomeHeroImageTone.ets')) + '; return HomeHeroImageTone;')();
const pageClass = (methods, names = [], values = []) => new Function(...names, 'HomeHeroSyncTrace',
  compile(`class Page { ${methods} }`) + '; return Page;')(...values, { palette() {}, applied() {} });

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
test('whole-color correction preserves distinct dark hues that used to collapse to the same light gray', () => {
  const warm = Colors.surface('#3c180c', 0xfff2f2f2);
  const cool = Colors.surface('#0c183c', 0xfff2f2f2);
  assert.notEqual(warm, cool);
  assert.ok(rgb(warm)[0] - rgb(warm)[2] >= 12);
  assert.ok(rgb(cool)[2] - rgb(cool)[0] >= 12);
  assert.ok(contrast(warm, '#182431') >= 4.5);
  assert.ok(contrast(cool, '#182431') >= 4.5);
});

test('whole-color dimming preserves pale warm and cool colors instead of clipping both to dark gray', () => {
  const warm = Colors.surface('#f0dcc8', 0xff121212);
  const cool = Colors.surface('#c8dcf0', 0xff121212);
  assert.notEqual(warm, cool);
  assert.ok(rgb(warm)[0] - rgb(warm)[2] >= 12);
  assert.ok(rgb(cool)[2] - rgb(cool)[0] >= 12);
  assert.ok(contrast(warm, '#e5e5e5') >= 4.5);
  assert.ok(contrast(cool, '#e5e5e5') >= 4.5);
});

test('color correction preserves hue order, neutral covers and readable bounds across both themes', () => {
  for (const base of [0xfff2f2f2, 0xffffffff, 0xff121212, 0xff000000]) {
    const dark = (base & 255) < 128;
    for (let red = 0; red <= 255; red += 17) {
      for (let green = 0; green <= 255; green += 17) {
        for (let blue = 0; blue <= 255; blue += 17) {
          const tone = '#' + [red, green, blue].map(v => v.toString(16).padStart(2, '0')).join('');
          const result = Colors.surface(tone, base), channels = rgb(result);
          assert.ok(dark ? Math.max(...channels) <= 88 : Math.min(...channels) >= 168);
          assert.ok(contrast(result, dark ? '#e5e5e5' : '#182431') >= 4.5);
          for (const [first, second] of [[0, 1], [1, 2], [0, 2]]) {
            const original = [red, green, blue];
            if (original[first] === original[second]) assert.equal(channels[first], channels[second]);
            else assert.ok((channels[first] - channels[second]) * (original[first] - original[second]) >= 0);
          }
        }
      }
    }
  }
});

function paletteFixture() {
  const state = { requests: [], logs: [], destroyed: 0, decoded: 0, pixelReleased: 0, sourceReleased: 0,
    status: 200, body: new ArrayBuffer(8), fail: '', gate: null, pixels: null, pickerCalls: 0,
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
  const image = { PixelMapFormat: { RGBA_8888: 3 }, AlphaType: { OPAQUE: 1, PREMUL: 2, UNPREMUL: 3 },
    createImageSource() { return { async createPixelMap(options) {
    state.decoded++; assert.deepEqual(options.desiredSize, { width: 64, height: 64 });
    assert.equal(options.desiredPixelFormat, image.PixelMapFormat.RGBA_8888);
    if (state.fail === 'decode') throw new Error('not an image');
    return { async getImageInfo() {
      if (state.fail === 'info') throw Error('metadata unavailable');
      return { size: { width: 64, height: 64 }, pixelFormat: state.fail === 'layout' ? 99 : 3, alphaType: 3 };
    }, getPixelBytesNumber: () => 64 * 64 * 4, async readPixelsToBuffer(buffer) {
      if (['read', 'picker'].includes(state.fail)) throw Error('pixels unavailable');
      const bytes = new Uint8Array(buffer);
      if (state.pixels) bytes.set(state.pixels);
      else for (let i = 0; i < bytes.length; i += 4) {
        bytes.set([state.color.red, state.color.green, state.color.blue, state.color.alpha], i);
      }
    }, async release() { state.pixelReleased++; } };
  }, async release() { state.sourceReleased++; } }; } };
  const effectKit = { async createColorPicker() { state.pickerCalls++; return { async getMainColor() {
    if (state.fail === 'picker') throw new Error('unsupported image');
    return state.color;
  } }; } };
  const Palette = new Function('http', 'image', 'effectKit', 'HomeHeroColors', 'hilog', 'HomeHeroPaletteStore', 'HomeHeroImageTone', compile(paletteSource) + '; return HomeHeroPalette;')(
    http, image, effectKit, Colors, { info: (...args) => state.logs.push(args) },
    { identity: async value => value, get: async () => '', put() {} }, ImageTone);
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

test('palette timing logs pair requests without credentials, cache-hit or frame-level noise', async () => {
  const { state, Palette } = paletteFixture();
  const artwork = 'https://images.test/a?api_key=private-token';
  let release; state.gate = new Promise(done => { release = done; });
  const first = Palette.resolve(artwork), shared = Palette.resolve(artwork);
  assert.equal(state.logs.length, 1);
  release(); await Promise.all([first, shared]);
  await Palette.resolve(artwork);
  for (let i = 0; i < 60; i++) Palette.at([artwork], i / 60, new Set());
  assert.equal(state.logs.length, 4);
  assert.equal(state.logs[0][1], 'HomeHeroPalette');
  assert.equal(state.logs[0][3], state.logs[3][3]);
  assert.ok(state.logs[1][2].startsWith('downloaded'));
  assert.equal(state.logs[1][5], 8); assert.equal(state.logs[1][6], 200);
  assert.ok(state.logs[2][2].includes('mode=pixels'));
  assert.ok(state.logs[3][4] >= 0); assert.equal(state.logs[3][5], 1);
  assert.equal(state.logs[3][6], '#123456');
  assert.ok(!JSON.stringify(state.logs).includes('private-token'));
  state.fail = 'network'; await Palette.resolve('https://images.test/fail');
  assert.equal(state.logs.at(-1)[5], 0);
});

test('mostly black artwork retains the whole-frame atmosphere instead of using a small red region', async () => {
  const { state, Palette } = paletteFixture();
  state.color = { red: 224, green: 48, blue: 80, alpha: 255 };
  state.pixels = new Uint8Array(64 * 64 * 4);
  for (let i = 0; i < 4096; i++) state.pixels.set(i < 3277 ? [16, 16, 16, 255] : [224, 48, 80, 255], i * 4);
  const tone = await Palette.resolve('https://images.test/mostly-black');
  assert.ok(Math.max(...rgb(tone)) - Math.min(...rgb(tone)) < 30);
  const surface = rgb(Colors.surface(tone, 0xffffffff));
  assert.ok(Math.max(...surface) - Math.min(...surface) < 16);
  assert.equal(state.pickerCalls, 0);
  assert.deepEqual([state.destroyed, state.pixelReleased, state.sourceReleased], [1, 1, 1]);
});

test('unavailable or unsupported pixel data uses the main color without selecting a vivid fallback region', async () => {
  for (const failure of ['read', 'info', 'layout']) {
    const { state, Palette } = paletteFixture();
    state.color = { red: 128, green: 128, blue: 128, alpha: 255 }; state.fail = failure;
    assert.equal(await Palette.resolve('https://images.test/' + failure), '#808080');
    assert.equal(state.pickerCalls, 1);
    assert.ok(state.logs.some(entry => entry[2].includes('mode=main')));
    assert.deepEqual([state.destroyed, state.pixelReleased, state.sourceReleased], [1, 1, 1]);
  }
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

test('cached tones blend synchronously in both directions and across the loop boundary without requests', () => {
  const { Palette, state } = paletteFixture();
  Palette.cache.set('a', '#0000ff'); Palette.cache.set('b', '#ff0000');
  assert.equal(Palette.at(['a', 'b'], 0, new Set()), '#0000ff');
  assert.equal(Palette.at(['a', 'b'], 0.25, new Set()), '#4000bf');
  assert.equal(Palette.at(['a', 'b'], 0.5, new Set()), '#800080');
  assert.equal(Palette.at(['a', 'b'], 1.75, new Set()), '#4000bf');
  assert.equal(Palette.at(['a', 'b'], -0.25, new Set()), '#4000bf');
  assert.equal(Palette.at(['a', 'b'], 0, new Set(['a'])), '');
  assert.equal(Palette.at([], 0, new Set()), ''); assert.equal(Palette.at(['a'], NaN, new Set()), '');
  assert.equal(state.requests.length, 0);
});

const loggedTones = ['#184040', '#f8e870', '#405860', '#e03050', '#183858', '#083050'];
const colorDistance = (first, second) => Math.hypot(...rgb(first).map((v, i) => v - rgb(second)[i]));

test('actual fifth and sixth logged tones produce separated backgrounds in light and dark themes', () => {
  const display = Colors.distinguish(loggedTones);
  for (const [base, minimum] of [[0xffffffff, 22], [0xfff2f2f2, 22], [0xff121212, 18], [0xff000000, 18]]) {
    const first = Colors.surface(display[4], base), second = Colors.surface(display[5], base);
    assert.ok(colorDistance(first, second) >= minimum, `${first} / ${second}`);
    const text = (base & 255) < 128 ? '#e5e5e5' : '#182431';
    assert.ok(contrast(first, text) >= 4.5 && contrast(second, text) >= 4.5);
  }
  assert.deepEqual(display.slice(0, 4), loggedTones.slice(0, 4));
  assert.equal(display[5], loggedTones[5]);
  const channels = rgb(display[4]); assert.ok(channels[2] > channels[1] && channels[1] > channels[0]);
});

test('palette distinction is deterministic across navigation direction, order and duplicate artwork', () => {
  const expected = new Map(loggedTones.map((tone, i) => [tone, Colors.distinguish(loggedTones)[i]]));
  for (const order of [loggedTones, [...loggedTones].reverse(), [...loggedTones.slice(3), ...loggedTones.slice(0, 3)],
    [...loggedTones, loggedTones[4], loggedTones[5]]]) {
    const actual = Colors.distinguish(order);
    order.forEach((tone, i) => assert.equal(actual[i], expected.get(tone)));
  }
  assert.deepEqual(Colors.distinguish(['#183858', '#183858']), ['#183858', '#183858']);
});

test('neutral and distinct color families keep their original tones and near-red hues handle wraparound', () => {
  const plain = ['#000000', '#ffffff', '#808080', '#0000ff', '#ff0000', '#00ff00'];
  assert.deepEqual(Colors.distinguish(plain), plain);
  assert.deepEqual(Colors.distinguish(['invalid', '', '#ABCDEF']), ['', '', '#abcdef']);
  const reds = ['#801820', '#802018'];
  const display = Colors.distinguish(reds);
  assert.notDeepEqual(display, reds);
  for (const tone of display) { const c = rgb(tone); assert.ok(c[0] > c[1] && c[0] > c[2]); }
});

test('adjusted endpoints remain continuous while swiping and never replace the source color cache', () => {
  const { Palette, state } = paletteFixture(); const urls = loggedTones.map((_, i) => 'cover-' + i);
  urls.forEach((url, i) => Palette.cache.set(url, loggedTones[i]));
  const endpoints = urls.map((_, i) => Palette.at(urls, i, new Set()));
  assert.deepEqual(endpoints, Colors.distinguish(loggedTones));
  for (const start of [4, 5]) {
    let previous = Palette.at(urls, start, new Set());
    for (let step = 1; step <= 120; step++) {
      const position = start + step / 120;
      const actual = Palette.at(urls, position, new Set());
      const expected = rgb(Colors.blend(endpoints[start], endpoints[(start + 1) % urls.length], step / 120));
      assert.ok(Math.max(...rgb(actual).map((value, i) => Math.abs(value - expected[i]))) <= 1);
      assert.ok(Math.max(...rgb(actual).map((value, i) => Math.abs(value - rgb(previous)[i]))) <= 2);
      const wrapped = rgb(Palette.at(urls, position - urls.length, new Set()));
      assert.ok(Math.max(...rgb(actual).map((value, i) => Math.abs(value - wrapped[i]))) <= 1);
      previous = actual;
    }
  }
  assert.deepEqual(urls.map(url => Palette.peek(url)), loggedTones);
  assert.equal(Palette.at(urls, 4, new Set([urls[5]])), loggedTones[4]);
  assert.equal(state.requests.length, 0);
});

test('separation work is reused across frames and invalidated only when the available palette changes', () => {
  const { Palette } = paletteFixture(); const urls = loggedTones.map((_, i) => 'cover-' + i);
  urls.forEach((url, i) => Palette.cache.set(url, loggedTones[i]));
  const distinguish = Colors.distinguish; let calls = 0;
  Colors.distinguish = tones => { calls++; return distinguish(tones); };
  try {
    for (let i = 0; i < 180; i++) Palette.at(urls, i / 30, new Set());
    assert.equal(calls, 1);
    Palette.at(urls, 4, new Set([urls[5]])); assert.equal(calls, 2);
    Palette.at(urls, 4, new Set()); assert.equal(calls, 3);
    Palette.cache.set(urls[4], '#123456'); Palette.at(urls, 4, new Set()); assert.equal(calls, 4);
  } finally { Colors.distinguish = distinguish; }
});

test('warming prioritizes the current and both adjacent covers with at most three concurrent tasks', async () => {
  const { Palette } = paletteFixture(); const pending = new Map(), requested = [];
  let active = 0, peak = 0, ready = 0;
  Palette.resolve = url => new Promise(done => {
    requested.push(url); active++; peak = Math.max(peak, active);
    pending.set(url, () => { pending.delete(url); active--; done('#123456'); });
  });
  const warming = Palette.warm(['a', 'b', 'c', 'd', 'e', 'a'], () => { ready++; }, 2);
  assert.deepEqual(requested, ['c', 'd', 'b']);
  while (pending.size > 0) {
    [...pending.values()].forEach(finish => finish()); await new Promise(done => setImmediate(done));
  }
  await warming;
  assert.equal(peak, 3); assert.equal(active, 0); assert.equal(ready, 5);
  assert.equal(new Set(requested).size, requested.length);
  let current = true; const previousReady = ready; requested.length = 0;
  const stopped = Palette.warm(['a', 'b', 'c', 'd', 'e'], () => { ready++; }, 0, () => current);
  current = false; [...pending.values()].forEach(finish => finish()); await stopped;
  assert.equal(requested.length, 3); assert.equal(ready, previousReady);
});

function bannerFixture() {
  const source = read('pages/catvod/CatVodHeroBanner.ets');
  const methods = source.slice(source.indexOf('  aboutToAppear()'), source.indexOf('  build()'));
  const tasks = new Map(), output = [];
  const Palette = new Function('HomeHeroColors', compile(paletteSource) + ';return HomeHeroPalette;')(Colors);
  Palette.resolve = url => {
    const cached = Palette.cache.get(url); if (cached !== undefined) return Promise.resolve(cached);
    if (!tasks.has(url)) {
      let resolve; const promise = new Promise(done => { resolve = done; });
      tasks.set(url, { promise, resolve });
    }
    return tasks.get(url).promise.then(color => { Palette.cache.set(url, color); return color; });
  };
  const Banner = pageClass(methods, ['HomeHeroPalette'], [Palette]);
  const banner = Object.assign(new Banner(), { alive: false, visible: true, isActive: true, foreground: true,
    paletteRequest: 0, version: 1, currentIndex: 0, visualProgress: 0, progressReady: false, lastColor: '', failedArtwork: new Set(),
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

test('Cat background tracks fractional positions immediately instead of waiting for selection completion', async () => {
  const { banner, output, tasks } = bannerFixture(); banner.aboutToAppear();
  tasks.get('a').resolve('#0000ff'); tasks.get('b').resolve('#ff0000'); await settle();
  banner.followProgress(0.25); assert.equal(output.at(-1), '#4000bf');
  banner.followProgress(0.75); assert.equal(output.at(-1), '#bf0040');
  banner.followProgress(0.25); assert.equal(output.at(-1), '#4000bf');
  banner.changeSlide(1); await settle(); assert.equal(output.at(-1), '#4000bf');
});

test('a late adjacent color applies to the latest drag progress rather than the previous request position', async () => {
  const { banner, output, tasks } = bannerFixture(); banner.aboutToAppear();
  tasks.get('a').resolve('#0000ff'); await settle();
  banner.followProgress(0.2); banner.followProgress(0.8);
  tasks.get('b').resolve('#ff0000'); await settle();
  assert.equal(output.at(-1), '#cc0033');
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
  const page = Object.assign(new Page(), { alive: true, isActive: true, embeddedHomeTitle: true,
    source: { id: 'sub', updatedAt: 1 }, heroColor: '', themeBase: 0, heroSurface: '',
    showHero: () => true, onHeroSurfaceChanged: () => { published++; } });
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
