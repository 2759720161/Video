import { MediaSourceInstance } from '../core/media/MediaSourceInstance'
import { PreferencesStore } from './PreferencesStore'
import { EmbyServerConfig } from '../providers/emby/EmbyModels'
import { createMediaSourceId } from '../core/media/MediaSourceInstance'
import { PlaybackHistoryStore } from './PlaybackHistoryStore'
import { EmbySourceConfigCodec } from '../providers/emby/EmbySourceConfig'
import { SecureCredentialStore } from '../services/security/SecureCredentialStore'
import { SourceCredential } from '../services/security/SourceCredential'

export const PREFS_KEY_MEDIA_SOURCES: string = 'mediaSourcesV1'
export const MEDIA_SOURCE_VERSION_KEY: string = 'mediaSourceVersion'

/** Preferences-backed source list. The built-in local source is always present. */
export class MediaSourceStore {
  private static version: number = 0
  private static mutationTail: Promise<void> = Promise.resolve()
  private static lastReadFailed: boolean = false

  static async getAll(): Promise<MediaSourceInstance[]> {
    // Reads that originate outside a mutation must observe the latest
    // completed write. Internal read-modify-write operations use
    // getAllInternal() below so they do not wait on their own queue entry.
    await MediaSourceStore.mutationTail
    return MediaSourceStore.getAllInternal()
  }

  private static async getAllInternal(): Promise<MediaSourceInstance[]> {
    let raw = '[]'
    MediaSourceStore.lastReadFailed = false
    try {
      raw = await PreferencesStore.getInstance().getStringStrict(PREFS_KEY_MEDIA_SOURCES, '[]')
    } catch (_err) {
      // Preference access can fail during early Ability startup. Continue
      // with the built-in source rather than making local playback unavailable.
      MediaSourceStore.lastReadFailed = true
    }
    const result: MediaSourceInstance[] = []
    try {
      const parsed: Object = JSON.parse(raw)
      if (!Array.isArray(parsed)) throw new Error('Media source preference must be an array')
      const values = parsed as Array<Record<string, Object>>
      const seenIds: Record<string, boolean> = {}
      for (let i = 0; i < values.length; i++) {
        const candidate = values[i] as Object
        if (candidate === null || typeof candidate !== 'object' || Array.isArray(candidate)) {
          MediaSourceStore.lastReadFailed = true
          continue
        }
        const source = MediaSourceStore.decode(candidate as Record<string, Object>)
        if (source !== null && source.id.length > 0 && source.providerType.length > 0 && seenIds[source.id] !== true) {
          if (source.id === 'local') {
            source.providerType = 'local'
            source.name = source.name.length > 0 ? source.name : '本地媒体'
            source.enabled = true
            source.sortOrder = 0
          }
          result.push(source)
          seenIds[source.id] = true
        }
      }
    } catch (_err) {
      // A malformed preference must not prevent the built-in source from loading.
      // It must also not be treated as an empty list by a later mutation.
      MediaSourceStore.lastReadFailed = true
    }
    let hasLocal = false
    for (let i = 0; i < result.length; i++) {
      if (result[i].id === 'local') hasLocal = true
    }
    if (!hasLocal) {
      const local = new MediaSourceInstance()
      local.id = 'local'
      local.providerType = 'local'
      local.name = '本地媒体'
      local.sortOrder = 0
      result.push(local)
    }
    result.sort((left: MediaSourceInstance, right: MediaSourceInstance) => {
      if (left.id === 'local' && right.id !== 'local') return -1
      if (right.id === 'local' && left.id !== 'local') return 1
      const order = left.sortOrder - right.sortOrder
      return order !== 0 ? order : left.id.localeCompare(right.id)
    })
    return result
  }

  static async getById(id: string): Promise<MediaSourceInstance | null> {
    const normalizedId = MediaSourceStore.normalizeText(id)
    if (normalizedId.length === 0) return null
    await MediaSourceStore.mutationTail
    const sources = await MediaSourceStore.getAllInternal()
    for (let i = 0; i < sources.length; i++) if (sources[i].id === normalizedId) return sources[i]
    return null
  }

  private static async getByIdInternal(id: string): Promise<MediaSourceInstance | null> {
    const normalizedId = MediaSourceStore.normalizeText(id)
    if (normalizedId.length === 0) return null
    const sources = await MediaSourceStore.getAllInternal()
    MediaSourceStore.ensureLastReadSucceeded()
    for (let i = 0; i < sources.length; i++) if (sources[i].id === normalizedId) return sources[i]
    return null
  }

