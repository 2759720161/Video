import { url } from '@kit.ArkTS'

/** Configuration is a tool entry, not a playable video or a persisted loopback URL. */
export class CatNodeConfiguration {
  static isItem(id: string, selectedKey: string): boolean {
    if (!id.startsWith('catnode:')) return selectedKey === 'baseset' && id === 'config-center'
    const parts = id.split(':')
    if (parts.length !== 3) return false
    try { return decodeURIComponent(parts[1]) === 'baseset' && decodeURIComponent(parts[2]) === 'config-center' }
    catch (_) { return false }
  }

  static pageUrl(base: string): string {
    const parsed = url.URL.parseURL(base)
    if (parsed.protocol !== 'http:' || parsed.hostname !== '127.0.0.1' ||
      !/^\d+$/.test(parsed.port) || Number(parsed.port) < 1 || Number(parsed.port) > 65535 ||
      parsed.username || parsed.password || parsed.search || parsed.hash || parsed.pathname !== '/') {
      throw new Error('配置中心地址无效')
    }
    return parsed.origin + '/website'
  }

  static allowsNavigation(address: string, entry: string): boolean {
    try {
      const target = url.URL.parseURL(address)
      const local = url.URL.parseURL(entry)
      if (target.username || target.password) return false
      return target.protocol === 'https:' || (target.protocol === 'http:' && target.origin === local.origin)
    } catch (_) { return false }
  }

  static isExport(address: string, entry: string): boolean {
    try {
      const target = url.URL.parseURL(address)
      return target.origin === url.URL.parseURL(entry).origin && target.pathname === '/website/api/db'
    } catch (_) { return false }
  }

  static exportUrl(entry: string): string { return CatNodeConfiguration.pageUrl(url.URL.parseURL(entry).origin) + '/api/db' }

  static isMutation(address: string, method: string, entry: string): boolean {
    try {
      const target = url.URL.parseURL(address)
      return target.origin === url.URL.parseURL(entry).origin && target.pathname.startsWith('/website/api/') &&
        ['POST', 'PUT', 'PATCH', 'DELETE'].includes(method.toUpperCase())
    } catch (_) { return false }
  }
}
