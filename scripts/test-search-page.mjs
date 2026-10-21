import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { runInNewContext } from 'node:vm';
import { test } from 'node:test';

const page = readFileSync(new URL('../entry/src/main/ets/pages/home/SearchPage.ets', import.meta.url), 'utf8');
const logic = page.slice(page.indexOf('  private cancelSearch()'), page.indexOf('  private titleOptions()'));
const Harness = runInNewContext(stripTypeScriptTypes(`class Harness { ${logic} } Harness`, { mode: 'transform' }),
  { setTimeout, clearTimeout });
function harness(provider) {
  return Object.assign(new Harness(), { provider, generation: 0, timer: -1, alive: true,
    query: '', items: [], error: '', searching: false, history: [], saveHistory: async () => {} });
}

test('首页搜索入口跳转并注册独立搜索页', () => {
  const home = readFileSync(new URL('../entry/src/main/ets/pages/home/HomePage.ets', import.meta.url), 'utf8');
  const routes = JSON.parse(readFileSync(new URL('../entry/src/main/resources/base/profile/main_pages.json', import.meta.url), 'utf8'));
  assert.ok(home.includes("url: 'pages/home/SearchPage'"));
  assert.ok(home.includes('params: { sourceId: this.selectedId }'));
  assert.ok(routes.src.includes('pages/home/SearchPage'));
});

test('搜索框在导航标题区域启用材质，短内容保持顶部对齐', () => {
  assert.ok(page.includes('options.content.bottomBuilder ='));
  assert.ok(page.includes('this.SearchField()'));
  assert.ok(page.includes('new SearchTitleMaterialModifier(this.materialThickness)'));
  assert.ok(page.includes('@StorageLink(PREFS_KEY_IMMERSIVE_MATERIAL_STYLE)'));
  assert.ok(page.includes('.align(Alignment.TopStart)'));
  assert.ok(page.includes('.alignItems(HorizontalAlign.Start)'));
  assert.equal(page.includes('.margin({ top: 64 })'), false);
  assert.ok(page.includes('wrap: FlexWrap.Wrap'));
  assert.equal(page.includes('Grid()'), false);
  assert.ok(page.includes('.scrollable(ScrollDirection.Vertical)'));
});

test('空白关键词清除结果且不发请求', () => {
  const control = harness({ searchRaw() { throw new Error('Should not search'); } });
  control.items = [1];
  control.search('   ', true);
  assert.equal(control.items.length, 0);
  assert.equal(control.searching, false);
});

test('搜索海报沿用首页共享转场并传递相同图片', () => {
  assert.ok(page.includes('enableSharedTransition: true'));
  assert.ok(page.includes('onCardClick: (transitionId: string)'));
  assert.match(page, /buildEmbyDetailRouteParams\(this\.sourceId, item, transitionId,\s*this\.provider\?\.imageUrlFor\(item, 360\) \?\? ''\)/);
});

test('搜索结果手机三列，大屏依次增加至四、五、六列', () => {
  const resolver = readFileSync(new URL('../entry/src/main/ets/ui/theme/ResponsiveSizeClass.ets', import.meta.url), 'utf8');
  const source = resolver.replace(/export /g, '');
  const columns = runInNewContext(stripTypeScriptTypes(source + '\nResponsiveSizeClassResolver',
    { mode: 'transform' }));
  assert.deepEqual([360, 599, 600, 839, 840, 1199, 1200].map(width => columns.columns(width) + 1),
    [3, 3, 4, 4, 5, 5, 6]);
  assert.equal(page.match(/ResponsiveSizeClassResolver\.columns\(this\.screenWidth\) \+ 1/g)?.length, 2);
});

test('新查询和离开页面后不接受旧响应', async () => {
  let resolve;
  const control = harness({ searchRaw: () => new Promise(done => { resolve = done; }) });
  const pending = control.runSearch('old', 0);
  control.cancelSearch();
  control.items = ['new'];
  resolve(['old']);
  await pending;
  assert.deepEqual(control.items, ['new']);
  const second = control.runSearch('new', 1);
  control.alive = false;
  resolve(['late']);
  await second;
  assert.deepEqual(control.items, ['new']);
});

test('有效结果展示，失败提供重试状态', async () => {
  const control = harness({ searchRaw: async () => ['result'] });
  await control.runSearch('query', 0);
  assert.deepEqual(control.items, ['result']);
  control.provider = { searchRaw: async () => { throw new Error('Network'); } };
  await control.runSearch('query', 0);
  assert.equal(control.error, '搜索失败，请重试');
  assert.equal(control.searching, false);
});

test('搜索历史去重置顶，最多二十条，支持单条删除和清空', () => {
  const control = harness(null);
  for (let index = 0; index < 25; index++) control.rememberSearch('词' + index);
  assert.equal(control.history.length, 20);
  control.rememberSearch('  词10  ');
  assert.equal(control.history[0], '词10');
  assert.equal(control.history.filter(word => word === '词10').length, 1);
  control.removeHistory('词10');
  assert.equal(control.history.includes('词10'), false);
  control.clearHistory();
  assert.equal(control.history.length, 0);
  assert.ok(page.includes("getString('emby_search_history', '[]')"));
  assert.ok(page.includes("setStringStrict('emby_search_history', JSON.stringify(this.history))"));
});
