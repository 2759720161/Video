import { bundleManager, common } from '@kit.AbilityKit'
import { fileIo, fileUri, picker } from '@kit.CoreFileKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { LocalVideoRecord } from '../models/LocalVideoRecord'
import { PreferencesStore } from '../store/PreferencesStore'
import { Logger } from '../utils/Logger'

const logger = new Logger('UserDownloadFolder')
const OWN_FOLDER_URI_PREFIX = 'file://docs/storage/Users/currentUser/Download/'
const M3U8_PROMPT_SUPPRESSED_KEY_PREFIX = 'm3u8_prompt_suppressed_'

class M3u8FolderScanNode {
  path: string = ''
  relativePath: string = ''
}

export class UserDownloadFolder {
  private static ownFolderPath: string = ''
  private static folderActivated: boolean = false
  private static m3u8PromptSuppressedPaths: Set<string> = new Set()

  /** Returns whether the m3u8 confirmation has been disabled for this folder. */
  static async isM3u8PromptSuppressed(relativeDirectory: string): Promise<boolean> {
    const normalizedDirectory = UserDownloadFolder.normalizeDirectory(relativeDirectory)
    if (normalizedDirectory.length === 0) {
      return false
    }
    if (UserDownloadFolder.m3u8PromptSuppressedPaths.has(normalizedDirectory)) {
      return true
    }
    const suppressed = await PreferencesStore.getInstance().getBoolean(
      UserDownloadFolder.m3u8PromptPreferenceKey(normalizedDirectory), false)
    if (suppressed) {
      UserDownloadFolder.m3u8PromptSuppressedPaths.add(normalizedDirectory)
    }
    return suppressed
  }

  /** Suppresses the m3u8 confirmation for one folder only and persists that folder-level choice. */
  static async suppressM3u8Prompt(relativeDirectory: string): Promise<void> {
    const normalizedDirectory = UserDownloadFolder.normalizeDirectory(relativeDirectory)
    if (normalizedDirectory.length > 0) {
      UserDownloadFolder.m3u8PromptSuppressedPaths.add(normalizedDirectory)
      await PreferencesStore.getInstance().setBoolean(
        UserDownloadFolder.m3u8PromptPreferenceKey(normalizedDirectory), true)
    }
  }

  /** Clears the cached Download authorization after the system revokes its access. */
  static resetOwnFolderAccess(): void {
    UserDownloadFolder.ownFolderPath = ''
    UserDownloadFolder.folderActivated = false
    logger.info('已清除应用专属目录缓存授权')
  }

  static async ensureOwnFolder(context: common.UIAbilityContext, forceReauthorize: boolean = false): Promise<string> {
    if (!forceReauthorize && UserDownloadFolder.folderActivated && UserDownloadFolder.ownFolderPath.length > 0) {
      return UserDownloadFolder.ownFolderPath
    }

    const bundleName = UserDownloadFolder.getBundleName()
    if (bundleName.length === 0) {
      return ''
    }

    const ownFolderUri = OWN_FOLDER_URI_PREFIX + bundleName
    const ownPath = new fileUri.FileUri(ownFolderUri).path

    try {
      if (!forceReauthorize && fileIo.accessSync(ownPath)) {
        UserDownloadFolder.ownFolderPath = ownPath
        UserDownloadFolder.folderActivated = true
        logger.info('Download包名目录已存在: %{public}s', ownPath)
        return ownPath
      }
    } catch (_err) {
    }

    try {
      const documentSaveOptions = new picker.DocumentSaveOptions()
      documentSaveOptions.pickerMode = picker.DocumentPickerMode.DOWNLOAD
      documentSaveOptions.newFileNames = ['.placeholder']
      const documentViewPicker = new picker.DocumentViewPicker(context)
      const saveResult: Array<string> = await documentViewPicker.save(documentSaveOptions)
      if (saveResult.length > 0) {
        const resultUri = saveResult[0]
        const resultPath = new fileUri.FileUri(resultUri).path
        const parentDir = resultPath.substring(0, resultPath.lastIndexOf('/'))
        UserDownloadFolder.ownFolderPath = parentDir
        UserDownloadFolder.folderActivated = true

        try {
          const placeholderPath = resultPath
          if (fileIo.accessSync(placeholderPath)) {
            fileIo.unlinkSync(placeholderPath)
            logger.info('已清理占位文件')
          }
        } catch (_err) {
        }

        logger.info('Download包名目录激活成功: %{public}s', parentDir)
        return parentDir
      }
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err)
      logger.warn('Download包名目录激活失败: %{public}s', msg)
    }

