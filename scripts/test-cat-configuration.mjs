import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { test } from 'node:test';

const read = path => readFileSync(new URL('../entry/src/main/ets/' + path, import.meta.url), 'utf8');
const compile = source => stripTypeScriptTypes(source.replace(/^import .*\r?\n/gm, ''), { mode: 'transform' });
const url = { URL: class extends URL { static parseURL(value) { return new this(value); } } };
const Policy = new Function('url', compile(read('providers/catvod/CatNodeConfiguration.ets').replace('export class', 'class')) +
  ';return CatNodeConfiguration;')(url);
const Feedback = new Function(compile(read('providers/catvod/CatNodeConfigurationScript.ets').replace('export class', 'class')) +
  ';return CatNodeConfigurationScript;')();
const pageSource = read('pages/catvod/CatNodeConfigurationPage.ets');
const methods = compile(`class Page { ${pageSource.slice(pageSource.indexOf('  aboutToAppear()'), pageSource.indexOf('  build()'))} }`);
const defer = () => { let resolve; const promise = new Promise(done => { resolve = done; }); return { promise, resolve }; };

test('configuration routing recognizes real tool IDs without treating unrelated videos as settings', () => {
  assert.equal(Policy.isItem('catnode:baseset:config-center', 'douban'), true);
  assert.equal(Policy.isItem('config-center', 'baseset'), true);
  for (const [id, key] of [['config-center', 'douban'], ['catnode:douban:config-center', 'baseset'],
    ['catnode:baseset:other', 'baseset'], ['catnode:%XX:config-center', 'baseset'], ['catnode:baseset:config-center:extra', 'baseset']]) {
    assert.equal(Policy.isItem(id, key), false);
  }
});

test('configuration URL always uses the actual engine loopback port and cannot target a file or another server', () => {
  for (const port of [1, 43009, 65535]) assert.equal(Policy.pageUrl(`http://127.0.0.1:${port}`), `http://127.0.0.1:${port}/website`);
  for (const value of ['file:///data/config', 'http://remote.invalid:3000', 'https://127.0.0.1:3000',
    'http://127.0.0.1:0', 'http://user:pass@127.0.0.1:3000', 'http://127.0.0.1:3000/path',
    'http://127.0.0.1:3000?token=1', 'http://127.0.0.1:3000#fragment']) assert.throws(() => Policy.pageUrl(value));
  const entry = Policy.pageUrl('http://127.0.0.1:43009');
  assert.equal(Policy.isExport(entry + '/api/db', entry), true);
  assert.equal(Policy.isExport('http://127.0.0.1:43010/website/api/db', entry), false);
  assert.equal(Policy.isExport('https://remote.invalid/website/api/db', entry), false);
  assert.equal(Policy.exportUrl(entry), entry + '/api/db');
  for (const value of [entry, entry + '/api/status', 'https://account.example.invalid/login']) assert.equal(Policy.allowsNavigation(value, entry), true);
  for (const value of ['file:///data/config', 'javascript:alert(1)', 'data:text/html,x', 'http://127.0.0.1:43010/website',
    'http://remote.invalid', 'https://user:pass@remote.invalid']) assert.equal(Policy.allowsNavigation(value, entry), false);
  assert.equal(Policy.isMutation(entry + '/api/db', 'POST', entry), true);
  assert.equal(Policy.isMutation(entry + '/api/credentials', 'put', entry), true);
  assert.equal(Policy.isMutation(entry + '/api/status', 'GET', entry), false);
  assert.equal(Policy.isMutation('https://external.invalid/website/api/db', 'POST', entry), false);
});

function setup() {
  const state = { providerGate: null, endpointGate: null, exportGate: null, pickerGate: null, available: true,
    data: '{"setting":"配置"}', files: ['file://chosen/config.json'], writeShort: false };
  const calls = { script: [], backward: 0, saves: 0, opens: 0, writes: [], closes: 0, toasts: [], requests: [], sourceUpdates: [], cacheClears: 0 };
  class Provider { async configurationUrl() { return state.endpointGate ? state.endpointGate.promise : 'http://127.0.0.1:43009/website'; } }
  const Controller = class { accessBackward() { return true; } backward() { calls.backward++; }
    async runJavaScript(script) { calls.script.push(script); } };
  const dependencies = { CatNodeProvider: Provider, CatNodeConfiguration: Policy, CatNodeConfigurationScript: Feedback,
    CatPlaybackPreparationCache: { clear() { calls.cacheClears++; } },
    ProviderRegistry: { async get() { return state.providerGate ? state.providerGate.promise : state.available ? new Provider() : null; } },
    webview: { WebviewController: Controller },
    CatNodeRuntime: { invalidatePlaybackMetadata() { calls.cacheClears++; },
      async request(url) { calls.requests.push(url); return state.exportGate ? state.exportGate.promise : state.data; } },
    picker: { DocumentSaveOptions: class {}, DocumentViewPicker: class { async save() {
      calls.saves++; return state.pickerGate ? state.pickerGate.promise : state.files;
    } } },
    fileIo: { OpenMode: { WRITE_ONLY: 1, TRUNC: 2 }, openSync() { calls.opens++; return { fd: 5 }; },
      writeSync(fd, data) { calls.writes.push(data); return Buffer.byteLength(data) - (state.writeShort ? 1 : 0); },
      closeSync() { calls.closes++; } }, buffer: { byteLength: Buffer.byteLength },
    MediaSourceStore: { async getById(id) { return { id, providerType: 'catnode', configJson: 'latest' }; },
      async update(value) { calls.sourceUpdates.push(value); } },
    buildDetailToastOptions: message => ({ message }), $r: id => ({ id }) };
  const Page = new Function(...Object.keys(dependencies), methods + ';return Page;')(...Object.values(dependencies));
  const page = Object.assign(new Page(), { alive: true, generation: 1, documentId: 0, entryUrl: '', loading: true, error: '', exporting: false,
    sourceId: 'source', attached: false, configurationDirty: false, controller: new Controller(), getUIContext: () => ({
      getHostContext: () => ({ resourceManager: { getStringSync: id => id } }),
      getPromptAction: () => ({ showToast: options => calls.toasts.push(options.message) }) }) });
  return { page, state, calls, Provider };
}

