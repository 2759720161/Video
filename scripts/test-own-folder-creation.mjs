// Node 24+: exercises real folder service and Services menu methods with mocked system APIs.
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { registerHooks, stripTypeScriptTypes } from 'node:module';
import { existsSync, readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const uriRoot = 'file://docs/storage/Users/currentUser/Download/com.yingxia.hmos';
const root = '/storage/Users/currentUser/Download/com.yingxia.hmos';
const state = { directories: new Set(), files: new Set(), saves: 0, changes: 0,
  mode: 'create', gate: null, denied: false };
globalThis.__ownFolderTest = state;
globalThis.AppStorage = { set() { state.changes++; return true; }, setOrCreate() { state.changes++; } };

registerHooks({
  resolve(specifier, context, nextResolve) {
    if (specifier.startsWith('@kit.')) return { url: 'test:' + specifier, shortCircuit: true };
    if (specifier.startsWith('.') && context.parentURL?.startsWith('file:')) {
      const url = new URL(specifier, context.parentURL);
      if (!url.pathname.endsWith('.ets')) url.pathname += '.ets';
      if (existsSync(fileURLToPath(url))) return { url: url.href, shortCircuit: true };
    }
    return nextResolve(specifier, context);
  },
  load(url, context, nextLoad) {
    if (url === 'test:@kit.AbilityKit') return { format: 'module', shortCircuit: true, source: `
      export const common = {};
      export const bundleManager = { BundleFlag: { GET_BUNDLE_INFO_WITH_APPLICATION: 1, GET_BUNDLE_INFO_WITH_METADATA: 2 },
        getBundleInfoForSelfSync() { return { name: 'com.yingxia.hmos' }; } };
    ` };
    if (url === 'test:@kit.CoreFileKit') return { format: 'module', shortCircuit: true, source: `
      const state = globalThis.__ownFolderTest;
      const root = ${JSON.stringify(root)};
      export const fileUri = { FileUri: class { constructor(uri) { this.path = uri.replace('file://docs', ''); } } };
      export const fileIo = {
        accessSync(path) { if (state.denied) throw new Error('permission denied');
          return state.directories.has(path) || state.files.has(path); },
        statSync(path) { return { isDirectory: () => state.directories.has(path), isFile: () => state.files.has(path) }; },
        listFileSync() { return []; },
        unlinkSync(path) { state.files.delete(path); },
        mkdirSync() { throw new Error('Unexpected direct directory creation'); }
      };
      export const picker = { DocumentSaveOptions: class {}, DocumentPickerMode: { DOWNLOAD: 1 },
        DocumentViewPicker: class { async save(options) {
          state.saves++;
          if (options.pickerMode !== 1) throw new Error('Expected DOWNLOAD mode');
          if (state.gate) await state.gate;
          if (state.mode === 'cancel') return [];
          if (state.mode === 'fail') throw new Error('save failed');
          if (state.mode === 'invalid') return ['file://docs/unexpected/.placeholder'];
          if (state.mode !== 'no_directory') {
            state.directories.add(root); state.files.add(root + '/.placeholder');
          }
          return [${JSON.stringify(uriRoot + '/.placeholder')}];
        } }
      };
    ` };
    if (url.startsWith('test:@kit.')) return { format: 'module', source: 'export const BusinessError = class extends Error {};', shortCircuit: true };
    if (url.endsWith('/utils/Logger.ets')) return { format: 'module', source: 'export class Logger { info() {} warn() {} error() {} }', shortCircuit: true };
    if (url.endsWith('/store/PreferencesStore.ets')) return { format: 'module', source: 'export class PreferencesStore {}', shortCircuit: true };
    if (url.endsWith('.ets')) return { format: 'module', shortCircuit: true,
      source: stripTypeScriptTypes(readFileSync(new URL(url), 'utf8'), { mode: 'transform' }) };
    return nextLoad(url, context);
  }
});

const { UserDownloadFolder: Folder, OwnFolderCreationStatus: Status } =
  await import('../entry/src/main/ets/services/UserDownloadFolder.ets');
const read = path => readFileSync(new URL('../entry/src/main/ets/' + path, import.meta.url), 'utf8');
function reset() {
  state.directories.clear(); state.files.clear(); state.saves = 0; state.changes = 0;
  state.mode = 'create'; state.gate = null; state.denied = false; Folder.resetOwnFolderAccess();
}

test('启动与浏览不含自动创建或重新激活入口', () => {
  assert.doesNotMatch(read('entryability/EntryAbility.ets'), /UserDownloadFolder|createOwnFolder/);
  for (const path of ['pages/library/LibraryPage.ets', 'pages/local/FolderPage.ets', 'services/M3u8ConverterService.ets']) {
    assert.doesNotMatch(read(path), /ensureOwnFolder|reactivateOwnFolder|createOwnFolder/);
  }
  assert.doesNotMatch(read('services/UserDownloadFolder.ets'), /ensureOwnFolder|reactivateOwnFolder/);
});
test('没有专属目录时读取、扫描、刷新、转换查找不调用保存接口', async () => {
  reset();
  assert.equal(Folder.getExistingOwnFolder(), '');
  assert.equal(await Folder.scanOwnVideoFiles({}), null);
  assert.equal(await Folder.listOwnDirectory({}, ''), null);
  assert.equal(await Folder.findM3u8Package({}), null);
  assert.equal(await Folder.listSiblingVideoRecords({}, 'file://docs/example.mp4'), null);
  assert.equal(await Folder.isM3u8PackageDirectory({}, 'foo'), false);
  assert.equal(state.saves, 0); assert.equal(state.directories.size, 0);
});
test('明确创建操作调用一次系统保存并清理占位文件', async () => {
  reset();
  const result = await Folder.createOwnFolder({});
  assert.equal(result.status, Status.CREATED); assert.equal(result.path, root);
  assert.equal(state.saves, 1); assert.equal(state.changes, 1);
  assert.equal(state.files.has(root + '/.placeholder'), false);
});
test('已有目录再次创建直接返回已存在，不调用保存也不清理目录内容', async () => {
  reset(); state.directories.add(root); state.files.add(root + '/movie.mp4');
  const result = await Folder.createOwnFolder({});
  assert.equal(result.status, Status.ALREADY_EXISTS);
  assert.equal(state.saves, 0); assert.equal(state.changes, 0);
  assert.equal(state.files.has(root + '/movie.mp4'), true);
});
test('重启清除内存状态后仍可识别已有目录', async () => {
  reset(); state.directories.add(root); Folder.resetOwnFolderAccess();
  assert.equal((await Folder.createOwnFolder({})).status, Status.ALREADY_EXISTS);
  assert.equal(state.saves, 0);
});
test('目录被外部删除后读取不重建，用户主动创建才恢复', async () => {
  reset(); await Folder.createOwnFolder({}); state.directories.delete(root);
  assert.equal(Folder.getExistingOwnFolder(), '');
  assert.equal(await Folder.scanOwnVideoFiles({}), null);
  assert.equal(state.saves, 1);
  assert.equal((await Folder.createOwnFolder({})).status, Status.CREATED);
  assert.equal(state.saves, 2);
});
test('取消创建不生成目录，不通知媒体库刷新', async () => {
  reset(); state.mode = 'cancel';
  assert.equal((await Folder.createOwnFolder({})).status, Status.CANCELLED);
  assert.equal(state.directories.size, 0); assert.equal(state.changes, 0);
});
test('保存接口失败后允许重试', async () => {
  reset(); state.mode = 'fail';
  assert.equal((await Folder.createOwnFolder({})).status, Status.FAILED);
  state.mode = 'create';
  assert.equal((await Folder.createOwnFolder({})).status, Status.CREATED);
  assert.equal(state.saves, 2);
});
test('未真正生成目录或返回错误目标不误报成功', async () => {
  for (const mode of ['no_directory', 'invalid']) {
    reset(); state.mode = mode;
    assert.equal((await Folder.createOwnFolder({})).status, Status.FAILED);
    assert.equal(state.changes, 0);
  }
});
test('权限失效后的浏览不打开保存接口', async () => {
  reset(); state.directories.add(root); state.denied = true;
  assert.equal(await Folder.scanOwnVideoFiles({}), null);
  assert.equal(state.saves, 0);
});
test('并发请求共用一次系统保存', async () => {
  reset(); let release; state.gate = new Promise(resolve => { release = resolve; });
  const first = Folder.createOwnFolder({}); const second = Folder.createOwnFolder({});
  release(); const results = await Promise.all([first, second]);
  assert.equal(state.saves, 1); assert.equal(state.changes, 1);
  assert.ok(results.every(result => result.status === Status.CREATED));
});

const servicesSource = read('pages/sources/ServicesContent.ets');
const methods = servicesSource.slice(servicesSource.indexOf('  private openAddFlow('), servicesSource.indexOf('  private async moveSource('));
const serviceClass = stripTypeScriptTypes(`class Services { ${methods} }`, { mode: 'transform' });
function services() {
  const toasts = []; const routes = [];
  const Services = new Function('UserDownloadFolder', 'OwnFolderCreationStatus', 'promptAction', 'getContext', 'router', 'buildDetailToastOptions',
    `${serviceClass}; return Services;`)(Folder, Status, { showToast: value => toasts.push(value.message) }, () => ({}),
    { pushUrl: value => routes.push(value.url) }, message => ({ message }));
  const page = new Services(); page.creatingLocalFolder = false;
  return { page, toasts, routes };
}
test('服务页创建后留在原页，再次点击显示指定 Toast', async () => {
  reset(); const { page, toasts, routes } = services();
  await page.createLocalFolder(); await page.createLocalFolder();
  assert.deepEqual(toasts, ['应用专属文件夹创建成功', '已创建应用专属文件夹']);
  assert.deepEqual(routes, []); assert.equal(state.saves, 1);
});
test('服务页取消时不误报成功；失败显示失败提示', async () => {
  reset(); const { page, toasts } = services(); state.mode = 'cancel';
  await page.createLocalFolder(); assert.deepEqual(toasts, []);
  state.mode = 'fail'; await page.createLocalFolder();
  assert.deepEqual(toasts, ['创建失败，请重试']);
});
test('服务页快速重复点击只提交一次，Emby 新增路由保持不变', async () => {
  reset(); const { page, routes, toasts } = services();
  await Promise.all([page.createLocalFolder(), page.createLocalFolder()]);
  assert.equal(state.saves, 1); assert.equal(toasts.length, 1);
  page.openAddFlow('emby'); assert.deepEqual(routes, ['pages/sources/EmbySourceEditPage']);
});

test('服务页猫源入口跳转到已注册的原生来源表单，不触发本地目录创建', () => {
  reset(); const { page, routes } = services();
  page.openAddFlow('catvod');
  assert.deepEqual(routes, ['pages/catvod/CatVodSourceEditPage']);
  assert.equal(state.saves, 0);
  const pages = JSON.parse(readFileSync(new URL('../entry/src/main/resources/base/profile/main_pages.json', import.meta.url), 'utf8'));
  assert.ok(pages.src.includes(routes[0]));
});
