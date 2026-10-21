// Tests the real HomePage reload methods; no ArkUI renderer or device filesystem is invoked.
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';

const read = path => readFileSync(new URL('../entry/src/main/ets/' + path, import.meta.url), 'utf8');
const pageSource = read('pages/home/HomePage.ets');

test('首页服务与搜索使用原生 HDS 图标，服务菜单保留沉浸材质', () => {
  assert.equal(pageSource.includes('.bindSheet('), false);
  assert.equal(pageSource.includes('showSwitcher'), false);
  assert.ok(pageSource.includes('if (this.isCatSource() && options.content !== undefined)'));
  assert.ok(pageSource.includes("options.content.title = { mainTitle: '' }"));
  assert.ok(pageSource.includes('options.content.stackBuilder = (): void => this.CatSourceTitle()'));
  assert.equal(pageSource.includes('HomeSourceSelect'), false);
  assert.ok(pageSource.includes('.bindMenu(this.showSourceMenu, this.sourceMenuItems(), this.sourceMenuOptions())'));
  assert.ok(pageSource.includes('buildDetailSheetMaterial(this.materialThickness)'));
  assert.ok(pageSource.includes('@StorageLink(PREFS_KEY_IMMERSIVE_MATERIAL_STYLE)'));
  assert.ok(pageSource.includes('source.id !== this.selectedId'));
  assert.ok(pageSource.includes('void this.select(source.id)'));
  assert.ok(pageSource.includes('HomeSourcePolicy.canSelect(source)'));
  assert.equal(pageSource.includes("$r('sys.symbol.gearshape')"), false);
  assert.equal(pageSource.includes('.arrowModifier('), false);
  assert.equal(pageSource.includes('.clip(true)'), false);
  assert.ok(pageSource.includes('action: () => this.handleSearchAction()'));
  assert.ok(pageSource.includes('menu: { value:'));
  assert.ok(pageSource.includes("icon: $r('sys.symbol.externaldrive')"));
  assert.ok(pageSource.includes('options.systemMaterial = material'));
  assert.ok(pageSource.includes('onDisappear: () => { this.showSourceMenu = false }'));
  assert.ok(pageSource.includes('.position({ x: Math.max(0, this.screenWidth - 112), y: this.topSafeHeight + 6 })'));
  assert.equal(pageSource.includes('.align(Alignment.TopEnd).margin('), false);
});
const policySource = stripTypeScriptTypes(read('services/library/HomeSourcePolicy.ets').replace(/^import .*\r?\n/gm, '')
  .replace('export class', 'class'), { mode: 'transform' });
const Policy = new Function(`${policySource}; return HomeSourcePolicy;`)();
const methods = pageSource.slice(pageSource.indexOf('  private async reloadSources()'), pageSource.indexOf('  build()'));
const pageClass = stripTypeScriptTypes(`class Page { ${methods} }`, { mode: 'transform' });
const local = () => ({ id: 'local', providerType: 'local', enabled: true });
function setup() {
  const state = { sources: [local()], folder: '', failed: false, gate: null, reads: 0, lookups: 0 };
  const Page = new Function('MediaSourceStore', 'ActiveSourceStore', 'HomeSourcePolicy', 'UserDownloadFolder',
    `${pageClass}; return Page;`)(
    { async getAllStrict() { state.reads++; if (state.gate) await state.gate;
      if (state.failed) throw new Error('storage unavailable'); return state.sources; } },
    { async restore() { return 'local'; } }, Policy,
    { getExistingOwnFolder() { state.lookups++; return state.folder; } });
  return { state, page: Object.assign(new Page(), { generation: 0, loading: true, hasServices: false,
    sources: [], error: '', selectedId: 'local' }) };
}
test('首次读取只有默认本地条目时显示无服务状态', async () => {
  const { state, page } = setup(); await page.reloadSources();
  assert.equal(page.loading, false); assert.equal(page.hasServices, false); assert.equal(page.error, '');
  assert.equal(state.lookups, 1);
});
test('服务页添加服务后重新读取，收起无服务提示且不改变当前选择', async () => {
  const { state, page } = setup(); await page.reloadSources();
  state.sources.push({ id: 'server', providerType: 'emby', enabled: true });
  await page.reloadSources();
  assert.equal(page.hasServices, true); assert.equal(page.selectedId, 'local');
});
test('创建或删除本地专属文件夹后重新读取正确更新提示', async () => {
  const { state, page } = setup(); state.folder = '/existing-folder';
  await page.reloadSources(); assert.equal(page.hasServices, true);
  state.folder = ''; await page.reloadSources(); assert.equal(page.hasServices, false);
});
test('配置读取失败呈现错误而不是伪装为未添加服务', async () => {
  const { state, page } = setup(); state.failed = true;
  await page.reloadSources();
  assert.equal(page.error, '无法读取服务，请重试'); assert.equal(state.lookups, 0);
  assert.ok(pageSource.indexOf('this.error.length > 0)') < pageSource.indexOf('!this.hasServices)'));
});
test('离开页面后忽略未完成读取，不发布过期状态', async () => {
  const { state, page } = setup(); let release;
  state.gate = new Promise(resolve => { release = resolve; });
  const pending = page.reloadSources(); ++page.generation;
  release(); await pending;
  assert.equal(page.loading, true); assert.equal(state.lookups, 0);
});
test('无服务界面居中避让安全区，按钮切换到服务 Tab', () => {
  const builder = pageSource.slice(pageSource.indexOf('  private NoServicesState()'), pageSource.indexOf('  private HomeState('));
  assert.match(builder, /justifyContent\(FlexAlign.Center\)/);
  assert.match(builder, /getTopSpacerHeight\(this.topSafeHeight\)/);
  assert.match(builder, /getBottomSpacerHeight\(this.bottomSafeHeight\)/);
  assert.match(builder, /Button\('前往服务页面'\)/);
  assert.match(builder, /this.currentTab = 1/);
  assert.match(pageSource, /LOCAL_MEDIA_LIBRARY_VERSION_KEY\) @Watch\('reloadSources'\)/);
});
