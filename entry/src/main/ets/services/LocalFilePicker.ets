import { picker, fileIo, fileShare, fileUri } from '@kit.CoreFileKit'
import { bundleManager, common } from '@kit.AbilityKit'
import { util } from '@kit.ArkTS'
import { Logger } from '../utils/Logger'

const logger = new Logger('LocalFilePicker')
const DOWNLOAD_MODE_URI_PREFIX = 'file://docs/storage/Users/currentUser/Download/'

export class LocalFileResult {
  fileName: string = ''
  uri: string = ''
  content: string = ''
  fileSize: number = 0
}

export class LocalVideoResult {
  fileName: string = ''
  uri: string = ''
  fileSize: number = 0
}

export class LocalM3u8Result {
  fileName: string = ''
  uri: string = ''
  fileSize: number = 0
}

export class LocalSubtitleResult {
  fileName: string = ''
  uri: string = ''
}

export class TextFileReadResult {
  content: string = ''
  fileSize: number = 0
}

export class LocalFilePicker {
  /** @deprecated The independent player does not offer this action. Retained only for old saved records. */
  static async pickDanmakuFile(context: common.UIAbilityContext): Promise<LocalFileResult | null> {
    const options = new picker.DocumentSelectOptions()
    options.maxSelectNumber = 1
    options.fileSuffixFilters = ['文本文件(.xml, .json, .ass)|.xml,.json,.ass']
    const documentPicker = new picker.DocumentViewPicker(context)
    const uris = await documentPicker.select(options)
    if (uris.length === 0) return null
    const result = LocalFilePicker.readDanmakuFileByUri(uris[0], LocalFilePicker.getFileNameFromUri(uris[0]))
    if (result === null) {
      throw new Error('弹幕文件读取失败或内容为空')
    }
    await LocalFilePicker.persistUriPermission(uris[0])
    return result
  }

  static async pickVideoFile(context: common.UIAbilityContext): Promise<LocalVideoResult | null> {
    try {
      const documentSelectOptions = new picker.DocumentSelectOptions()
      documentSelectOptions.maxSelectNumber = 1
      documentSelectOptions.fileSuffixFilters = ['视频文件|.mp4,.mkv,.avi,.webm,.ts,.flv,.mov,.wmv,.3gp']
      const documentPicker = new picker.DocumentViewPicker(context)
      const uris: string[] = await documentPicker.select(documentSelectOptions)
      if (uris.length === 0) {
        return null
      }

      const uri = uris[0]
      const fileName = LocalFilePicker.getFileNameFromUri(uri)
      logger.info('选择视频文件: %{public}s, uri=%{public}s', fileName, uri.substring(0, 60))
      await LocalFilePicker.persistUriPermission(uri)
      const result = new LocalVideoResult()
      result.fileName = fileName
      result.uri = uri
      result.fileSize = LocalFilePicker.getFileSize(uri)
      return result
    } catch (err) {
      logger.error('选择视频文件失败: %{public}s', err instanceof Error ? err.message : String(err))
      return null
    }
  }

  static async pickM3u8File(context: common.UIAbilityContext): Promise<LocalM3u8Result | null> {
    try {
      const options = new picker.DocumentSelectOptions()
      options.maxSelectNumber = 1
      options.fileSuffixFilters = ['m3u8 播放列表|.m3u8,.m3u']
      const documentPicker = new picker.DocumentViewPicker(context)
      const uris: string[] = await documentPicker.select(options)
      if (uris.length === 0) {
        return null
      }
      const uri = uris[0]
      await LocalFilePicker.persistUriPermission(uri)
      const result = new LocalM3u8Result()
      result.uri = uri
      result.fileName = LocalFilePicker.getFileNameFromUri(uri)
      result.fileSize = LocalFilePicker.getFileSize(uri)
      return result
    } catch (err) {
      logger.warn('选择 m3u8 文件失败: %{public}s', err instanceof Error ? err.message : String(err))
      return null
    }
  }

