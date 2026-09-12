import { http } from '@kit.NetworkKit'
import {
  EmbyItem,
  EmbyItemsPage,
  EmbyPlaybackContext,
  EmbyPlaybackRoute,
  EmbyServerConfig
} from './EmbyModels'
import { EmbyMediaSource, EmbyPlaybackInfo } from './EmbyPlaybackInfo'
import { EmbyPlaybackMode, EmbyPlaybackPolicy } from './EmbyPlaybackPolicy'
import { PlaybackVariant } from '../../core/playback/PlaybackVariant'
import { EmbyLibraryPresentation } from './EmbyLibraryPresentation'

const EMBY_CLIENT_NAME: string = 'Yingxia'
const EMBY_DEVICE_NAME: string = 'HarmonyOS'
const EMBY_CLIENT_VERSION: string = '1.0.0'

export class EmbyClient {
  private config: EmbyServerConfig
  private playbackInfoCache: Record<string, EmbyPlaybackInfo | null> = {}

  constructor(config: EmbyServerConfig) {
    this.config = config
  }

  static async login(serverUrl: string, userName: string, password: string,
    existingDeviceId: string = ''): Promise<EmbyServerConfig> {
    const config = new EmbyServerConfig()
    config.baseUrl = EmbyClient.normalizeBaseUrl(serverUrl)
    const normalizedDeviceId = EmbyClient.normalizeText(existingDeviceId)
    const normalizedUserName = EmbyClient.normalizeText(userName)
    config.deviceId = normalizedDeviceId.length > 0 ? normalizedDeviceId : EmbyClient.createDeviceId()
    const client = new EmbyClient(config)
    const publicInfo = await client.requestObject('/System/Info/Public', http.RequestMethod.GET, null, false)
    const body: Record<string, Object> = {
      'Username': normalizedUserName,
      'Pw': password
    }
    const auth = await client.requestObject('/Users/AuthenticateByName', http.RequestMethod.POST, body, false)
    const user = EmbyClient.readObject(auth, 'User')
    config.serverId = EmbyClient.readString(auth, 'ServerId', EmbyClient.readString(publicInfo, 'Id'))
    config.serverName = EmbyClient.readString(publicInfo, 'ServerName')
    config.serverVersion = EmbyClient.readString(publicInfo, 'Version')
    config.userId = EmbyClient.readString(user, 'Id')
    config.userName = EmbyClient.readString(user, 'Name', normalizedUserName)
    config.accessToken = EmbyClient.readString(auth, 'AccessToken')
    if (!config.isValid()) {
      throw new Error('Emby 登录响应缺少用户或令牌信息')
    }
    return config
  }

  async getLibraries(): Promise<EmbyItem[]> {
    const path = '/Users/' + encodeURIComponent(this.config.userId) + '/Views?IncludeExternalContent=false'
    const response = await this.requestObject(path, http.RequestMethod.GET)
    return this.parseItems(response)
  }

  async getItem(itemId: string): Promise<EmbyItem | null> {
    const normalizedItemId = EmbyClient.normalizeText(itemId)
    if (normalizedItemId.length === 0) return null
    const path = '/Users/' + encodeURIComponent(this.config.userId) + '/Items/' + encodeURIComponent(normalizedItemId) +
      '?Fields=Overview%2CPrimaryImageAspectRatio%2CParentId%2CSeriesId%2CSeasonId%2CBackdropImageTags' +
      '%2CChildCount%2CRecursiveItemCount&EnableImages=true&EnableUserData=true'
    const value = await this.requestObject(path, http.RequestMethod.GET)
    const items = this.parseItems({ 'Items': [value] })
    return items.length === 0 ? null : items[0]
  }

  async searchItems(keyword: string, limit: number = 50): Promise<EmbyItem[]> {
    const query = '/Users/' + encodeURIComponent(this.config.userId) + '/Items?SearchTerm=' +
      encodeURIComponent(EmbyClient.normalizeText(keyword)) + '&Recursive=true&Limit=' + Math.max(1, limit) +
      '&Fields=Overview%2CPrimaryImageAspectRatio%2CParentId%2CSeriesId%2CSeasonId%2CBackdropImageTags' +
      '&EnableImages=true&EnableUserData=true'
    return this.parseItems(await this.requestObject(query, http.RequestMethod.GET))
  }

