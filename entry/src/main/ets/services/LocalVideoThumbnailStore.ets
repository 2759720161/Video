import { fileIo as fs, fileUri } from '@kit.CoreFileKit'
import { image } from '@kit.ImageKit'
import { media } from '@kit.MediaKit'
import mpvNapi from 'libmpv_napi.so'
import { FileStore } from '../store/FileStore'
import { Logger } from '../utils/Logger'

const logger = new Logger('LocalVideoThumbnailStore')

interface NativeVideoThumbnailUpdate {
  success: boolean
  errorCode: number
  message: string
  outputPath: string
}

interface NativeVideoThumbnailApi {
  nativeGenerateVideoThumbnail: (source: string, output: string,
    callback: (update: NativeVideoThumbnailUpdate) => void) => number
}

export class LocalVideoThumbnailStore {
  private static instance: LocalVideoThumbnailStore | null = null
  /** The first frame remains available for callers that explicitly need it. */
  static readonly FIRST_FRAME_TIME_MS: number = 0
  private static readonly RANDOM_FRAME_MIN_RATIO: number = 0.12
  private static readonly RANDOM_FRAME_MAX_RATIO: number = 0.88
  private static readonly RANDOM_FRAME_EDGE_GUARD_MS: number = 1000
  private readonly cacheDirName: string = 'local_video_covers'
  /** Serializing cover jobs prevents page callbacks from exhausting the media helper service. */
  private mediaTaskQueue: Promise<void> = Promise.resolve()
  private readonly pendingTasks: Map<string, Promise<string>> = new Map()
  private readonly failedUntil: Map<string, number> = new Map()
  private readonly durationCache: Map<string, number> = new Map()
  private readonly randomFrameTimeCache: Map<string, number> = new Map()
  private readonly suspendedPaths: Map<string, boolean> = new Map()
  private static readonly FAILURE_RETRY_DELAY_MS: number = 60000

  private constructor() {}

  static getInstance(): LocalVideoThumbnailStore {
    if (LocalVideoThumbnailStore.instance === null) {
      LocalVideoThumbnailStore.instance = new LocalVideoThumbnailStore()
    }
    return LocalVideoThumbnailStore.instance
  }

  /** Prevents queued cover work from opening a file while it is being replaced. */
  suspendFile(pathOrUri: string): void {
    this.suspendedPaths.set(this.resolveFilePath(pathOrUri), true)
  }

  resumeFile(pathOrUri: string): void {
    this.suspendedPaths.delete(this.resolveFilePath(pathOrUri))
  }

  /**
   * Generates one cover from the requested playback position. The position is part of
   * the cache key, so an exit-frame cover never reuses an old first-frame thumbnail.
   */
  async ensureThumbnail(videoUri: string, fileName: string, fileSize: number,
    frameTimeMs: number = LocalVideoThumbnailStore.FIRST_FRAME_TIME_MS): Promise<string> {
    if (videoUri.length === 0) {
      return ''
    }
    if (this.isSuspended(videoUri)) {
      return ''
    }

    const safeFrameTimeMs = Math.max(0, Math.floor(frameTimeMs))
    const path = this.getCachePath(videoUri, fileName, fileSize, safeFrameTimeMs)
    if (this.isValidCacheFile(path)) {
      return fileUri.getUriFromPath(path)
    }

    const taskKey = `frame|${path}`
    const failureKey = this.getFailureKey(videoUri, fileName, fileSize)
    if (this.isInFailureBackoff(failureKey)) {
      return ''
    }
    const pendingTask: Promise<string> | undefined = this.pendingTasks.get(taskKey)
    if (pendingTask !== undefined) {
      return pendingTask
    }

    const task = this.enqueueThumbnailTask(videoUri, fileName, fileSize, safeFrameTimeMs)
    this.trackPendingTask(taskKey, failureKey, task)
    return task
  }

  private enqueueThumbnailTask(videoUri: string, fileName: string, fileSize: number,
    frameTimeMs: number): Promise<string> {
    const task: Promise<string> = this.mediaTaskQueue.then((): Promise<string> => {
      return this.generateThumbnail(videoUri, fileName, fileSize, frameTimeMs)
    })
    this.mediaTaskQueue = task.then((): void => {}, (): void => {})
    return task
  }

