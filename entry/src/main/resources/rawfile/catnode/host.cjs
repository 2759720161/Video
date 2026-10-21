'use strict';
const fs = require('node:fs');
const path = require('node:path');
const http = require('node:http');
const crypto = require('node:crypto');

function createHost(root, notify = () => {}) {
  const profilePath = path.join(root, 'profile.json');
  const playbackPath = path.join(root, 'playback.json');
  const token = crypto.randomBytes(24).toString('hex');
  let engine = null;
  let engineServer = null;
  let stopping = false;
  const requests = new Map();
  const readJson = (file, fallback) => {
    try { return JSON.parse(fs.readFileSync(file, 'utf8')); }
    catch (error) { if (error.code === 'ENOENT') return fallback; throw error; }
  };
  const saveJson = (file, value) => {
    const temporary = file + '.pending';
    fs.writeFileSync(temporary, JSON.stringify(value), { encoding: 'utf8', mode: 0o600 });
    fs.renameSync(temporary, file);
  };
  function send(response, status, body) {
    if (response.destroyed || response.writableEnded) return;
    response.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' });
    response.end(JSON.stringify(body));
  }
  async function body(request) {
    const chunks = [];
    let size = 0;
    for await (const chunk of request) {
      size += chunk.length;
      if (size > 2 * 1024 * 1024) throw new Error('请求内容过大');
      chunks.push(chunk);
    }
    return JSON.parse(Buffer.concat(chunks).toString('utf8') || '{}');
  }
  function unsupported(action) {
    return { success: false, code: -1, message: '当前版本暂不支持此功能：' + action };
  }
  async function hostAction(message) {
    if (message.action === 'queryProfile') {
      const profile = readJson(profilePath, null);
      return profile === null ? { success: false, code: -1 } : { success: true, data: { wexfnwconfig: profile } };
    }
    if (message.action === 'saveProfile') {
      const profile = message.opt?.wexfnwconfig;
      if (profile === null || typeof profile !== 'object' || Array.isArray(profile)) throw new Error('来源配置无效');
      saveJson(profilePath, profile);
      return { success: true, code: 0 };
    }
    if (message.action === 'getPlayInfo') return readJson(playbackPath, { success: false, code: -1 });
    if (message.action === 'toast') {
      notify({ type: 'toast', opt: message.opt });
      return { success: true, code: 0 };
    }
    // A feature must not report success until the UI has actually handled it.
    if (message.action === 'openInternalWebview') {
      const id = crypto.randomBytes(12).toString('hex');
      return new Promise(resolve => {
        const timer = setTimeout(() => { requests.delete(id); resolve(unsupported(message.action)); }, 9000);
        requests.set(id, { resolve, timer });
        notify({ type: 'webview', id, opt: message.opt });
      });
    }
    return unsupported(message.action);
  }
  const server = http.createServer(async (request, response) => {
    try {
      const url = new URL(request.url, 'http://127.0.0.1');
      if (url.pathname === '/msg' && request.method === 'POST') {
        send(response, 200, await hostAction(await body(request))); return;
      }
      if (request.headers['x-video-token'] !== token) {
        send(response, 403, { message: '请求未授权' }); return;
      }
      if (url.pathname === '/runtime/playback' && request.method === 'POST') {
        saveJson(playbackPath, await body(request)); send(response, 200, { ok: true }); return;
      }
      if (url.pathname === '/runtime/host-reply' && request.method === 'POST') {
        const value = await body(request);
        const pending = requests.get(value.id);
        if (pending) { clearTimeout(pending.timer); requests.delete(value.id); pending.resolve(value.result); }
        send(response, 200, { ok: Boolean(pending) }); return;
      }
      if (url.pathname === '/runtime/stop' && request.method === 'POST') {
        send(response, 200, { ok: true });
        setImmediate(() => stop().catch(error => notify({ type: 'error', message: error.message })));
        return;
      }
      send(response, 404, { message: '接口不存在' });
    } catch (error) { send(response, 400, { message: error.message }); }
  });
  server.requestTimeout = 15000;
  server.headersTimeout = 10000;
  async function start(bundlePath) {
    fs.mkdirSync(root, { recursive: true, mode: 0o700 });
    await new Promise((resolve, reject) => {
      server.once('error', reject);
      server.listen(0, '127.0.0.1', resolve);
    });
    notify({ type: 'host-ready', hostPort: server.address().port, token });
    process.env.CATVOD_DISABLE_AUTOSTART = '1';
    process.env.NODE_ENV = 'production';
    process.env.NODE_PATH = root;
    process.env.HOST = '127.0.0.1';
    process.env.PORT = '0';
    process.env.DEV_HTTP_PORT = '0';
    globalThis.catDartServerPort = () => server.address()?.port || 0;
    globalThis.catServerFactory = handler => {
      engineServer = http.createServer(handler);
      return engineServer;
    };
    try {
      engine = require(bundlePath);
      if (typeof engine.start !== 'function' || typeof engine.stop !== 'function') throw new Error('猫源包缺少启动接口');
      await engine.start();
      const port = engineServer?.address()?.port;
      if (!Number.isInteger(port) || port <= 0) throw new Error('猫源服务没有就绪');
      const ready = { type: 'ready', port, hostPort: server.address().port, token,
        nodeVersion: process.version, wasm: typeof WebAssembly !== 'undefined' };
      notify(ready);
      return ready;
    } catch (error) {
      await stop(false).catch(() => {});
      throw error;
    }
  }
  async function stop(notifyStopped = true) {
    if (stopping) return;
    stopping = true;
    for (const pending of requests.values()) { clearTimeout(pending.timer); pending.resolve({ success: false, code: -1 }); }
    requests.clear();
    try { if (typeof engine?.stop === 'function') await engine.stop(); }
    finally {
      if (server.listening) await new Promise(resolve => { server.close(resolve); server.closeAllConnections(); });
      if (notifyStopped) notify({ type: 'engine-stopped' });
    }
  }
  return { start, stop, hostAction };
}

module.exports = { createHost };
