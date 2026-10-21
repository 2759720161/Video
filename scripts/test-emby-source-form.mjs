// Tests the real address parser, source persistence and page business methods.
// Platform network, secure storage and navigation are replaced with in-memory doubles.
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { registerHooks, stripTypeScriptTypes } from 'node:module';
import { readFileSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const preferences = new Map();
const credentials = new Map();
globalThis.__embyFormPreferences = preferences;
globalThis.__embyFormCredentials = credentials;
globalThis.AppStorage = { setOrCreate() {} };
registerHooks({
  resolve(specifier, context, nextResolve) {
    if (specifier.startsWith('.') && context.parentURL?.startsWith('file:')) {
      const url = new URL(specifier, context.parentURL);
      if (!url.pathname.endsWith('.ets')) url.pathname += '.ets';
      if (existsSync(fileURLToPath(url))) return { url: url.href, shortCircuit: true };
    }
    return nextResolve(specifier, context);
  },
  load(url, context, nextLoad) {
    const stubs = {
      '/store/PreferencesStore.ets': `export class PreferencesStore {
        static getInstance() { return {
          async getStringStrict(key, fallback) { return globalThis.__embyFormPreferences.get(key) ?? fallback; },
          async setStringStrict(key, value) { globalThis.__embyFormPreferences.set(key, value); }
        }; }
      }`,
      '/services/security/SecureCredentialStore.ets': `export class SecureCredentialStore {
        static getInstance() { return {
          async get(id) { return globalThis.__embyFormCredentials.get(id) ?? null; },
          async set(value) { globalThis.__embyFormCredentials.set(value.sourceId, value.copy()); },
          async delete(id) { globalThis.__embyFormCredentials.delete(id); }
        }; }
      }`,
      '/store/PlaybackHistoryStore.ets': 'export class PlaybackHistoryStore {}'
    };
    for (const [suffix, source] of Object.entries(stubs)) {
      if (url.endsWith(suffix)) return { format: 'module', source, shortCircuit: true };
    }
    if (url.endsWith('.ets')) {
      return { format: 'module', source: stripTypeScriptTypes(readFileSync(new URL(url), 'utf8'),
        { mode: 'transform' }), shortCircuit: true };
    }
    return nextLoad(url, context);
  }
});

const { EmbyConnectionAddress: Address } = await import('../entry/src/main/ets/providers/emby/EmbyConnectionAddress.ets');
const { EmbyServerConfig } = await import('../entry/src/main/ets/providers/emby/EmbyModels.ets');
const { EmbySourceConfigCodec } = await import('../entry/src/main/ets/providers/emby/EmbySourceConfig.ets');
const { MediaSourceStore } = await import('../entry/src/main/ets/store/MediaSourceStore.ets');

function config() {
  return Object.assign(new EmbyServerConfig(), { baseUrl: 'https://example.com/emby', serverId: 'server-1',
    serverName: '远程服务器', userId: 'user-1', userName: 'alice', accessToken: 'test-only-token', deviceId: 'test-device' });
}

test('完整地址拆分协议、主机、端口及反向代理路径', () => {
  const value = Address.parse(' HTTPS://Example.COM:08920/video/emby/ ');
  assert.deepEqual([value.protocol, value.host, value.port, value.path], ['https', 'example.com', '8920', '/video/emby']);
});
test('无协议地址沿用已选协议，IP 与路径保留', () => {
  const value = Address.parse('192.168.1.10:8096/emby', 'https');
  assert.equal(Address.build(value.protocol, value.host, value.port, value.path), 'https://192.168.1.10:8096/emby');
});
test('空端口不擅自插入 8096；路径补齐前导斜杠', () => {
  assert.equal(Address.build('https', ' EXAMPLE.com ', '', 'proxy/emby/'), 'https://example.com/proxy/emby');
  assert.equal(Address.build('http', 'nas.local', '', ''), 'http://nas.local');
});
test('括号 IPv6 支持端口和路径', () => {
  const value = Address.parse('http://[2001:db8::1]:8096/emby');
  assert.equal(Address.build(value.protocol, value.host, value.port, value.path), 'http://[2001:db8::1]:8096/emby');
});
test('端口校验上下界及非法值', () => {
  for (const port of ['0', '65536', 'abc', '1.5', '-1']) {
    assert.throws(() => Address.build('http', 'nas.local', port, ''));
  }
  for (const port of ['1', '65535']) assert.ok(Address.build('http', 'nas.local', port, '').endsWith(':' + port));
});
test('拒绝非 HTTP 协议、URL 凭据、查询参数、片段和空白地址', () => {
  for (const value of ['', 'ftp://nas.local', 'https://u:p@nas.local', 'nas.local?api_key=secret',
    'nas.local/emby#test', 'not a host', 'http://']) assert.throws(() => Address.parse(value));
});
test('分开的主机输入不允许混入完整 URL', () => {
  assert.throws(() => Address.build('http', 'http://nas.local:8096', '', ''));
});
test('自定义名称保存；密码与令牌不混入普通配置', async () => {
  preferences.clear(); credentials.clear();
  const id = await MediaSourceStore.upsertEmby(config(), '', ' 家庭主服 ');
  const source = await MediaSourceStore.getById(id);
  assert.equal(source.name, '家庭主服');
  assert.equal(JSON.parse(source.configJson).serverName, '远程服务器');
  assert.ok(!source.configJson.includes('test-only-token'));
  assert.equal(credentials.get(id).values.accessToken, 'test-only-token');
});
test('重新登录未指定名称时保留已有自定义名称', async () => {
  const id = await MediaSourceStore.upsertEmby(config(), '', '家庭主服');
  await MediaSourceStore.upsertEmby(config(), id);
  assert.equal((await MediaSourceStore.getById(id)).name, '家庭主服');
});
test('名称留空使用服务端名称，再为空使用 Emby', async () => {
  const value = config();
  const id = await MediaSourceStore.upsertEmby(value, '', ' ');
  assert.equal((await MediaSourceStore.getById(id)).name, '远程服务器');
  value.serverName = '';
  await MediaSourceStore.upsertEmby(value, id, '');
  assert.equal((await MediaSourceStore.getById(id)).name, 'Emby');
});

// ArkUI's declarative builders cannot run in Node. Extract only the actual
// business methods, leaving their bodies unchanged, and inject platform doubles.
const pageSource = readFileSync(new URL('../entry/src/main/ets/pages/sources/EmbySourceEditPage.ets', import.meta.url), 'utf8');
const methods = pageSource.slice(pageSource.indexOf('  private invalidateVerification()'), pageSource.lastIndexOf('\n}'));
const pageClass = stripTypeScriptTypes(`class Page { ${methods} }`, { mode: 'transform' });
function createPage() {
  let logins = 0, checks = 0, writes = 0, backs = 0, fail = false, gate = null;
  class Client {
    static normalizeBaseUrl(url) { return url.endsWith('/emby') ? url : url + '/emby'; }
    static async login() { logins++; if (gate) await gate; if (fail) throw new Error('账号或密码错误'); return config(); }
    async getLibraries() { checks++; if (fail) throw new Error('服务器不可用'); return []; }
  }
  const store = { async upsertEmby(value, id, name) { writes++; assert.equal(name, '家庭主服'); return 'saved'; } };
  const Page = new Function('EmbyClient', 'EmbyConnectionAddress', 'EmbySourceConfigCodec', 'MediaSourceStore',
    'SecureCredentialStore', 'promptAction', `${pageClass}; return Page;`)(Client, Address, EmbySourceConfigCodec,
    store, {}, { showToast() {} });
  const page = Object.assign(new Page(), { host: 'example.com', protocol: 'https', port: '', path: '/emby',
    userName: 'alice', password: 'secret', displayName: '家庭主服', busy: false, loading: false,
    saving: false, sourceId: '', loadGeneration: 0, verifiedConfig: null, connectedConfig: null,
    connectionMessage: '', connectionFailed: false,
    getUIContext() { return { getRouter() { return { async back() { backs++; } }; } }; } });
  return { page, counts: () => ({ logins, checks, writes, backs }), fail: () => { fail = true; },
    waitFor: promise => { gate = promise; } };
}
test('测试连接不保存也不返回；随后保存复用已验证登录', async () => {
  const { page, counts } = createPage();
  await page.submit(false);
  assert.deepEqual(counts(), { logins: 1, checks: 0, writes: 0, backs: 0 });
  assert.match(page.connectionMessage, /连接成功/);
  await page.submit(true);
  assert.deepEqual(counts(), { logins: 1, checks: 0, writes: 1, backs: 1 });
  assert.equal(page.password, '');
});
test('重复测试连接重新检查网络，不重复登录', async () => {
  const { page, counts, fail } = createPage();
  await page.submit(false);
  fail();
  await page.submit(false);
  assert.equal(counts().checks, 1);
  assert.equal(page.connectionFailed, true);
  assert.equal(page.verifiedConfig, null);
});
test('修改账号输入使验证缓存失效，保存重新验证', async () => {
  const { page, counts } = createPage();
  await page.submit(false);
  page.password = 'changed'; page.invalidateVerification();
  await page.submit(true);
  assert.equal(counts().logins, 2);
});
test('编辑名称时复用已保存令牌，无需重新输入密码', async () => {
  const { page, counts } = createPage();
  page.connectedConfig = config(); page.password = ''; page.sourceId = 'existing';
  await page.submit(true);
  assert.deepEqual(counts(), { logins: 0, checks: 1, writes: 1, backs: 1 });
});
test('更换地址或账号不能沿用旧令牌，密码提示随之调整', async () => {
  const { page, counts } = createPage();
  page.connectedConfig = config(); page.password = '';
  assert.equal(page.passwordPlaceholder(), '留空保留现有登录');
  page.userName = 'bob';
  assert.equal(page.passwordPlaceholder(), '无密码可留空');
  await page.submit(true);
  assert.equal(counts().logins, 1); assert.equal(counts().checks, 0);
});
test('认证失败不写入配置、不返回，保留表单供重试', async () => {
  const { page, counts, fail } = createPage(); fail();
  await page.submit(true);
  assert.equal(counts().writes, 0); assert.equal(counts().backs, 0);
  assert.equal(page.password, 'secret'); assert.equal(page.busy, false);
  assert.equal(page.connectionMessage, '账号或密码错误');
});
test('用户名缺失在发起网络请求前拦截', async () => {
  const { page, counts } = createPage(); page.userName = ' ';
  await page.submit(true);
  assert.equal(counts().logins, 0); assert.equal(page.connectionMessage, '请输入用户名');
});
test('粘贴完整 URL 自动拆分，而普通主机保留已有独立参数', () => {
  const { page } = createPage();
  page.host = 'http://192.168.1.10:8096/proxy/emby/'; page.recognizeAddress(true);
  assert.deepEqual([page.protocol, page.host, page.port, page.path], ['http', '192.168.1.10', '8096', '/proxy/emby']);
  page.host = 'nas.local'; page.recognizeAddress(true);
  assert.equal(page.port, '8096'); assert.equal(page.path, '/proxy/emby');
});
test('忙碌期间拦截重复提交', async () => {
  const { page, counts, waitFor } = createPage();
  let release; waitFor(new Promise(resolve => { release = resolve; }));
  const pending = page.submit(true);
  await page.submit(true);
  release(); await pending;
  assert.equal(counts().writes, 1); assert.equal(counts().logins, 1);
});
test('连接未完成时离开页面，不保存配置或触发返回', async () => {
  const { page, counts, waitFor } = createPage();
  let release; waitFor(new Promise(resolve => { release = resolve; }));
  const pending = page.submit(true);
  ++page.loadGeneration; // Mirrors the page's aboutToDisappear generation guard.
  release(); await pending;
  assert.equal(counts().writes, 0); assert.equal(counts().backs, 0);
});