    return ''
  }

  static async reactivateOwnFolder(context: common.UIAbilityContext): Promise<string> {
    UserDownloadFolder.resetOwnFolderAccess()
    return UserDownloadFolder.ensureOwnFolder(context, true)
  }

  static async scanOwnVideoFiles(context: common.UIAbilityContext): Promise<LocalVideoRecord[] | null> {
    const folderPath = await UserDownloadFolder.ensureOwnFolder(context)
    if (folderPath.length === 0) {
      return null
    }

    const records: LocalVideoRecord[] = []
    let skippedM3u8Files = 0
    let skippedTsFiles = 0
    try {
      const m3u8Directories = UserDownloadFolder.findM3u8PackageDirectories(folderPath)
      const filenames = UserDownloadFolder.collectFilesRecursively(folderPath)
      for (let i = 0; i < filenames.length; i++) {
        const filePath = filenames[i]
        const rootPrefix = folderPath.endsWith('/') ? folderPath : folderPath + '/'
        const relativePath = filePath.startsWith(rootPrefix) ? filePath.substring(rootPrefix.length) :
          UserDownloadFolder.getFileName(UserDownloadFolder.normalizeRelativePath(filePath))
        if (relativePath.length === 0) {
          continue
        }
        // A conversion package is identified by its contents, not by its
        // folder name. Never expose any file below such a folder as a card.
        if (UserDownloadFolder.isInsideM3u8Package(filePath, m3u8Directories)) {
          skippedM3u8Files++
          continue
        }
        // TS is an HLS segment, not a user-facing local video. The converter
        // scans TS files separately; the normal media library must never add
        // them as cards, even when the device returns basename-only paths.
        if (relativePath.toLowerCase().endsWith('.ts') || filePath.toLowerCase().endsWith('.ts')) {
          skippedTsFiles++
          continue
        }
        if (!fileIo.accessSync(filePath)) {
          continue
        }
        const stat = fileIo.statSync(filePath)
        if (!stat.isFile()) {
          continue
        }

        if (UserDownloadFolder.isVideoFile(relativePath)) {
          const record = new LocalVideoRecord()
          record.fileUri = new fileUri.FileUri(filePath).toString()
          record.fileName = UserDownloadFolder.getFileName(relativePath)
          record.fileSize = stat.size
          record.fileKey = record.fileUri + '|' + record.fileSize + '|' + record.fileName
          records.push(record)
        }
      }
      logger.info('扫描Download包名目录视频: %{public}d，跳过 m3u8 文件: %{public}d，跳过 TS 分片: %{public}d',
        records.length, skippedM3u8Files, skippedTsFiles)
    } catch (err) {
      logger.warn('扫描Download包名目录失败: %{public}s', err instanceof Error ? err.message : String(err))
      return null
    }
    return records
  }

  /** Finds a local HLS package anywhere below the app-owned Download folder. */
  static async findM3u8Package(context: common.UIAbilityContext,
    relativeDirectory: string = '', exactDirectory: boolean = false): Promise<M3u8PackageInfo | null> {
    const rootPath = await UserDownloadFolder.ensureOwnFolder(context)
    if (rootPath.length === 0) {
      return null
    }

    try {
      const normalizedDirectory = UserDownloadFolder.normalizeDirectory(relativeDirectory)
      const packageDirectories = exactDirectory
        ? [normalizedDirectory.length > 0 ? rootPath + '/' + normalizedDirectory : rootPath]
        : normalizedDirectory.length > 0
          ? [rootPath + '/' + normalizedDirectory]
          : UserDownloadFolder.findM3u8PackageDirectories(rootPath)
      if (packageDirectories.length === 0) {
        logger.info('应用专属目录中未找到包含 m3u8 播放列表的文件夹: %{public}s', rootPath)
        return null
      }
      const packageInfo = UserDownloadFolder.inspectM3u8PackageDirectory(packageDirectories[0])
      if (packageInfo === null) {
        return null
      }
      logger.info('已识别 m3u8 文件夹: playlist=%{public}s, segments=%{public}d',
        packageInfo.playlistName, packageInfo.segmentCount)
      return packageInfo
    } catch (err) {
      logger.warn('扫描应用专属目录中的 m3u8 文件夹失败: %{public}s', err instanceof Error ? err.message : String(err))
      return null
    }
  }

  /** Returns selectable m3u8 folders inside the application-owned directory. */
  static async listM3u8FolderChoices(context: common.UIAbilityContext): Promise<M3u8FolderChoice[] | null> {
    const rootPath = await UserDownloadFolder.ensureOwnFolder(context)
    if (rootPath.length === 0) {
      return null
    }
    const choices: M3u8FolderChoice[] = []
    const rootNode = new M3u8FolderScanNode()
    rootNode.path = rootPath
    const pending: M3u8FolderScanNode[] = [rootNode]
    const visited: Map<string, boolean> = new Map()
    try {
      while (pending.length > 0) {
        const current = pending.shift()
        if (current === undefined || visited.has(current.path)) {
          continue
        }
        visited.set(current.path, true)
        if (UserDownloadFolder.hasM3u8Playlist(current.path)) {
          const packageInfo = UserDownloadFolder.inspectM3u8PackageDirectory(current.path)
          if (packageInfo !== null) {
            const choice = new M3u8FolderChoice()
            choice.relativePath = current.relativePath
            choice.folderName = current.relativePath.length > 0
              ? UserDownloadFolder.getFileName(current.relativePath)
              : '应用专属目录'
            choice.playlistName = packageInfo.playlistName
            choice.segmentCount = packageInfo.segmentCount
            choices.push(choice)
          }
        }
        const names = fileIo.listFileSync(current.path)
        for (let i = 0; i < names.length; i++) {
          const name = UserDownloadFolder.getFileName(UserDownloadFolder.normalizeRelativePath(names[i]))
          if (name.length === 0 || name === '.subtitles') {
            continue
          }
          const childPath = current.path + '/' + name
          if (!fileIo.accessSync(childPath) || !fileIo.statSync(childPath).isDirectory()) {
            continue
          }
          const childNode = new M3u8FolderScanNode()
          childNode.path = childPath
          childNode.relativePath = current.relativePath.length > 0
            ? current.relativePath + '/' + name : name
          pending.push(childNode)
        }
      }
      choices.sort((first: M3u8FolderChoice, second: M3u8FolderChoice): number =>
        first.relativePath.localeCompare(second.relativePath))
      logger.info('发现可选择的 m3u8 文件夹: %{public}d', choices.length)
      return choices
    } catch (err) {
      logger.warn('读取可选择的 m3u8 文件夹失败: %{public}s', err instanceof Error ? err.message : String(err))
      return null
    }
  }

  /** Lists only the immediate folders and playable videos of one app-owned directory. */
  static async listOwnDirectory(context: common.UIAbilityContext, relativeDirectory: string = ''): Promise<UserFolderEntry[] | null> {
    const rootPath = await UserDownloadFolder.ensureOwnFolder(context)
    if (rootPath.length === 0) {
      return null
    }
    const normalizedDirectory = UserDownloadFolder.normalizeDirectory(relativeDirectory)
    const directoryPath = normalizedDirectory.length > 0 ? rootPath + '/' + normalizedDirectory : rootPath
    // Keep HLS source files out of the media list through isVideoFile(), but
    // still browse the directory normally. This makes a generated MP4 visible
    // inside its source folder without exposing .m3u8 playlists or .ts shards.
    const entries: UserFolderEntry[] = []
    try {
      const names = fileIo.listFileSync(directoryPath)
      for (let i = 0; i < names.length; i++) {
        const name = UserDownloadFolder.normalizeRelativePath(names[i])
        if (name.length === 0) {
          continue
        }
        // Imported subtitle cache is an implementation detail, not a user
        // media folder. It must not appear in the local-library hierarchy.
        if (name === '.subtitles') {
          continue
        }
        const childPath = directoryPath + '/' + name
        if (!fileIo.accessSync(childPath)) {
          continue
        }
        const stat = fileIo.statSync(childPath)
        const relativePath = normalizedDirectory.length > 0 ? normalizedDirectory + '/' + name : name
        if (stat.isDirectory()) {
          const entry = new UserFolderEntry()
          entry.name = UserDownloadFolder.getFileName(name)
          entry.relativePath = relativePath
          entry.isDirectory = true
          entry.modifiedTime = stat.mtime
          entry.isM3u8Package = UserDownloadFolder.hasM3u8Playlist(childPath)
          // An HLS package can also contain the MP4 generated by the converter.
          // Count playable direct children for every directory; otherwise an
          // m3u8 package is permanently reported as empty after conversion.
          const summary = UserDownloadFolder.getDirectDirectorySummary(childPath)
          entry.childDirectoryCount = summary.directoryCount
          entry.childVideoCount = summary.videoCount
          entries.push(entry)
          continue
        }
        if (!stat.isFile() || !UserDownloadFolder.isVideoFile(name)) {
          continue
        }
        const entry = new UserFolderEntry()
        entry.name = UserDownloadFolder.getFileName(name)
        entry.relativePath = relativePath
        entry.isDirectory = false
        entry.modifiedTime = stat.mtime
        entry.video.fileUri = new fileUri.FileUri(childPath).toString()
        entry.video.fileName = entry.name
        entry.video.fileSize = stat.size
        entry.video.fileKey = entry.video.fileUri + '|' + entry.video.fileSize + '|' + entry.video.fileName
        entries.push(entry)
      }
      entries.sort((first: UserFolderEntry, second: UserFolderEntry): number => {
        if (first.isDirectory !== second.isDirectory) {
          return first.isDirectory ? -1 : 1
        }
        return first.name.localeCompare(second.name)
      })
      return entries
    } catch (err) {
      logger.warn('读取应用专属子目录失败: %{public}s', err instanceof Error ? err.message : String(err))
      return null
    }
  }

  /**
   * Returns the playable files directly beside an app-owned file.
   *
   * The player can also be opened from the home page or playback history,
   * where the route queue is not a directory queue. Resolve the file back to
   * the app-owned directory so automatic next playback always stays local to
   * the current folder.
   */
  static async listSiblingVideoRecords(context: common.UIAbilityContext,
    targetUri: string): Promise<LocalVideoRecord[] | null> {
    if (targetUri.length === 0) {
      return null
    }
    const rootPath = await UserDownloadFolder.ensureOwnFolder(context)
    if (rootPath.length === 0) {
      return null
    }
    try {
      const targetPath = new fileUri.FileUri(targetUri).path
      const normalizedRoot = rootPath.endsWith('/') ? rootPath.substring(0, rootPath.length - 1) : rootPath
      const rootPrefix = normalizedRoot + '/'
      if (!targetPath.startsWith(rootPrefix)) {
        return null
      }
      const relativeFile = targetPath.substring(rootPrefix.length)
      const slashIndex = relativeFile.lastIndexOf('/')
      const relativeDirectory = slashIndex >= 0 ? relativeFile.substring(0, slashIndex) : ''
      const entries = await UserDownloadFolder.listOwnDirectory(context, relativeDirectory)
      if (entries === null) {
        return null
      }
      const records: LocalVideoRecord[] = []
      for (let i = 0; i < entries.length; i++) {
        if (!entries[i].isDirectory && entries[i].video.fileUri.length > 0) {
          records.push(entries[i].video)
        }
      }
      return records
    } catch (err) {
      logger.warn('解析当前视频所在目录失败: %{public}s', err instanceof Error ? err.message : String(err))
      return null
    }
  }

  /** Creates one direct child folder inside the selected app-owned directory. Returns an empty string on success. */
  static async createOwnDirectory(context: common.UIAbilityContext, relativeDirectory: string, folderName: string): Promise<string> {
    const name = folderName.trim()
    if (name.length === 0) {
      return '请输入文件夹名称'
    }
    if (name === '.' || name === '..' || name.indexOf('/') >= 0 || name.indexOf('\\') >= 0 ||
      name.indexOf(':') >= 0 || name.indexOf('*') >= 0 || name.indexOf('?') >= 0 ||
      name.indexOf('"') >= 0 || name.indexOf('<') >= 0 || name.indexOf('>') >= 0 || name.indexOf('|') >= 0) {
      return '名称不能包含 / \\ : * ? " < > |'
    }

    const rootPath = await UserDownloadFolder.ensureOwnFolder(context)
    if (rootPath.length === 0) {
      return '应用专属目录暂不可访问'
    }
    const normalizedDirectory = UserDownloadFolder.normalizeDirectory(relativeDirectory)
    const parentPath = normalizedDirectory.length > 0 ? rootPath + '/' + normalizedDirectory : rootPath
    const targetPath = parentPath + '/' + name
    try {
      if (fileIo.accessSync(targetPath)) {
        return '已存在同名文件或文件夹'
      }
    } catch (_err) {
      // The path does not exist and can be created below.
    }
    try {
      fileIo.mkdirSync(targetPath)
      logger.info('已创建应用专属子目录: %{public}s', targetPath)
      return ''
    } catch (err) {
      logger.warn('创建应用专属子目录失败: %{public}s', err instanceof Error ? err.message : String(err))
      return '创建失败，请稍后重试'
    }
  }

  private static normalizeDirectory(path: string): string {
    const segments = path.split('/')
    const clean: string[] = []
    for (let i = 0; i < segments.length; i++) {
      if (segments[i].length > 0 && segments[i] !== '.' && segments[i] !== '..') {
        clean.push(segments[i])
      }
    }
    return clean.join('/')
  }

  private static m3u8PromptPreferenceKey(normalizedDirectory: string): string {
    return M3U8_PROMPT_SUPPRESSED_KEY_PREFIX + normalizedDirectory.replace(/\//g, '__')
  }

  private static chooseM3u8Playlist(names: string[]): string {
    const preferredNames: string[] = ['video.m3u8', 'index.m3u8', 'media.m3u8', 'playlist.m3u8']
    for (let i = 0; i < preferredNames.length; i++) {
      for (let j = 0; j < names.length; j++) {
        if (names[j].toLowerCase() === preferredNames[i]) {
          return names[j]
        }
      }
    }
    names.sort((first: string, second: string): number => first.localeCompare(second))
    return names[0]
  }

  private static normalizeRelativePath(path: string): string {
    let normalized = path
    while (normalized.startsWith('/')) {
      normalized = normalized.substring(1)
    }
    return normalized
  }

  static async isM3u8PackageDirectory(context: common.UIAbilityContext, relativeDirectory: string): Promise<boolean> {
    const rootPath = await UserDownloadFolder.ensureOwnFolder(context)
    if (rootPath.length === 0) {
      return false
    }
    const normalizedDirectory = UserDownloadFolder.normalizeDirectory(relativeDirectory)
    if (normalizedDirectory.length === 0) {
      return false
    }
    return UserDownloadFolder.hasM3u8Playlist(rootPath + '/' + normalizedDirectory)
  }

  private static hasM3u8Playlist(directoryPath: string): boolean {
    try {
      if (!fileIo.accessSync(directoryPath) || !fileIo.statSync(directoryPath).isDirectory()) {
        return false
      }
      const names = fileIo.listFileSync(directoryPath)
      for (let i = 0; i < names.length; i++) {
        const name = UserDownloadFolder.getFileName(UserDownloadFolder.normalizeRelativePath(names[i])).toLowerCase()
        if (name.endsWith('.m3u8') || name.endsWith('.m3u')) {
          return true
        }
      }
    } catch (_err) {
      return false
    }
    return false
  }

  private static findM3u8PackageDirectories(rootPath: string): string[] {
    const result: string[] = []
    const pending: string[] = [rootPath]
    const visited: Map<string, boolean> = new Map()
    while (pending.length > 0) {
      const directoryPath = pending.shift()
      if (directoryPath === undefined || visited.has(directoryPath)) {
        continue
      }
      visited.set(directoryPath, true)
      try {
        if (!fileIo.accessSync(directoryPath) || !fileIo.statSync(directoryPath).isDirectory()) {
          continue
        }
        const names = fileIo.listFileSync(directoryPath)
        let hasPlaylist = false
        for (let i = 0; i < names.length; i++) {
          const listedName = UserDownloadFolder.getFileName(UserDownloadFolder.normalizeRelativePath(names[i]))
          if (listedName.length === 0) {
            continue
          }
          const childPath = directoryPath + '/' + listedName
          if (!fileIo.accessSync(childPath)) {
            continue
          }
          const stat = fileIo.statSync(childPath)
          if (stat.isDirectory()) {
            pending.push(childPath)
            continue
          }
          const lowerName = listedName.toLowerCase()
          if (stat.isFile() && (lowerName.endsWith('.m3u8') || lowerName.endsWith('.m3u'))) {
            hasPlaylist = true
          }
        }
        if (hasPlaylist) {
          result.push(directoryPath)
        }
      } catch (err) {
        logger.warn('扫描 m3u8 候选目录失败: %{public}s', err instanceof Error ? err.message : String(err))
      }
    }
    return result
  }

  private static inspectM3u8PackageDirectory(packagePath: string): M3u8PackageInfo | null {
    const playlistNames: string[] = []
    let segmentCount = 0
    const names = fileIo.listFileSync(packagePath)
    for (let i = 0; i < names.length; i++) {
      const name = UserDownloadFolder.getFileName(UserDownloadFolder.normalizeRelativePath(names[i]))
      if (name.length === 0) {
        continue
      }
      const childPath = packagePath + '/' + name
      if (!fileIo.accessSync(childPath) || !fileIo.statSync(childPath).isFile()) {
        continue
      }
      const lowerName = name.toLowerCase()
      if (lowerName.endsWith('.m3u8') || lowerName.endsWith('.m3u')) {
        playlistNames.push(name)
      } else if (lowerName.endsWith('.ts')) {
        segmentCount++
      }
    }
    if (playlistNames.length === 0) {
      return null
    }
    const result = new M3u8PackageInfo()
    const playlistName = UserDownloadFolder.chooseM3u8Playlist(playlistNames)
    result.folderPath = packagePath
    result.playlistName = playlistName
    result.playlistPath = packagePath + '/' + playlistName
    result.playlistCount = playlistNames.length
    result.segmentCount = segmentCount
    return result
  }

  private static collectFilesRecursively(rootPath: string): string[] {
    const result: string[] = []
    const pending: string[] = [rootPath]
    while (pending.length > 0) {
      const directoryPath = pending.shift()
      if (directoryPath === undefined) {
        continue
      }
      try {
        const names = fileIo.listFileSync(directoryPath)
        for (let i = 0; i < names.length; i++) {
          const listedName = UserDownloadFolder.getFileName(UserDownloadFolder.normalizeRelativePath(names[i]))
          if (listedName.length === 0) {
            continue
          }
          const childPath = directoryPath + '/' + listedName
          if (!fileIo.accessSync(childPath)) {
            continue
          }
          const stat = fileIo.statSync(childPath)
          if (stat.isDirectory()) {
            pending.push(childPath)
          } else if (stat.isFile()) {
            result.push(childPath)
          }
        }
      } catch (err) {
        logger.warn('递归扫描媒体文件失败: %{public}s', err instanceof Error ? err.message : String(err))
      }
    }
    return result
  }

  private static isInsideM3u8Package(filePath: string, packageDirectories: string[]): boolean {
    for (let i = 0; i < packageDirectories.length; i++) {
      const packagePath = packageDirectories[i]
      if (filePath === packagePath || filePath.startsWith(packagePath + '/')) {
        return true
      }
    }
    return false
  }

  private static isVideoFile(path: string): boolean {
    const lowerPath = path.toLowerCase()
    // stream-record requires a recognizable .mp4 suffix while writing. Keep
    // its staging file out of folder cards until the final atomic rename.
    if (lowerPath.endsWith('.part.mp4')) {
      return false
    }
    return lowerPath.endsWith('.mp4') || lowerPath.endsWith('.mkv') || lowerPath.endsWith('.avi') ||
      lowerPath.endsWith('.webm') || lowerPath.endsWith('.flv') ||
      lowerPath.endsWith('.mov') || lowerPath.endsWith('.wmv') || lowerPath.endsWith('.3gp')
  }

  private static getFileName(path: string): string {
    const slashIndex = path.lastIndexOf('/')
    if (slashIndex >= 0 && slashIndex < path.length - 1) {
      return path.substring(slashIndex + 1)
    }
    return path
  }

  /** Counts only direct children so the folder card describes the next page accurately. */
  private static getDirectDirectorySummary(directoryPath: string): UserDirectorySummary {
    const summary = new UserDirectorySummary()
    try {
      const names = fileIo.listFileSync(directoryPath)
      for (let i = 0; i < names.length; i++) {
        const name = UserDownloadFolder.normalizeRelativePath(names[i])
        if (name.length === 0) {
          continue
        }
        const path = directoryPath + '/' + name
        if (!fileIo.accessSync(path)) {
          continue
        }
        const stat = fileIo.statSync(path)
        if (stat.isDirectory()) {
          summary.directoryCount++
        } else if (stat.isFile() && UserDownloadFolder.isVideoFile(name)) {
          summary.videoCount++
        }
      }
    } catch (err) {
      logger.warn('读取子目录摘要失败: %{public}s', err instanceof Error ? err.message : String(err))
    }
    return summary
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
}

export class UserFolderEntry {
  name: string = ''
  relativePath: string = ''
  isDirectory: boolean = false
  modifiedTime: number = 0
  childDirectoryCount: number = 0
  childVideoCount: number = 0
  isM3u8Package: boolean = false
  video: LocalVideoRecord = new LocalVideoRecord()
}

export class M3u8PackageInfo {
  folderPath: string = ''
  playlistPath: string = ''
  playlistName: string = ''
  playlistCount: number = 0
  segmentCount: number = 0
}

export class M3u8FolderChoice {
  relativePath: string = ''
  folderName: string = ''
  playlistName: string = ''
  segmentCount: number = 0
}

class UserDirectorySummary {
  directoryCount: number = 0
  videoCount: number = 0
}