  static async add(source: MediaSourceInstance): Promise<void> {
    const snapshot = MediaSourceStore.copySource(source)
    return MediaSourceStore.enqueueMutation<void>(() => MediaSourceStore.addInternal(snapshot))
  }

  private static async addInternal(source: MediaSourceInstance): Promise<void> {
    MediaSourceStore.normalizeSource(source)
    if (!MediaSourceStore.isValid(source) || source.id === 'local') throw new Error('Invalid media source')
    const sources = await MediaSourceStore.getAllInternal()
    MediaSourceStore.ensureLastReadSucceeded()
    for (let i = 0; i < sources.length; i++) {
      if (sources[i].id === source.id) throw new Error('Media source already exists: ' + source.id)
    }
    const now = Date.now()
    source.createdAt = source.createdAt > 0 ? source.createdAt : now
    source.updatedAt = now
    sources.push(source)
    await MediaSourceStore.save(sources)
  }

  static async update(source: MediaSourceInstance): Promise<void> {
    const snapshot = MediaSourceStore.copySource(source)
    return MediaSourceStore.enqueueMutation<void>(() => MediaSourceStore.updateInternal(snapshot))
  }

  private static async updateInternal(source: MediaSourceInstance): Promise<void> {
    MediaSourceStore.normalizeSource(source)
    if (!MediaSourceStore.isValid(source) || source.id === 'local') throw new Error('Invalid media source')
    const sources = await MediaSourceStore.getAllInternal()
    MediaSourceStore.ensureLastReadSucceeded()
    let found = false
    for (let i = 0; i < sources.length; i++) {
      if (sources[i].id === source.id) {
        source.createdAt = sources[i].createdAt
        source.updatedAt = Date.now()
        sources[i] = source
        found = true
        break
      }
    }
    if (!found) throw new Error('Media source not found: ' + source.id)
    await MediaSourceStore.save(sources)
  }

  static async remove(id: string): Promise<void> {
    return MediaSourceStore.enqueueMutation<void>(() => MediaSourceStore.removeInternal(id))
  }

  private static async removeInternal(id: string): Promise<void> {
    const normalizedId = MediaSourceStore.normalizeText(id)
    if (normalizedId === 'local' || normalizedId.length === 0) throw new Error('Built-in local source cannot be removed')
    const sources = await MediaSourceStore.getAllInternal()
    MediaSourceStore.ensureLastReadSucceeded()
    const filtered: MediaSourceInstance[] = []
    for (let i = 0; i < sources.length; i++) {
      if (sources[i].id !== normalizedId) filtered.push(sources[i])
    }
    if (filtered.length === sources.length) throw new Error('Media source not found: ' + normalizedId)
    await MediaSourceStore.save(filtered)
    await new PlaybackHistoryStore().deleteBySourceId(normalizedId)
    await SecureCredentialStore.getInstance().delete(normalizedId)
  }

  static async setEnabled(id: string, enabled: boolean): Promise<void> {
    return MediaSourceStore.enqueueMutation<void>(async () => {
      const normalizedId = MediaSourceStore.normalizeText(id)
      if (normalizedId === 'local') throw new Error('Built-in local source cannot be disabled')
      const source = await MediaSourceStore.getByIdInternal(normalizedId)
      if (source === null) throw new Error('Media source not found: ' + id)
      source.enabled = enabled
      await MediaSourceStore.updateInternal(source)
    })
  }

  static async move(id: string, sortOrder: number): Promise<void> {
    return MediaSourceStore.enqueueMutation<void>(async () => {
      const source = await MediaSourceStore.getByIdInternal(MediaSourceStore.normalizeText(id))
      if (source === null) throw new Error('Media source not found: ' + id)
      if (!Number.isFinite(sortOrder)) throw new Error('Invalid source sort order')
      source.sortOrder = Math.max(0, Math.floor(sortOrder))
      await MediaSourceStore.updateInternal(source)
    })
  }

  /** 在同一个串行写事务中交换两个来源的排序，避免中间状态被观察到。 */
  static async swapOrder(firstId: string, secondId: string): Promise<void> {
    return MediaSourceStore.enqueueMutation<void>(async () => {
      const normalizedFirstId = MediaSourceStore.normalizeText(firstId)
      const normalizedSecondId = MediaSourceStore.normalizeText(secondId)
      if (normalizedFirstId.length === 0 || normalizedSecondId.length === 0 || normalizedFirstId === normalizedSecondId) {
        throw new Error('Invalid media source order swap')
      }
      if (normalizedFirstId === 'local' || normalizedSecondId === 'local') {
        throw new Error('Built-in local source cannot be reordered')
      }
      const sources = await MediaSourceStore.getAllInternal()
      MediaSourceStore.ensureLastReadSucceeded()
      let first: MediaSourceInstance | null = null
      let second: MediaSourceInstance | null = null
      for (let i = 0; i < sources.length; i++) {
        if (sources[i].id === normalizedFirstId) first = sources[i]
        if (sources[i].id === normalizedSecondId) second = sources[i]
      }
      if (first === null || second === null) throw new Error('Media source not found')
      const firstOrder = first.sortOrder
      first.sortOrder = second.sortOrder
      second.sortOrder = firstOrder
      const now = Date.now()
      first.updatedAt = now
      second.updatedAt = now
      await MediaSourceStore.save(sources)
    })
  }