  async getItems(parentId: string, limit: number = 0, recursive: boolean = false,
    itemTypes: string = '', sortBy: string = 'SortName', sortOrder: string = 'Ascending'): Promise<EmbyItem[]> {
    const normalizedParentId = EmbyClient.normalizeText(parentId)
    const query: string[] = [
      'ParentId=' + encodeURIComponent(normalizedParentId),
      'Recursive=' + (recursive ? 'true' : 'false'),
      'SortBy=' + encodeURIComponent(sortBy),
      'SortOrder=' + encodeURIComponent(sortOrder),
      'Fields=Overview%2CPrimaryImageAspectRatio%2CParentId%2CSeriesId%2CSeasonId%2CBackdropImageTags%2CChildCount%2CRecursiveItemCount',
      'EnableImages=true',
      'EnableUserData=true',
      'ImageTypeLimit=1'
    ]
    const normalizedItemTypes = EmbyClient.normalizeText(itemTypes)
    if (normalizedItemTypes.length > 0) {
      query.push('IncludeItemTypes=' + encodeURIComponent(normalizedItemTypes))
    }
    if (limit > 0) {
      query.push('Limit=' + limit)
    }
    const path = '/Users/' + encodeURIComponent(this.config.userId) + '/Items?' + query.join('&')
    const response = await this.requestObject(path, http.RequestMethod.GET)
    return this.parseItems(response)
  }

  /** Series metadata hierarchy; unlike getItems(), this never treats a show as a physical folder. */
  async getSeriesSeasons(seriesId: string): Promise<EmbyItem[]> {
    const normalizedSeriesId = EmbyClient.normalizeText(seriesId)
    if (normalizedSeriesId.length === 0) return []
    const query: string[] = [
      'UserId=' + encodeURIComponent(this.config.userId),
      'Fields=Overview%2CPrimaryImageAspectRatio%2CParentId%2CSeriesId%2CSeasonId%2CBackdropImageTags%2CChildCount%2CRecursiveItemCount',
      'EnableImages=true',
      'EnableUserData=true'
    ]
    const path = '/Shows/' + encodeURIComponent(normalizedSeriesId) + '/Seasons?' + query.join('&')
    return this.parseItems(await this.requestObject(path, http.RequestMethod.GET))
  }

  /** Loads episodes for one selected season through Emby's show-aware endpoint. */
  async getSeasonEpisodes(seriesId: string, seasonId: string): Promise<EmbyItem[]> {
    return (await this.getSeasonEpisodesPage(seriesId, seasonId)).items
  }

  /** Server-paged episode query for large seasons. A zero limit returns the full season. */
  async getSeasonEpisodesPage(seriesId: string, seasonId: string,
    startIndex: number = 0, limit: number = 0): Promise<EmbyItemsPage> {
    const normalizedSeriesId = EmbyClient.normalizeText(seriesId)
    const normalizedSeasonId = EmbyClient.normalizeText(seasonId)
    const emptyPage = new EmbyItemsPage()
    if (normalizedSeasonId.length === 0) return emptyPage
    const normalizedStart = Math.max(0, Math.floor(startIndex))
    // Older servers may omit SeriesId on a Season response. Preserve correct
    // behavior with a non-recursive fallback while keeping the normal path semantic.
    if (normalizedSeriesId.length === 0) {
      const fallbackItems = await this.getItems(normalizedSeasonId)
      emptyPage.totalRecordCount = fallbackItems.length
      emptyPage.startIndex = normalizedStart
      emptyPage.items = limit > 0 ? fallbackItems.slice(normalizedStart, normalizedStart + limit) : fallbackItems
      return emptyPage
    }
    const query: string[] = [
      'UserId=' + encodeURIComponent(this.config.userId),
      'SeasonId=' + encodeURIComponent(normalizedSeasonId),
      'Fields=Overview%2CPrimaryImageAspectRatio%2CParentId%2CSeriesId%2CSeasonId%2CBackdropImageTags',
      'EnableImages=true',
      'EnableUserData=true',
      'EnableTotalRecordCount=true',
      'SortBy=IndexNumber',
      'SortOrder=Ascending'
    ]
    if (normalizedStart > 0) query.push('StartIndex=' + normalizedStart)
    if (limit > 0) query.push('Limit=' + Math.max(1, Math.floor(limit)))
    const path = '/Shows/' + encodeURIComponent(normalizedSeriesId) + '/Episodes?' + query.join('&')
    const response = await this.requestObject(path, http.RequestMethod.GET)
    const page = new EmbyItemsPage()
    page.items = this.parseItems(response)
    page.totalRecordCount = Math.max(normalizedStart + page.items.length,
      Math.floor(EmbyClient.readNumber(response, 'TotalRecordCount')))
    page.startIndex = normalizedStart
    return page
  }

