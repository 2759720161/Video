import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { createHash } from 'node:crypto';
import { test } from 'node:test';

const read = name => readFileSync(new URL('../entry/src/main/ets/services/media/' + name + '.ets', import.meta.url), 'utf8');
const compile = source => stripTypeScriptTypes(source.replace(/^import .*\r?\n/gm, '').replace(/export class /g, 'class '), { mode: 'transform' });
const Colors = new Function(compile(read('HomeHeroColors')) + ';return HomeHeroColors;')();

function storeFixture(initial = '[]') {
  let now = 1_000_000, id = 0;
  const timers = new Map(), state = { data: initial, legacyData: '[]', reads: 0, readKeys: [], writes: [], failRead: false, failWrite: false };
  const preferences = { getInstance: () => ({
    async getString(key) { state.reads++; state.readKeys.push(key); if (state.failRead) throw Error('read failed');
      return key === 'home_hero_palette_v1' ? state.legacyData : state.data; },
    async setString(key, value) { if (state.failWrite) throw Error('write failed'); state.data = value; state.writes.push([key, value]); }
  }) };
  const crypto = { createMd(algorithm) {
    assert.equal(algorithm, 'SHA256'); const hash = createHash('sha256');
    return { async update({ data }) { hash.update(data); }, async digest() { return { data: new Uint8Array(hash.digest()) }; } };
  } };
  const encoder = { TextEncoder: class { encodeInto(value) { return new TextEncoder().encode(value); } } };
  const makeStore = () => new Function('cryptoFramework', 'util', 'PreferencesStore', 'Date', 'setTimeout',
    compile(read('HomeHeroPaletteStore')) + ';return HomeHeroPaletteStore;')(
      crypto, encoder, preferences, { now: () => now }, callback => { timers.set(++id, callback); return id; });
  const Store = makeStore();
  return { Store, state, makeStore, timers, advance: ms => { now += ms; },
    flush: async () => { const tasks = [...timers.values()]; timers.clear(); tasks.forEach(task => task()); await Promise.resolve(); } };
}

test('persistent tones survive a fresh store and save only SHA256 identities, RGB and expiration', async () => {
  const { Store, state, makeStore, flush } = storeFixture();
  const url = 'https://图片.test/poster?api_key=secret-token&tag=123';
  const key = await Store.identity(url);
  assert.equal(key, createHash('sha256').update(url, 'utf8').digest('hex'));
  assert.notEqual(key, await Store.identity(url.replace('secret-token', 'rotated-token')));
  assert.equal(await Store.get(key), '');
  Store.put(key, '#3058b0'); Store.put(key, '#4058b0'); await flush();
  assert.equal(state.writes.length, 1);
  assert.ok(!state.data.includes('secret-token') && !state.data.includes('图片.test'));
  assert.deepEqual(Object.keys(JSON.parse(state.data)[0]).sort(), ['expiresAt', 'key', 'tone']);
  const fresh = makeStore();
  assert.equal(await fresh.get(key), '#4058b0');
  assert.equal(await fresh.get(await fresh.identity(url + 'changed')), '');
  assert.ok(state.readKeys.every(key => key === 'home_hero_palette_v2'));
  assert.ok(state.writes.every(([key]) => key === 'home_hero_palette_v2'));
});

test('stored colors expire after 24 hours and corrupt or unbounded records never become colors', async () => {
  for (const data of ['{broken', '{}', '[null]', 'x'.repeat(33 * 1024),
    JSON.stringify([{ key: 'a'.repeat(64), tone: 'red', expiresAt: 1_000_001 }]),
    JSON.stringify([{ key: 'a'.repeat(64), tone: '#123456', expiresAt: 100_000_000 }])]) {
    const { Store } = storeFixture(data); assert.equal(await Store.get('a'.repeat(64)), '');
  }
  const { Store, advance } = storeFixture(); const key = 'a'.repeat(64);
  await Store.get(key); Store.put(key, '#123456');
  advance(24 * 60 * 60 * 1000 - 1); assert.equal(await Store.get(key), '#123456');
  advance(1); assert.equal(await Store.get(key), '');
});