  static async pickSubtitleFile(context: common.UIAbilityContext): Promise<LocalSubtitleResult | null> {
    let uris: string[] = []
    try {
      const options = new picker.DocumentSelectOptions()
      options.maxSelectNumber = 1
      options.fileSuffixFilters = ['字幕文件(.srt, .ass, .ssa, .vtt)|.srt,.ass,.ssa,.vtt']
      const documentPicker = new picker.DocumentViewPicker(context)
      uris = await documentPicker.select(options)
    } catch (err) {
      logger.warn('打开字幕文件选择器失败: %{public}s', err instanceof Error ? err.message : String(err))
      return null
    }

    if (uris.length === 0) {
      return null
    }

    const uri = uris[0]
    const fileName = LocalFilePicker.getFileNameFromUri(uri)
    // Persisting access is best-effort: the subsequent import only needs the
    // temporary read grant provided by the document picker.
    await LocalFilePicker.persistUriPermission(uri)
    try {
      const result = new LocalSubtitleResult()
      result.fileName = fileName
      // libmpv runs inside the app sandbox and cannot directly open a document
      // picker URI such as file://docs/storage/.../Huawei Share/.... Import it
      // into the app-private files directory, which native MPV can read
      // without depending on the document-provider storage grant.
      result.uri = await LocalFilePicker.importSubtitleToAppFiles(context, uri, fileName)
      return result
    } catch (err) {
      logger.warn('导入字幕文件失败: name=%{public}s, error=%{public}s', fileName,
        err instanceof Error ? err.message : String(err))
      throw new Error('导入字幕文件失败: ' + (err instanceof Error ? err.message : String(err)))
    }
  }