test('the configuration page resolves the current engine and rejects stale or disposed loads', async () => {
  const { page } = setup(); await page.load();
  assert.equal(page.entryUrl, 'http://127.0.0.1:43009/website'); assert.equal(page.loading, true);
  for (const dispose of [false, true]) {
    const f = setup(); f.state.endpointGate = defer(); const pending = f.page.load(); await Promise.resolve();
    if (dispose) f.page.aboutToDisappear(); else f.page.generation++;
    f.state.endpointGate.resolve('http://127.0.0.1:1234/website'); await pending;
    assert.equal(f.page.entryUrl, '');
  }
  const f = setup(); f.state.available = false; await f.page.load(); assert.equal(f.page.loading, false); assert.ok(f.page.error);
});

test('page errors survive end callbacks and old callbacks cannot modify a reloaded or closed page', async () => {
  const { page, calls } = setup(); await page.load(); const address = page.entryUrl;
  const generation = page.generation;
  page.attached = true; page.failed(address, generation, 'HTTP 500'); page.end(address, generation);
  assert.equal(page.error, 'HTTP 500'); assert.equal(page.loading, false); assert.equal(calls.script.length, 0);
  page.begin(address, generation); page.end(address, generation); await Promise.resolve();
  assert.equal(page.error, ''); assert.equal(calls.script.length, 1);
  await page.load(); page.failed(address, generation, 'old, same URL'); assert.equal(page.error, '');
  page.entryUrl = 'http://127.0.0.1:1234/website'; page.failed(address, page.generation, 'old'); assert.equal(page.error, '');
  page.loading = false; page.aboutToDisappear(); page.begin(page.entryUrl, page.generation); assert.equal(page.loading, false);
});

test('export validates JSON, uses the chosen destination and writes UTF-8 bytes once', async () => {
  const { page, calls } = setup(); await page.load();
  await page.exportConfiguration(page.entryUrl + '/api/db');
  assert.equal(calls.saves, 1); assert.equal(calls.opens, 1); assert.equal(calls.closes, 1);
  assert.deepEqual(calls.writes, ['{"setting":"配置"}']); assert.equal(page.exporting, false);
  await page.exportConfiguration('https://remote.invalid/website/api/db'); assert.equal(calls.saves, 1);
  const f = setup(); await f.page.load(); f.state.data = '<html>error</html>';
  await f.page.exportConfiguration(f.page.entryUrl + '/api/db'); assert.equal(f.calls.saves, 0); assert.equal(f.calls.opens, 0);
});

test('cancelled, duplicate, short or abandoned exports do not write unexpected files or leak handles', async () => {
  const f = setup(); await f.page.load(); f.state.exportGate = defer();
  const pending = f.page.exportConfiguration(f.page.entryUrl + '/api/db');
  await f.page.exportConfiguration(f.page.entryUrl + '/api/db'); assert.equal(f.calls.requests.length, 1);
  f.page.aboutToDisappear(); f.state.exportGate.resolve('{}'); await pending; assert.equal(f.calls.saves, 0);
  const cancelled = setup(); await cancelled.page.load(); cancelled.state.files = [];
  await cancelled.page.exportConfiguration(cancelled.page.entryUrl + '/api/db'); assert.equal(cancelled.calls.opens, 0);
  const short = setup(); await short.page.load(); short.state.writeShort = true;
  await short.page.exportConfiguration(short.page.entryUrl + '/api/db'); assert.equal(short.calls.closes, 1);
  assert.match(short.calls.toasts[0], /export_failed/);
  const left = setup(); await left.page.load(); left.state.pickerGate = defer();
  const picking = left.page.exportConfiguration(left.page.entryUrl + '/api/db'); await Promise.resolve();
  left.page.aboutToDisappear(); left.state.pickerGate.resolve(['file://chosen/config.json']); await picking;
  assert.equal(left.calls.opens, 0);
});

test('leaving after configuration edits refreshes the latest source once, while read-only visits do not invalidate caches', async () => {
  const f = setup(); f.page.configurationDirty = true; f.page.aboutToDisappear(); f.page.aboutToDisappear();
  await Promise.resolve(); await Promise.resolve();
  assert.deepEqual(f.calls.sourceUpdates, [{ id: 'source', providerType: 'catnode', configJson: 'latest' }]);
  assert.equal(f.calls.cacheClears, 1);
  const readOnly = setup(); readOnly.page.aboutToDisappear(); await Promise.resolve();
  assert.equal(readOnly.calls.sourceUpdates.length, 0);
  assert.equal(readOnly.calls.cacheClears, 0);
});
