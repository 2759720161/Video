import type { PlaybackVariant } from '../../core/playback/PlaybackVariant'

export class EmbyServerConfig {
  baseUrl: string = ''
  serverId: string = ''
  serverName: string = ''
  serverVersion: string = ''
  userId: string = ''
  userName: string = ''
  accessToken: string = ''
  deviceId: string = ''

  copy(): EmbyServerConfig {
    const config = new EmbyServerConfig()
    config.baseUrl = this.baseUrl
    config.serverId = this.serverId
    config.serverName = this.serverName
    config.serverVersion = this.serverVersion
    config.userId = this.userId
    config.userName = this.userName
    config.accessToken = this.accessToken
    config.deviceId = this.deviceId
    return config
  }

  isValid(): boolean {
    return this.baseUrl.length > 0 && this.userId.length > 0 && this.accessToken.length > 0
  }
}

export class EmbyUserData {
  playbackPositionTicks: number = 0
  playedPercentage: number = 0
  played: boolean = false
}

export class EmbyItem {
  id: string = ''
  name: string = ''
  type: string = ''
  parentId: string = ''
  collectionType: string = ''
  isFolder: boolean = false
  runTimeTicks: number = 0
  productionYear: number = 0
  indexNumber: number = 0
  parentIndexNumber: number = 0
  seriesName: string = ''
  overview: string = ''
  imageItemId: string = ''
  primaryImageTag: string = ''
  backdropImageTag: string = ''
  backdropItemId: string = ''
  thumbnailImageTag: string = ''
  thumbnailItemId: string = ''
  /** PlaybackInfo 返回的可选线路；详情页加载后写入，列表响应通常为空。 */
  variants: PlaybackVariant[] = []
  /** 当前选择的线路；空值表示交给播放策略自动选择。 */
  variantId: string = ''
  container: string = ''
  userData: EmbyUserData = new EmbyUserData()

  durationMs(): number {
    return Number.isFinite(this.runTimeTicks) && this.runTimeTicks > 0 ?
      Math.floor(this.runTimeTicks / 10000) : 0
  }

  resumePositionMs(): number {
    const positionMs = Number.isFinite(this.userData.playbackPositionTicks) && this.userData.playbackPositionTicks > 0 ?
      Math.floor(this.userData.playbackPositionTicks / 10000) : 0
    const durationMs = this.durationMs()
    return durationMs > 0 ? Math.min(positionMs, durationMs) : positionMs
  }

  subtitle(): string {
    if (this.type === 'Episode') {
      const episode = this.indexNumber > 0 ? '第 ' + this.indexNumber + ' 集' : '单集'
      return this.seriesName.length > 0 ? this.seriesName + ' · ' + episode : episode
    }
    if (this.type === 'Season' && this.indexNumber > 0) {
      return '第 ' + this.indexNumber + ' 季'
    }
    if (this.productionYear > 0) {
      return String(this.productionYear)
    }
    return EmbyItem.typeLabel(this.type)
  }

  static typeLabel(type: string): string {
    switch (type) {
      case 'Movie': return '电影'
      case 'Series': return '剧集'
      case 'Season': return '季'
      case 'Episode': return '单集'
      case 'Video': return '视频'
      case 'CollectionFolder': return '媒体库'
      case 'BoxSet': return '合集'
      case 'Folder': return '文件夹'
      default: return type.length > 0 ? type : '媒体'
    }
  }
}

export class EmbyPlaybackContext {
  itemId: string = ''
  mediaSourceId: string = ''
  playSessionId: string = ''
  playMethod: string = 'DirectStream'

  encode(): string {
    return JSON.stringify(this)
  }

  static decode(raw: string): EmbyPlaybackContext | null {
    if (typeof raw !== 'string' || raw.length === 0) {
      return null
    }
    try {
      const parsed = JSON.parse(raw) as Object
      if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) return null
      const value = parsed as Record<string, Object>
      const context = new EmbyPlaybackContext()
      context.itemId = typeof value['itemId'] === 'string' ? (value['itemId'] as string).trim() : ''
      context.mediaSourceId = typeof value['mediaSourceId'] === 'string' ? (value['mediaSourceId'] as string).trim() : ''
      context.playSessionId = typeof value['playSessionId'] === 'string' ? (value['playSessionId'] as string).trim() : ''
      context.playMethod = typeof value['playMethod'] === 'string' ? (value['playMethod'] as string).trim() : 'DirectStream'
      if (context.playMethod.length === 0) context.playMethod = 'DirectStream'
      return context.itemId.length > 0 ? context : null
    } catch (_err) {
      return null
    }
  }
}

export class EmbyPlaybackRoute {
  url: string = ''
  context: EmbyPlaybackContext = new EmbyPlaybackContext()
  mediaSourceId: string = ''
  playSessionId: string = ''
  playMethod: string = 'DirectStream'
  requiredHttpHeaders: Record<string, string> = {}
}
