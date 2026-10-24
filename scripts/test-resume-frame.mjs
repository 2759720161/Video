import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { test } from 'node:test';

const read = name => readFileSync(new URL('../entry/src/main/ets/' + name, import.meta.url), 'utf8');
const compile = source => stripTypeScriptTypes(source.replace(/^import .*\r?\n/gm, '').replace(/^export /gm, ''), { mode: 'transform' });
const defer = () => { let resolve; const promise = new Promise(done => { resolve = done; }); return { promise, resolve }; };

function fixture() {
  const files = new Map(), handles = new Map(), directories = new Set(); let fd = 0;
  const state = { failCapture: false, failPack: false, shortWrite: false, failRename: false, gates: [], sdk: 26 };
  const calls = { events: [], notices: 0, closed: 0, pixelReleases: 0, packerReleases: 0 };
  const fileIo = {
    OpenMode: { CREATE: 1, WRITE_ONLY: 2, TRUNC: 4 },
    accessSync: path => files.has(path) || directories.has(path), mkdirSync: path => directories.add(path),
    openSync(path) { handles.set(++fd, path); return { fd }; },
    writeSync(fd, bytes) { const buffer = Buffer.from(bytes); files.set(handles.get(fd), buffer); return buffer.length - (state.shortWrite ? 1 : 0); },
    closeSync(file) { calls.closed++; handles.delete(file.fd); },
    readTextSync(path) { if (!files.has(path)) throw new Error('missing'); return files.get(path).toString('utf8'); },
    renameSync(from, to) { if (state.failRename) throw new Error('rename'); files.set(to, files.get(from)); files.delete(from); },
    unlinkSync: path => files.delete(path),
    listFileSync: root => [...files.keys()].filter(path => path.startsWith(root + '/')).map(path => path.slice(root.length + 1))
  };
  const pixel = () => {
    calls.events.push('capture'); if (state.failCapture) throw new Error('no surface');
    return { getImageInfoSync: () => ({ size: { width: 1920, height: 1080 } }),
      async scale(x, y) { calls.events.push(['scale', x, y]); }, async release() { calls.pixelReleases++; } };
  };
  const image = { createPixelMapFromSurfaceSync: pixel,
    createPixelMapFromSurfaceWithTransformationSync(id, enabled) { assert.equal(enabled, true); return pixel(); },
    createImagePacker: () => ({ async packToData(value, options) {
      assert.equal(options.format, 'image/jpeg'); const gate = state.gates.shift(); if (gate) await gate.promise;
      if (state.failPack) throw new Error('encode'); return new Uint8Array([255, 216, 255, 217]).buffer;
    }, async release() { calls.packerReleases++; } }) };
  const cryptoFramework = { createMd: () => {
    const digest = createHash('sha256'); return { async update({ data }) { digest.update(data); },
      async digest() { return { data: new Uint8Array(digest.digest()) }; } };
  } };
  const dependencies = { image, cryptoFramework, fileIo, fileUri: { getUriFromPath: path => 'file://' + path },
    util: { TextEncoder: class { encodeInto(text) { return new TextEncoder().encode(text); } } },
    PlaybackHistoryChangeSignal: { notifyChanged() { calls.notices++; } },
    Logger: class { info() {} warn() {} }, deviceInfo: { get sdkApiVersion() { return state.sdk; } } };
  const restart = () => new Function(...Object.keys(dependencies), compile(read('services/media/ResumeFrameStore.ets')) +
    ';return ResumeFrameStore;')(...Object.values(dependencies));
  const Store = restart();
  const context = { filesDir: '/private/app' };
  const capture = (source = 'cat-a', id = 'episode:1', position = 17000) => Store.capture(context, source, id, 'surface', position);
  const resolve = (source = 'cat-a', id = 'episode:1', position = 17000) => Store.resolve(context, source, id, position);
  return { Store, restart, files, handles, state, calls, context, capture, resolve };
}