  static canReadUri(uri: string): boolean {
    if (uri.length === 0) {
      return false
    }
    try {
      const file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY)
      fileIo.closeSync(file)
      return true
    } catch (_err) {
      return false
    }
  }

  static async authorizeExistingUri(context: common.UIAbilityContext, uri: string): Promise<boolean> {
    if (uri.length === 0) {
      return false
    }
    if (await LocalFilePicker.ensureReadableUri(uri)) {
      return true
    }
    if (!LocalFilePicker.isDocumentFileUri(uri)) {
      logger.warn('持久化授权不可用且跳过批量授权：该URI不是文档文件URI: %{public}s',
        uri.substring(0, 60))
      return false
    }
    return LocalFilePicker.authorizeExistingUris(context, [uri])
  }

  static async ensureReadableUri(uri: string): Promise<boolean> {
    if (uri.length === 0) {
      return false
    }
    // Files below the activated app-owned Download directory are exposed as
    // file://docs URIs, but opening those URIs through DataShare produces a
    // failing IPC round trip on current devices. Verify the authorized path
    // directly instead.
    if (LocalFilePicker.isOwnDownloadModeUri(uri)) {
      try {
        const path = new fileUri.FileUri(uri).path
        return fileIo.accessSync(path) && fileIo.statSync(path).isFile()
      } catch (_err) {
        return false
      }
    }
    if (LocalFilePicker.canReadUri(uri)) {
      return true
    }
    const activated = await LocalFilePicker.activatePersistedUriPermission(uri)
    if (!activated) {
      return false
    }
    return LocalFilePicker.canReadUri(uri)
  }

  static async persistUriPermission(uri: string): Promise<boolean> {
    if (uri.length === 0) {
      return false
    }
    if (LocalFilePicker.isOwnDownloadModeUri(uri) && LocalFilePicker.canReadUri(uri)) {
      logger.info('本应用Download模式文件已具备访问权限: %{public}s', uri.substring(0, 60))
      return true
    }
    if (!LocalFilePicker.canUsePersistentPermission()) {
      logger.warn('当前设备不支持文件持久化授权')
      return false
    }
    try {
      const policies: Array<fileShare.PolicyInfo> = [LocalFilePicker.buildReadPolicy(uri)]
      const checked = await fileShare.checkPersistentPermission(policies)
      if (checked.length > 0 && checked[0]) {
        await LocalFilePicker.activatePersistedUriPermission(uri)
        return true
      }
      await fileShare.persistPermission(policies)
      await LocalFilePicker.activatePersistedUriPermission(uri)
      logger.info('持久化本地文件授权成功: %{public}s', uri.substring(0, 60))
      return true
    } catch (err) {
      logger.warn('持久化本地文件授权失败: %{public}s', err instanceof Error ? err.message : String(err))
      return false
    }
  }

  static async activatePersistedUriPermission(uri: string): Promise<boolean> {
    if (uri.length === 0) {
      return false
    }
    if (LocalFilePicker.isOwnDownloadModeUri(uri)) {
      return LocalFilePicker.canReadUri(uri)
    }
    if (!LocalFilePicker.canUsePersistentPermission()) {
      return false
    }
    try {
      const policies: Array<fileShare.PolicyInfo> = [LocalFilePicker.buildReadPolicy(uri)]
      await fileShare.activatePermission(policies)
      logger.info('激活本地文件持久化授权成功: %{public}s', uri.substring(0, 60))
      return true
    } catch (err) {
      logger.warn('激活本地文件持久化授权失败: %{public}s', err instanceof Error ? err.message : String(err))
      return false
    }
  }

  static async revokeUriPermission(uri: string): Promise<void> {
    if (LocalFilePicker.isOwnDownloadModeUri(uri)) {
      return
    }
    if (uri.length === 0 || !LocalFilePicker.canUsePersistentPermission()) {
      return
    }
    try {
      const policies: Array<fileShare.PolicyInfo> = [LocalFilePicker.buildReadPolicy(uri)]
      await fileShare.revokePermission(policies)
      logger.info('撤销本地文件持久化授权成功: %{public}s', uri.substring(0, 60))
    } catch (err) {
      logger.warn('撤销本地文件持久化授权失败: %{public}s', err instanceof Error ? err.message : String(err))
    }
  }

  static async authorizeExistingUris(context: common.UIAbilityContext, uris: string[]): Promise<boolean> {
    const targetUris: string[] = []
    for (let i = 0; i < uris.length; i++) {
      if (uris[i].length > 0 && LocalFilePicker.isDocumentFileUri(uris[i])) {
        targetUris.push(uris[i])
      } else if (uris[i].length > 0) {
        logger.warn('跳过批量授权URI：不是文档文件URI: %{public}s', uris[i].substring(0, 60))
      }
    }
    if (targetUris.length === 0) {
      return false
    }
    try {
      const documentSelectOptions = new picker.DocumentSelectOptions()
      documentSelectOptions.multiAuthMode = true
      documentSelectOptions.multiUriArray = targetUris
      const documentPicker = new picker.DocumentViewPicker(context)
      const authorizedUris: string[] = await documentPicker.select(documentSelectOptions)
      logger.info('授权本地文件: requested=%{public}d, returned=%{public}d',
        targetUris.length, authorizedUris.length)
      for (let i = 0; i < targetUris.length; i++) {
        if (!LocalFilePicker.canReadUri(targetUris[i])) {
          logger.warn('授权后仍无法读取文件: %{public}s', targetUris[i].substring(0, 60))
          return false
        }
      }
      return true
    } catch (err) {
      logger.warn('本地文件授权失败: %{public}s', err instanceof Error ? err.message : String(err))
      return false
    }
  }

  private static readTextFile(uri: string): TextFileReadResult {
    const empty = new TextFileReadResult()
    try {
      const file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY)
      try {
        const stat = fileIo.statSync(file.fd)
        if (stat.size > 20 * 1024 * 1024) return empty
        const buffer = new ArrayBuffer(stat.size)
        fileIo.readSync(file.fd, buffer)
        const result = new TextFileReadResult()
        result.content = util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(buffer))
        result.fileSize = stat.size
        return result
      } finally {
        fileIo.closeSync(file)
      }
    } catch (_err) {
      return empty
    }
  }

  /** @deprecated Compatibility-only API. */
  static readDanmakuFileByUri(uri: string, fileName: string): LocalFileResult | null {
    const text = LocalFilePicker.readTextFile(uri)
    if (text.content.length === 0) return null
    const result = new LocalFileResult()
    result.fileName = fileName.length > 0 ? fileName : LocalFilePicker.getFileNameFromUri(uri)
    result.uri = uri
    result.content = text.content
    result.fileSize = text.fileSize
    return result
  }

  private static getFileSize(uri: string): number {
    try {
      const file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY)
      try {
        const stat = fileIo.statSync(file.fd)
        return stat.size
      } finally {
        fileIo.closeSync(file)
      }
    } catch (err) {
      logger.warn('读取文件大小失败: %{public}s', err instanceof Error ? err.message : String(err))
      return 0
    }
  }

  private static async importSubtitleToAppFiles(context: common.UIAbilityContext, sourceUri: string,
    fileName: string): Promise<string> {
    const sourceFile = fileIo.openSync(sourceUri, fileIo.OpenMode.READ_ONLY)
    try {
      const stat = fileIo.statSync(sourceFile.fd)
      if (stat.size <= 0 || stat.size > 20 * 1024 * 1024) {
        throw new Error('字幕文件大小不受支持')
      }
      const importDir = context.filesDir
      if (importDir.length === 0) {
        throw new Error('无法访问应用私有文件目录')
      }
      const subtitleDir = importDir + '/external_subtitles'
      LocalFilePicker.ensureSubtitleImportDirectory(subtitleDir)
      // mpv's native subtitle loader is more reliable with a short ASCII path.
      // Keep the source name for display, but use a private cache name for the
      // file handed to libass/mpv. This also avoids spaces and punctuation in
      // downloaded release names such as "[Moozzi2] ... .ass".
      const nameParts = fileName.toLowerCase().match(/\.([a-z0-9]+)$/)
      const extension = nameParts !== null && nameParts.length > 1 ? nameParts[1] : 'ass'
      const targetPath = subtitleDir + '/subtitle-' + Date.now().toString() + '.' + extension
      const buffer = new ArrayBuffer(stat.size)
      const readLength = fileIo.readSync(sourceFile.fd, buffer, { offset: 0, length: stat.size })
      if (readLength !== stat.size) {
        throw new Error('字幕源文件读取不完整: ' + String(readLength) + '/' + String(stat.size))
      }
      const targetFile = fileIo.openSync(targetPath,
        fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC | fileIo.OpenMode.WRITE_ONLY)
      try {
        const writeLength = fileIo.writeSync(targetFile.fd, buffer, { offset: 0, length: stat.size })
        if (writeLength !== stat.size) {
          throw new Error('字幕缓存文件写入不完整: ' + String(writeLength) + '/' + String(stat.size))
        }
      } finally {
        fileIo.closeSync(targetFile)
      }
      logger.info('字幕已导入应用私有目录: %{public}s', targetPath.substring(0, 80))
      return targetPath
    } finally {
      fileIo.closeSync(sourceFile)
    }
  }

  /**
   * Some device file systems report EEXIST for mkdirSync(path, true) when the
   * directory was created by a previous subtitle import. Reuse a real
   * directory and only surface an error if the path is occupied by a file.
   */
  private static ensureSubtitleImportDirectory(directoryPath: string): void {
    let exists = false
    try {
      exists = fileIo.accessSync(directoryPath)
    } catch (_err) {
      exists = false
    }

    if (exists) {
      if (!fileIo.statSync(directoryPath).isDirectory()) {
        throw new Error('字幕缓存路径被同名文件占用')
      }
      return
    }

    try {
      fileIo.mkdirSync(directoryPath, true)
    } catch (err) {
      // Another import may have created the folder between accessSync and
      // mkdirSync. Treat that race as success only when it is a directory.
      try {
        if (fileIo.accessSync(directoryPath) && fileIo.statSync(directoryPath).isDirectory()) {
          return
        }
      } catch (_verifyErr) {
      }
      throw new Error(err instanceof Error ? err.message : String(err))
    }
  }

  private static isDocumentFileUri(uri: string): boolean {
    const lowerUri = uri.toLowerCase()
    if (lowerUri.includes('/media') || lowerUri.includes('medialibrary') || lowerUri.includes('/photo/')) {
      return false
    }
    return lowerUri.startsWith('file://')
  }

  private static buildReadPolicy(uri: string): fileShare.PolicyInfo {
    return {
      uri: uri,
      operationMode: fileShare.OperationMode.READ_MODE
    }
  }

  private static canUsePersistentPermission(): boolean {
    try {
      return canIUse('SystemCapability.FileManagement.AppFileService.FolderAuthorization')
    } catch (_err) {
      return false
    }
  }

  private static isOwnDownloadModeUri(uri: string): boolean {
    if (!uri.startsWith(DOWNLOAD_MODE_URI_PREFIX)) {
      return false
    }
    const bundleName = LocalFilePicker.getBundleName()
    if (bundleName.length === 0) {
      return false
    }
    const ownDownloadPrefix = DOWNLOAD_MODE_URI_PREFIX + bundleName + '/'
    return uri === DOWNLOAD_MODE_URI_PREFIX + bundleName || uri.startsWith(ownDownloadPrefix)
  }

  private static getBundleName(): string {
    try {
      const bundleFlags = bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION |
      bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_METADATA
      const bundleInfo = bundleManager.getBundleInfoForSelfSync(bundleFlags)
      return bundleInfo.name
    } catch (err) {
      logger.warn('获取应用包名失败: %{public}s', err instanceof Error ? err.message : String(err))
      return ''
    }
  }

  private static getFileNameFromUri(uri: string): string {
    const cleanUri = uri.split('?')[0].split('#')[0]
    const lastSlash = cleanUri.lastIndexOf('/')
    if (lastSlash >= 0 && lastSlash < cleanUri.length - 1) {
      try {
        return decodeURIComponent(cleanUri.substring(lastSlash + 1))
      } catch (_err) {
        return cleanUri.substring(lastSlash + 1)
      }
    }
    return cleanUri
  }
}