  /** Physical directory traversal used only by the explicit folder-browse mode. */
  async getFolderChildren(parentId: string): Promise<EmbyItem[]> {
    return this.getItems(parentId, 0, false, '', 'SortName', 'Ascending')
  }

  /**
   * Query only the server-side count for a child type. Limit=1 keeps the
   * response small while TotalRecordCount still describes the full result.
   */
  async getItemCount(parentId: string, itemType: string): Promise<number> {
    const normalizedParentId = EmbyClient.normalizeText(parentId)
    const normalizedItemType = EmbyClient.normalizeText(itemType)
    if (normalizedParentId.length === 0 || normalizedItemType.length === 0) return 0
    const query = '/Users/' + encodeURIComponent(this.config.userId) + '/Items?' +
      'ParentId=' + encodeURIComponent(normalizedParentId) +
      '&Recursive=true&IncludeItemTypes=' + encodeURIComponent(normalizedItemType) +
      '&Limit=1&EnableImages=false&EnableUserData=false'
    const response = await this.requestObject(query, http.RequestMethod.GET)
    const total = EmbyClient.readNumber(response, 'TotalRecordCount')
    return Number.isFinite(total) && total > 0 ? Math.floor(total) : 0
  }

  /**
   * Returns the actual media entries inside a library instead of its immediate
   * child folders/ Series and movies are deliberately selected so a TV library
   * is rendered as newest-first poster cards rather than a second folder tree/
   */
  async getLibraryItems(parentId: string, limit: number = 0, collectionType: string = '',
    sortBy: string = 'DateCreated', sortOrder: string = 'Descending'): Promise<EmbyItem[]> {
    const itemTypes = EmbyLibraryPresentation.itemTypes(collectionType)
    return await this.getItems(parentId, limit, true, itemTypes, sortBy, sortOrder)
  }

  async getResumeItems(limit: number = 12): Promise<EmbyItem[]> {
    const query: string[] = [
      'Recursive=true',
      'MediaTypes=Video',
      'Limit=' + Math.max(1, limit),
      'Fields=Overview%2CPrimaryImageAspectRatio%2CParentId%2CSeriesId%2CSeasonId%2CBackdropImageTags',
      'EnableImages=true',
      'EnableUserData=true',
      'ImageTypeLimit=1'
    ]
    const path = '/Users/' + encodeURIComponent(this.config.userId) + '/Items/Resume?' + query.join('&')
    const response = await this.requestObject(path, http.RequestMethod.GET)
    return this.parseItems(response)
  }

  /** Resolve a show's/season's watch target independently of the visible episode page. */
  async getDetailPlaybackTarget(parentId: string): Promise<EmbyItem | null> {
    const parent = EmbyClient.normalizeText(parentId)
    if (parent.length === 0) return null
    const base = '/Users/' + encodeURIComponent(this.config.userId) + '/Items?' +
      'ParentId=' + encodeURIComponent(parent) + '&Recursive=true&IncludeItemTypes=Episode&Limit=1' +
      '&EnableUserData=true&Fields=ParentId%2CSeriesId%2CSeasonId&EnableImages=true'
    const resume = this.parseItems(await this.requestObject(base +
      '&Filters=IsResumable&IsPlayed=false&SortBy=DatePlayed&SortOrder=Descending', http.RequestMethod.GET))
    if (resume.length > 0) return resume[0]
    const unplayed = this.parseItems(await this.requestObject(base +
      '&IsPlayed=false&SortBy=ParentIndexNumber%2CIndexNumber&SortOrder=Ascending', http.RequestMethod.GET))
    if (unplayed.length > 0) return unplayed[0]
    const first = this.parseItems(await this.requestObject(base +
      '&SortBy=ParentIndexNumber%2CIndexNumber&SortOrder=Ascending', http.RequestMethod.GET))
    return first.length > 0 ? first[0] : null
  }

