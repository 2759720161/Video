import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { test } from 'node:test';
import { runInNewContext } from 'node:vm';

const page = readFileSync(new URL('../entry/src/main/ets/pages/emby/EmbyDetailPage.ets', import.meta.url), 'utf8');
function method(name) {
  const start = page.indexOf(`  private ${name}(`);
  assert.ok(start >= 0, `Missing ${name}`);
  const body = page.indexOf('{', start);
  let depth = 1;
  let end = body + 1;
  for (; end < page.length && depth > 0; end++) {
    if (page[end] === '{') depth++;
    if (page[end] === '}') depth--;
  }
  assert.equal(depth, 0);
  return page.slice(start, end);
}
const enumSource = page.slice(page.indexOf('enum EmbyDetailSheetType'), page.indexOf('@Entry'));
const methods = ['openVariantMenu', 'openMetadataSheet', 'detailInfoSummary', 'isCurrentPlaybackRequest'];
const source = stripTypeScriptTypes(`${enumSource}\nclass Harness {\n${methods.map(method).join('\n')}\n}\n({ Harness, EmbyDetailSheetType })`, { mode: 'transform' });
const { Harness, EmbyDetailSheetType: types } = runInNewContext(source, {
  EmbyItem: { typeLabel: (type) => ({ Movie: '电影', Series: '剧集', Season: '季' }[type] ?? type) }
});
function harness(overrides = {}) {
  return Object.assign(new Harness(), {
    item: { name: '作品', overview: '完整简介', type: 'Movie', productionYear: 2025, container: 'mkv' },
    loading: false, showDetailSheet: false, playbackVariants: [{ id: 'auto' }, { id: '1080p' }],
    detailSheetType: types.PLAYBACK_VARIANTS
  }, overrides);
}

test('overview Toggle expands the inline preview without opening a sheet', () => {
  const overview = method('OverviewSection');
  assert.ok(overview.includes('.maxLines(this.overviewExpanded ? Infinity : 3)'));
  assert.ok(overview.includes('type: ToggleType.Button, isOn: this.overviewExpanded'));
  assert.ok(overview.indexOf('Text(item.overview)') > overview.indexOf('Toggle({'));
  assert.equal(overview.includes("'完整简介'"), false);
  assert.equal(overview.includes('.height(44)'), false);
  assert.ok(overview.includes('this.overviewExpanded = isOn'));
  assert.ok(overview.includes('new DetailToggleButtonMaterialModifier(this.materialThickness,'));
  assert.ok(overview.includes("this.overviewExpanded, 'overview'"));
  assert.equal(overview.includes('.backgroundColor('), false);
  assert.equal(overview.includes('.selectedColor('), false);
  assert.equal(overview.includes('this.openMetadataSheet('), false);
  assert.ok(overview.includes('暂无作品简介'));
  for (const attribute of ['.backgroundBlurStyle(', '.border(', '.shadow(']) {
    assert.equal(overview.includes(attribute), false);
  }
  assert.ok(page.includes('@State private overviewExpanded: boolean = false'));
});

test('information Toggle always displays full metadata without interaction', () => {
  const entry = method('DetailInfoSection');
  assert.ok(entry.includes('type: ToggleType.Button, isOn: true'));
  assert.equal(entry.includes('informationExpanded'), false);
  assert.equal(entry.includes('.onChange('), false);
  assert.ok(entry.includes('.hitTestBehavior(HitTestMode.None)'));
  assert.ok(entry.includes('.focusable(false)'));
  assert.ok(entry.includes('this.DetailInformationContent(item)'));
  assert.ok(entry.includes('new DetailToggleButtonMaterialModifier(this.materialThickness,'));
  assert.ok(entry.includes("true, 'information'"));
  assert.equal(entry.includes('.backgroundColor('), false);
  assert.equal(entry.includes('.selectedColor('), false);
  assert.equal(entry.includes('.height(44)'), false);
  assert.ok(entry.indexOf('this.DetailInformationContent(item)') > entry.indexOf('Toggle({'));
  assert.equal(entry.includes('this.openMetadataSheet('), false);
  assert.equal(entry.includes('this.DetailInfoRow('), false);
  assert.equal(entry.includes('.backgroundBlurStyle('), false);
  const control = harness();
  assert.equal(control.detailInfoSummary(control.item), '电影 · 2025 · MKV');
  assert.equal(control.detailInfoSummary({ type: 'Series', productionYear: 0, container: '' }), '剧集');
});

test('overview and information open with the correct content type', () => {
  const control = harness();
  for (const type of [types.OVERVIEW, types.INFORMATION]) {
    control.showDetailSheet = false;
    control.openMetadataSheet(type);
    assert.equal(control.showDetailSheet, true);
    assert.equal(control.detailSheetType, type);
  }
});

