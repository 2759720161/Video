import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import assert from 'node:assert/strict';
import { test } from 'node:test';

const source = readFileSync(new URL('../entry/src/main/ets/providers/catvod/CatPlaybackSnapshotStore.ets', import.meta.url), 'utf8');
const compiled = stripTypeScriptTypes(source.replace(/^import .*\r?\n/gm, '').replace(/^export /gm, ''), { mode: 'transform' });
function fixture() {
  const files = new Map(); const state = { now: 1000000, short: false };
  const fileIo = { accessSync: path => files.has(path), statSync: path => ({ size: Buffer.byteLength(files.get(path)) }),
    readTextSync: path => files.get(path), OpenMode: { CREATE: 1, TRUNC: 2, WRITE_ONLY: 4 },
    openSync: path => ({ fd: path }), closeSync() {}, writeSync(path, text, options) {
      assert.equal(options.encoding, 'utf-8'); files.set(path, text);
      return Buffer.byteLength(text, 'utf8') - (state.short ? 1 : 0);
    }, renameSync(from, to) { files.set(to, files.get(from)); files.delete(from); }, unlinkSync: path => files.delete(path) };
  const make = () => new Function('fileIo', 'buffer', 'CatArtwork', 'Date', compiled + ';return CatPlaybackSnapshotStore;')(
    fileIo, { byteLength: Buffer.byteLength }, { needsHeaders: value => /^https:\/\/img\d*\.doubanio\.com\//.test(value) }, { now: () => state.now });
  return { Store: make(), make, state, files, root: '/private/source', key: 'a'.repeat(64) };
}
const video = () => ({ id: 'work', name: '作品', poster: 'https://images.invalid/cover.jpg', overview: '简介',
  roads: [{ id: 'line:0', name: '线路', spiderKey: 'directory', episodes: [{ name: '正片', url: 'opaque-file-id', occurrence: 0 }] }] });

test('metadata survives a new store instance; reader mutations are isolated and preferences do not extend freshness', () => {
  const f = fixture(); const detail = video();
  assert.equal(f.Store.put(f.root, f.key, detail, f.Store.revision()), true);
  const restarted = f.make(); const first = restarted.get(f.root, f.key, 'work'); first.name = '更改';
  assert.equal(restarted.get(f.root, f.key, 'work').name, '作品');
  f.state.now += 10 * 60 * 1000;
  assert.equal(restarted.put(f.root, f.key, detail, restarted.revision(), 'episode', 'line:0'), true);
  assert.equal(restarted.preferred(f.root, f.key, 'episode'), 'line:0');
  const newer = { ...video(), name: '较新详情' };
  assert.equal(restarted.put(f.root, f.key, newer, restarted.revision()), true);
  assert.equal(restarted.put(f.root, f.key, detail, restarted.revision(), 'episode', 'line:0'), true);
  assert.equal(restarted.get(f.root, f.key, 'work').name, '较新详情');
  assert.equal(restarted.get(f.root, 'b'.repeat(64), 'work'), null);
  assert.equal(restarted.get(f.root, f.key, 'other'), null);
  f.state.now += 30 * 60 * 1000;
  assert.equal(restarted.get(f.root, f.key, 'work'), null);
  assert.equal(restarted.put(f.root, f.key, detail, restarted.revision(), 'episode', 'line:0'), false);
});

test('clock rollback, corrupt files, wrong shapes and partial writes never expose invalid metadata', () => {
  const f = fixture(); f.Store.put(f.root, f.key, video(), f.Store.revision());
  const path = f.root + '/playback-metadata.json'; const saved = f.files.get(path);
  f.state.now--; assert.equal(f.Store.get(f.root, f.key, 'work'), null); f.state.now++;
  for (const malformed of ['{broken', '{}', '[null]', '[{}]', JSON.stringify([{ key: f.key, savedAt: f.state.now, detail: { id: 'work' } }])]) {
    f.files.set(path, malformed); assert.equal(f.Store.get(f.root, f.key, 'work'), null);
  }
  f.files.set(path, saved); f.state.short = true;
  assert.equal(f.Store.put(f.root, f.key, { ...video(), name: '不完整' }, f.Store.revision()), false);
  assert.equal(f.Store.get(f.root, f.key, 'work').name, '作品');
});

test('runtime playback URLs are excluded and protected artwork is restored as an original URL', () => {
  const f = fixture(); const detail = video();
  for (const url of ['http://127.0.0.1:9999/proxy?id=old', 'js2p://_WEB_/proxy', 'http://localhost:9999/a', 'http://[::1]:99/a']) {
    detail.roads[0].episodes[0].url = url;
    assert.equal(f.Store.put(f.root, f.key, detail, f.Store.revision()), false);
  }
  detail.roads[0].episodes[0].url = 'opaque-file-id';
  detail.poster = 'http://127.0.0.1:99/__video_artwork?url=' + encodeURIComponent('https://img2.doubanio.com/a.webp');
  assert.equal(f.Store.put(f.root, f.key, detail, f.Store.revision()), true);
  assert.equal(f.Store.get(f.root, f.key, 'work').poster, 'https://img2.doubanio.com/a.webp');
  assert.ok(!f.files.get(f.root + '/playback-metadata.json').includes('127.0.0.1'));
});

test('cache is bounded and invalidation prevents a late read from storing old configuration', () => {
  const f = fixture(); const detail = video(); detail.overview = '长'.repeat(400000);
  for (let i = 0; i < 10; i++) f.Store.put(f.root, String(i).padStart(64, '0'), detail, f.Store.revision());
  const text = f.files.get(f.root + '/playback-metadata.json');
  assert.ok(text.length <= 2 * 1024 * 1024); assert.ok(JSON.parse(text).length <= 6);
  const revision = f.Store.revision(); f.Store.invalidate(f.root);
  assert.equal(f.Store.put(f.root, f.key, video(), revision), false);
  assert.equal(f.Store.get(f.root, f.key, 'work'), null);
});

test('observed detail dependency survives restart without extending snapshot validity', () => {
  const f = fixture(); f.Store.put(f.root, f.key, video(), f.Store.revision());
  f.state.now += 10 * 60 * 1000; f.Store.markRequiresLive(f.root, f.key);
  assert.equal(f.make().requiresLive(f.root, f.key), true);
  assert.equal(f.Store.requiresLive(f.root, 'b'.repeat(64)), false);
  f.state.now += 20 * 60 * 1000;
  assert.equal(f.Store.get(f.root, f.key, 'work'), null);
  assert.equal(f.make().requiresLive(f.root, f.key), false);
});