  async getLatestItems(limit: number = 16): Promise<EmbyItem[]> {
    const query: string[] = [
      'Recursive=true',
      'IncludeItemTypes=Movie%2CSeries%2CEpisode%2CVideo',
      'SortBy=DateCreated',
      'SortOrder=Descending',
      'Fields=Overview%2CPrimaryImageAspectRatio%2CParentId%2CSeriesId%2CSeasonId%2CBackdropImageTags',
      'EnableImages=true',
      'EnableUserData=true',
      'ImageTypeLimit=1'
    ]
    if (limit > 0) {
      query.push('Limit=' + limit)
    }
    const path = '/Users/' + encodeURIComponent(this.config.userId) + '/Items?' + query.join('&')
    const response = await this.requestObject(path, http.RequestMethod.GET)
    return this.parseItems(response)
  }

  primaryImageUrl(item: EmbyItem, maxWidth: number = 500): string {
    if (item.imageItemId.length === 0 || item.primaryImageTag.length === 0) {
      return ''
    }
    return this.config.baseUrl + '/Items/' + encodeURIComponent(item.imageItemId) + '/Images/Primary' +
      '?maxWidth=' + maxWidth + '&quality=85&tag=' + encodeURIComponent(item.primaryImageTag) +
      '&api_key=' + encodeURIComponent(this.config.accessToken)
  }

  backdropImageUrl(item: EmbyItem, maxWidth: number = 1200): string {
    if (item.backdropItemId.length === 0 || item.backdropImageTag.length === 0) return ''
    return this.config.baseUrl + '/Items/' + encodeURIComponent(item.backdropItemId) + '/Images/Backdrop' +
      '?maxWidth=' + maxWidth + '&quality=85&tag=' + encodeURIComponent(item.backdropImageTag) +
      '&api_key=' + encodeURIComponent(this.config.accessToken)
  }

  thumbnailImageUrl(item: EmbyItem, maxWidth: number = 800): string {
    if (item.thumbnailItemId.length === 0 || item.thumbnailImageTag.length === 0) return ''
    return this.config.baseUrl + '/Items/' + encodeURIComponent(item.thumbnailItemId) + '/Images/Thumb' +
      '?maxWidth=' + maxWidth + '&quality=85&tag=' + encodeURIComponent(item.thumbnailImageTag) +
      '&api_key=' + encodeURIComponent(this.config.accessToken)
  }

  /** 兼容旧调用方；新页面应按 primary/backdrop 语义选择 URL。 */
  imageUrl(item: EmbyItem, maxWidth: number = 500): string {
    return this.primaryImageUrl(item, maxWidth)
  }

  async getPlaybackVariants(item: EmbyItem): Promise<PlaybackVariant[]> {
    const path = '/Items/' + encodeURIComponent(item.id) + '/PlaybackInfo?UserId=' +
      encodeURIComponent(this.config.userId)
    const response = await this.requestObject(path, http.RequestMethod.GET)
    const info = EmbyPlaybackInfo.parse(response)
    if (info.mediaSources.length > 0) this.playbackInfoCache[item.id] = info
    const result: PlaybackVariant[] = []
    const usedIds: Record<string, boolean> = {}
    for (let i = 0; i < info.mediaSources.length; i++) {
      const source = info.mediaSources[i]
      const id = source.id.length > 0 ? source.id : 'source_' + i
      if (usedIds[id] === true) continue
      usedIds[id] = true
      const variant = new PlaybackVariant()
      variant.id = id
      variant.name = source.name.length > 0 ? source.name : (source.container.length > 0 ? source.container.toUpperCase() : '播放版本 ' + (i + 1))
      variant.quality = EmbyClient.playbackQuality(source.bitrate)
      result.push(variant)
    }
    return result
  }

