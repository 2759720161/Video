import { PreferencesStore } from '../../store/PreferencesStore'
import { MediaSourceStore } from '../../store/MediaSourceStore'
import { EmbySourceConfigCodec } from '../../providers/emby/EmbySourceConfig'
import { WebDavSourceConfigCodec } from '../../providers/webdav/WebDavSourceConfig'
import { SourceCredential } from './SourceCredential'
import { SecureCredentialStore } from './SecureCredentialStore'

const MIGRATION_DONE_KEY: string = 'sourceCredentialMigrationV2Done'

/** 将旧 configJson 中的敏感字段迁移到凭据边界。 */
export class SourceCredentialMigration {
  private static task: Promise<void> | null = null

  static async runIfNeeded(): Promise<void> {
    if (SourceCredentialMigration.task !== null) {
      await SourceCredentialMigration.task
      return
    }
    const task = SourceCredentialMigration.run()
    SourceCredentialMigration.task = task
    try {
      await task
    } finally {
      if (SourceCredentialMigration.task === task) SourceCredentialMigration.task = null
    }
  }

  private static async run(): Promise<void> {
    const prefs = PreferencesStore.getInstance()
    if (await prefs.getBoolean(MIGRATION_DONE_KEY, false)) return
    const sources = await MediaSourceStore.getAll()
    const credentials = SecureCredentialStore.getInstance()
    for (let i = 0; i < sources.length; i++) {
      const source = sources[i]
      if (source.providerType === 'emby') {
        const config = EmbySourceConfigCodec.decode(source.configJson)
        if (config !== null && config.accessToken.length > 0) {
          const existing = await credentials.get(source.id)
          if (existing === null || SourceCredentialMigration.value(existing, 'accessToken').length === 0) {
            const credential = new SourceCredential()
            credential.sourceId = source.id
            credential.providerType = 'emby'
            credential.values['accessToken'] = config.accessToken
            await credentials.set(credential)
          }
          source.configJson = EmbySourceConfigCodec.encode(config)
          await MediaSourceStore.update(source)
        }
      } else if (source.providerType === 'webdav') {
        const config = WebDavSourceConfigCodec.decode(source.configJson)
        if (config !== null && config.password.length > 0) {
          const existing = await credentials.get(source.id)
          if (existing === null || SourceCredentialMigration.value(existing, 'password').length === 0) {
            const credential = new SourceCredential()
            credential.sourceId = source.id
            credential.providerType = 'webdav'
            credential.values['password'] = config.password
            await credentials.set(credential)
          }
          source.configJson = WebDavSourceConfigCodec.encode(config)
          await MediaSourceStore.update(source)
        }
      }
    }
    await prefs.setBoolean(MIGRATION_DONE_KEY, true)
  }

  private static value(credential: SourceCredential, key: string): string {
    const value = credential.values[key]
    return typeof value === 'string' ? value.trim() : ''
  }
}
