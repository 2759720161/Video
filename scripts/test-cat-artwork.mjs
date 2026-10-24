import assert from 'node:assert/strict';
import { createServer, get } from 'node:http';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes, createRequire } from 'node:module';
import { test } from 'node:test';
const require = createRequire(import.meta.url);
const { createArtworkProxy, imagePolicy } = require('../entry/src/main/resources/rawfile/catnode/artwork.cjs');
const source = readFileSync(new URL('../entry/src/main/ets/providers/catvod/CatArtwork.ets', import.meta.url), 'utf8');
const Artwork = new Function(stripTypeScriptTypes(source.replace('export class', 'class')) + ';return CatArtwork;')();
const image = Buffer.from('524946460400000057454250', 'hex');
const address = 'https://img1.doubanio.com/view/photo/s_ratio_poster/public/example.webp';

test('image normalization preserves source proxies, relative paths, direct media and protected-domain query strings', () => {
  const base = 'http://127.0.0.1:40001';
  const value = address + '?v=1&size=2';
  const proxied = Artwork.resolve(value, base);
  assert.equal(new URL(proxied).pathname, '/__video_artwork');
  assert.equal(new URL(proxied).searchParams.get('url'), value);
  assert.equal(Artwork.resolve(proxied, 'http://127.0.0.1:40002'), proxied.replace(':40001', ':40002'));
  assert.equal(Artwork.resolve(proxied), '');
  assert.equal(Artwork.resolve(value), '');
  assert.equal(Artwork.resolve('js2p://_WEB_/image?key=x', base), base + '/image?key=x');
  assert.equal(Artwork.resolve('/image?key=x', base), base + '/image?key=x');
  assert.equal(Artwork.resolve('//other.example/image'), 'https://other.example/image');
  for (const url of ['https://other.example/p.jpg', 'file:///private/frame.jpg', 'data:image/png;base64,abc']) {
    assert.equal(Artwork.resolve(url, base), url);
  }
});

test('header policy is restricted to exact known image domains with default ports and no embedded credentials', () => {
  for (const value of [address, address.replace('img1', 'img9'), address.replace('https:', 'http:'),
    address.replace('.com/', '.com:443/')]) {
    assert.ok(Artwork.needsHeaders(value));
    const policy = imagePolicy(value);
    assert.equal(policy.headers.Referer, 'https://movie.douban.com/');
    assert.match(policy.headers['User-Agent'], /Mozilla/);
  }
  for (const value of ['https://img1.doubanio.com.evil.example/p', 'https://user:pass@img1.doubanio.com/p',
    'http://127.0.0.1/p', 'file:///private/p', 'https://img1.doubanio.com:1234/p', 'https://other.example/p']) {
    assert.equal(Artwork.needsHeaders(value), false); assert.equal(imagePolicy(value), null);
  }
});

