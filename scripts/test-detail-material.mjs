// Exercise the real material adapter against missing/disabled native APIs without a device.
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { registerHooks, stripTypeScriptTypes } from 'node:module';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';
import { runInNewContext } from 'node:vm';

const runtime = {
  version: 26, available: true, supported: true, state: 1, failCapability: false,
  nativeReads: 0, versionChecks: 0, created: [], logs: [], level: 0, failLevel: false
};
const settings = new Map();
globalThis.AppStorage = { get: (key) => settings.get(key), setOrCreate: (key, value) => settings.set(key, value) };
globalThis.Color = { Transparent: 'transparent' };
const nativeMaterial = {
  MaterialState: { DISABLE: 2 },
  MaterialLevel: { EXQUISITE: 0, GENTLE: 1, SMOOTH: 2 },
  getGlobalMaterialLevel() { if (runtime.failLevel) throw new Error('Level unavailable'); return runtime.level; },
  ImmersiveStyle: { ULTRA_THIN: 0, THIN: 1, REGULAR: 2, THICK: 3, ULTRA_THICK: 4 },
  isImmersiveMaterialSupported() {
    if (runtime.failCapability) throw new Error('Native capability query unavailable');
    return runtime.supported;
  },
  getMaterialInfo() { return { state: runtime.state }; },
  ImmersiveMaterial: class {
    constructor(options) { this.options = options; runtime.created.push(this); }
  }
};
globalThis.__detailMaterialTest = {
  uiMaterial: new Proxy(nativeMaterial, {
    get(target, key) {
      runtime.nativeReads++;
      assert.ok(runtime.version >= 26 && runtime.available, 'Accessed unavailable API 26 material');
      return target[key];
    }
  }),
  deviceInfo: {
    get sdkApiVersion() { return runtime.version; },
    apiAvailable(version) {
      runtime.versionChecks++;
      assert.ok(runtime.version >= 26, 'Called the new version API on an old device');
      assert.equal(version, '26.0.0');
      return runtime.available;
    }
  }
};
registerHooks({
  resolve(specifier, context, nextResolve) {
    if (specifier === './Logger' && context.parentURL?.endsWith('/DetailMaterial.ets')) {
      return { url: 'test:material-logger', shortCircuit: true };
    }
    if (specifier === '@kit.ArkUI' || specifier === '@kit.BasicServicesKit') {
      return { url: 'test:detail-native', shortCircuit: true };
    }
    if (specifier === '@kit.UIDesignKit') return { url: 'test:hds-native', shortCircuit: true };
    if (specifier.startsWith('.') && context.parentURL?.startsWith('file:')) {
      const url = new URL(specifier, context.parentURL);
      if (!url.pathname.endsWith('.ets')) url.pathname += '.ets';
      if (existsSync(fileURLToPath(url))) return { url: url.href, shortCircuit: true };
    }
    return nextResolve(specifier, context);
  },
  load(url, context, nextLoad) {
    if (url === 'test:material-logger') {
      globalThis.__materialLogs = runtime.logs;
      return { format: 'module', shortCircuit: true, source:
        'export class Logger { info(...args) { globalThis.__materialLogs.push(args); } warn(...args) { this.info(...args); } } export const extractErrorMsg = (err) => err.message;' };
    }
    if (url === 'test:detail-native') {
      return { format: 'module', shortCircuit: true,
        source: 'export const { uiMaterial, deviceInfo } = globalThis.__detailMaterialTest; export const promptAction = {}, LengthMetrics = { vp: (value) => value };' };
    }
    if (url === 'test:hds-native') {
      return { format: 'module', shortCircuit: true, source:
        'export const HdsNavigationTitleBarOptions = {}, TitleBarStyleOptions = {}, ScrollEffectType = {}, SystemMaterialParams = {}, hdsMaterial = {};' };
    }
    if (url.endsWith('.ets')) {
      return { format: 'module', shortCircuit: true,
        source: stripTypeScriptTypes(readFileSync(new URL(url), 'utf8'), { mode: 'transform' }) };
    }
    return nextLoad(url, context);
  }
});
const material = await import('../entry/src/main/ets/utils/DetailMaterial.ets');
const preferences = await import('../entry/src/main/ets/utils/HdsPageStyle.ets');

