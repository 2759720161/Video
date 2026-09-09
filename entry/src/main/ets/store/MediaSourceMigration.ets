import { EmbyServerStore } from './EmbyServerStore'
import { MediaSourceInstance, createMediaSourceId } from '../core/media/MediaSourceInstance'
import { MediaSourceStore } from './MediaSourceStore'
import { PreferencesStore } from './PreferencesStore'
import { EmbySourceConfigCodec } from '../providers/emby/EmbySourceConfig'
import { SecureCredentialStore } from '../services/security/SecureCredentialStore'
import { SourceCredential } from '../services/security/SourceCredential'

export const PREFS_KEY_SOURCE_MIGRATION_V1: string = 'mediaSourceMigrationV1Done'

/** V1 Emby 配置迁移；旧 key 保留作只读兜底，避免升级失败时丢失账号。 */
export class MediaSourceMigration {
  private static migrationPromise: Promise<void> | null = null

  static async runIfNeeded(): Promise<void> {
    if (MediaSourceMigration.migrationPromise !== null) {
      await MediaSourceMigration.migrationPromise
      return
    }
    const task = MediaSourceMigration.performMigration()
    MediaSourceMigration.migrationPromise = task
    try {
      await task
    } finally {
      if (MediaSourceMigration.migrationPromise === task) {
        MediaSourceMigration.migrationPromise = null
      }
    }
  }

  private static async performMigration(): Promise<void> {
    const prefs = PreferencesStore.getInstance()
    if (await prefs.getBoolean(PREFS_KEY_SOURCE_MIGRATION_V1, false)) return
    const existing = await MediaSourceStore.getAll()
    const oldConfig = await EmbyServerStore.loadStrict()
    const normalizedOldConfig = oldConfig === null ? null :
      EmbySourceConfigCodec.decode(JSON.stringify(oldConfig))
    let hasMigratedEmby = false
    let invalidEmby: MediaSourceInstance | null = null
    for (let i = 0; i < existing.length; i++) {
      if (existing[i].providerType !== 'emby') continue
      const existingConfig = EmbySourceConfigCodec.decode(existing[i].configJson)
      if (existingConfig !== null && normalizedOldConfig !== null) {
        const sameServerAccount = normalizedOldConfig.serverId.length > 0 &&
          existingConfig.serverId === normalizedOldConfig.serverId &&
          normalizedOldConfig.userId.length > 0 && existingConfig.userId === normalizedOldConfig.userId
        const sameAddressAccount = existingConfig.baseUrl === normalizedOldConfig.baseUrl &&
          normalizedOldConfig.userId.length > 0 && existingConfig.userId === normalizedOldConfig.userId
        if (sameServerAccount || sameAddressAccount) hasMigratedEmby = true
        if (sameServerAccount || sameAddressAccount) {
          const existingCredential = await SecureCredentialStore.getInstance().get(existing[i].id)
          const existingToken = existingCredential === null ? '' : existingCredential.values['accessToken']
          if (existingCredential === null || typeof existingToken !== 'string' || existingToken.trim().length === 0) {
            const credential = new SourceCredential()
            credential.sourceId = existing[i].id
            credential.providerType = 'emby'
            credential.values['accessToken'] = normalizedOldConfig.accessToken
            await SecureCredentialStore.getInstance().set(credential)
          }
          // Existing sources may still carry a V1 token; rewrite after the
          // secure credential has been confirmed.
          existing[i].configJson = EmbySourceConfigCodec.encode(existingConfig)
          await MediaSourceStore.update(existing[i])
        }
      }
      if (existingConfig === null && invalidEmby === null) {
        invalidEmby = existing[i]
      }
    }
    if (oldConfig !== null && !hasMigratedEmby) {
      const normalizedConfig = EmbySourceConfigCodec.decode(JSON.stringify(oldConfig))
      const source = invalidEmby === null ? new MediaSourceInstance() : invalidEmby
      source.id = source.id.length > 0 ? source.id : createMediaSourceId('emby')
      source.providerType = 'emby'
      source.name = oldConfig.serverName.length > 0 ? oldConfig.serverName : 'Emby'
      source.enabled = true
      source.sortOrder = source.sortOrder > 0 ? source.sortOrder : 10
      if (normalizedConfig !== null && normalizedConfig.accessToken.length > 0) {
        const credential = new SourceCredential()
        credential.sourceId = source.id
        credential.providerType = 'emby'
        credential.values['accessToken'] = normalizedConfig.accessToken
        await SecureCredentialStore.getInstance().set(credential)
      }
      // 迁移成功后立即固定规范格式；若旧数据无法通过新边界校验，
      // 仍保留原值，避免升级过程覆盖用户配置。
      source.configJson = normalizedConfig === null ? JSON.stringify(oldConfig) :
        EmbySourceConfigCodec.encode(normalizedConfig)
      if (source.createdAt > 0) {
        await MediaSourceStore.update(source)
      } else {
        source.createdAt = Date.now()
        source.updatedAt = source.createdAt
        await MediaSourceStore.add(source)
      }
    }
    // The old singleton preference is no longer needed once its token has
    // been copied to a source-scoped secure credential.
    if (oldConfig !== null && normalizedOldConfig !== null && normalizedOldConfig.accessToken.length > 0) {
      await EmbyServerStore.clear()
    }
    await prefs.setBoolean(PREFS_KEY_SOURCE_MIGRATION_V1, true)
  }
}
