/**
 * Artwork 的稳定引用。它只描述来源和媒体身份，不包含 token、Cookie 或临时 URL。
 * 该值可以安全地放进播放历史和队列快照；实际 URL 由 Provider 在运行时生成。
 */
export class ArtworkRef {
  sourceId: string = ''
  mediaId: string = ''
  imageTag: string = ''
  imageType: string = 'Primary'

  encode(): string {
    const source = ArtworkRef.encodePart(this.sourceId)
    const media = ArtworkRef.encodePart(this.mediaId)
    const tag = ArtworkRef.encodePart(this.imageTag)
    const type = ArtworkRef.encodePart(this.imageType.length > 0 ? this.imageType : 'Primary')
    if (source.length === 0 || media.length === 0) return ''
    return 'artwork:v1:' + source + ':' + media + ':' + type + ':' + tag
  }

  static fromMedia(sourceId: string, mediaId: string, imageTag: string = '', imageType: string = 'Primary'): string {
    const ref = new ArtworkRef()
    ref.sourceId = ArtworkRef.normalize(sourceId)
    ref.mediaId = ArtworkRef.normalize(mediaId)
    ref.imageTag = ArtworkRef.normalize(imageTag)
    ref.imageType = ArtworkRef.normalize(imageType)
    return ref.encode()
  }

  static decode(value: string): ArtworkRef | null {
    const raw = ArtworkRef.normalize(value)
    const parts = raw.split(':')
    if (parts.length !== 6 || parts[0] !== 'artwork' || parts[1] !== 'v1') return null
    const ref = new ArtworkRef()
    ref.sourceId = ArtworkRef.decodePart(parts[2])
    ref.mediaId = ArtworkRef.decodePart(parts[3])
    ref.imageType = ArtworkRef.decodePart(parts[4])
    ref.imageTag = ArtworkRef.decodePart(parts[5])
    return ref.sourceId.length > 0 && ref.mediaId.length > 0 ? ref : null
  }

  private static encodePart(value: string): string {
    return encodeURIComponent(ArtworkRef.normalize(value))
  }

  private static decodePart(value: string): string {
    try {
      const decoded = decodeURIComponent(value)
      return ArtworkRef.normalize(decoded)
    } catch (_) {
      return ''
    }
  }

  private static normalize(value: string): string {
    return typeof value === 'string' ? value.trim() : ''
  }
}