test('play capsule leaves borders and shadows to the native material', () => {
  const stage = readFileSync(new URL('../entry/src/main/ets/components/media/ImmersiveDetailStage.ets', import.meta.url), 'utf8');
  const start = stage.indexOf('Toggle({ type: ToggleType.Button, isOn: $$this.primaryActionSelected })');
  const end = stage.indexOf('if (this.actionDescription.length > 0)', start);
  assert.ok(start >= 0 && end > start);
  const capsule = stage.slice(start, end);
  assert.equal(capsule.includes('.border('), false);
  assert.equal(capsule.includes('.shadow('), false);
  assert.ok(capsule.includes('new DetailToggleButtonMaterialModifier(this.materialThickness)'));
  assert.ok(capsule.includes('.borderRadius(999)'));
  assert.ok(capsule.includes('.onChange((isOn: boolean) => this.handlePrimaryActionChange(isOn))'));
  assert.equal(capsule.includes('.onClick('), false, 'Do not launch twice through click and change');
  assert.ok(capsule.includes('.enabled(this.actionEnabled && !this.busy)'));
  assert.ok(stage.includes('@StorageLink(PREFS_KEY_IMMERSIVE_MATERIAL_STYLE) materialThickness'));
});

function createPlayActionHarness() {
  const stage = readFileSync(new URL('../entry/src/main/ets/components/media/ImmersiveDetailStage.ets', import.meta.url), 'utf8');
  const start = stage.indexOf('  private handlePrimaryActionChange(');
  const end = stage.indexOf('\n  @Builder', start);
  assert.ok(start >= 0 && end > start);
  const resetClass = stage.slice(stage.indexOf('class DetailPlayActionReset extends FrameCallback'));
  const source = stripTypeScriptTypes(resetClass + '\nclass Harness {\n' + stage.slice(start, end) + '\n}\nHarness', { mode: 'transform' });
  const Harness = runInNewContext(source, { FrameCallback: class {} });
  const control = new Harness();
  const frames = [];
  control.primaryActionSelected = true; // Native two-way binding updates before onChange.
  control.primaryActionResetPending = false;
  control.actionAreaAlive = true;
  control.actionEnabled = true;
  control.busy = false;
  control.getUIContext = () => ({ postFrameCallback: (frame) => frames.push(frame) });
  return { control, frames };
}

test('play toggle launches once and resets after rendering, including repeated playback', () => {
  const { control, frames } = createPlayActionHarness();
  let launches = 0;
  control.onPrimaryAction = () => launches++;
  control.handlePrimaryActionChange(true);
  control.handlePrimaryActionChange(true);
  assert.equal(launches, 1);
  assert.equal(frames.length, 1);
  assert.equal(control.primaryActionSelected, true);
  frames.shift().onIdle(2000000);
  assert.equal(control.primaryActionSelected, false);
  assert.equal(control.primaryActionResetPending, false);
  control.handlePrimaryActionChange(false);
  assert.equal(launches, 1, 'Reset must not start playback');
  control.primaryActionSelected = true;
  control.handlePrimaryActionChange(true);
  assert.equal(launches, 2);
  frames.shift().onIdle(2000000);
  assert.equal(control.primaryActionSelected, false);
});

test('busy, disabled, missing and throwing actions still leave the toggle resettable', () => {
  for (const overrides of [{ busy: true }, { actionEnabled: false }, { onPrimaryAction: undefined }]) {
    const { control, frames } = createPlayActionHarness();
    let launches = 0;
    control.onPrimaryAction = () => launches++;
    Object.assign(control, overrides);
    control.handlePrimaryActionChange(true);
    assert.equal(launches, 0);
    frames.shift().onIdle(2000000);
    assert.equal(control.primaryActionSelected, false);
    assert.equal(control.primaryActionResetPending, false);
  }
  const { control, frames } = createPlayActionHarness();
  control.onPrimaryAction = () => { throw new Error('Launch failed'); };
  assert.throws(() => control.handlePrimaryActionChange(true), /Launch failed/);
  frames.shift().onIdle(2000000);
  assert.equal(control.primaryActionSelected, false);
});