test('exit frame is read before caller teardown, scaled and persisted under source/media identity with resources released', async () => {
  const f = fixture(); const saved = f.capture(); f.calls.events.push('stop'); await saved;
  assert.equal(f.calls.events[0], 'capture'); assert.equal(f.calls.events[2], 'stop');
  assert.deepEqual(f.calls.events[1], ['scale', 1 / 3, 1 / 3]);
  const uri = await f.resolve(); assert.match(uri, /^file:\/\/\/private\/app\/resume_frames\/[a-f0-9]{64}-\d+-\d+\.jpg$/);
  assert.equal(await f.resolve('cat-b'), ''); assert.equal(await f.resolve('cat-a', 'episode:2'), '');
  assert.equal(await f.resolve('cat-a', 'episode:1', 90000), ''); assert.equal(await f.resolve('cat-a', 'episode:1', NaN), '');
  assert.equal(f.calls.notices, 1); assert.equal(f.handles.size, 0);
  assert.equal(f.calls.pixelReleases, 1); assert.equal(f.calls.packerReleases, 1);
  assert.ok([...f.files.keys()].every(name => !name.includes('cat-a') && !name.includes('episode')));
});

test('replacement changes image URI, cleans the old frame and can be resolved by a fresh instance', async () => {
  const f = fixture(); await f.capture(); const old = await f.resolve();
  await f.capture('cat-a', 'episode:1', 25000); const latest = await f.resolve('cat-a', 'episode:1', 25000);
  assert.notEqual(old, latest); assert.equal(f.files.has(old.slice(7)), false);
  assert.equal(await f.restart().resolve(f.context, 'cat-a', 'episode:1', 25000), latest);
  assert.equal(f.files.size, 2);
  f.state.sdk = 20; await f.capture('cat-a', 'another', 5000);
  assert.ok(await f.resolve('cat-a', 'another', 5000));
});

test('late encoding from an older exit cannot overwrite a newer exit frame', async () => {
  const f = fixture(); const gate = defer(); f.state.gates.push(gate);
  const first = f.capture('cat-a', 'episode:1', 10000);
  await Promise.resolve(); await f.capture('cat-a', 'episode:1', 80000);
  const latest = await f.resolve('cat-a', 'episode:1', 80000);
  gate.resolve(); await first;
  assert.equal(await f.resolve('cat-a', 'episode:1', 80000), latest);
  assert.equal(await f.resolve('cat-a', 'episode:1', 10000), ''); assert.equal(f.calls.notices, 1);
});

test('capture, encode, write or rename failures preserve an existing frame and never publish incomplete metadata', async () => {
  for (const failure of ['failCapture', 'failPack', 'shortWrite', 'failRename']) {
    const f = fixture(); await f.capture(); const old = await f.resolve();
    f.state[failure] = true; await f.capture();
    assert.equal(await f.resolve(), old, failure); assert.equal(f.files.size, 2, failure);
    assert.equal(f.handles.size, 0); assert.equal(f.calls.notices, 1);
    assert.equal(f.calls.pixelReleases, failure === 'failCapture' ? 1 : 2);
    assert.equal(f.calls.packerReleases, failure === 'failCapture' ? 1 : 2);
  }
});

test('frame cache retains at most 64 entries and never deletes unrelated files', async () => {
  const f = fixture(); f.files.set('/private/app/resume_frames/unrelated.txt', Buffer.from('keep'));
  for (let i = 0; i < 67; i++) await f.capture('cat-a', String(i), 1000 + i);
  const names = [...f.files.keys()];
  assert.equal(names.filter(name => name.endsWith('.json')).length, 64);
  assert.equal(names.filter(name => name.endsWith('.jpg')).length, 64);
  assert.equal(f.files.get('/private/app/resume_frames/unrelated.txt').toString(), 'keep');
});

