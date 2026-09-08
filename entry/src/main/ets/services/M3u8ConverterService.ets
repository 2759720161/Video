import { common } from '@kit.AbilityKit'
import { fileIo } from '@kit.CoreFileKit'
import mpvNapi from 'libmpv_napi.so'
import { M3u8PackageInfo, UserDownloadFolder } from './UserDownloadFolder'
import { LocalVideoThumbnailStore } from './LocalVideoThumbnailStore'
import { Logger } from '../utils/Logger'

const logger = new Logger('M3u8ConverterService')

export interface M3u8ConversionUpdate {
  progress: number
  finished: boolean
  success: boolean
  errorCode: number
  message: string
  outputPath: string
}

interface M3u8NativeApi {
  nativeConvertM3u8ToMp4: (source: string, output: string,
    callback: (update: M3u8ConversionUpdate) => void) => number
}

export class M3u8ConverterService {
  private static instance: M3u8ConverterService = new M3u8ConverterService()
  private active: boolean = false

  static getInstance(): M3u8ConverterService {
    return M3u8ConverterService.instance
  }

  isActive(): boolean {
    return this.active
  }

  async findLocalPackage(context: common.UIAbilityContext,
    relativeDirectory: string = '', exactDirectory: boolean = false): Promise<M3u8PackageInfo | null> {
    return UserDownloadFolder.findM3u8Package(context, relativeDirectory, exactDirectory)
  }

  async start(context: common.UIAbilityContext, source: string, packageFolderPath: string,
    callback: (update: M3u8ConversionUpdate) => void): Promise<string> {
    if (this.active) {
      throw new Error('已有转换任务正在进行')
    }
    const trimmedSource = source.trim()
    if (trimmedSource.length === 0) {
      throw new Error('未找到可转换的 m3u8 播放列表')
    }

    const folderPath = await UserDownloadFolder.ensureOwnFolder(context)
    if (folderPath.length === 0) {
      throw new Error('应用专属目录暂不可访问')
    }
    const targetFolderPath = packageFolderPath.trim()
    let targetFolderExists = false
    try {
      targetFolderExists = targetFolderPath.length > 0 && fileIo.accessSync(targetFolderPath)
    } catch (_err) {
      targetFolderExists = false
    }
    if (!targetFolderExists) {
      throw new Error('m3u8 所在文件夹不可访问')
    }
    const outputPath = this.createOutputPath(targetFolderPath)
    const api = mpvNapi as M3u8NativeApi
    if (api.nativeConvertM3u8ToMp4 === undefined) {
      throw new Error('当前安装包未包含转换内核，请重新编译安装')
    }

    this.active = true
    const thumbnailStore = LocalVideoThumbnailStore.getInstance()
    thumbnailStore.suspendFile(outputPath)
    const result = api.nativeConvertM3u8ToMp4(this.normalizeSource(trimmedSource), outputPath,
      (update: M3u8ConversionUpdate) => {
        if (update.finished) {
          this.active = false
          thumbnailStore.resumeFile(outputPath)
        }
        callback(update)
      })
    if (result < 0) {
      this.active = false
      thumbnailStore.resumeFile(outputPath)
      throw new Error('启动转换任务失败: ' + String(result))
    }
    logger.info('m3u8 转换任务已启动: output=%{public}s', outputPath)
    return outputPath
  }

  private normalizeSource(source: string): string {
    if (source.startsWith('file://docs/')) {
      return 'file:///' + source.substring('file://docs/'.length)
    }
    return source
  }

  private createOutputPath(packageFolderPath: string): string {
    const normalizedFolderPath = packageFolderPath.replace(/\\/g, '/')
    const trimmedFolderPath = normalizedFolderPath.replace(/\/+$/, '')
    const slashIndex = trimmedFolderPath.lastIndexOf('/')
    let name = slashIndex >= 0 ? trimmedFolderPath.substring(slashIndex + 1) : trimmedFolderPath
    name = name.replace(/[\\/:*?"<>|]/g, '_').trim()
    if (name.length === 0) {
      name = 'video'
    }
    if (name.length > 80) {
      name = name.substring(0, 80)
    }
    let candidate = trimmedFolderPath + '/' + name + '.mp4'
    let suffix = 2
    while (this.pathExists(candidate)) {
      candidate = trimmedFolderPath + '/' + name + ' (' + String(suffix) + ').mp4'
      suffix++
    }
    return candidate
  }

  private pathExists(path: string): boolean {
    try {
      return fileIo.accessSync(path)
    } catch (_err) {
      return false
    }
  }
}