  async getPlaybackRoute(item: EmbyItem, variantId: string = ''): Promise<EmbyPlaybackRoute> {
    let info = this.playbackInfoCache[item.id]
    if (info === undefined || info === null) {
      const path = '/Items/' + encodeURIComponent(item.id) + '/PlaybackInfo?UserId=' +
        encodeURIComponent(this.config.userId)
      const response = await this.requestObject(path, http.RequestMethod.GET)
      info = EmbyPlaybackInfo.parse(response)
    } else {
      this.playbackInfoCache[item.id] = null
    }
    if (info.mediaSources.length === 0) {
      throw new Error('Emby 未返回可播放的媒体源')
    }
    const playbackMode = await EmbyPlaybackPolicy.loadMode()
    let source: EmbyMediaSource | null = null
    const requestedVariantId = EmbyClient.normalizeText(variantId)
    if (requestedVariantId.length > 0) {
      for (let i = 0; i < info.mediaSources.length; i++) {
        if (info.mediaSources[i].id === requestedVariantId ||
          (info.mediaSources[i].id.length === 0 && requestedVariantId === 'source_' + i)) {
          source = info.mediaSources[i]
          break
        }
      }
    }
    if (source === null) source = EmbyPlaybackPolicy.selectSource(info.mediaSources, playbackMode)
    const mediaSourceId = source.id.length > 0 ? source.id : item.id
    const playSessionId = info.playSessionId.length > 0 ? info.playSessionId : EmbyClient.createSessionId()
    let url = ''
    let playMethod = 'DirectStream'
    // DirectPlayUrl can point at a storage path reachable by the server but
    // not by a phone. Prefer the server-mediated direct stream, which still
    // avoids transcoding while preserving the authenticated Emby route.
    if (playbackMode !== EmbyPlaybackMode.TRANSCODE && source.directStreamUrl.length > 0) {
      url = this.normalizePlaybackUrl(this.absoluteUrl(source.directStreamUrl))
      playMethod = 'DirectStream'
    }
    if (url.length === 0 && playbackMode !== EmbyPlaybackMode.TRANSCODE && source.directPlayUrl.length > 0) {
      url = this.normalizePlaybackUrl(this.absoluteUrl(source.directPlayUrl))
      playMethod = 'DirectPlay'
    }
    if (url.length === 0 && playbackMode !== EmbyPlaybackMode.DIRECT && source.transcodingUrl.length > 0) {
      url = this.normalizePlaybackUrl(this.absoluteUrl(source.transcodingUrl))
      playMethod = 'Transcode'
    }
    if (url.length === 0) {
      const container = EmbyClient.safeContainer(source.container.length > 0 ? source.container : item.container)
      // Emby's static stream endpoint uses the container as a file extension
      // (`stream.mkv`), not a path segment (`stream/mkv`). The latter is a
      // valid-looking URL but is answered with HTTP 404 by Emby.
      url = this.config.baseUrl + '/Videos/' + encodeURIComponent(item.id) + '/stream.' + container +
      '?static=true&MediaSourceId=' + encodeURIComponent(mediaSourceId) +
      '&PlaySessionId=' + encodeURIComponent(playSessionId)
      if (playbackMode === EmbyPlaybackMode.TRANSCODE) {
        playMethod = 'Transcode'
      } else if (source.supportsDirectPlay && !source.supportsDirectStream) {
        playMethod = 'DirectPlay'
      } else {
        playMethod = 'DirectStream'
      }
    }
    url = this.normalizePlaybackUrl(EmbyClient.appendQuery(url, 'api_key', this.config.accessToken))
    const route = new EmbyPlaybackRoute()
    route.url = url
    route.mediaSourceId = mediaSourceId
    route.playSessionId = playSessionId
    route.playMethod = playMethod
    route.requiredHttpHeaders = this.buildPlaybackHeaders(source.requiredHttpHeaders)
    route.context.itemId = item.id
    route.context.mediaSourceId = mediaSourceId
    route.context.playSessionId = playSessionId
    route.context.playMethod = playMethod
    return route
  }