test('missing, loading or empty overview does not open a sheet; empty metadata remains readable', () => {
  for (const overrides of [{ item: null }, { loading: true }, { item: { overview: '' } }]) {
    const control = harness(overrides);
    control.openMetadataSheet(types.OVERVIEW);
    assert.equal(control.showDetailSheet, false);
  }
  const control = harness({ item: { overview: '' } });
  control.openMetadataSheet(types.INFORMATION);
  assert.equal(control.showDetailSheet, true);
});

test('an open sheet does not change type underneath the reader', () => {
  const control = harness({ showDetailSheet: true, detailSheetType: types.OVERVIEW });
  control.openMetadataSheet(types.INFORMATION);
  assert.equal(control.detailSheetType, types.OVERVIEW);
});

test('opening playback versions after reading metadata restores the version sheet', () => {
  const control = harness({ detailSheetType: types.INFORMATION });
  control.openVariantMenu();
  assert.equal(control.detailSheetType, types.PLAYBACK_VARIANTS);
  assert.equal(control.showDetailSheet, true);
  const singleVersion = harness({ playbackVariants: [{ id: 'auto' }] });
  singleVersion.openVariantMenu();
  assert.equal(singleVersion.showDetailSheet, false);
});

test('all sheets share reference material, transparent content and scrolling', () => {
  assert.equal((page.match(/\.bindSheet\(/g) ?? []).length, 1);
  assert.ok(page.includes('this.DetailSheet(), this.buildReferenceSheetOptions()'));
  const options = method('buildReferenceSheetOptions');
  assert.ok(options.includes('height: 410'));
  assert.ok(options.includes('style: uiMaterial.ImmersiveStyle.THICK'));
  for (const excluded of ['colorInvert', 'detents', 'preferType', 'materialThickness']) {
    assert.equal(options.includes(excluded), false);
  }
  const sheet = method('DetailSheet');
  assert.ok(sheet.includes('Scroll(this.sheetScroller)'));
  assert.ok(sheet.includes('.scrollBar(BarState.Off)'));
  assert.ok(sheet.includes('this.sheetScroller.scrollTo({ xOffset: 0, yOffset: 0 })'));
  assert.ok(sheet.includes('.backgroundColor(Color.Transparent)'));
  assert.ok(sheet.includes('top: 24, bottom: 24'));
  assert.ok(sheet.includes('this.selectPlaybackVariant(variant)'));
  assert.ok(sheet.includes('Text(this.item!.overview)'));
  assert.ok(sheet.includes('.copyOption(CopyOptions.LocalDevice)'));
  assert.equal(sheet.includes('.maxLines('), false);
});

test('playback metadata matches IDs across state proxies while rejecting stale requests', () => {
  const control = harness({ playbackGeneration: 2, detailLoadGeneration: 3 });
  control.actionItem = () => ({ id: 'movie-1' });
  assert.equal(control.isCurrentPlaybackRequest('movie-1', 2, 3), true);
  assert.equal(control.isCurrentPlaybackRequest('movie-1', 1, 3), false);
  assert.equal(control.isCurrentPlaybackRequest('movie-1', 2, 2), false);
  assert.equal(control.isCurrentPlaybackRequest('other', 2, 3), false);
  control.actionItem = () => null;
  assert.equal(control.isCurrentPlaybackRequest('movie-1', 2, 3), false);
  control.item = null;
  assert.equal(control.isCurrentPlaybackRequest('movie-1', 2, 3), false);
  assert.ok(page.includes('this.isCurrentPlaybackRequest(loadedItem.id, generation, loadGeneration)'));
  assert.equal(page.includes('this.actionItem(this.item) !== loadedItem'), false);
});

test('temporary empty material probe is removed without affecting the real detail sheet', () => {
  for (const marker of ['showMaterialTestSheet', 'EmptyMaterialTestSheet', "Button('材质测试'"]) {
    assert.equal(page.includes(marker), false);
  }
});

test('track diagnostics expose counts and selection without logging credential-bearing data', () => {
  const load = page.slice(page.indexOf('  private async loadPlaybackVariants('),
    page.indexOf('  private updateTrackOptions('));
  const selection = method('updateTrackOptions');
  for (const marker of ['load start', 'load response', 'externalAudio=', 'subtitles=', 'load discarded',
    'load empty', 'load failed', 'stage=%{public}s']) assert.ok(load.includes(marker));
  for (const marker of ['selection missing', 'audioOptions=', 'subtitleTracks=', 'subtitleOptions=',
    'selectedAudio=', 'selectedSubtitle=']) assert.ok(selection.includes(marker));
  assert.equal(load.includes('extractErrorMsg('), false);
  assert.equal(load.includes('err.message'), false);
});

test('reference sheet options use only API level branching and fixed THICK material', () => {
  const reference = stripTypeScriptTypes(`class Reference { ${method('buildReferenceSheetOptions')} } new Reference()`,
    { mode: 'transform' });
  for (const api of [23, 25, 26]) {
    const control = runInNewContext(reference, {
      deviceInfo: { sdkApiVersion: api }, Color: { Transparent: 'transparent' },
      $r: (name) => name,
      uiMaterial: { ImmersiveStyle: { THICK: 3 }, ImmersiveMaterial: class {
        constructor(options) { this.options = options; }
      } }
    });
    const options = control.buildReferenceSheetOptions();
    assert.equal(options.height, 410);
    assert.equal(options.maskColor, '#66000000');
    assert.equal(options.showClose, false);
    assert.equal(options.dragBar, false);
    if (api >= 26) {
      assert.equal(options.backgroundColor, 'transparent');
      assert.equal(options.systemMaterial.options.style, 3);
      assert.equal(Object.keys(options.systemMaterial.options).length, 1);
    } else {
      assert.equal(options.backgroundColor, 'app.color.card_background');
      assert.equal(options.systemMaterial, undefined);
    }
    control.showDetailSheet = true;
    options.onDisappear();
    assert.equal(control.showDetailSheet, false);
  }
});

test('close control reconstructs measured HdsTabs material with no point light', () => {
  const close = readFileSync(new URL('../entry/src/main/ets/components/media/DetailSheetCloseButton.ets', import.meta.url), 'utf8');
  for (const marker of ['.opacity(0)', '.onSizeChange(', '.offset({ y: this.offsetY })',
    'HdsTabs(', '.tabBar(this.CloseButton())', '.barFloatingStyle(',
    'hdsMaterial.MaterialType.IMMERSIVE', 'hdsMaterial.MaterialLevel.ADAPTIVE',
    "maskColor: '#00999999'", 'scale: 0.94']) {
    assert.ok(close.includes(marker), `Missing ${marker}`);
  }
  assert.equal(close.includes('pointLight'), false);
});

test('short modal contents stay at the top without constraining long content height', () => {
  const sheet = method('DetailSheet');
  const scroll = sheet.slice(sheet.indexOf('Scroll(this.sheetScroller)'), sheet.indexOf('.onAppear('));
  assert.match(scroll, /\}\s*\.width\('100%'\)\.height\('100%'\)\.align\(Alignment\.TopStart\)/);
  const content = scroll.slice(scroll.indexOf('Column({ space: AppSpacing.SM })'), scroll.lastIndexOf('}'));
  assert.ok(content.includes('.alignItems(HorizontalAlign.Start)'));
  assert.equal(content.includes(".height('100%')"), false, 'Long content must keep its natural scrollable height');
  assert.equal(content.includes('.justifyContent(FlexAlign.Center)'), false);
  for (const type of ['PLAYBACK_VARIANTS', 'OVERVIEW']) {
    assert.ok(content.includes(`EmbyDetailSheetType.${type}`));
  }
  assert.ok(content.includes('this.DetailInformationContent(this.item!)'));
});

