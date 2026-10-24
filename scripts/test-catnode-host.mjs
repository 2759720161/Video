import assert from 'node:assert/strict';
import { test } from 'node:test';
import { mkdtempSync, writeFileSync, readFileSync, rmSync, realpathSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const { createHost } = require('../entry/src/main/resources/rawfile/catnode/host.cjs');

async function fixture(body, program = null) {
  const parent = realpathSync(tmpdir());
  const root = mkdtempSync(path.join(parent, 'video-node-host-'));
  const file = path.join(root, 'fixture.cjs');
  writeFileSync(file, program ?? `
    const http = require('node:http'); let server;
    module.exports = {
      async start() {
        server = globalThis.catServerFactory((request, response) => {
          response.setHeader('Content-Type', 'application/json');
          response.end(JSON.stringify({ ok: true, path: request.url }));
        });
        await new Promise(resolve => server.listen(Number(process.env.PORT), process.env.HOST, resolve));
      },
      async stop() { if (server?.listening) await new Promise(resolve => { server.close(resolve); server.closeAllConnections(); }); }
    };`, 'utf8');
  const events = [];
  const host = createHost(root, event => events.push(event));
  try { await body({ root, file, host, events }); }
  finally {
    await host.stop();
    // Resolve and verify the exact task-owned temporary directory before removal.
    const actual = realpathSync(root);
    assert.ok(actual.startsWith(parent + path.sep + 'video-node-host-'));
    rmSync(actual, { recursive: true, force: true });
  }
}

test('host starts on discovered loopback ports and preserves the process working directory', async () => {
  await fixture(async ({ host, file, events }) => {
    const cwd = process.cwd();
    const ready = await host.start(file);
    assert.ok(ready.port > 0 && ready.hostPort > 0 && ready.port !== ready.hostPort);
    assert.match(ready.token, /^[0-9a-f]{48}$/);
    assert.equal(process.cwd(), cwd);
    assert.equal(process.env.HOST, '127.0.0.1');
    assert.equal(process.env.CATVOD_DISABLE_AUTOSTART, '1');
    assert.equal(globalThis.catDartServerPort(), ready.hostPort);
    const response = await fetch(`http://127.0.0.1:${ready.port}/health`);
    assert.deepEqual(await response.json(), { ok: true, path: '/health' });
    const deniedImage = await fetch(`http://127.0.0.1:${ready.port}/__video_artwork?url=http%3A%2F%2F127.0.0.1%2Fprivate`);
    assert.equal(deniedImage.status, 400);
    assert.equal(events[0].type, 'host-ready');
    assert.ok(events.some(event => event.type === 'ready'));
  });
});

test('profile bridge persists UTF-8 data and reloads the original host response shape', async () => {
  await fixture(async ({ host, root }) => {
    assert.equal((await host.hostAction({ action: 'queryProfile' })).success, false);
    const profile = { config: { sites: { list: ['中文片单'] } } };
    await host.hostAction({ action: 'saveProfile', opt: { wexfnwconfig: profile } });
    assert.deepEqual(JSON.parse(readFileSync(path.join(root, 'profile.json'), 'utf8')), profile);
    const reloaded = createHost(root);
    assert.deepEqual(await reloaded.hostAction({ action: 'queryProfile' }), {
      success: true, data: { wexfnwconfig: profile }
    });
    await assert.rejects(host.hostAction({ action: 'saveProfile', opt: { wexfnwconfig: [] } }), /配置无效/);
  });
});

test('control routes reject missing tokens and accept only the session token', async () => {
  await fixture(async ({ host, file }) => {
    const ready = await host.start(file);
    const url = `http://127.0.0.1:${ready.hostPort}/runtime/playback`;
    const denied = await fetch(url, { method: 'POST', body: '{}' });
    assert.equal(denied.status, 403);
    const accepted = await fetch(url, { method: 'POST', headers: { 'X-Video-Token': ready.token },
      body: JSON.stringify({ name: '作品', episode: '第1集' }) });
    assert.equal(accepted.status, 200);
    assert.deepEqual(await host.hostAction({ action: 'getPlayInfo' }), { name: '作品', episode: '第1集' });
  });
});

test('WebView requests wait for an explicit host result and unsupported actions report failure', async () => {
  await fixture(async ({ host, file, events }) => {
    const ready = await host.start(file);
    const pending = host.hostAction({ action: 'openInternalWebview', opt: { url: 'https://example.invalid/' } });
    const event = events.find(value => value.type === 'webview');
    assert.ok(event?.id);
    const result = { success: false, code: -1, message: '未支持' };
    const response = await fetch(`http://127.0.0.1:${ready.hostPort}/runtime/host-reply`, {
      method: 'POST', headers: { 'X-Video-Token': ready.token }, body: JSON.stringify({ id: event.id, result })
    });
    assert.equal(response.status, 200);
    assert.deepEqual(await pending, result);
    assert.equal((await host.hostAction({ action: 'danmuPush' })).success, false);
  });
});

test('stop closes both services and releases pending interactive requests', async () => {
  await fixture(async ({ host, file }) => {
    const ready = await host.start(file);
    const pending = host.hostAction({ action: 'openInternalWebview' });
    await host.stop();
    assert.equal((await pending).success, false);
    await assert.rejects(fetch(`http://127.0.0.1:${ready.port}/health`));
    await assert.rejects(fetch(`http://127.0.0.1:${ready.hostPort}/msg`));
  });
});

test('invalid bundle exports retain the original error and clean up the host listener', async () => {
  await fixture(async ({ host, file, events }) => {
    await assert.rejects(host.start(file), /缺少启动接口/);
    assert.ok(!events.some(event => event.type === 'ready' || event.type === 'engine-stopped'));
  }, 'module.exports = {};');
});
