// Execute the supplied engine in a fresh, filesystem-restricted desktop process.
// This verifies the package protocol, not the HarmonyOS native runtime.
import { fork } from 'node:child_process';
import { mkdtempSync, mkdirSync, copyFileSync, writeFileSync, realpathSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';

const parent = realpathSync(tmpdir());
const root = mkdtempSync(path.join(parent, 'video-node-probe-'));
const program = path.join(root, 'program');
mkdirSync(program);
const source = fileURLToPath(new URL('../entry/src/main/resources/rawfile/catnode/', import.meta.url));
for (const file of ['host.cjs', 'bootstrap.cjs', 'artwork.cjs']) copyFileSync(path.join(source, file), path.join(program, file));
const bundleArgument = process.argv.indexOf('--bundle');
const fixture = bundleArgument >= 0 ? process.argv[bundleArgument + 1] :
  fileURLToPath(new URL('../native/node/vendor/cat-source-fixture/index.cjs', import.meta.url));
const bundleBytes = readFileSync(fixture);
const md5 = createHash('md5').update(bundleBytes).digest('hex');
const manifest = { file: `index.${md5}.cjs`, md5, sha256: createHash('sha256').update(bundleBytes).digest('hex') };
writeFileSync(path.join(program, manifest.file), bundleBytes);
writeFileSync(path.join(root, 'bundle.json'), JSON.stringify(manifest), 'utf8');
const launcher = path.join(root, 'launcher.cjs');
writeFileSync(launcher, `globalThis.videoNativeNotify = json => process.send(JSON.parse(json));
require(${JSON.stringify(path.join(program, 'bootstrap.cjs'))});\n`, 'utf8');
const child = fork(launcher, [root], {
  execArgv: ['--jitless', '--permission', '--allow-fs-read=' + root, '--allow-fs-write=' + root, '--allow-worker'],
  env: { SystemRoot: process.env.SystemRoot, TEMP: root, TMP: root, NODE_ENV: 'production', UV_USE_IO_URING: '0' },
  stdio: ['ignore', 'ignore', 'ignore', 'ipc']
});
let closed = false;
const exit = new Promise(resolve => child.once('exit', () => { closed = true; resolve(); }));
try {
  const ready = await new Promise((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error('完整包桌面启动超时')), 60000);
    child.on('message', message => {
      if (message.type === 'ready') { clearTimeout(timeout); resolve(message); }
      if (message.type === 'error') { clearTimeout(timeout); reject(new Error(message.message)); }
    });
    child.once('exit', code => { clearTimeout(timeout); reject(new Error('完整包提前退出：' + code)); });
  });
  const base = `http://127.0.0.1:${ready.port}`;
  const health = await (await fetch(base + '/health')).json();
  assert.equal(health.ok, true);
  const config = await (await fetch(base + '/config')).json();
  const sites = config.video?.sites ?? [];
  assert.ok(sites.length > 0);
  const target = sites.find(site => /^\/spider\/[^/]+\/\d+$/.test(site.api) && Number(site.type) >= 0 && Number(site.type) < 10);
  assert.ok(target);
  let spiderRoute = target.api;
  const post = async (route, body) => {
    const response = await fetch(base + spiderRoute + route, {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body),
      signal: AbortSignal.timeout(30000)
    });
    const value = await response.json();
    if (!response.ok) {
      if (route === '/init' && response.status === 404 &&
          value.message === 'Route POST:' + spiderRoute + route + ' not found' &&
          (!value.code || value.code === 'FST_ERR_NOT_FOUND') && /\/\d+$/.test(spiderRoute)) {
        spiderRoute = spiderRoute.replace(/\/\d+$/, '');
        return post(route, body);
      }
      throw new Error('来源接口 HTTP ' + response.status);
    }
    return typeof value === 'string' ? JSON.parse(value) : value;
  };
  await post('/init', { ext: target.ext ?? '' });
  const home = await post('/home', { filter: true });
  assert.ok(Array.isArray(home.class) && home.class.length > 0);
  let browse = null;
  if (process.argv.includes('--browse')) {
    try {
      const listing = await post('/category', { id: String(home.class[0].type_id), page: 1, pg: 1, filter: true, extend: {}, filters: {} });
      assert.ok(Array.isArray(listing.list) && listing.list.length > 0, '来源分类没有返回作品');
      const selected = listing.list[0];
      const details = await post('/detail', { id: [String(selected.vod_id)] });
      const detail = details.list?.find(video => String(video.vod_id) === String(selected.vod_id));
      assert.ok(detail, '详情没有保留请求的作品身份');
      const roads = String(detail.vod_play_from || '').split('$$$');
      const episodes = String(detail.vod_play_url || '').split('$$$')[0].split('#');
      const episode = episodes[0].slice(episodes[0].indexOf('$') + 1);
      assert.ok(roads[0] && episode, '详情没有播放线路');
      const playback = await post('/play', { flag: roads[0], id: episode, flags: [roads[0]] });
      browse = { categoryVideoCount: listing.list.length, matchingDetail: true,
        playbackUrlReturned: typeof playback.url === 'string' && playback.url.length > 0, parse: playback.parse };
    } catch (error) { browse = { upstreamOrProtocolError: error.message }; }
  }
  console.log(JSON.stringify({ scope: 'desktop-permission-restricted', nodeVersion: ready.nodeVersion,
    wasm: ready.wasm, health, videoSourceCount: sites.length,
    defaultSource: { key: target.key, name: target.name, api: target.api },
    defaultSourceCategoryCount: home.class.length, browse }, null, 2));
  await fetch(`http://127.0.0.1:${ready.hostPort}/runtime/stop`, {
    method: 'POST', headers: { 'X-Video-Token': ready.token }, body: '{}'
  });
} finally {
  if (!closed) child.kill();
  await exit;
  const actual = realpathSync(root);
  assert.ok(actual.startsWith(parent + path.sep + 'video-node-probe-'));
  rmSync(actual, { recursive: true, force: true });
}
