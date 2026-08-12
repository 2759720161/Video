import { bundleManager, common } from '@kit.AbilityKit'
import { fileIo, fileUri, picker, ListFileOptions } from '@kit.CoreFileKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { LocalVideoRecord } from '../models/LocalVideoRecord'
import { Logger } from '../utils/Logger'

const logger = new Logger('UserDownloadFolder')
const OWN_FOLDER_URI_PREFIX = 'file://docs/storage/Users/currentUser/Download/'

export class UserDownloadFolder {
  private static ownFolderPath: string = ''
  private static folderActivated: boolean = false

  static async ensureOwnFolder(context: common.UIAbilityContext): Promise<string> {
    if (UserDownloadFolder.folderActivated && UserDownloadFolder.ownFolderPath.length > 0) {
      return UserDownloadFolder.ownFolderPath
    }

    const bundleName = UserDownloadFolder.getBundleName()
    if (bundleName.length === 0) {
      return ''
    }

    const ownFolderUri = OWN_FOLDER_URI_PREFIX + bundleName
    const ownPath = new fileUri.FileUri(ownFolderUri).path

    try {
      if (fileIo.accessSync(ownPath)) {
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

  static async scanOwnVideoFiles(context: common.UIAbilityContext): Promise<LocalVideoRecord[] | null> {
    const folderPath = await UserDownloadFolder.ensureOwnFolder(context)
    if (folderPath.length === 0) {
      return null
    }

    const records: LocalVideoRecord[] = []
    try {
      const listFileOptions: ListFileOptions = {
        recursion: true
      }
      const filenames = fileIo.listFileSync(folderPath, listFileOptions)
      for (let i = 0; i < filenames.length; i++) {
        const relativePath = UserDownloadFolder.normalizeRelativePath(filenames[i])
        if (relativePath.length === 0) {
          continue
        }

        const filePath = folderPath + '/' + relativePath
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
      logger.info('扫描Download包名目录视频: %{public}d', records.length)
    } catch (err) {
      logger.warn('扫描Download包名目录失败: %{public}s', err instanceof Error ? err.message : String(err))
      return null
    }
    return records
  }

  /** Lists only the immediate folders and playable videos of one app-owned directory. */
  static async listOwnDirectory(context: common.UIAbilityContext, relativeDirectory: string = ''): Promise<UserFolderEntry[] | null> {
    const rootPath = await UserDownloadFolder.ensureOwnFolder(context)
    if (rootPath.length === 0) {
      return null
    }
    const normalizedDirectory = UserDownloadFolder.normalizeDirectory(relativeDirectory)
    const directoryPath = normalizedDirectory.length > 0 ? rootPath + '/' + normalizedDirectory : rootPath
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

  private static normalizeRelativePath(path: string): string {
    let normalized = path
    while (normalized.startsWith('/')) {
      normalized = normalized.substring(1)
    }
    return normalized
  }

  private static isVideoFile(path: string): boolean {
    const lowerPath = path.toLowerCase()
    return lowerPath.endsWith('.mp4') || lowerPath.endsWith('.mkv') || lowerPath.endsWith('.avi') ||
      lowerPath.endsWith('.webm') || lowerPath.endsWith('.ts') || lowerPath.endsWith('.flv') ||
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
  video: LocalVideoRecord = new LocalVideoRecord()
}

class UserDirectorySummary {
  directoryCount: number = 0
  videoCount: number = 0
}
