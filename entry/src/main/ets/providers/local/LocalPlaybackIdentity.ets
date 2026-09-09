import { LocalVideoRecord } from '../../models/LocalVideoRecord'

/** 本地公共队列使用的稳定身份；文件 URI 只留在 Local Provider 内部。 */
export class LocalPlaybackIdentity {
  static fromRecord(record: LocalVideoRecord): string {
    const fileUri = LocalPlaybackIdentity.normalizeText(record.fileUri)
    const storedKey = LocalPlaybackIdentity.normalizeText(record.fileKey)
    const fileName = LocalPlaybackIdentity.safeText(record.fileName)
    const fileSize = LocalPlaybackIdentity.safeNumber(record.fileSize)
    const durationMs = LocalPlaybackIdentity.safeNumber(record.durationMs)
    if (fileUri.length === 0 && storedKey.startsWith('local_')) return storedKey
    const seed = fileUri.length > 0
      ? fileUri + '\u0000' + String(fileSize) + '\u0000' + fileName
      : storedKey.length > 0 ? storedKey : fileName + '\u0000' + String(fileSize) +
        '\u0000' + String(durationMs)
    return 'local_' + String(seed.length) + '_' + String(LocalPlaybackIdentity.hash(seed))
  }

  private static hash(value: string): number {
    let hash = 5381
    for (let i = 0; i < value.length; i++) {
      hash = ((hash << 5) + hash + value.charCodeAt(i)) & 0x7fffffff
    }
    return hash
  }

  private static normalizeText(value: string): string {
    return typeof value === 'string' ? value.trim() : ''
  }

  private static safeText(value: string): string {
    return typeof value === 'string' ? value : ''
  }

  private static safeNumber(value: number): number {
    return typeof value === 'number' && Number.isFinite(value) && value >= 0 ? Math.floor(value) : 0
  }
}