test('pending reset does not update a destroyed detail component', () => {
  const { control, frames } = createPlayActionHarness();
  control.handlePrimaryActionChange(true);
  control.actionAreaAlive = false;
  frames.shift().onIdle(2000000);
  assert.equal(control.primaryActionSelected, true);
});

function reset(overrides = {}) {
  runtime.logs.length = 0;
  settings.clear();
  Object.assign(runtime, { version: 26, available: true, supported: true, state: 1,
    failCapability: false, nativeReads: 0, versionChecks: 0, created: [], level: 0, failLevel: false }, overrides);
}

test('sheet diagnostics expose thickness, device tier, configured material and fallback without changing behavior', () => {
  reset({ level: 2 });
  assert.ok(material.buildDetailSheetOptions('thin', {}).systemMaterial);
  assert.ok(runtime.logs.some(([message, value]) => message.includes('device level') && value === 2));
  assert.ok(runtime.logs.some(([message, value]) => message.includes('requested thickness') && value === 'thin'));
  assert.ok(runtime.logs.some(([message]) => message.includes('result=native_configured')));
  reset({ supported: false });
  assert.equal(material.buildDetailSheetOptions('thick', {}).systemMaterial, undefined);
  assert.ok(runtime.logs.some(([message]) => message.includes('result=fallback')));
  reset({ failLevel: true });
  assert.ok(material.buildDetailSheetOptions('regular', {}).systemMaterial);
  assert.ok(runtime.logs.some(([message]) => message.includes('level query failed')));
  reset({ failCapability: true });
  assert.equal(material.buildDetailSheetOptions('regular', {}).systemMaterial, undefined);
  assert.ok(runtime.logs.some(([message]) => message.includes('capability query failed')));
});
function expectOrdinaryControls() {
  assert.equal(material.buildDetailSheetMaterial(), undefined);
  assert.deepEqual(material.buildDetailSheetOptions('thin', { backgroundColor: '#FFFFFF' }),
    { backgroundColor: '#FFFFFF' });
  assert.deepEqual(material.buildDetailToastOptions('无法播放该媒体'), { message: '无法播放该媒体' });
  // Old SelectAttribute has neither systemMaterial nor menuSystemMaterial.
  new material.DetailSelectMaterialModifier('regular').applyNormalAttribute({});
  new material.DetailToggleButtonMaterialModifier('regular').applyNormalAttribute({});
  new material.DetailTitleButtonMaterialModifier('regular').applyNormalAttribute({});
  assert.equal(runtime.created.length, 0);
}

test('search title material follows thickness and avoids unsupported native APIs', () => {
  reset();
  let applied;
  let background;
  new material.SearchTitleMaterialModifier('thin').applyNormalAttribute({
    backgroundColor: (value) => { background = value; },
    systemMaterial: (value) => { applied = value.options; }
  });
  assert.equal(background, 'transparent');
  assert.equal(applied.style, 1);
  assert.equal(applied.colorInvert, true);
  assert.equal(applied.interactive, true);
  reset({ version: 23 });
  new material.SearchTitleMaterialModifier('thin').applyNormalAttribute({});
  assert.equal(runtime.nativeReads, 0);
  reset({ supported: false });
  new material.SearchTitleMaterialModifier('regular').applyNormalAttribute({});
  assert.equal(runtime.created.length, 0);
});