test('compact cards fit two columns, cap on large screens and format finite playback positions', () => {
  const P = new Function(compile(read('components/media/ContinueWatchingPresentation.ets')) + ';return ContinueWatchingPresentation;')();
  assert.equal(P.width(350), 169); assert.equal(P.width(760), 240); assert.equal(P.width(NaN), 154);
  assert.equal(P.time(17000), '00:17'); assert.equal(P.time(3723000), '1:02:03');
  assert.equal(P.time(NaN), '00:00'); assert.equal(P.time(-1), '00:00');
});

test('normal player back captures once before navigation, skipping local, unready and fullscreen-only back', () => {
  const source = read('pages/player/PlayerPage.ets');
  const capture = source.slice(source.indexOf('  private captureContinueFrame('), source.indexOf('  private stopPlaybackBeforeLeaving('));
  const leave = source.slice(source.indexOf('  private leavePlayerNormally('), source.indexOf('  private shouldAutoLeaveWithTypeNodePiP('));
  const calls = [];
  const Page = new Function('ResumeFrameStore', 'router', 'logger', compile('class Page { ' + capture + leave + ' }') + ';return Page;')(
    { capture(...args) { calls.push(['capture', ...args]); } }, { back() { calls.push(['back']); } }, { warn() {} });
  const page = Object.assign(new Page(), { isLocalSource: false, session: { media: { sourceId: 'cat', mediaId: 'episode' } },
    xComponentController: { getXComponentSurfaceId: () => 'surface' }, hasEngine: true, videoWidth: 1920, positionMs: 17000,
    videoUri: 'stream', continueFrameVideo: '', playerEngine: { getState: () => ({ positionMs: 17500 }) },
    getUIContext: () => ({ getHostContext: () => ({}) }), handleBackFromPlayer: () => false });
  page.leavePlayerNormally(); page.captureContinueFrame();
  assert.equal(calls.length, 2); assert.equal(calls[0][0], 'capture'); assert.equal(calls[0].at(-1), 17500); assert.equal(calls[1][0], 'back');
  page.continueFrameVideo = ''; page.isLocalSource = true; page.captureContinueFrame(); assert.equal(calls.length, 2);
  page.isLocalSource = false; page.videoWidth = 0; page.captureContinueFrame(); assert.equal(calls.length, 2);
  page.handleBackFromPlayer = () => true; page.leavePlayerNormally(); assert.equal(calls.length, 2);
});

test('Emby resume covers publish only the latest live request and clear missing frames', async () => {
  const source = read('pages/emby/EmbyHomeContent.ets');
  const method = source.slice(source.indexOf('  private async refreshResumeFrames('), source.indexOf('  private hasFeaturedBackground('));
  let gate = null;
  const Page = new Function('ResumeFrameStore', compile('class Page { ' + method + ' }') + ';return Page;')({
    async resolve(context, source, id, position) { return gate ? gate.promise : id === 'saved' ? 'file:///exit-frame.jpg' : ''; }
  });
  const page = Object.assign(new Page(), { alive: true, isActive: true, generation: 1, resumeFrameRequest: 0, resumeFrames: {},
    source: { id: 'emby' }, getUIContext: () => ({ getHostContext: () => ({}) }) });
  const snapshot = id => ({ resumeItems: [{ id, resumePositionMs: () => 17000 }] });
  await page.refreshResumeFrames(snapshot('saved')); assert.deepEqual(page.resumeFrames, { saved: 'file:///exit-frame.jpg' });
  gate = defer(); const first = page.refreshResumeFrames(snapshot('old')); const old = gate;
  gate = null; await page.refreshResumeFrames(snapshot('missing')); old.resolve('file:///old.jpg'); await first;
  assert.deepEqual(page.resumeFrames, {});
  gate = defer(); const last = page.refreshResumeFrames(snapshot('saved')); page.alive = false;
  gate.resolve('file:///late.jpg'); await last; assert.deepEqual(page.resumeFrames, {});
});
