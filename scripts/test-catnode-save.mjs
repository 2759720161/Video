// Execute the page's real save methods. Native UI rendering is covered by the SDK build.
import { registerHooks, stripTypeScriptTypes } from 'node:module';
import { readFileSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { setImmediate } from 'node:timers/promises';
import assert from 'node:assert/strict';
import { test } from 'node:test';

registerHooks({
  resolve(specifier, context, next) {
    if (specifier.startsWith('@kit.')) return { url: new URL('./fixtures/catnode-kit.mjs', import.meta.url).href, shortCircuit: true };
    if (specifier.startsWith('.') && context.parentURL?.startsWith('file:')) {
      const target = new URL(specifier, context.parentURL);
      if (!target.pathname.endsWith('.ets')) target.pathname += '.ets';
      if (existsSync(fileURLToPath(target))) return { url: target.href, shortCircuit: true };
    }
    return next(specifier, context);
  },
  load(url, context, next) {
    if (url.endsWith('.ets')) return { format: 'module', source:
      stripTypeScriptTypes(readFileSync(new URL(url), 'utf8'), { mode: 'transform' }), shortCircuit: true };
    return next(url, context);
  }
});
const { CatNodeSourceConfig, CatNodeSubscriptionCodec, CatNodeSubscriptionStage: Stage } =
  await import('../entry/src/main/ets/providers/catvod/CatNodeSubscription.ets');
const { MediaSourceInstance } = await import('../entry/src/main/ets/core/media/MediaSourceInstance.ets');
const source = readFileSync(new URL('../entry/src/main/ets/pages/catvod/CatNodeSourceEditPage.ets', import.meta.url), 'utf8');
const methods = source.slice(source.indexOf('  private async save('), source.indexOf('  private stageLabel('));
assert.ok(methods.includes('private titleOptions()'));
const classSource = stripTypeScriptTypes(`class Page { ${methods} }`, { mode: 'transform' });

function fixture() {
  const calls = [], toasts = [], logs = [], saved = [];
  let gate = null, failure = null, existing = null;
  let sites = [{ key: 'first', name: '目录第一项' }, { key: 'wexaitiantang', name: '天堂采集' }];
  const runtime = {
    async shutdown() { calls.push('stop'); },
    async sites(context, address, onStage) {
      calls.push(['sites', address]);
      onStage(Stage.CHECKING); onStage(Stage.DOWNLOADING);
      if (gate) await gate;
      if (failure) throw failure;
      onStage(Stage.VERIFYING); onStage(Stage.STARTING); onStage(Stage.READING);
      return sites;
    }
  };
  const store = {
    async getById() { return existing; },
    async add(value) { calls.push('add'); saved.push(value); },
    async update(value) { calls.push('update'); saved.push(value); }
  };
  const bindings = {
    hilog: { info(...args) { logs.push(args); }, error(...args) { logs.push(args); } },
    CatNodeSubscriptionCodec, CatNodeSourceConfig, CatNodeSubscriptionStage: Stage,
    MediaSourceInstance, MediaSourceStore: store, CatNodeRuntime: runtime,
    createMediaSourceId: () => 'catnode-fixture', buildDetailToastOptions: message => ({ message }),
    extractErrorMsg: error => error.message || String(error),
    buildTitleBarOptions: () => ({}), IconStyleMode: { SMALL: 1 },
    SymbolGlyphModifier: class { constructor(resource) { this.resource = resource; } },
    $r: id => ({ id })
  };
  const Page = new Function(...Object.keys(bindings), `${classSource}; return Page;`)(...Object.values(bindings));
  const page = Object.assign(new Page(), {
    alive: true, generation: 0, saving: false, loading: false, picking: false,
    name: '', md5Url: ' https://example.com/cat/index.js.md5?key=fixture ', error: '',
    originalUrl: '', sourceId: '', config: new CatNodeSourceConfig(), stage: Stage.CHECKING,
    materialLevel: 'adaptive',
    async storeIcon() { return ''; },
    getUIContext() {
      return {
        getHostContext: () => ({ resourceManager: { getStringSync: id => id } }),
        getPromptAction: () => ({ showToast: options => toasts.push(options.message) }),
        getRouter: () => ({ back: () => calls.push('back') })
      };
    }
  });
  return { page, calls, saved, toasts, logs, fail(error) { failure = error; },
    wait(promise) { gate = promise; }, sites(value) { sites = value; }, existing(value) { existing = value; } };
}

test('toolbar save invokes the real save flow and starts the subscription request', async () => {
  const { page, calls, saved } = fixture();
  const action = page.titleOptions().content.menu.value[0].content;
  assert.ok(action.icon.resource);
  assert.equal(action.isEnabled, true);
  action.action();
  await setImmediate();
  assert.deepEqual(calls, ['stop', ['sites', 'https://example.com/cat/index.js.md5?key=fixture'], 'add', 'back']);
  assert.equal(saved[0].name, 'Cat 订阅');
  assert.equal(JSON.parse(saved[0].configJson).spiderKey, 'first');
  assert.equal(page.saving, false);
});

test('invalid address gives an immediate visible error without stopping the runtime or downloading', async () => {
  const { page, calls, toasts } = fixture();
  page.md5Url = '';
  await page.save();
  assert.deepEqual(calls, []);
  assert.match(page.error, /请填写/);
  assert.equal(toasts[0], page.error);
  assert.equal(page.saving, false);
});

test('download failures retain the form, show the error and allow another attempt', async () => {
  const { page, saved, calls, toasts, fail } = fixture();
  fail(new Error('订阅下载失败（HTTP 403）'));
  await page.save();
  assert.equal(saved.length, 0);
  assert.ok(!calls.includes('back'));
  assert.match(page.error, /HTTP 403/);
  assert.equal(toasts.at(-1), page.error);
  assert.equal(page.saving, false);
  fail(null);
  await page.save();
  assert.equal(saved.length, 1);
  assert.equal(page.error, '');
});

test('download stages update the page and repeated clicks cannot submit twice', async () => {
  const { page, calls, wait, saved } = fixture();
  let release;
  wait(new Promise(resolve => { release = resolve; }));
  const pending = page.save();
  await setImmediate();
  assert.equal(page.stage, Stage.DOWNLOADING);
  assert.equal(page.titleOptions().content.menu.value[0].content.isEnabled, false);
  await page.save();
  release(); await pending;
  assert.equal(calls.filter(value => value === 'stop').length, 1);
  assert.equal(saved.length, 1);
});

test('leaving during download prevents persistence and navigation', async () => {
  const { page, calls, saved, wait } = fixture();
  let release;
  wait(new Promise(resolve => { release = resolve; }));
  const pending = page.save();
  await setImmediate();
  page.alive = false; page.generation++;
  release(); await pending;
  assert.equal(saved.length, 0);
  assert.ok(!calls.includes('back'));
});

test('a package without video sources reports an error instead of persisting an unusable subscription', async () => {
  const { page, sites, saved } = fixture(); sites([]);
  await page.save();
  assert.equal(saved.length, 0);
  assert.match(page.error, /没有返回可用/);
});

test('editing preserves the source identity, enabled state and historical spider key', async () => {
  const f = fixture();
  f.page.sourceId = 'existing'; f.page.name = '自定义订阅';
  f.page.config.legacySpiderKey = 'legacy';
  const old = Object.assign(new MediaSourceInstance(), {
    id: 'existing', providerType: 'catnode', enabled: false, sortOrder: 7, createdAt: 123
  });
  f.existing(old);
  await f.page.save();
  assert.equal(f.saved.length, 1);
  assert.ok(f.calls.includes('update'));
  assert.deepEqual([f.saved[0].id, f.saved[0].enabled, f.saved[0].sortOrder, f.saved[0].createdAt], ['existing', false, 7, 123]);
  assert.equal(JSON.parse(f.saved[0].configJson).legacySpiderKey, 'legacy');
});

test('editing the same subscription retains a valid manual selection', async () => {
  const f = fixture();
  f.page.sourceId = 'existing';
  f.page.originalUrl = CatNodeSubscriptionCodec.normalizeUrl(f.page.md5Url);
  f.page.config.spiderKey = 'wexaitiantang';
  f.existing(Object.assign(new MediaSourceInstance(), { id: 'existing', providerType: 'catnode' }));
  await f.page.save();
  assert.equal(JSON.parse(f.saved[0].configJson).spiderKey, 'wexaitiantang');
});

test('changing the subscription URL resets the default to its first entry', async () => {
  const f = fixture();
  f.page.sourceId = 'existing'; f.page.originalUrl = 'https://old.invalid/index.js.md5';
  f.page.config.spiderKey = 'wexaitiantang';
  f.existing(Object.assign(new MediaSourceInstance(), { id: 'existing', providerType: 'catnode' }));
  await f.page.save();
  assert.equal(JSON.parse(f.saved[0].configJson).spiderKey, 'first');
});

test('provider opens the first catalog entry by default, preserves valid choices, and falls back for missing ones', async () => {
  const text = readFileSync(new URL('../entry/src/main/ets/providers/catvod/CatNodeProvider.ets', import.meta.url), 'utf8');
  const method = text.slice(text.indexOf('  static async create('), text.indexOf('  async sites('));
  const compiled = stripTypeScriptTypes(`class CatNodeProvider {
    constructor(source, client, context, config) { this.client = client; this.config = config; }
    ${method}
  }`, { mode: 'transform' });
  const Provider = new Function('CatNodeSubscriptionCodec', 'CatNodeRuntime', 'CatNodeClient',
    `${compiled}; return CatNodeProvider;`)(CatNodeSubscriptionCodec,
    { async sites() { return [{ key: 'first' }, { key: 'wexaitiantang' }]; } },
    class { constructor(context, key) { this.key = key; } });
  for (const [saved, expected] of [['', 'first'], ['wexaitiantang', 'wexaitiantang'], ['removed', 'first']]) {
    const source = new MediaSourceInstance();
    source.configJson = JSON.stringify({ md5Url: 'https://fixture.invalid/index.js.md5', spiderKey: saved });
    const provider = await Provider.create(source, {});
    assert.equal(provider.client.key, expected);
    assert.equal(provider.config.spiderKey, expected);
  }
});