  private async generateThumbnail(videoUri: string, fileName: string, fileSize: number,
    frameTimeMs: number): Promise<string> {
    if (this.isSuspended(videoUri)) {
      return ''
    }
    const path = this.getCachePath(videoUri, fileName, fileSize, frameTimeMs)
    if (this.isValidCacheFile(path)) {
      return fileUri.getUriFromPath(path)
    }

    let videoFile: fs.File | null = null
    let extractor: media.AVMetadataExtractor | null = null
    let imageGenerator: media.AVImageGenerator | null = null
    let pixelMap: image.PixelMap | null = null
    let extractorError: string = ''
    try {
      const sourcePath = this.resolveFilePath(videoUri)
      videoFile = fs.openSync(sourcePath, fs.OpenMode.READ_ONLY)
      const videoLength = this.getFileLength(sourcePath)
      const avFileDescriptor: media.AVFileDescriptor = {
        fd: videoFile.fd,
        offset: 0,
        length: videoLength
      }
      // API 20+ AVMetadataExtractor uses the current metadata-helper pipeline
      // for both metadata and thumbnails. It is more reliable for FFmpeg-muxed
      // MP4 files than the legacy AVImageGenerator path on current devices.
      extractor = await media.createAVMetadataExtractor()
      extractor.fdSrc = avFileDescriptor
      try {
        pixelMap = await this.fetchPreviewFrame(extractor, frameTimeMs)
      } catch (err) {
        extractorError = err instanceof Error ? err.message : String(err)
        // The metadata helper can time out when seeking in stream-remuxed MP4
        // files. Release its fd completely before falling back to the dedicated
        // thumbnail API used by the reference project.
        try {
          await extractor.release()
        } catch (_releaseErr) {
        }
        extractor = null
        fs.closeSync(videoFile)
        videoFile = null

        videoFile = fs.openSync(sourcePath, fs.OpenMode.READ_ONLY)
        imageGenerator = await media.createAVImageGenerator()
        imageGenerator.fdSrc = {
          fd: videoFile.fd,
          offset: 0,
          length: videoLength
        }
        pixelMap = await this.fetchGeneratorFallbackFrame(imageGenerator)
        logger.warn('视频随机帧取帧失败，已使用首段同步帧: %{public}s, err=%{public}s',
          this.shorten(fileName), extractorError)
      }

      const packer = image.createImagePacker()
      try {
        const data = await packer.packToData(pixelMap, {
          format: 'image/jpeg',
          quality: 82
        })
        this.writeBinary(path, data)
      } finally {
        await packer.release()
      }

      logger.info('本地视频封面生成成功: %{public}s position=%{public}d', this.shorten(fileName), frameTimeMs)
      return fileUri.getUriFromPath(path)
    } catch (err) {
      const systemError = err instanceof Error ? err.message : String(err)
      if (pixelMap !== null) {
        try {
          await pixelMap.release()
        } catch (_releaseErr) {
        }
        pixelMap = null
      }
      if (extractor !== null) {
        try {
          await extractor.release()
        } catch (_releaseErr) {
        }
        extractor = null
      }
      if (imageGenerator !== null) {
        try {
          await imageGenerator.release()
        } catch (_releaseErr) {
        }
        imageGenerator = null
      }
      if (videoFile !== null) {
        try {
          fs.closeSync(videoFile)
        } catch (_releaseErr) {
        }
        videoFile = null
      }

      this.ensureParentDirectory(path)
      if (await this.generateNativeThumbnail(this.resolveFilePath(videoUri), path)) {
        logger.warn('系统取帧失败，已使用 mpv 软件解码封面: %{public}s, err=%{public}s',
          this.shorten(fileName), systemError)
        return fileUri.getUriFromPath(path)
      }
      logger.warn('本地视频封面生成失败: %{public}s, systemErr=%{public}s',
        this.shorten(fileName), systemError)
      return ''
    } finally {
      if (pixelMap !== null) {
        try {
          await pixelMap.release()
        } catch (_err) {
        }
      }
      if (extractor !== null) {
        try {
          await extractor.release()
        } catch (_err) {
        }
      }
      if (imageGenerator !== null) {
        try {
          await imageGenerator.release()
        } catch (_err) {
        }
      }
      if (videoFile !== null) {
        try {
          fs.closeSync(videoFile)
        } catch (_err) {
        }
      }
    }
  }