test('overview expansion and collapse reapply transparent native material through one owner', () => {
  reset();
  const applied = [];
  const instance = {
    backgroundColor: (value) => applied.push(['background', value]),
    selectedColor: (value) => applied.push(['selected', value]),
    systemMaterial: (value) => applied.push(['material', value.options.style])
  };
  for (const expanded of [false, true, false, true, false]) {
    new material.DetailToggleButtonMaterialModifier('regular', expanded, 'overview', 'fallback', 'selected')
      .applyNormalAttribute(instance);
  }
  assert.equal(applied.length, 15);
  for (let i = 0; i < applied.length; i += 3) {
    assert.deepEqual(applied.slice(i, i + 3), [['background', 'transparent'], ['selected', 'transparent'], ['material', 2]]);
  }
  assert.equal(runtime.logs.filter(([message]) => message.includes('toggle result=native_configured')).length, 5);
  reset({ version: 23 });
  applied.length = 0;
  new material.DetailToggleButtonMaterialModifier('regular', false, 'overview', 'fallback', 'selected')
    .applyNormalAttribute(instance);
  assert.deepEqual(applied, [['background', 'fallback'], ['selected', 'selected']]);
  assert.equal(runtime.nativeReads, 0);
});

test('API 23–25 never access new material or version APIs', () => {
  for (const version of [23, 24, 25]) {
    reset({ version });
    expectOrdinaryControls();
    assert.equal(runtime.nativeReads, 0);
    assert.equal(runtime.versionChecks, 0);
  }
});
test('unavailable platform version keeps controls usable', () => {
  reset({ available: false });
  expectOrdinaryControls();
  assert.equal(runtime.nativeReads, 0);
});
test('unsupported hardware and native query failure use ordinary controls', () => {
  reset({ supported: false });
  expectOrdinaryControls();
  reset({ failCapability: true });
  expectOrdinaryControls();
});
test('application-wide disable cannot be overridden by detail components', () => {
  reset({ state: 2 });
  expectOrdinaryControls();
});
test('API 26 enables sheet and toast material in both default and enabled application modes', () => {
  for (const state of [0, 1]) {
    reset({ state });
    const sheet = material.buildDetailSheetMaterial();
    assert.equal(sheet.options.style, nativeMaterial.ImmersiveStyle.REGULAR);
    const toast = material.buildDetailToastOptions('无法播放该媒体');
    assert.equal(toast.message, '无法播放该媒体');
    assert.equal(toast.systemMaterial.options.style, nativeMaterial.ImmersiveStyle.REGULAR);
  }
});

test('all five settings values reach sheet and toast without stale or hardcoded thickness', () => {
  reset();
  const choices = [preferences.IMMERSIVE_STYLE_ULTRA_THIN, preferences.IMMERSIVE_STYLE_THIN,
    preferences.IMMERSIVE_STYLE_REGULAR, preferences.IMMERSIVE_STYLE_THICK, preferences.IMMERSIVE_STYLE_ULTRA_THICK];
  const labels = ['超薄', '薄', '常规', '厚', '超厚'];
  for (const [index, choice] of choices.entries()) {
    assert.equal(preferences.getImmersiveMaterialStyleLabel(choice), labels[index]);
    AppStorage.setOrCreate(preferences.PREFS_KEY_IMMERSIVE_MATERIAL_STYLE, choice);
    const sheet = material.buildDetailSheetMaterial();
    const toast = material.buildDetailToastOptions('已更新');
    assert.equal(sheet.options.style, index);
    assert.equal(toast.systemMaterial.options.style, index);
    assert.equal(sheet.options.colorInvert, index < 2);
    assert.equal(toast.systemMaterial.options.colorInvert, index < 2);
    const liveSheet = material.buildDetailSheetOptions(choice, { backgroundColor: '#FFFFFF' });
    assert.equal(liveSheet.systemMaterial.options.style, index);
    assert.equal(liveSheet.backgroundColor, Color.Transparent);
  }
  AppStorage.setOrCreate(preferences.PREFS_KEY_IMMERSIVE_MATERIAL_STYLE, 'invalid');
  assert.equal(material.buildDetailSheetMaterial().options.style, nativeMaterial.ImmersiveStyle.REGULAR);
});