test('new whole-image cache does not reuse old vivid-region colors and persists the replacement', async () => {
  const { Store, state, makeStore, flush } = storeFixture();
  const key = await Store.identity('https://server.test/same-poster');
  state.legacyData = JSON.stringify([{ key, tone: '#e03050', expiresAt: 1_010_000 }]);
  assert.equal(await Store.get(key), '');
  assert.deepEqual(state.readKeys, ['home_hero_palette_v2']);
  Store.put(key, '#3d3436'); await flush();
  assert.equal(await makeStore().get(key), '#3d3436');
  assert.ok(state.legacyData.includes('#e03050'));
});

test('persistent cache shares hydration, bounds entries and batches writes without frame timers', async () => {
  const { Store, state, timers, flush } = storeFixture();
  await Promise.all([Store.get('a'), Store.get('b'), Store.get('c')]); assert.equal(state.reads, 1);
  for (let i = 0; i < 140; i++) Store.put(i.toString(16).padStart(64, '0'), '#123456');
  assert.equal(timers.size, 1); assert.equal(state.writes.length, 0);
  assert.equal(await Store.get('0'.repeat(64)), ''); await flush();
  assert.equal(JSON.parse(state.data).length, 128); assert.equal(state.writes.length, 1);
  Store.put('invalid', '#123456'); Store.put('a'.repeat(64), 'invalid'); assert.equal(timers.size, 0);
});

test('storage failures cannot reject cached-color readers or scheduled persistence', async () => {
  const { Store, state, flush } = storeFixture(); state.failRead = true; state.failWrite = true;
  assert.equal(await Store.get('a'), '');
  Store.put('a'.repeat(64), '#123456'); await flush();
  assert.equal(await Store.get('a'.repeat(64)), '#123456');
});

function paletteFixture(Store) {
  const logs = [], requested = [];
  const Palette = new Function('HomeHeroColors', 'HomeHeroPaletteStore', 'hilog',
    compile(read('HomeHeroPalette')) + ';return HomeHeroPalette;')(
      Colors, Store, { info: (...args) => logs.push(args) });
  Palette.extract = async url => { requested.push(url); return '#3058b0'; };
  return { Palette, logs, requested };
}

test('fresh palette restores persisted tones before network; shared calls and animation frames do not download', async () => {
  const { Store, makeStore, flush } = storeFixture();
  const original = 'https://server.test/poster?maxWidth=900&api_key=secret';
  const sample = original.replace('900', '64');
  const first = paletteFixture(Store);
  assert.deepEqual(await Promise.all([first.Palette.resolve(original, sample), first.Palette.resolve(original, sample)]),
    ['#3058b0', '#3058b0']);
  assert.deepEqual(first.requested, [sample]); await flush();
  const fresh = paletteFixture(makeStore());
  assert.equal(await fresh.Palette.resolve(original, sample), '#3058b0');
  assert.ok(fresh.logs.some(entry => entry[2] === 'restored id=%{public}d'));
  for (let i = 0; i < 120; i++) assert.equal(fresh.Palette.at([original], i / 120, new Set()), '#3058b0');
  assert.deepEqual(fresh.requested, []);
  assert.ok(!JSON.stringify(fresh.logs).includes('secret'));
});

test('warm uses each corresponding small sample while retaining original cache identities', async () => {
  const { Store } = storeFixture(); const { Palette, requested } = paletteFixture(Store);
  const original = ['a', 'b', 'c'].map(id => 'https://server.test/' + id + '?maxWidth=900');
  const small = original.map(url => url.replace('900', '64'));
  await Palette.warm(original, () => {}, 1, () => true, small);
  assert.deepEqual(requested, [small[1], small[2], small[0]]);
  assert.equal(Palette.peek(original[1]), '#3058b0'); assert.equal(Palette.peek(small[1]), '');
});