  /** 保存 Emby 设置并返回对应 sourceId；按 serverId 或账号地址复用实例。 */
  static async upsertEmby(config: EmbyServerConfig, preferredSourceId: string = ''): Promise<string> {
    const snapshot = config.copy()
    return MediaSourceStore.enqueueMutation<string>(() => MediaSourceStore.upsertEmbyInternal(snapshot, preferredSourceId))
  }

  private static async upsertEmbyInternal(config: EmbyServerConfig, preferredSourceId: string = ''): Promise<string> {
    const normalizedConfig = EmbySourceConfigCodec.decode(JSON.stringify(config))
    if (normalizedConfig === null) throw new Error('Invalid Emby configuration')
    const normalizedPreferredSourceId = MediaSourceStore.normalizeText(preferredSourceId)
    const sources = await MediaSourceStore.getAllInternal()
    MediaSourceStore.ensureLastReadSucceeded()
    let source: MediaSourceInstance | null = null
    for (let i = 0; i < sources.length; i++) {
      const candidate = sources[i]
      if (candidate.providerType !== 'emby') continue
      if (normalizedPreferredSourceId.length > 0 && candidate.id === normalizedPreferredSourceId) {
        source = candidate
        break
      }
      const oldConfig = EmbySourceConfigCodec.decode(candidate.configJson)
      if (oldConfig === null) continue
      const serverId = oldConfig.serverId
      const baseUrl = oldConfig.baseUrl
      const userId = oldConfig.userId
      const sameServerAccount = normalizedConfig.serverId.length > 0 && serverId === normalizedConfig.serverId &&
        normalizedConfig.userId.length > 0 && userId === normalizedConfig.userId
      const sameAddressAccount = baseUrl === normalizedConfig.baseUrl &&
        userId === normalizedConfig.userId && normalizedConfig.userId.length > 0
      if (sameServerAccount || sameAddressAccount) {
        source = candidate
        break
      }
    }
    if (source === null) {
      source = new MediaSourceInstance()
      source.id = createMediaSourceId('emby')
      source.providerType = 'emby'
      source.sortOrder = 10 + sources.length
    }
    source.name = normalizedConfig.serverName.length > 0 ? normalizedConfig.serverName : 'Emby'
    source.enabled = true
    source.configJson = EmbySourceConfigCodec.encode(normalizedConfig)
    const credential = new SourceCredential()
    credential.sourceId = source.id
    credential.providerType = 'emby'
    credential.values['accessToken'] = normalizedConfig.accessToken
    // 写入凭据成功后再落盘无敏感字段的 source，避免升级过程中丢失令牌。
    await SecureCredentialStore.getInstance().set(credential)
    if (source.createdAt === 0) {
      await MediaSourceStore.addInternal(source)
    } else {
      await MediaSourceStore.updateInternal(source)
    }
    return source.id
  }

  /** 删除指定 Emby 账号及其本地缓存历史。 */
  static async removeEmby(config: EmbyServerConfig): Promise<void> {
    const snapshot = config.copy()
    return MediaSourceStore.enqueueMutation<void>(() => MediaSourceStore.removeEmbyInternal(snapshot))
  }