  /**
   * Creates a stable random cover for folder and library views. The timestamp is
   * derived from the file identity, so re-entering a folder keeps the same cover
   * while avoiding the usually unrepresentative opening frame.
   */
  async ensureRandomThumbnail(videoUri: string, fileName: string, fileSize: number): Promise<string> {
    if (videoUri.length === 0) {
      return ''
    }
    const failureKey = this.getFailureKey(videoUri, fileName, fileSize)
    if (this.isSuspended(videoUri)) {
      return ''
    }
    const cachedFrameTimeMs: number | undefined = this.randomFrameTimeCache.get(failureKey)
    if (cachedFrameTimeMs !== undefined) {
      const cachedPath = this.getCachePath(videoUri, fileName, fileSize, cachedFrameTimeMs)
      if (this.isValidCacheFile(cachedPath)) {
        return fileUri.getUriFromPath(cachedPath)
      }
    }
    const taskKey = `random|${failureKey}`
    if (this.isInFailureBackoff(failureKey)) {
      return ''
    }
    const pendingTask: Promise<string> | undefined = this.pendingTasks.get(taskKey)
    if (pendingTask !== undefined) {
      return pendingTask
    }

    const task: Promise<string> = this.mediaTaskQueue.then(async (): Promise<string> => {
      if (this.isSuspended(videoUri)) {
        return ''
      }
      let durationMs: number | undefined = this.durationCache.get(failureKey)
      if (durationMs === undefined) {
        durationMs = await this.readDurationMs(videoUri)
        this.durationCache.set(failureKey, durationMs)
      }
      let frameTimeMs: number | undefined = this.randomFrameTimeCache.get(failureKey)
      if (frameTimeMs === undefined) {
        frameTimeMs = this.getStableRandomFrameTime(videoUri, fileName, fileSize, durationMs)
        this.randomFrameTimeCache.set(failureKey, frameTimeMs)
      }
      return this.generateThumbnail(videoUri, fileName, fileSize, frameTimeMs)
    })
    this.mediaTaskQueue = task.then((): void => {}, (): void => {})
    this.trackPendingTask(taskKey, failureKey, task)
    return task
  }

  private trackPendingTask(taskKey: string, failureKey: string, task: Promise<string>): void {
    this.pendingTasks.set(taskKey, task)
    task.then((coverUri: string): void => {
      this.pendingTasks.delete(taskKey)
      if (coverUri.length > 0) {
        this.failedUntil.delete(failureKey)
      } else {
        this.failedUntil.set(failureKey, Date.now() + LocalVideoThumbnailStore.FAILURE_RETRY_DELAY_MS)
      }
    }, (): void => {
      this.pendingTasks.delete(taskKey)
      this.failedUntil.set(failureKey, Date.now() + LocalVideoThumbnailStore.FAILURE_RETRY_DELAY_MS)
    })
  }

  private isInFailureBackoff(failureKey: string): boolean {
    const retryAt: number | undefined = this.failedUntil.get(failureKey)
    if (retryAt === undefined) {
      return false
    }
    if (Date.now() >= retryAt) {
      this.failedUntil.delete(failureKey)
      return false
    }
    return true
  }

  private getFailureKey(videoUri: string, fileName: string, fileSize: number): string {
    return `${videoUri}|${fileName}|${fileSize}`
  }

  private isValidCacheFile(path: string): boolean {
    try {
      if (!fs.accessSync(path)) {
        return false
      }
      const stat = fs.statSync(path)
      return stat.size > 100
    } catch (_err) {
      return false
    }
  }

  /** Prefer the actual nearest frame. A separate image generator handles failures. */
  private async fetchPreviewFrame(extractor: media.AVMetadataExtractor,
    frameTimeMs: number): Promise<image.PixelMap> {
    return extractor.fetchFrameByTime(
      frameTimeMs * 1000,
      media.AVImageQueryOptions.AV_IMAGE_QUERY_CLOSEST,
      { width: 540, height: 304 }
    )
  }

  /** Kazumi-compatible fallback for MP4 files whose random seek is rejected. */
  private async fetchGeneratorFallbackFrame(generator: media.AVImageGenerator): Promise<image.PixelMap> {
    const queryTimesUs: number[] = [1000000, 0]
    const queryOptions: media.AVImageQueryOptions[] = [
      media.AVImageQueryOptions.AV_IMAGE_QUERY_CLOSEST_SYNC,
      media.AVImageQueryOptions.AV_IMAGE_QUERY_NEXT_SYNC
    ]
    let lastError: string = ''
    for (let i = 0; i < queryTimesUs.length; i++) {
      try {
        return await generator.fetchFrameByTime(
          queryTimesUs[i],
          queryOptions[i],
          { width: 540, height: 304 }
        )
      } catch (err) {
        lastError = err instanceof Error ? err.message : String(err)
      }
    }
    throw new Error(lastError.length > 0 ? lastError : 'FetchFrameByTime failed')
  }

  private async readDurationMs(videoUri: string): Promise<number> {
    if (this.isSuspended(videoUri)) {
      return 0
    }
    let videoFile: fs.File | null = null
    let extractor: media.AVMetadataExtractor | null = null
    try {
      const sourcePath = this.resolveFilePath(videoUri)
      videoFile = fs.openSync(sourcePath, fs.OpenMode.READ_ONLY)
      extractor = await media.createAVMetadataExtractor()
      extractor.fdSrc = {
        fd: videoFile.fd,
        offset: 0,
        length: this.getFileLength(sourcePath)
      }
      const metadata = await extractor.fetchMetadata()
      const durationMs = Number(metadata.duration)
      return Number.isFinite(durationMs) && durationMs > 0 ? Math.floor(durationMs) : 0
    } catch (err) {
      logger.warn('读取本地视频时长失败: %{public}s, err=%{public}s',
        this.shorten(videoUri), err instanceof Error ? err.message : String(err))
      return 0
    } finally {
      if (extractor !== null) {
        try {
          await extractor.release()
        } catch (_err) {
        }
      }
      if (videoFile !== null) {
        try {
          fs.closeSync(videoFile)
        } catch (_err) {
        }
      }
    }
  }

