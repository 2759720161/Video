import { common } from '@kit.AbilityKit'
import { MediaSourceInstance } from '../../core/media/MediaSourceInstance'
import type { MediaProvider } from './MediaProvider'
import { MediaSourceStore } from '../../store/MediaSourceStore'
import { LocalProvider } from '../local/LocalProvider'
import { EmbyProvider } from '../emby/EmbyProvider'
import { WebDavProvider } from '../webdav/WebDavProvider'
import { Logger } from '../../utils/Logger'

export type MediaProviderFactory = (source: MediaSourceInstance,
  context: common.UIAbilityContext | null) => Promise<MediaProvider | null>

/** 以 sourceId 查找来源实例并创建 Provider，支持同类型多实例。 */
export class ProviderRegistry {
  private static factories: Map<string, MediaProviderFactory> = new Map()
  private static readonly logger: Logger = new Logger('ProviderRegistry')

  static register(providerType: string, factory: MediaProviderFactory): void {
    const normalizedType = ProviderRegistry.normalizeText(providerType).toLowerCase()
    if (normalizedType.length === 0) throw new Error('Provider type cannot be empty')
    ProviderRegistry.factories.set(normalizedType, factory)
  }

  static unregister(providerType: string): void {
    ProviderRegistry.factories.delete(ProviderRegistry.normalizeText(providerType).toLowerCase())
  }

  static async get(sourceId: string,
    context: common.UIAbilityContext | null = null, allowDisabled: boolean = false): Promise<MediaProvider | null> {
    const normalizedSourceId = ProviderRegistry.normalizeText(sourceId)
    if (normalizedSourceId.length === 0) return null
    const source = await MediaSourceStore.getById(normalizedSourceId)
    if (source === null || (!source.enabled && !allowDisabled)) return null
    const factory = ProviderRegistry.factories.get(source.providerType)
    if (factory === undefined) return null
    try {
      return await factory(source, context)
    } catch (err) {
      ProviderRegistry.logger.warn('Create provider failed: source=%{public}s type=%{public}s error=%{public}s',
        source.id, source.providerType, err instanceof Error ? err.message : String(err))
      return null
    }
  }

  static registerBuiltIns(): void {
    ProviderRegistry.register('local', async (_source, context) =>
      context === null ? null : new LocalProvider(context))
    ProviderRegistry.register('emby', async (source, _context) => EmbyProvider.fromSource(source))
    ProviderRegistry.register('webdav', async (source, _context) => WebDavProvider.fromSource(source))
  }

  static supports(providerType: string): boolean {
    return ProviderRegistry.factories.has(ProviderRegistry.normalizeText(providerType).toLowerCase())
  }

  private static normalizeText(value: string): string {
    return typeof value === 'string' ? value.trim() : ''
  }

}