function traceFixture() {
  let now = 1_000_000; const logs = [], frames = [];
  const Trace = new Function('FrameCallback', 'hilog', 'Date', compile(read('HomeHeroSyncTrace')) + ';return HomeHeroSyncTrace;')(
    class {}, { info: (...args) => logs.push(args) }, { now: () => now });
  const trace = new Trace(), context = { postFrameCallback: probe => frames.push(probe) };
  return { Trace, trace, context, logs, frames, advance: ms => { now += ms; },
    draw: () => { frames.splice(0).forEach(probe => probe.onFrame(now * 1e6)); } };
}

test('progress diagnostics distinguish available tones, synchronous propagation and next-frame scheduling', () => {
  const { Trace, trace, context, logs, frames, advance, draw } = traceFixture();
  for (let i = 0; i < 30; i++) {
    trace.sample(context, 'cat', i / 30, () => {
      Trace.palette('cat', true); Trace.applied('cat', 'content'); Trace.applied('cat', 'home'); advance(3);
    });
    advance(13); draw();
  }
  assert.equal(logs.length, 0); assert.equal(frames.length, 0);
  trace.flush(); assert.equal(logs.length, 1);
  const entry = logs[0];
  assert.deepEqual(entry.slice(3, 8), ['cat', 30, 30, 30, 30]);
  assert.equal(entry[8], 3); assert.equal(entry[9], 16); assert.equal(entry[10], 16);
  Trace.applied('cat', 'home'); trace.flush(); assert.equal(logs.length, 1);
});

test('diagnostics summarize long drags, ignore foreign layers and invalidate delayed frame probes on reset', () => {
  const { Trace, trace, context, logs, advance, draw } = traceFixture();
  for (let i = 0; i < 80; i++) {
    trace.sample(context, 'emby', i / 80, () => { Trace.palette('emby', false); Trace.applied('cat', 'home'); });
    advance(16); draw();
  }
  trace.flush(); assert.ok(logs.length >= 1 && logs.length <= 2);
  assert.equal(logs.reduce((sum, entry) => sum + entry[4], 0), 80);
  assert.ok(logs.every(entry => entry[5] === 0 && entry[7] === 0));
  trace.sample(context, 'emby', 0, () => {}); trace.flush(); advance(2000); draw();
  trace.sample(context, 'emby', 1, () => {}); advance(16); draw(); trace.flush();
  assert.equal(logs.at(-1)[10], 16);
});