test('Select enables both native backplates and follows all five thickness choices', () => {
  const choices = ['ultraThin', 'thin', 'regular', 'thick', 'ultraThick'];
  for (const state of [0, 1]) {
    for (const [index, thickness] of choices.entries()) {
      reset({ state });
      const applied = {};
      new material.DetailSelectMaterialModifier(thickness).applyNormalAttribute({
        backgroundColor(value) { applied.background = value; },
        selectedOptionBgColor(value) { applied.selectedOptionBackground = value; },
        dividerStyle(value) { applied.divider = value; },
        menuBackgroundColor(value) { applied.menuBackground = value; },
        systemMaterial(value) { applied.trigger = value; },
        menuSystemMaterial(value) { applied.menu = value; }
      });
      assert.equal(applied.background, Color.Transparent);
      assert.equal(applied.selectedOptionBackground, Color.Transparent);
      assert.equal(applied.divider.strokeWidth, 0);
      assert.equal(applied.divider.color, Color.Transparent);
      assert.equal(applied.menuBackground, Color.Transparent);
      assert.equal(applied.trigger.options.style, index);
      assert.equal(applied.menu.options.style, index);
      assert.equal(applied.trigger.options.colorInvert, index < 2);
      assert.equal(applied.menu.options.colorInvert, index < 2);
      assert.equal(applied.trigger.options.interactive, true);
      assert.deepEqual(applied.trigger.options.lightEffect, {});
      assert.notEqual(applied.trigger, applied.menu);
    }
  }
});

test('play toggle supports DEFAULT/ENABLE modes, live thickness, readable thin materials and native interaction', () => {
  for (const state of [0, 1]) {
    for (const [index, thickness] of ['ultraThin', 'thin', 'regular', 'thick', 'ultraThick'].entries()) {
      reset({ state });
      const applied = {};
      new material.DetailToggleButtonMaterialModifier(thickness).applyNormalAttribute({
        backgroundColor(value) { applied.background = value; },
        selectedColor(value) { applied.selectedBackground = value; },
        systemMaterial(value) { applied.material = value; }
      });
      assert.equal(applied.background, Color.Transparent);
      assert.equal(applied.selectedBackground, Color.Transparent);
      assert.equal(applied.material.options.style, index);
      assert.equal(applied.material.options.colorInvert, index < 2);
      assert.equal(applied.material.options.interactive, true);
      assert.deepEqual(applied.material.options.lightEffect, {});
    }
  }
});

test('native title close button follows every thickness setting and updates an existing control', () => {
  for (const state of [0, 1]) {
    reset({ state });
    const applied = {};
    const control = {
      backgroundColor(value) { applied.background = value; },
      systemMaterial(value) { applied.material = value; }
    };
    for (const [index, thickness] of ['ultraThin', 'thin', 'regular', 'thick', 'ultraThick', 'thin'].entries()) {
      const style = index === 5 ? 1 : index;
      new material.DetailTitleButtonMaterialModifier(thickness).applyNormalAttribute(control);
      assert.equal(applied.background, Color.Transparent);
      assert.equal(applied.material.options.style, style);
      assert.equal(applied.material.options.colorInvert, style < 2);
      assert.equal(applied.material.options.interactive, true);
      assert.deepEqual(applied.material.options.lightEffect, {});
      const sheet = material.buildDetailSheetOptions(thickness, { backgroundColor: '#FFFFFF' });
      assert.equal(sheet.systemMaterial.options.style, applied.material.options.style);
    }
  }
});

test('sheet stays transparent and retains selected material when expanded', () => {
  reset();
  for (const height of [360, 720, 1000]) {
    const options = material.buildDetailSheetOptions(preferences.IMMERSIVE_STYLE_THIN,
      { height, backgroundColor: '#FFFFFF', showClose: false });
    assert.equal(options.height, height);
    assert.equal(options.showClose, false);
    assert.equal(options.backgroundColor, Color.Transparent);
    assert.equal(options.systemMaterial.options.style, nativeMaterial.ImmersiveStyle.THIN);
  }
});
