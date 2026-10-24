import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { createServer } from 'node:http';

const read = file => readFileSync(new URL('../entry/src/main/ets/' + file, import.meta.url), 'utf8');
const compile = source => stripTypeScriptTypes(source.replace(/^import .*\r?\n/gm, '').replace(/^export /gm, ''), { mode: 'transform' });
function fixture() {
  const state = { now: 1800000000000, short: false }; const files = new Map();
  const clock = { now: () => state.now };
  const Stream = new Function('Date', compile(read('core/playback/PlaybackStream.ets')) + ';return PlaybackStream;')(clock);
  const Policy = new Function('buffer', 'PlaybackStream', compile(read('providers/catvod/CatStreamCachePolicy.ets')) + ';return CatStreamCachePolicy;')(
    { from: Buffer.from }, Stream);
  const io = { accessSync: name => files.has(name), statSync: name => ({ size: Buffer.byteLength(files.get(name)) }),
    readTextSync: name => files.get(name), OpenMode: { CREATE: 1, TRUNC: 2, WRITE_ONLY: 4 }, openSync: name => ({ fd: name }),
    closeSync() {}, writeSync(name, value, options) { assert.equal(options.encoding, 'utf-8'); files.set(name, value);
      return Buffer.byteLength(value) - (state.short ? 1 : 0); },
    renameSync(from, to) { files.set(to, files.get(from)); files.delete(from); }, unlinkSync: name => files.delete(name) };
  const make = () => new Function('fileIo', 'buffer', 'PlaybackStream', 'CatStreamCachePolicy', 'Date',
    compile(read('providers/catvod/CatPlaybackStreamCache.ets')) + ';return CatPlaybackStreamCache;')(io,
    { byteLength: Buffer.byteLength }, Stream, Policy, clock);
  const stream = Object.assign(new Stream(), { url: 'https://media.invalid/video.mp4', headers: { Cookie: 'fixture-only' } });
  return { state, files, Stream, Policy, Cache: make(), make, stream, root: '/private/source', key: 'a'.repeat(64) };
}

test('stream cache survives restart, preserves request headers and never extends expiry on a hit', () => {
  const f = fixture(); f.Cache.put(f.root, f.key, f.stream, f.Cache.revision());
  const restarted = f.make(); const one = restarted.get(f.root, f.key);
  assert.equal(one.url, f.stream.url); assert.equal(one.headers.Cookie, 'fixture-only'); assert.equal(one.reused, true);
  assert.equal(one.expiresAt, f.state.now + 15 * 60000); one.headers.Cookie = 'changed';
  assert.equal(restarted.get(f.root, f.key).headers.Cookie, 'fixture-only');
  f.state.now += 15 * 60000 - 30000; assert.equal(restarted.get(f.root, f.key), null);
});

test('explicit expirations accept epoch seconds/milliseconds and are capped; unknown never becomes permanent', () => {
  const f = fixture(); const seconds = Math.floor((f.state.now + 90000) / 1000);
  assert.equal(f.Policy.expires({ expiresAt: seconds }, f.stream.url), seconds * 1000);
  assert.equal(f.Policy.expires({ expire_at: seconds * 1000 }, f.stream.url), seconds * 1000);
  assert.equal(f.Policy.expires({}, f.stream.url + '?expires=' + seconds), seconds * 1000);
  f.stream.expiresAt = f.state.now + 12 * 3600000;
  f.Cache.put(f.root, f.key, f.stream, f.Cache.revision());
  assert.equal(f.Cache.get(f.root, f.key).expiresAt, f.state.now + 2 * 3600000);
  f.stream.expiresAt = f.state.now - 1; assert.equal(f.Cache.put(f.root, 'b'.repeat(64), f.stream, f.Cache.revision()), false);
  f.state.now--; assert.equal(f.Cache.get(f.root, f.key), null);
});