test('grouped metadata retains all previous fields and does not truncate long values', () => {
  const info = method('DetailInformationContent');
  for (const label of ['媒体类型', '年份', '季数', '总集数', '集数', '时长', '格式', '评分', '题材', '制作', '分级', '首播']) {
    assert.ok(info.includes(`this.DetailInfoRow('${label}'`), `Missing ${label}`);
  }
  for (const group of ['基本信息', '评分与分类', '制作与发行']) {
    assert.ok(info.includes(`this.DetailInfoGroupHeading('${group}')`));
  }
  const row = method('DetailInfoRow');
  assert.equal(row.includes('.maxLines('), false);
  assert.equal(row.includes('TextOverflow.Ellipsis'), false);
  assert.ok(row.includes("$r('sys.color.font_primary')"));
});

test('modal hides its title and close button without reserving header space', () => {
  const sheet = method('DetailSheet');
  assert.ok(sheet.includes('HdsNavigation()'));
  assert.ok(sheet.includes('.hideTitleBar(true)'));
  assert.equal(sheet.includes('.titleBar('), false);
  assert.equal(sheet.includes('.titleMode('), false);
  assert.equal(page.includes('DetailSheetHeader'), false);
  assert.equal(page.includes('DetailSheetCloseButton'), false);
  assert.equal(page.includes('detailSheetTitle'), false);
  assert.ok(sheet.includes('top: 24'));
  assert.ok(page.includes('showClose: false'));
  assert.ok(page.includes('onDisappear: () => { this.showDetailSheet = false }'));
  assert.ok(sheet.includes('.backgroundColor(Color.Transparent)'));
  assert.ok(sheet.includes('.edgeEffect(EdgeEffect.Spring)'));
  assert.equal(sheet.includes('this.hdsMaterialLevel'), false);
  // Keep the sheet's content inset separate from the full page's status-bar spacer.
  assert.equal(sheet.includes('getTopSpacerHeight('), false);
  assert.equal(sheet.includes('.expandSafeArea('), false);
});
