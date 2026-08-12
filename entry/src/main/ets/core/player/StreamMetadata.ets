export class VariantStreamMetadata {
  uri: string = ''
  bandwidth: number = 0
  width: number = 0
  height: number = 0
  codecs: string[] = []
}

export class HlsKeyMetadata {
  method: string = ''
  uri: string = ''
  iv: string = ''
}

export class HlsSegmentMetadata {
  uri: string = ''
  duration: number = 0
  discontinuityGroup: number = 0
  key: HlsKeyMetadata | null = null
  likelyAd: boolean = false
}

export class StreamMetadata {
  sourceType: string = ''
  isHls: boolean = false
  isMasterPlaylist: boolean = false
  variants: VariantStreamMetadata[] = []
  segments: HlsSegmentMetadata[] = []
  codecs: string[] = []
  maxWidth: number = 0
  maxHeight: number = 0
  minBandwidth: number = 0
  maxBandwidth: number = 0
  targetDuration: number = 0
  totalDuration: number = 0
  isVod: boolean = false
  hasEncryptedSegments: boolean = false
  uniqueKeyUris: string[] = []
  discontinuityGroupCount: number = 0
  likelyAdSegmentCount: number = 0
  likelyAdDuration: number = 0
  hasAacAudio: boolean = false
  hasHevcVideo: boolean = false
  hasDolbyVision: boolean = false
  hasHdrCodecHint: boolean = false
  warnings: string[] = []

  isEmpty(): boolean {
    return !this.isHls && this.variants.length === 0 && this.segments.length === 0 && this.codecs.length === 0
  }

  summary(): string {
    const parts: string[] = []
    if (this.isHls) {
      parts.push(this.isMasterPlaylist ? 'hls-master' : 'hls-media')
    }
    if (this.maxWidth > 0 && this.maxHeight > 0) {
      parts.push(String(this.maxWidth) + 'x' + String(this.maxHeight))
    }
    if (this.maxBandwidth > 0) {
      parts.push('bw=' + String(this.maxBandwidth))
    }
    if (this.segments.length > 0) {
      parts.push('segments=' + String(this.segments.length))
    }
    if (this.totalDuration > 0) {
      parts.push('duration=' + String(Math.round(this.totalDuration)) + 's')
    }
    if (this.uniqueKeyUris.length > 0) {
      parts.push('keys=' + String(this.uniqueKeyUris.length))
    }
    if (this.likelyAdSegmentCount > 0) {
      parts.push('adSegments=' + String(this.likelyAdSegmentCount))
    }
    if (this.codecs.length > 0) {
      parts.push('codecs=' + this.codecs.join('|'))
    }
    if (this.warnings.length > 0) {
      parts.push('warnings=' + this.warnings.join('|'))
    }
    return parts.join(' ')
  }
}
