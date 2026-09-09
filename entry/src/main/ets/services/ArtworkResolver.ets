import { ArtworkRef } from '../core/media/ArtworkRef'
import { common } from '@kit.AbilityKit'
import { ProviderRegistry } from '../providers/base/ProviderRegistry'
import { ProviderCapability } from '../core/media/ProviderCapabilities'

/**
 * Artwork 持久化边界。Provider 的 image URL 可以带认证参数，但历史数据库只能保存
 * ArtworkRef；页面需要图片时再根据引用向 Provider 请求运行时 URL。
 */
export class ArtworkResolver {
  /**
   * Resolve a persisted stable reference to a fresh runtime image URL.
   * The returned value is intentionally runtime-only and must not be persisted.
   */
  static async resolve(sourceId: string, mediaId: string, artworkRef: string,
    context: common.UIAbilityContext | null = null): Promise<string> {
    const decoded = ArtworkRef.decode(artworkRef)
    const resolvedSourceId = ArtworkResolver.normalizeText(sourceId.length > 0 ? sourceId :
      decoded === null ? '' : decoded.sourceId)
    const resolvedMediaId = ArtworkResolver.normalizeText(mediaId.length > 0 ? mediaId :
      decoded === null ? '' : decoded.mediaId)
    if (resolvedSourceId.length === 0 || resolvedMediaId.length === 0) return ''
    if (decoded !== null && (decoded.sourceId !== resolvedSourceId || decoded.mediaId !== resolvedMediaId)) {
      return ''
    }
    const provider = await ProviderRegistry.get(resolvedSourceId, context)
    if (provider === null || !provider.hasCapability(ProviderCapability.ARTWORK)) return ''
    const item = await provider.getItem(resolvedMediaId)
    return item === null ? '' : item.poster
  }

  static forEmby(sourceId: string, mediaId: string, imageTag: string): string {
    return ArtworkRef.fromMedia(sourceId, mediaId, imageTag, 'Primary')
  }

  static persistedValue(runtimeUrl: string, stableRef: string = ''): string {
    const ref = ArtworkRef.decode(stableRef)
    if (ref !== null) return ref.encode()
    const value = typeof runtimeUrl === 'string' ? runtimeUrl.trim() : ''
    // api_key、access_token、token 和 cookie 都可能授予媒体访问权限，不能进入 RDB。
    if (ArtworkResolver.containsCredential(value)) return ''
    return value
  }

  static isStableReference(value: string): boolean {
    return ArtworkRef.decode(value) !== null
  }

  private static containsCredential(value: string): boolean {
    const lower = value.toLowerCase()
    return lower.indexOf('api_key=') >= 0 || lower.indexOf('access_token=') >= 0 ||
      lower.indexOf('token=') >= 0 || lower.indexOf('authorization=') >= 0 ||
      lower.indexOf('cookie=') >= 0
  }

  private static normalizeText(value: string): string {
    return typeof value === 'string' ? value.trim() : ''
  }
}