for (const kind of ['cat', 'emby']) {
  test(`${kind} cached swipe reaches content and outer-home state synchronously through the real handlers`, () => {
    const readPage = path => readFileSync(new URL('../entry/src/main/ets/pages/' + path + '.ets', import.meta.url), 'utf8');
    const { Trace, trace, context, logs } = traceFixture();
    const { Store } = storeFixture(); const { Palette } = paletteFixture(Store);
    const urls = ['https://server.test/blue', 'https://server.test/red'];
    Palette.cache.set(urls[0], '#0000ff'); Palette.cache.set(urls[1], '#ff0000');
    const makeClass = methods => new Function('HomeHeroSyncTrace', 'HomeHeroPalette', 'HomeHeroColors', '$r',
      compile(`class Page { ${methods} }`) + ';return Page;')(Trace, Palette, Colors, value => value);
    const homeSource = readPage('home/HomePage');
    const Home = makeClass(homeSource.slice(homeSource.indexOf('  private onCatSurfaceChanged('), homeSource.indexOf('  private homeBackground(')) +
      homeSource.slice(homeSource.indexOf('  private onEmbyBackgroundChanged('), homeSource.indexOf('  private catTitleSites(')));
    const source = { id: 'server', updatedAt: 123, providerType: kind === 'cat' ? 'catnode' : 'emby' };
    const home = Object.assign(new Home(), { isActive: true, selectedSource: () => source,
      isCatSource: () => kind === 'cat', catNavigation: { sourceId: source.id, heroVisible: true, heroSurface: '' } });
    let applyProgress, content;
    if (kind === 'cat') {
      const contentSource = readPage('catvod/CatVodContent');
      const Content = makeClass(contentSource.slice(contentSource.indexOf('  private setHeroColor('),
        contentSource.indexOf('  @Builder', contentSource.indexOf('  private setHeroColor('))));
      content = Object.assign(new Content(), { alive: true, isActive: true, embeddedHomeTitle: true,
        source, showHero: () => true, heroColor: '', heroSurface: '', themeBase: 0xfff2f2f2,
        onHeroSurfaceChanged: (...args) => home.onCatSurfaceChanged(...args) });
      const bannerSource = readPage('catvod/CatVodHeroBanner');
      const Banner = makeClass(bannerSource.slice(bannerSource.indexOf('  aboutToAppear('), bannerSource.indexOf('  build()')));
      const banner = Object.assign(new Banner(), { alive: true, isActive: true, foreground: true,
        currentIndex: 0, progressReady: false, lastColor: '', failedArtwork: new Set(),
        items: urls.map(poster => ({ poster })), onColorChanged: tone => content.setHeroColor(tone) });
      applyProgress = position => banner.followProgress(position);
    } else {
      const contentSource = readPage('emby/EmbyHomeContent');
      const Content = makeClass(contentSource.slice(contentSource.indexOf('  private hasFeaturedBackground('), contentSource.indexOf('  build()')));
      content = Object.assign(new Content(), { alive: true, isActive: true, foreground: true,
        source, query: '', error: '', heroTone: '', heroSurface: '', themeBase: 0xfff2f2f2, failedArtwork: new Set(),
        featuredItems: () => urls.map(poster => ({ poster })), provider: { imageUrlFor: item => item.poster },
        onBackgroundChanged: (...args) => home.onEmbyBackgroundChanged(...args) });
      applyProgress = position => content.onFeaturedProgress(position);
    }
    for (const position of [0, 0.25, 0.5, 0.75, 1]) {
      trace.sample(context, kind, position, () => applyProgress(position));
      const expected = Colors.surface(Palette.at(urls, position, new Set()), 0xfff2f2f2);
      assert.equal(content.heroSurface, expected);
      assert.equal(kind === 'cat' ? home.catNavigation.heroSurface : home.embyBackgroundColor, expected);
    }
    trace.flush(); assert.deepEqual(logs[0].slice(3, 8), [kind, 5, 5, 5, 5]);
    const finalSurface = Colors.surface('#ff0000', 0xfff2f2f2);
    assert.deepEqual(logs[0].slice(12), ['#ff0000', finalSurface, finalSurface]);
    Palette.cache.set(urls[0], '#183858'); Palette.cache.set(urls[1], '#083050');
    const surfaces = [];
    for (const position of [0, 0.25, 0.5, 0.75, 1]) {
      trace.sample(context, kind, position, () => applyProgress(position));
      const expected = Colors.surface(Palette.at(urls, position, new Set()), 0xfff2f2f2);
      assert.equal(content.heroSurface, expected);
      assert.equal(kind === 'cat' ? home.catNavigation.heroSurface : home.embyBackgroundColor, expected);
      surfaces.push(expected);
    }
    const channels = value => [1, 3, 5].map(i => parseInt(value.slice(i, i + 2), 16));
    assert.ok(Math.hypot(...channels(surfaces[0]).map((v, i) => v - channels(surfaces[4])[i])) >= 22);
    assert.deepEqual(urls.map(url => Palette.peek(url)), ['#183858', '#083050']);
    trace.flush(); assert.deepEqual(logs[1].slice(3, 8), [kind, 5, 5, 5, 5]);
  });
}

test('color diagnostics contain valid RGB only and do not carry previous-window colors forward', () => {
  const { Trace, trace, context, logs } = traceFixture();
  trace.sample(context, 'emby', 0, () => {
    Trace.palette('emby', true, '#123456');
    Trace.applied('emby', 'content', '#b3bac1'); Trace.applied('emby', 'home', '#b3bac1');
  });
  trace.flush(); assert.deepEqual(logs[0].slice(12), ['#123456', '#b3bac1', '#b3bac1']);
  trace.sample(context, 'emby', 1, () => {
    Trace.palette('emby', false, 'https://server.test?api_key=secret');
    Trace.applied('cat', 'home', '#abcdef');
  });
  trace.flush(); assert.deepEqual(logs[1].slice(12), ['', '', '']);
  assert.ok(!JSON.stringify(logs).includes('secret'));
});
