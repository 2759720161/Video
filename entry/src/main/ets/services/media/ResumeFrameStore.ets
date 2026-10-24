import { common } from '@kit.AbilityKit'
import { image } from '@kit.ImageKit'
import { cryptoFramework } from '@kit.CryptoArchitectureKit'
import { util } from '@kit.ArkTS'
import { fileIo, fileUri } from '@kit.CoreFileKit'
import { PlaybackHistoryChangeSignal } from '../../store/PlaybackHistoryChangeSignal'
import { Logger } from '../../utils/Logger'
import { deviceInfo } from '@kit.BasicServicesKit'

class ResumeFrameMetadata {
  filename: string = ''
  positionMs: number = 0
  updatedAt: number = 0
}

const logger = new Logger('ResumeFrame')

/** Private, bounded exit-frame cache, independent of provider artwork and progress reporting. */
export class ResumeFrameStore {
  private static sequence: number = 0
  private static latest: Map<string, number> = new Map()

  static async resolve(context: common.Context, sourceId: string, mediaId: string, positionMs: number): Promise<string> {
    if (!sourceId || !mediaId || !Number.isFinite(positionMs) || positionMs <= 0) return ''
    try {
      const root = context.filesDir + '/resume_frames'
      const key = await ResumeFrameStore.key(sourceId, mediaId)
      const metadata = ResumeFrameStore.read(root + '/' + key + '.json')
      if (metadata === null || Math.abs(metadata.positionMs - positionMs) > 15000 ||
        !metadata.filename.startsWith(key + '-') || !fileIo.accessSync(root + '/' + metadata.filename)) return ''
      return fileUri.getUriFromPath(root + '/' + metadata.filename)
    } catch (_) { return '' }
  }

  /** The first surface read is synchronous, before the caller releases/stops its player. */
  static async capture(context: common.Context, sourceId: string, mediaId: string,
    surfaceId: string, positionMs: number): Promise<void> {
    if (!sourceId || !mediaId || !surfaceId || !Number.isFinite(positionMs) || positionMs <= 0) return
    const identity = JSON.stringify([sourceId, mediaId])
    const ticket = ++ResumeFrameStore.sequence
    ResumeFrameStore.latest.set(identity, ticket)
    let pixel: image.PixelMap | null = null
    let packer: image.ImagePacker | null = null
    try {
      pixel = deviceInfo.sdkApiVersion >= 23 ? image.createPixelMapFromSurfaceWithTransformationSync(surfaceId, true) :
        image.createPixelMapFromSurfaceSync(surfaceId)
      const size = pixel.getImageInfoSync().size
      if (size.width <= 0 || size.height <= 0) return
      const scale = Math.min(1, 640 / Math.max(size.width, size.height))
      if (scale < 1) await pixel.scale(scale, scale)
      packer = image.createImagePacker()
      const bytes = await packer.packToData(pixel, { format: 'image/jpeg', quality: 82 })
      const key = await ResumeFrameStore.key(sourceId, mediaId)
      if (ResumeFrameStore.latest.get(identity) !== ticket || bytes.byteLength === 0) return
      const root = context.filesDir + '/resume_frames'
      if (!fileIo.accessSync(root)) fileIo.mkdirSync(root, true)
      const old = ResumeFrameStore.read(root + '/' + key + '.json')
      const metadata = new ResumeFrameMetadata()
      metadata.updatedAt = Date.now(); metadata.positionMs = Math.floor(positionMs)
      metadata.filename = key + '-' + metadata.updatedAt + '-' + ticket + '.jpg'
      let published = false
      try {
        ResumeFrameStore.write(root + '/' + metadata.filename, bytes)
        const temporary = root + '/' + key + '.pending'
        ResumeFrameStore.write(temporary, new util.TextEncoder('utf-8').encodeInto(JSON.stringify(metadata)).buffer as ArrayBuffer)
        fileIo.renameSync(temporary, root + '/' + key + '.json')
        published = true
      } finally {
        if (!published) ResumeFrameStore.remove(root + '/' + metadata.filename)
        ResumeFrameStore.remove(root + '/' + key + '.pending')
      }
      if (old !== null) ResumeFrameStore.remove(root + '/' + old.filename)
      ResumeFrameStore.trim(root)
      PlaybackHistoryChangeSignal.notifyChanged()
      logger.info('saved positionMs=%{public}d', metadata.positionMs)
    } catch (_) { logger.warn('capture_unavailable; keeping provider artwork') }
    finally {
      if (packer !== null) { try { await packer.release() } catch (_) {} }
      if (pixel !== null) { try { await pixel.release() } catch (_) {} }
      if (ResumeFrameStore.latest.get(identity) === ticket) ResumeFrameStore.latest.delete(identity)
    }
  }

  private static async key(sourceId: string, mediaId: string): Promise<string> {
    const digest = cryptoFramework.createMd('SHA256')
    await digest.update({ data: new util.TextEncoder('utf-8').encodeInto(JSON.stringify([sourceId, mediaId])) })
    const bytes = (await digest.digest()).data
    let key = ''
    for (let i = 0; i < bytes.length; i++) key += bytes[i].toString(16).padStart(2, '0')
    return key
  }
  private static read(path: string): ResumeFrameMetadata | null {
    try {
      const data = JSON.parse(fileIo.readTextSync(path, { encoding: 'utf-8' })) as ResumeFrameMetadata
      return typeof data.filename === 'string' && /^[0-9a-f]{64}-\d+-\d+\.jpg$/.test(data.filename) &&
        Number.isFinite(data.positionMs) && data.positionMs > 0 && Number.isFinite(data.updatedAt) ? data : null
    } catch (_) { return null }
  }
  private static write(path: string, data: ArrayBuffer): void {
    const file = fileIo.openSync(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC)
    try { if (fileIo.writeSync(file.fd, data) !== data.byteLength) throw new Error('Incomplete frame write') }
    finally { fileIo.closeSync(file) }
  }
  private static remove(path: string): void { try { fileIo.unlinkSync(path) } catch (_) {} }
  private static trim(root: string): void {
    try {
      const names = fileIo.listFileSync(root).filter((name: string) => /^[0-9a-f]{64}\.json$/.test(name))
      names.sort((left: string, right: string) =>
        (ResumeFrameStore.read(root + '/' + right)?.updatedAt ?? 0) - (ResumeFrameStore.read(root + '/' + left)?.updatedAt ?? 0))
      for (let i = 64; i < names.length; i++) {
        const metadata = ResumeFrameStore.read(root + '/' + names[i])
        if (metadata !== null) ResumeFrameStore.remove(root + '/' + metadata.filename)
        ResumeFrameStore.remove(root + '/' + names[i])
      }
    } catch (_) {}
  }
}