test('self-contained proxy ticket keeps both upstream and a validated route rebound to the current port', () => {
  const f = fixture();
  const ticket = Buffer.from(JSON.stringify({ url: 'https://media.invalid/upstream.mp4',
    headers: { Cookie: 'ticket-cookie', 'User-Agent': 'ticket-agent', Referer: 'https://share.invalid/' },
    createdAt: f.state.now, threads: 16 })).toString('base64url');
  f.stream.url = 'http://127.0.0.1:12345/spider/source/3/proxy/anything/old-uuid?pst=' + encodeURIComponent(ticket);
  f.stream.headers = { Authorization: 'proxy-only-must-not-forward' };
  assert.equal(f.Cache.put(f.root, f.key, f.stream, f.Cache.revision()), true);
  const cached = f.make().get(f.root, f.key);
  assert.equal(cached.url, 'https://media.invalid/upstream.mp4'); assert.equal(cached.headers.Cookie, 'ticket-cookie');
  assert.equal(cached.headers.Authorization, undefined); assert.equal(cached.userAgent, 'ticket-agent');
  assert.equal(cached.referer, 'https://share.invalid/');
  const disk = f.files.get(f.root + '/playback-streams.json');
  assert.ok(!disk.includes('127.0.0.1') && !disk.includes('12345') && !disk.includes('proxy-only'));
  const local = f.make().get(f.root, f.key, 'http://127.0.0.1:23456');
  assert.match(local.url, /^http:\/\/127\.0\.0\.1:23456\/spider\/source\/3\/proxy\//);
  assert.deepEqual(local.headers, {}); assert.equal(local.userAgent, ''); assert.equal(local.reused, true);
  assert.equal(local.expiresAt, cached.expiresAt);
  for (const base of ['https://remote.invalid', 'http://127.0.0.1:23456/path', 'http://127.0.0.1:70000'])
    assert.equal(f.Cache.get(f.root, f.key, base), null);
  const entries = JSON.parse(disk); entries[0].sourceProxyPath = '/runtime/stop?pst=' + ticket;
  f.files.set(f.root + '/playback-streams.json', JSON.stringify(entries));
  assert.equal(f.Cache.get(f.root, f.key, 'http://127.0.0.1:23456'), null);
  assert.equal(f.Cache.get(f.root, f.key).url, cached.url);
  entries[0].sourceProxyPath = entries[0].sourceProxyPath.replace('/runtime/stop', '/spider/source/3/proxy/id');
  entries[0].stream.url = 'https://media.invalid/different.mp4';
  f.files.set(f.root + '/playback-streams.json', JSON.stringify(entries));
  assert.equal(f.Cache.get(f.root, f.key, 'http://127.0.0.1:23456'), null, 'ticket must match the cached upstream');
  for (const url of ['http://127.0.0.1:1234/proxy/id', 'js2p://_WEB_/proxy/id', 'file://video', 'javascript:bad',
    'http://127.0.0.1:1234/proxy?id=1&pst=bad', 'https://user:pass@media.invalid/a.mp4']) {
    f.stream.url = url; assert.equal(f.Policy.reusable(f.stream), null, url);
  }
});

test('old direct-only cache remains readable without fabricating a source proxy route', () => {
  const f = fixture(); f.Cache.put(f.root, f.key, f.stream, f.Cache.revision());
  const path = f.root + '/playback-streams.json'; const entries = JSON.parse(f.files.get(path));
  delete entries[0].sourceProxyPath; f.files.set(path, JSON.stringify(entries));
  assert.equal(f.Cache.get(f.root, f.key).url, f.stream.url);
  assert.equal(f.Cache.get(f.root, f.key, 'http://127.0.0.1:2222'), null);
});

test('restored source transport forwards authentication and both first-byte and distant seek ranges over real HTTP', async () => {
  const received = [];
  const origin = createServer((req, res) => {
    received.push({ range: req.headers.range, cookie: req.headers.cookie, agent: req.headers['user-agent'] });
    const start = Number(req.headers.range?.match(/bytes=(\d+)-/)?.[1] ?? 0);
    res.writeHead(206, { 'content-type': 'video/mp4', 'content-range': `bytes ${start}-${start + 15}/2000000` });
    res.end(Buffer.from('\0\0\0\x18ftypisom\0\0\0\0', 'binary'));
  });
  await new Promise(resolve => origin.listen(0, '127.0.0.1', resolve));
  // The fixture emulates a source's complete-ticket proxy. Its upstream here is
  // localhost for isolation; production policy still only accepts remote media.
  let ticketRequest;
  const proxy = createServer(async (req, res) => {
    try {
      const ticket = new URL(req.url, 'http://127.0.0.1').searchParams.get('pst');
      ticketRequest = JSON.parse(Buffer.from(ticket, 'base64url').toString('utf8'));
      const upstream = await fetch('http://127.0.0.1:' + origin.address().port + '/media', {
        headers: { ...ticketRequest.headers, Range: req.headers.range }
      });
      res.writeHead(upstream.status, Object.fromEntries(upstream.headers));
      res.end(Buffer.from(await upstream.arrayBuffer()));
    } catch { res.writeHead(500); res.end(); }
  });
  await new Promise(resolve => proxy.listen(0, '127.0.0.1', resolve));
  const f = fixture();
  const ticket = Buffer.from(JSON.stringify({ url: 'https://media.invalid/large.mp4',
    headers: { Cookie: 'fixture-auth', 'User-Agent': 'fixture-agent' }, threads: 8, chunkKB: 256 })).toString('base64url');
  f.stream.url = 'http://127.0.0.1:1/spider/source/3/proxy/media/opaque?pst=' + ticket;
  try {
    assert.equal(f.Cache.put(f.root, f.key, f.stream, f.Cache.revision()), true);
    const restored = f.make().get(f.root, f.key, 'http://127.0.0.1:' + proxy.address().port);
    for (const range of ['bytes=0-4095', 'bytes=1000000-']) {
      const response = await fetch(restored.url, { headers: { Range: range } });
      assert.equal(response.status, 206); assert.equal((await response.arrayBuffer()).byteLength, 16);
      assert.equal(received.at(-1).range, range); assert.equal(received.at(-1).cookie, 'fixture-auth');
      assert.equal(received.at(-1).agent, 'fixture-agent');
    }
    assert.equal(ticketRequest.threads, 8); assert.equal(ticketRequest.chunkKB, 256);
  } finally {
    for (const server of [proxy, origin]) { server.closeAllConnections(); await new Promise(resolve => server.close(resolve)); }
  }
});

test('malformed headers, broken files, partial writes, bounded capacity and invalidation are safe misses', () => {
  const f = fixture(); f.stream.headers.Cookie = 'line\r\ninjection';
  assert.equal(f.Cache.put(f.root, f.key, f.stream, f.Cache.revision()), false);
  f.stream.headers = { Cookie: 'fixture-only' }; f.Cache.put(f.root, f.key, f.stream, f.Cache.revision());
  const path = f.root + '/playback-streams.json'; const saved = f.files.get(path);
  for (const broken of ['{', '{}', '[null]', '[{}]']) { f.files.set(path, broken); assert.equal(f.Cache.get(f.root, f.key), null); }
  f.files.set(path, saved); f.state.short = true; f.stream.url = 'https://media.invalid/new.mp4';
  assert.equal(f.Cache.put(f.root, f.key, f.stream, f.Cache.revision()), false);
  assert.equal(f.Cache.get(f.root, f.key).url, 'https://media.invalid/video.mp4');
  f.state.short = false;
  for (let i = 0; i < 20; i++) f.Cache.put(f.root, String(i).padStart(64, '0'), f.stream, f.Cache.revision());
  assert.ok(JSON.parse(f.files.get(path)).length <= 12); assert.ok(f.files.get(path).length <= 512 * 1024);
  const revision = f.Cache.revision(); f.Cache.invalidate(f.root);
  assert.equal(f.Cache.put(f.root, f.key, f.stream, revision), false); assert.equal(f.Cache.get(f.root, f.key), null);
});

function probeFixture(response) {
  const f = fixture(); const calls = { destroyed: 0, requests: [], timers: [], cleared: [] };
  const http = { RequestMethod: { GET: 'GET' }, HttpDataType: { ARRAY_BUFFER: 1 }, createHttp: () => ({
    request(url, options) { calls.requests.push({ url, options }); return response instanceof Promise ? response : Promise.resolve(response); },
    destroy() { calls.destroyed++; }
  }) };
  const Probe = new Function('http', 'PlaybackStream', 'setTimeout', 'clearTimeout',
    compile(read('providers/catvod/CatStreamProbe.ets')) + ';return CatStreamProbe;')(
    http, f.Stream, (action, ms) => { calls.timers.push({ action, ms }); return calls.timers.length; }, id => calls.cleared.push(id));
  return { ...f, Probe, calls };
}
const body = text => Uint8Array.from(Buffer.from(text)).buffer;
test('stream probe uses bounded range GET with original authentication and rejects HTML/JSON/status failures', async () => {
  const f = probeFixture({ responseCode: 206, header: { 'Content-Type': 'video/mp4' }, result: body('\0\0\0\x18ftypisom') });
  assert.equal(await f.Probe.check(f.stream), true);
  const options = f.calls.requests[0].options;
  assert.equal(options.header.Range, 'bytes=0-4095'); assert.equal(options.header.Cookie, 'fixture-only');
  assert.equal(options.maxLimit, 8192); assert.equal(f.calls.timers[0].ms, 1500); assert.equal(f.calls.destroyed, 1);
  for (const response of [
    { responseCode: 403, header: {}, result: body('forbidden') },
    { responseCode: 200, header: { 'content-type': 'text/html' }, result: body('<html>login</html>') },
    { responseCode: 206, header: { 'content-type': 'video/mp4' }, result: body('{"error":"login"}') },
    { responseCode: 206, header: {}, result: new ArrayBuffer(0) }
  ]) { const invalid = probeFixture(response); assert.equal(await invalid.Probe.check(invalid.stream), false); assert.equal(invalid.calls.destroyed, 1); }
});

test('a hanging probe hits its total deadline and always releases the request', async () => {
  const f = probeFixture(new Promise(() => {})); const pending = f.Probe.check(f.stream);
  f.calls.timers[0].action(); assert.equal(await pending, false); assert.equal(f.calls.destroyed, 1);
});

test('session refresh bypasses stream cache exactly during resolution and restores intent even after rejection', async () => {
  const f = fixture();
  const Manager = new Function('PlaybackSession', 'PlaybackQueueItem', 'PlaybackSubtitle', 'PlaybackReportController',
    compile(read('services/PlaybackSessionManager.ets')) + ';return PlaybackSessionManager;')(class {}, class {}, class {}, class {});
  for (const fail of [false, true]) {
    const manager = new Manager(); const item = { sourceId: 'source', mediaId: 'work', bypassStreamCache: false };
    const current = { id: 'session', media: { sourceId: 'source', mediaId: 'work' }, stream: f.stream, queue: [item], queueIndex: 0 };
    manager.sessions.set('session', current);
    manager.resolvers.set('session', { async resolvePlayback(selected) {
      assert.equal(selected.bypassStreamCache, true); if (fail) throw new Error('unavailable');
      return { ...current, stream: f.stream };
    }, createReporterForSession() { return null; } });
    if (fail) await assert.rejects(manager.ensureFreshStream('session', 30000, true), /unavailable/);
    else assert.equal((await manager.ensureFreshStream('session', 30000, true)).media.mediaId, 'work');
    assert.equal(item.bypassStreamCache, false);
  }
});

test('probe exchanges a real HTTP range request and rejects a successful HTTP login page', async () => {
  const requests = [];
  const server = createServer((request, response) => {
    requests.push(request.headers);
    if (request.url === '/login') { response.writeHead(200, { 'content-type': 'text/html' }); response.end('<html>login</html>'); return; }
    if (request.url === '/denied') { response.writeHead(403); response.end('denied'); return; }
    response.writeHead(206, { 'content-type': 'video/mp4', 'content-range': 'bytes 0-15/102400' });
    response.end(Buffer.from('\0\0\0\x18ftypisom\0\0\0\0', 'binary'));
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const f = fixture();
  const http = { RequestMethod: { GET: 'GET' }, HttpDataType: { ARRAY_BUFFER: 1 }, createHttp: () => {
    const abort = new AbortController();
    return { async request(url, options) {
      const response = await fetch(url, { method: options.method, headers: options.header, signal: abort.signal });
      return { responseCode: response.status, header: Object.fromEntries(response.headers), result: await response.arrayBuffer() };
    }, destroy() { abort.abort(); } };
  } };
  const Probe = new Function('http', 'PlaybackStream', compile(read('providers/catvod/CatStreamProbe.ets')) + ';return CatStreamProbe;')(http, f.Stream);
  const base = 'http://127.0.0.1:' + server.address().port;
  try {
    f.stream.url = base + '/media'; assert.equal(await Probe.check(f.stream), true);
    assert.equal(requests[0].range, 'bytes=0-4095'); assert.equal(requests[0].cookie, 'fixture-only');
    f.stream.url = base + '/login'; assert.equal(await Probe.check(f.stream), false);
    f.stream.url = base + '/denied'; assert.equal(await Probe.check(f.stream), false);
  } finally { server.closeAllConnections(); await new Promise(resolve => server.close(resolve)); }
});