  private static async removeEmbyInternal(config: EmbyServerConfig): Promise<void> {
    const normalizedConfig = EmbySourceConfigCodec.decode(JSON.stringify(config))
    if (normalizedConfig === null) throw new Error('Invalid Emby configuration')
    const sources = await MediaSourceStore.getAllInternal()
    MediaSourceStore.ensureLastReadSucceeded()
    const retained: MediaSourceInstance[] = []
    const removedSourceIds: string[] = []
    for (let i = 0; i < sources.length; i++) {
      const source = sources[i]
      if (source.providerType !== 'emby') {
        retained.push(source)
        continue
      }
      const value = EmbySourceConfigCodec.decode(source.configJson)
      if (value === null) {
        retained.push(source)
        continue
      }
      const serverId = value.serverId
      const baseUrl = value.baseUrl
      const userId = value.userId
      const sameServerAccount = normalizedConfig.serverId.length > 0 && serverId === normalizedConfig.serverId &&
        normalizedConfig.userId.length > 0 && userId === normalizedConfig.userId
      const sameAddressAccount = baseUrl === normalizedConfig.baseUrl &&
        userId === normalizedConfig.userId && normalizedConfig.userId.length > 0
      const sameServer = sameServerAccount || sameAddressAccount
      if (!sameServer) retained.push(source)
      else removedSourceIds.push(source.id)
    }
    if (retained.length !== sources.length) {
      await MediaSourceStore.save(retained)
      const historyStore = new PlaybackHistoryStore()
      for (let i = 0; i < removedSourceIds.length; i++) {
        await historyStore.deleteBySourceId(removedSourceIds[i])
        await SecureCredentialStore.getInstance().delete(removedSourceIds[i])
      }
    }
  }

  /*
   * The public mutators above are serialized so each read-modify-write cycle
   * sees the result of the previous one. `tail` is always kept resolved,
   * allowing a failed mutation to be followed by a later valid mutation.
   */
  private static enqueueMutation<T>(operation: () => Promise<T>): Promise<T> {
    const result: Promise<T> = MediaSourceStore.mutationTail.then(operation, operation)
    MediaSourceStore.mutationTail = result.then(() => {}, () => {})
    return result
  }

  private static copySource(source: MediaSourceInstance): MediaSourceInstance {
    const copy = new MediaSourceInstance()
    copy.id = source.id
    copy.providerType = source.providerType
    copy.name = source.name
    copy.enabled = source.enabled
    copy.sortOrder = source.sortOrder
    copy.configJson = source.configJson
    copy.createdAt = source.createdAt
    copy.updatedAt = source.updatedAt
    return copy
  }

  private static async save(sources: MediaSourceInstance[]): Promise<void> {
    MediaSourceStore.ensureLastReadSucceeded()
    const persisted = sources.filter((source: MediaSourceInstance) => source.id !== 'local')
    await PreferencesStore.getInstance().setStringStrict(PREFS_KEY_MEDIA_SOURCES, JSON.stringify(persisted))
    MediaSourceStore.version = Math.max(Date.now(), MediaSourceStore.version + 1)
    AppStorage.setOrCreate(MEDIA_SOURCE_VERSION_KEY, MediaSourceStore.version)
  }

  private static isValid(source: MediaSourceInstance): boolean {
    return source.id.length > 0 && source.providerType.length > 0 && source.name.length > 0
  }

  private static normalizeSource(source: MediaSourceInstance): void {
    source.id = source.id.trim()
    source.providerType = source.providerType.trim().toLowerCase()
    source.name = source.name.trim()
    source.sortOrder = Math.max(source.id === 'local' ? 0 : 1, Math.floor(Number.isFinite(source.sortOrder) ? source.sortOrder : 0))
  }

  private static decode(value: Record<string, Object>): MediaSourceInstance | null {
    const source = new MediaSourceInstance()
    source.id = MediaSourceStore.readString(value, 'id').trim()
    source.providerType = MediaSourceStore.readString(value, 'providerType').trim().toLowerCase()
    source.name = MediaSourceStore.readString(value, 'name').trim()
    source.enabled = MediaSourceStore.readBoolean(value, 'enabled', true)
    source.sortOrder = Math.max(0, Math.floor(MediaSourceStore.readNumber(value, 'sortOrder', 0)))
    source.configJson = MediaSourceStore.readString(value, 'configJson') || '{}'
    source.createdAt = Math.max(0, Math.floor(MediaSourceStore.readNumber(value, 'createdAt', 0)))
    source.updatedAt = Math.max(0, Math.floor(MediaSourceStore.readNumber(value, 'updatedAt', 0)))
    return source.id.length > 0 && source.providerType.length > 0 ? source : null
  }

  private static readString(value: Record<string, Object>, key: string): string {
    return typeof value[key] === 'string' ? value[key] as string : ''
  }

  private static readBoolean(value: Record<string, Object>, key: string, fallback: boolean): boolean {
    return typeof value[key] === 'boolean' ? value[key] as boolean : fallback
  }

  private static readNumber(value: Record<string, Object>, key: string, fallback: number): number {
    return typeof value[key] === 'number' && Number.isFinite(value[key] as number) ? value[key] as number : fallback
  }

  private static ensureLastReadSucceeded(): void {
    if (MediaSourceStore.lastReadFailed) {
      throw new Error('Media source storage is unavailable')
    }
  }

  private static normalizeText(value: string): string {
    return typeof value === 'string' ? value.trim() : ''
  }
}
