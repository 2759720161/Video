// Verify the real home title selection and persistence handlers without native UI.
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';

const source = readFileSync(new URL('../entry/src/main/ets/pages/home/HomePage.ets', import.meta.url), 'utf8');
const start = source.indexOf('  private titleOptions()');
const methods = source.slice(start, source.indexOf('  @Builder', start));
const classSource = stripTypeScriptTypes(`class Page { ${methods} }`, { mode: 'transform' });
class Site { key = ''; name = ''; }

function setup(type = 'catnode') {
  const requests = [], toasts = [];
  const state = { failure: null, gate: null };
  const provider = { async selectSite(key) { requests.push(key); if (state.gate) await state.gate; if (state.failure) throw state.failure; } };
  const Page = new Function('CatNodeSite', 'buildHeroTitleBarStyle', 'buildImmersiveTitleBarStyle',
    'buildDetailToastOptions', '$r', `${classSource}; return Page;`)(
    Site, () => ({ kind: 'hero' }), () => ({ kind: 'standard' }), message => ({ message }), id => ({ id }));
  const page = Object.assign(new Page(), {
    selectedId: 'subscription-a', isActive: true, loading: false, catSelecting: false, catSelectionGeneration: 0,
    hdsMaterialLevel: 'adaptive',
    source: { id: 'subscription-a', name: '我的订阅', providerType: type, configJson: '{}' },
    catNavigation: { sourceId: 'subscription-a', selectedKey: 'a', loading: false, provider,
      sites: [{ key: 'a', name: '来源甲' }, { key: 'b', name: '来源乙' }] },
    selectedSource() { return this.source; },
    selectableSources() { return [this.source]; },
    supportsHomeSearch() { return this.isCatSource(); },
    async select(key) { this.selectedId = key; },
    CatSourceTitle() {},
    getUIContext() { return { getPromptAction: () => ({ showToast: options => toasts.push(options.message) }) }; }
  });
  return { page, requests, toasts, state };
}

test('猫源使用下拉标题区域，其他首页保留原生首页标题', () => {
  for (const type of ['catnode', 'catvod', 'emby', 'webdav', 'local']) {
    const { page } = setup(type);
    const options = page.titleOptions();
    const cat = type === 'catnode' || type === 'catvod';
    assert.equal(options.content.title.mainTitle, cat ? '' : '首页');
    assert.equal(typeof options.content.stackBuilder, cat ? 'function' : 'undefined');
    assert.equal(options.content.menu.value.length, 2);
  }
});

test('标题名称、选中键及来源列表使用内容区发布的同一选择', () => {
  const { page } = setup();
  assert.equal(page.catTitleName(), '来源甲');
  assert.equal(page.catTitleKey(), 'a');
  const updated = { ...page.catNavigation, selectedKey: 'b' };
  page.onCatNavigationChanged(updated);
  assert.equal(page.catTitleName(), '来源乙');
  assert.equal(page.catTitleKey(), 'b');
  assert.equal(page.catTitleSites(), updated.sites);
});

test('切换首页服务或离开首页后，忽略旧订阅延迟发布的目录', () => {
  const { page } = setup();
  const original = page.catNavigation;
  page.onCatNavigationChanged({ ...original, sourceId: 'another-subscription' });
  assert.equal(page.catNavigation, original);
  page.isActive = false;
  page.onCatNavigationChanged({ ...original, selectedKey: 'b' });
  assert.equal(page.catNavigation, original);
  page.selectedId = 'another-subscription';
  assert.deepEqual(page.catTitleSites(), []);
  assert.equal(page.catTitleKey(), '');
});

test('菜单选择调用订阅现有持久化方法；当前项和无效项不重复写入', async () => {
  const { page, requests } = setup();
  await page.selectCatSite('a'); await page.selectCatSite('missing');
  assert.deepEqual(requests, []);
  await page.selectCatSite('b');
  assert.deepEqual(requests, ['b']);
  assert.equal(page.catSelecting, false);
});

test('快速重复选择只提交一次，失败提示后保留原选择并允许重试', async () => {
  const { page, state, requests, toasts } = setup();
  let release;
  state.gate = new Promise(resolve => { release = resolve; });
  state.failure = new Error('来源配置保存失败');
  const pending = page.selectCatSite('b');
  await page.selectCatSite('b');
  assert.equal(page.catSelecting, true);
  assert.deepEqual(requests, ['b']);
  release(); await pending;
  assert.equal(page.catTitleKey(), 'a');
  assert.equal(toasts.at(-1), '来源配置保存失败');
  assert.equal(page.catSelecting, false);
  state.failure = null; state.gate = null;
  await page.selectCatSite('b');
  assert.deepEqual(requests, ['b', 'b']);
});

test('加载中以及已过期的来源目录不会触发持久化', async () => {
  const { page, requests } = setup();
  page.catNavigation.loading = true;
  await page.selectCatSite('b');
  assert.deepEqual(requests, []);
  page.catNavigation.loading = false; page.catNavigation.sourceId = 'outdated';
  await page.selectCatSite('b');
  assert.deepEqual(requests, []);
});

test('离开后返回同一订阅，不让旧切换结果覆盖新界面的忙碌状态', async () => {
  const { page, state, toasts } = setup();
  let release;
  state.gate = new Promise(resolve => { release = resolve; });
  state.failure = new Error('旧页面的保存失败');
  const pending = page.selectCatSite('b');
  page.catSelectionGeneration++; // The page was left and a new selection began.
  page.catSelecting = true;
  release(); await pending;
  assert.equal(page.catSelecting, true);
  assert.deepEqual(toasts, []);
});

test('只有当前猫源显示轮播时才使用大图标题栏样式', () => {
  const { page } = setup();
  assert.equal(page.titleOptions().style.kind, 'standard');
  page.catNavigation.heroVisible = true;
  assert.equal(page.titleOptions().style.kind, 'hero');
  page.catNavigation.sourceId = 'another-subscription';
  assert.equal(page.titleOptions().style.kind, 'standard');
  page.source.providerType = 'webdav';
  assert.equal(page.titleOptions().style.kind, 'standard');
});
