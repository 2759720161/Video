'use strict';
const http = require('node:http');
const https = require('node:https');
const PROXY_PATH = '/__video_artwork';
const MAX_BYTES = 5 * 1024 * 1024;
const MAX_CACHE_BYTES = 8 * 1024 * 1024;
const USER_AGENT = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

function imagePolicy(value) {
  try {
    const url = new URL(value);
    if (!['http:', 'https:'].includes(url.protocol) || url.username || url.password || url.port ||
        !/^img\d*\.doubanio\.com$/i.test(url.hostname)) return null;
    return { url, headers: { Referer: 'https://movie.douban.com/', 'User-Agent': USER_AGENT,
      Accept: 'image/webp,image/jpeg,image/png,image/*;q=0.8' } };
  } catch { return null; }
}

/** Public-image bridge for image domains needing headers. No account headers, URLs or bodies are logged. */
function createArtworkProxy(get = (url, options, callback) => (url.protocol === 'https:' ? https : http).get(url, options, callback)) {
  const cache = new Map(), pending = new Map(), requests = new Set();
  const lanes = Array.from({ length: 4 }, () => Promise.resolve());
  let cursor = 0, cachedBytes = 0, closed = false;
  function download(value, redirects = 0) {
    if (closed) return Promise.reject(new Error('closed'));
    const policy = imagePolicy(value);
    if (!policy) return Promise.reject(new Error('unsupported image domain'));
    return new Promise((resolve, reject) => {
      let request, timer;
      const finish = () => { clearTimeout(timer); requests.delete(request); };
      request = get(policy.url, { headers: policy.headers }, response => {
        const status = response.statusCode;
        if ([301, 302, 303, 307, 308].includes(status)) {
          response.destroy(); finish();
          let target;
          try { if (response.headers.location) target = new URL(response.headers.location, policy.url).href; } catch {}
          if (redirects >= 3 || !target || !imagePolicy(target)) { reject(new Error('invalid image redirect')); return; }
          download(target, redirects + 1).then(resolve, reject); return;
        }
        const type = String(response.headers['content-type'] || '').split(';')[0].trim();
        if (status !== 200 || !/^image\/[a-z0-9.+-]+$/i.test(type) ||
            Number(response.headers['content-length'] || 0) > MAX_BYTES) {
          response.destroy(); finish(); reject(new Error('image response rejected')); return;
        }
        const chunks = []; let size = 0;
        response.on('data', chunk => {
          size += chunk.length;
          if (size > MAX_BYTES) { request.destroy(new Error('image too large')); return; }
          chunks.push(chunk);
        });
        response.on('error', error => { finish(); reject(error); });
        response.on('aborted', () => { finish(); reject(new Error('image response aborted')); });
        response.on('end', () => {
          finish();
          if (!size || size > MAX_BYTES) { reject(new Error('invalid image size')); return; }
          resolve({ data: Buffer.concat(chunks), type, expires: Date.now() + 3600000 });
        });
      });
      requests.add(request);
      timer = setTimeout(() => request.destroy(new Error('image timeout')), 12000);
      request.on('error', error => { finish(); reject(error); });
    });
  }
  function load(value) {
    const hit = cache.get(value);
    if (hit?.expires > Date.now()) return Promise.resolve(hit);
    if (hit) { cache.delete(value); cachedBytes -= hit.data.length; }
    if (pending.has(value)) return pending.get(value);
    if (pending.size >= 128) return Promise.reject(new Error('image queue full'));
    const lane = cursor++ % lanes.length;
    const task = lanes[lane].then(() => download(value)).then(image => {
      if (!closed) {
        cache.set(value, image); cachedBytes += image.data.length;
        while (cache.size > 32 || cachedBytes > MAX_CACHE_BYTES) {
          const key = cache.keys().next().value;
          cachedBytes -= cache.get(key).data.length; cache.delete(key);
        }
      }
      return image;
    }).finally(() => pending.delete(value));
    pending.set(value, task); lanes[lane] = task.then(() => {}, () => {});
    return task;
  }
  function handle(request, response) {
    let url;
    try { url = new URL(request.url, 'http://127.0.0.1'); } catch { return false; }
    if (url.pathname !== PROXY_PATH) return false;
    const fail = status => {
      if (!response.destroyed && !response.writableEnded) { response.writeHead(status, { 'Cache-Control': 'no-store' }); response.end(); }
    };
    if (request.method !== 'GET') { fail(405); return true; }
    const value = url.searchParams.get('url') || '';
    if (value.length > 16384 || !imagePolicy(value)) { fail(400); return true; }
    load(value).then(image => {
      if (response.destroyed || response.writableEnded) return;
      response.writeHead(200, { 'Content-Type': image.type, 'Content-Length': image.data.length,
        'Cache-Control': 'private, max-age=3600', 'X-Content-Type-Options': 'nosniff' });
      response.end(image.data);
    }, () => fail(502));
    return true;
  }
  function close() {
    closed = true; cache.clear(); cachedBytes = 0;
    for (const request of requests) request.destroy(new Error('image service stopped'));
    requests.clear();
  }
  return { handle, close };
}
module.exports = { createArtworkProxy, imagePolicy };