async function fixture(upstream, body) {
  const records = [];
  const remote = createServer(upstream);
  await new Promise(resolve => remote.listen(0, '127.0.0.1', resolve));
  const remoteBase = 'http://127.0.0.1:' + remote.address().port;
  const proxy = createArtworkProxy((url, options, callback) => {
    records.push({ url: url.href, headers: options.headers });
    return get(remoteBase + url.pathname + url.search, options, callback);
  });
  const server = createServer((request, response) => {
    if (!proxy.handle(request, response)) { response.writeHead(404); response.end(); }
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const base = 'http://127.0.0.1:' + server.address().port;
  const request = (value = address, options) => fetch(base + '/__video_artwork?url=' + encodeURIComponent(value), options);
  try { await body({ request, records, proxy, base }); }
  finally {
    proxy.close();
    await Promise.all([server, remote].map(service => new Promise(resolve => { service.close(resolve); service.closeAllConnections(); })));
  }
}

test('public image bridge supplies required headers, coalesces concurrent downloads and caches successful bytes', async () => {
  await fixture((request, response) => {
    assert.equal(request.headers.referer, 'https://movie.douban.com/');
    assert.match(request.headers['user-agent'], /Mozilla/);
    assert.equal(request.headers.cookie, undefined);
    setTimeout(() => { response.writeHead(200, { 'Content-Type': 'image/webp' }); response.end(image); }, 15);
  }, async ({ request, records }) => {
    for (const response of await Promise.all(Array.from({ length: 8 }, () => request()))) {
      assert.equal(response.status, 200); assert.equal(response.headers.get('content-type'), 'image/webp');
      assert.deepEqual(Buffer.from(await response.arrayBuffer()), image);
    }
    assert.equal(records.length, 1);
    assert.equal((await request()).status, 200); assert.equal(records.length, 1);
  });
});

test('unsupported targets and methods never reach an upstream server', async () => {
  await fixture((_request, response) => response.end(), async ({ request, records, base }) => {
    for (const value of ['http://127.0.0.1/private', 'file:///private/secret', 'https://other.example/image']) {
      assert.equal((await request(value)).status, 400);
    }
    assert.equal((await request(address, { method: 'POST' })).status, 405);
    assert.equal((await fetch(base + '/unrelated')).status, 404);
    assert.equal(records.length, 0);
  });
});

test('redirects remain within supported image domains and terminate after a bounded number of hops', async () => {
  await fixture((request, response) => {
    if (request.url === '/good') response.writeHead(302, { Location: 'https://img9.doubanio.com/final' }).end();
    else if (request.url === '/bad') response.writeHead(302, { Location: 'http://127.0.0.1/private' }).end();
    else if (request.url === '/loop') response.writeHead(302, { Location: '/loop' }).end();
    else response.writeHead(200, { 'Content-Type': 'image/webp' }).end(image);
  }, async ({ request, records }) => {
    assert.equal((await request('https://img1.doubanio.com/good')).status, 200);
    assert.equal((await request('https://img1.doubanio.com/bad')).status, 502);
    assert.equal(records.filter(record => record.url.includes('127.0.0.1')).length, 0);
    const count = records.length;
    assert.equal((await request('https://img1.doubanio.com/loop')).status, 502);
    assert.equal(records.length - count, 4);
  });
});

test('HTTP failures, non-image bodies, empty images and oversized responses are never cached as images', async () => {
  await fixture((request, response) => {
    if (request.url === '/status') response.writeHead(418).end('blocked');
    else if (request.url === '/html') response.writeHead(200, { 'Content-Type': 'text/html' }).end('<html>');
    else if (request.url === '/huge') response.writeHead(200, { 'Content-Type': 'image/webp', 'Content-Length': 6 * 1024 * 1024 }).end();
    else response.writeHead(200, { 'Content-Type': 'image/webp' }).end();
  }, async ({ request, records }) => {
    for (const path of ['status', 'html', 'empty', 'huge']) {
      const count = records.length;
      for (let attempt = 0; attempt < 2; attempt++) assert.equal((await request('https://img1.doubanio.com/' + path)).status, 502);
      assert.equal(records.length - count, 2);
    }
  });
});

test('concurrent unique images use at most four upstream downloads and close aborts pending work', async () => {
  let active = 0, maxActive = 0;
  await fixture((_request, response) => {
    maxActive = Math.max(maxActive, ++active);
    setTimeout(() => { active--; response.writeHead(200, { 'Content-Type': 'image/webp' }).end(image); }, 15);
  }, async ({ request }) => {
    const responses = await Promise.all(Array.from({ length: 12 }, (_, i) => request('https://img1.doubanio.com/p' + i)));
    assert.ok(responses.every(response => response.status === 200)); assert.equal(maxActive, 4);
  });
  await fixture(() => {}, async ({ request, proxy, records }) => {
    const response = request();
    while (records.length === 0) await new Promise(resolve => setTimeout(resolve, 5));
    proxy.close(); assert.equal((await response).status, 502);
  });
});