  async reportPlayback(endpoint: string, context: EmbyPlaybackContext, positionMs: number,
    durationMs: number, playing: boolean, speed: number, eventName: string = ''): Promise<void> {
    const normalizedDurationMs = Number.isFinite(durationMs) && durationMs > 0 ? Math.floor(durationMs) : 0
    let normalizedPositionMs = Number.isFinite(positionMs) ? Math.max(0, Math.floor(positionMs)) : 0
    if (normalizedDurationMs > 0) normalizedPositionMs = Math.min(normalizedPositionMs, normalizedDurationMs)
    const normalizedSpeed = Number.isFinite(speed) && speed > 0 ? speed : 1
    const body: Record<string, Object> = {
      'QueueableMediaTypes': ['Video'],
      'CanSeek': true,
      'ItemId': context.itemId,
      'MediaSourceId': context.mediaSourceId,
      'IsPaused': !playing,
      'IsMuted': false,
      'PositionTicks': normalizedPositionMs * 10000,
      'PlayMethod': context.playMethod,
      'PlaySessionId': context.playSessionId,
      'PlaylistIndex': 0,
      'PlaylistLength': 1,
      'PlaybackRate': normalizedSpeed
    }
    if (normalizedDurationMs > 0) {
      body['RunTimeTicks'] = normalizedDurationMs * 10000
    }
    if (eventName.length > 0) {
      body['EventName'] = eventName
    }
    await this.requestObject(endpoint, http.RequestMethod.POST, body)
  }

  async logout(): Promise<void> {
    await this.requestObject('/Sessions/Logout', http.RequestMethod.POST, {})
  }

