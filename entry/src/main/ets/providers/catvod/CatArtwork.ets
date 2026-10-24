/** Image-domain capabilities are independent of the catalog's name, package or method routes. */
export class CatArtwork {
  static readonly PROXY_PATH: string = '/__video_artwork'

  static needsHeaders(artwork: string): boolean {
    if (artwork.startsWith('//')) return CatArtwork.needsHeaders('https:' + artwork)
    const match = artwork.match(/^(https?):\/\/img\d*\.doubanio\.com(?::(\d+))?\//i)
    return match !== null && (match[2] === undefined || match[2] === (match[1].toLowerCase() === 'https' ? '443' : '80')) &&
      !/[\u0000-\u0020\u007f\\]/.test(artwork)
  }

  static needsRuntime(artwork: string): boolean {
    return /^http:\/\/127\.0\.0\.1:\d+\//.test(artwork) || CatArtwork.needsHeaders(artwork)
  }

  static resolve(artwork: string, base: string = ''): string {
    let value = artwork
    if (value.startsWith('js2p://_WEB_')) value = value.substring('js2p://_WEB_'.length)
    const local = value.match(/^http:\/\/127\.0\.0\.1:\d+(\/.*)$/)
    if (local !== null) return base.length > 0 ? base + local[1] : ''
    if (value.startsWith('//')) value = 'https:' + value
    else if (value.startsWith('/')) return base.length > 0 ? base + value : ''
    if (CatArtwork.needsHeaders(value)) {
      return base.length > 0 ? base + CatArtwork.PROXY_PATH + '?url=' + encodeURIComponent(value) : ''
    }
    return value
  }
}