  private getStableRandomFrameTime(videoUri: string, fileName: string, fileSize: number, durationMs: number): number {
    if (durationMs <= 0) {
      // Metadata may be absent for a few containers. Keep a non-zero, stable
      // fallback instead of silently regressing to the opening frame.
      return 3000 + this.hashNumber(`${videoUri}|${fileName}|${fileSize}`) % 12000
    }
    const lowerBound = Math.min(LocalVideoThumbnailStore.RANDOM_FRAME_EDGE_GUARD_MS,
      Math.floor(durationMs * LocalVideoThumbnailStore.RANDOM_FRAME_MIN_RATIO))
    const upperBound = Math.max(lowerBound, Math.min(durationMs - 1,
      Math.floor(durationMs * LocalVideoThumbnailStore.RANDOM_FRAME_MAX_RATIO)))
    if (upperBound <= lowerBound) {
      return Math.max(1, Math.floor(durationMs / 2))
    }
    const range = upperBound - lowerBound + 1
    return lowerBound + this.hashNumber(`${videoUri}|${fileName}|${fileSize}`) % range
  }

  private writeBinary(path: string, data: ArrayBuffer): void {
    this.ensureParentDirectory(path)
    const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.WRITE_ONLY)
    try {
      fs.writeSync(file.fd, data)
    } finally {
      fs.closeSync(file)
    }
  }

  private ensureParentDirectory(path: string): void {
    const dirPath = path.substring(0, path.lastIndexOf('/'))
    if (!this.pathExists(dirPath)) {
      fs.mkdirSync(dirPath, true)
    }
  }

  /** Uses bundled mpv's software decoder when the system metadata service rejects a playable MP4. */
  private async generateNativeThumbnail(sourcePath: string, outputPath: string): Promise<boolean> {
    const api = mpvNapi as NativeVideoThumbnailApi
    if (api.nativeGenerateVideoThumbnail === undefined) {
      logger.warn('当前安装包未包含 mpv 封面生成接口')
      return false
    }
    return new Promise<boolean>((resolve: (value: boolean) => void): void => {
      const result = api.nativeGenerateVideoThumbnail(sourcePath, outputPath,
        (update: NativeVideoThumbnailUpdate): void => {
          if (!update.success) {
            logger.warn('mpv 软件解码封面失败: code=%{public}d message=%{public}s',
              update.errorCode, update.message)
          }
          resolve(update.success && this.isValidCacheFile(outputPath))
        })
      if (result < 0) {
        logger.warn('启动 mpv 软件解码封面失败: %{public}d', result)
        resolve(false)
      }
    })
  }

  private pathExists(path: string): boolean {
    try {
      return fs.accessSync(path)
    } catch (_err) {
      return false
    }
  }

  private getFileLength(videoUri: string): number {
    const stat = fs.statSync(videoUri)
    const length = Number(stat.size)
    if (!Number.isFinite(length) || length <= 0) {
      throw new Error('视频文件大小无效')
    }
    return length
  }

  private isSuspended(pathOrUri: string): boolean {
    return this.suspendedPaths.has(this.resolveFilePath(pathOrUri))
  }

  /** Own Download files are already authorized as paths; avoid DataShare URI opens. */
  private resolveFilePath(pathOrUri: string): string {
    if (!pathOrUri.startsWith('file://')) {
      return pathOrUri
    }
    try {
      return new fileUri.FileUri(pathOrUri).path
    } catch (_err) {
      return pathOrUri
    }
  }

  private getCachePath(videoUri: string, fileName: string, fileSize: number, frameTimeMs: number): string {
    const cacheDir = FileStore.getInstance().getCacheDir()
    const key = `${videoUri}|${fileName}|${fileSize}|${frameTimeMs}`
    return `${cacheDir}/${this.cacheDirName}/${this.hashKey(key)}.jpg`
  }

  private hashKey(value: string): string {
    return this.hashNumber(value).toString(16)
  }

  private hashNumber(value: string): number {
    let hash = 5381
    for (let i = 0; i < value.length; i++) {
      hash = ((hash << 5) + hash + value.charCodeAt(i)) & 0x7fffffff
    }
    return hash
  }

  private shorten(value: string): string {
    return value.length > 80 ? value.substring(0, 80) : value
  }
}