  private async requestObject(path: string, method: http.RequestMethod,
    body: Record<string, Object> | null = null, authenticated: boolean = true): Promise<Record<string, Object>> {
    const request = http.createHttp()
    try {
      const headers: Record<string, string> = {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'X-Emby-Authorization': this.authorizationHeader(authenticated)
      }
      if (authenticated && this.config.accessToken.length > 0) {
        headers['X-Emby-Token'] = this.config.accessToken
      }
      const options: http.HttpRequestOptions = {
        method: method,
        header: headers,
        connectTimeout: 15000,
        readTimeout: 30000,
        expectDataType: http.HttpDataType.STRING
      }
      if (body !== null) {
        options.extraData = JSON.stringify(body)
      }
      const response = await request.request(this.config.baseUrl + path, options)
      if (response.responseCode < 200 || response.responseCode >= 300) {
        if (response.responseCode === 401) {
          throw new Error('用户名、密码或 Emby 登录状态无效')
        }
        throw new Error('Emby 请求失败（HTTP ' + response.responseCode + '）')
      }
      const raw = typeof response.result === 'string' ? response.result : JSON.stringify(response.result)
      if (raw.length === 0) {
        return {}
      }
      const parsed: Object = JSON.parse(raw)
      if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) {
        throw new Error('Emby 响应格式无效')
      }
      return parsed as Record<string, Object>
    } finally {
      request.destroy()
    }
  }

  private authorizationHeader(authenticated: boolean): string {
    const parts: string[] = [
      'Client="' + EMBY_CLIENT_NAME + '"',
      'Device="' + EMBY_DEVICE_NAME + '"',
      'DeviceId="' + this.config.deviceId + '"',
      'Version="' + EMBY_CLIENT_VERSION + '"'
    ]
    if (authenticated && this.config.userId.length > 0) {
      parts.push('UserId="' + this.config.userId + '"')
    }
    return 'Emby ' + parts.join(', ')
  }

  private parseItems(response: Record<string, Object>): EmbyItem[] {
    const values = EmbyClient.readObjectArray(response, 'Items')
    const items: EmbyItem[] = []
    for (let i = 0; i < values.length; i++) {
      const value = values[i]
      const item = new EmbyItem()
      item.id = EmbyClient.readString(value, 'Id')
      item.name = EmbyClient.readString(value, 'Name')
      item.type = EmbyClient.readString(value, 'Type')
      item.parentId = EmbyClient.readString(value, 'ParentId')
      item.seriesId = EmbyClient.readString(value, 'SeriesId')
      item.seasonId = EmbyClient.readString(value, 'SeasonId')
      item.collectionType = EmbyClient.readString(value, 'CollectionType')
      item.isFolder = EmbyClient.readBoolean(value, 'IsFolder') || EmbyClient.isFolderType(item.type)
      item.runTimeTicks = EmbyClient.readNumber(value, 'RunTimeTicks')
      item.productionYear = EmbyClient.readNumber(value, 'ProductionYear')
      item.indexNumber = EmbyClient.readNumber(value, 'IndexNumber')
      item.parentIndexNumber = EmbyClient.readNumber(value, 'ParentIndexNumber')
      item.seasonCount = EmbyClient.readNumber(value, 'SeasonCount')
      item.childCount = EmbyClient.readNumber(value, 'ChildCount')
      item.recursiveItemCount = EmbyClient.readNumber(value, 'RecursiveItemCount')
      item.seriesName = EmbyClient.readString(value, 'SeriesName')
      item.overview = EmbyClient.readString(value, 'Overview')
      item.container = EmbyClient.readString(value, 'Container')
      item.primaryImageTag = EmbyClient.readString(value, 'PrimaryImageTag')
      item.imageItemId = item.id
      if (item.primaryImageTag.length === 0) {
        item.primaryImageTag = EmbyClient.readString(EmbyClient.readObject(value, 'ImageTags'), 'Primary')
      }
      if (item.primaryImageTag.length === 0) {
      item.primaryImageTag = EmbyClient.readString(value, 'SeriesPrimaryImageTag')
        item.imageItemId = EmbyClient.readString(value, 'SeriesId', item.id)
      }
      const imageTags = EmbyClient.readObject(value, 'ImageTags')
      item.backdropImageTag = EmbyClient.readString(value, 'BackdropImageTag')
      if (item.backdropImageTag.length === 0) {
        const backdropTags = EmbyClient.readStringArray(value, 'BackdropImageTags')
        if (backdropTags.length > 0) item.backdropImageTag = backdropTags[0]
      }
      if (item.backdropImageTag.length === 0) item.backdropImageTag = EmbyClient.readString(imageTags, 'Backdrop')
      item.backdropItemId = EmbyClient.readString(value, 'BackdropItemId', item.id)
      item.thumbnailImageTag = EmbyClient.readString(imageTags, 'Thumb')
      item.thumbnailItemId = item.id
      const userData = EmbyClient.readObject(value, 'UserData')
      item.userData.playbackPositionTicks = EmbyClient.readNumber(userData, 'PlaybackPositionTicks')
      item.userData.playedPercentage = EmbyClient.readNumber(userData, 'PlayedPercentage')
      item.userData.played = EmbyClient.readBoolean(userData, 'Played')
      if (item.id.length > 0 && item.name.length > 0) {
        items.push(item)
      }
    }
    return items
  }

  private absoluteUrl(path: string): string {
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return path
    }
    const lowerPath = path.toLowerCase()
    if (lowerPath === '/emby' || lowerPath.startsWith('/emby/')) {
      const marker = this.config.baseUrl.toLowerCase().lastIndexOf('/emby')
      return (marker >= 0 ? this.config.baseUrl.substring(0, marker) : this.config.baseUrl) + path
    }
    return this.config.baseUrl + (path.startsWith('/') ? path : '/' + path)
  }

  /**
   * Normalize the legacy `/Videos/{id}/stream/{container}` form returned by
   * some Emby versions and reverse proxies. The Emby media endpoint expects
   * the container as a file extension (`stream.mkv`); the legacy form returns
   * HTTP 404 before authentication is evaluated.
   */
  private normalizePlaybackUrl(url: string): string {
    const marker = '/stream/'
    const lower = url.toLowerCase()
    const markerIndex = lower.indexOf(marker)
    if (markerIndex < 0) return url
    const containerStart = markerIndex + marker.length
    let containerEnd = containerStart
    while (containerEnd < url.length) {
      const code = url.charCodeAt(containerEnd)
      const isDigit = code >= 48 && code <= 57
      const isUpper = code >= 65 && code <= 90
      const isLower = code >= 97 && code <= 122
      if (!isDigit && !isUpper && !isLower) break
      containerEnd++
    }
    if (containerEnd === containerStart) return url
    return url.substring(0, markerIndex) + '/stream.' +
      url.substring(containerStart, containerEnd) + url.substring(containerEnd)
  }

  /**
   * Playback URLs can be redirected by a reverse proxy, where the api_key
   * query parameter is not always retained. Keep the server-provided headers
   * and supply the authenticated Emby headers for the media request too.
   */
  private buildPlaybackHeaders(requiredHeaders: Record<string, string>): Record<string, string> {
    const headers: Record<string, string> = {}
    const keys = Object.keys(requiredHeaders)
    for (let i = 0; i < keys.length; i++) {
      const key = keys[i].trim()
      const value = requiredHeaders[keys[i]].trim()
      if (key.length > 0 && value.length > 0) {
        headers[key] = value
      }
    }
    if (!this.hasHeader(headers, 'X-Emby-Token') && this.config.accessToken.length > 0) {
      headers['X-Emby-Token'] = this.config.accessToken
    }
    if (!this.hasHeader(headers, 'X-Emby-Authorization')) {
      headers['X-Emby-Authorization'] = this.authorizationHeader(true)
    }
    return headers
  }

  private hasHeader(headers: Record<string, string>, name: string): boolean {
    const target = name.toLowerCase()
    const keys = Object.keys(headers)
    for (let i = 0; i < keys.length; i++) {
      if (keys[i].trim().toLowerCase() === target) return true
    }
    return false
  }

  static normalizeBaseUrl(value: string): string {
    let baseUrl = EmbyClient.normalizeText(value)
    const scheme = baseUrl.toLowerCase()
    if (!scheme.startsWith('http://') && !scheme.startsWith('https://')) {
      baseUrl = 'http://' + baseUrl
    }
    while (baseUrl.endsWith('/')) {
      baseUrl = baseUrl.substring(0, baseUrl.length - 1)
    }
    const urlParts = baseUrl.match(/^(https?):\/\/([^/]+)(.*)$/i)
    if (urlParts !== null) {
      baseUrl = urlParts[1].toLowerCase() + '://' + urlParts[2].toLowerCase() + urlParts[3]
    }
    if (!baseUrl.toLowerCase().endsWith('/emby')) {
      baseUrl += '/emby'
    }
    return baseUrl
  }

  private static createDeviceId(): string {
    return 'yingxia-' + Date.now() + '-' + Math.floor(Math.random() * 1000000000)
  }

  private static createSessionId(): string {
    return String(Date.now()) + String(Math.floor(Math.random() * 1000000000))
  }

  private static appendQuery(url: string, key: string, value: string): string {
    if (url.indexOf(key + '=') >= 0) {
      return url
    }
    return url + (url.indexOf('?') >= 0 ? '&' : '?') + key + '=' + encodeURIComponent(value)
  }

  private static safeContainer(value: string): string {
    const normalized = value.toLowerCase().split(',')[0]
    return /^[a-z0-9]+$/.test(normalized) ? normalized : 'mp4'
  }

  private static playbackQuality(bitrate: number): string {
    if (!Number.isFinite(bitrate) || bitrate <= 0) return ''
    if (bitrate >= 1000000) {
      return (Math.round(bitrate / 100000) / 10) + ' Mbps'
    }
    return Math.max(1, Math.round(bitrate / 1000)) + ' Kbps'
  }


  private static isFolderType(type: string): boolean {
    return type === 'CollectionFolder' || type === 'Folder' || type === 'UserView' ||
      type === 'Series' || type === 'Season' || type === 'BoxSet' || type === 'Playlist'
  }

  private static readString(value: Record<string, Object>, key: string, fallback: string = ''): string {
    return typeof value[key] === 'string' ? value[key] as string : fallback
  }

  private static normalizeText(value: string): string {
    return typeof value === 'string' ? value.trim() : ''
  }

  private static readNumber(value: Record<string, Object>, key: string): number {
    return typeof value[key] === 'number' && Number.isFinite(value[key] as number) ? value[key] as number : 0
  }

  private static readBoolean(value: Record<string, Object>, key: string): boolean {
    return typeof value[key] === 'boolean' ? value[key] as boolean : false
  }

  private static readObject(value: Record<string, Object>, key: string): Record<string, Object> {
    const nested = value[key]
    return nested !== null && typeof nested === 'object' ? nested as Record<string, Object> : {}
  }

  private static readObjectArray(value: Record<string, Object>, key: string): Array<Record<string, Object>> {
    const nested = value[key]
    if (!Array.isArray(nested)) return []
    const result: Array<Record<string, Object>> = []
    for (let i = 0; i < nested.length; i++) {
      const candidate = nested[i] as Object
      if (candidate !== null && typeof candidate === 'object' && !Array.isArray(candidate)) {
        result.push(candidate as Record<string, Object>)
      }
    }
    return result
  }

  private static readStringArray(value: Record<string, Object>, key: string): string[] {
    const nested = value[key]
    if (!Array.isArray(nested)) return []
    const result: string[] = []
    for (let i = 0; i < nested.length; i++) {
      if (typeof nested[i] === 'string') result.push(nested[i] as string)
    }
    return result
  }
}
