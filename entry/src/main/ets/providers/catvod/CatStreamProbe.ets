import { http } from '@kit.NetworkKit'
import { PlaybackStream } from '../../core/playback/PlaybackStream'

/** A bounded ranged GET; HEAD alone can accept a login page or reject valid media. */
export class CatStreamProbe {
  static valid(status: number, rawHeaders: Object, data: ArrayBuffer): boolean {
    if (status !== 200 && status !== 206 || data.byteLength === 0 || data.byteLength > 8192) return false
    let prefix = ''
    const bytes = new Uint8Array(data)
    for (let i = 0; i < Math.min(bytes.length, 80); i++) prefix += String.fromCharCode(bytes[i])
    if (/^\s*(?:<!doctype|<html|<\?xml|\{|\[)/i.test(prefix)) return false
    let contentType = ''
    try {
      const headers = (typeof rawHeaders === 'string' ? JSON.parse(rawHeaders as string) : rawHeaders) as Record<string, Object>
      for (const key of Object.keys(headers)) if (key.toLowerCase() === 'content-type' && typeof headers[key] === 'string') contentType = headers[key] as string
    } catch (_) { return false }
    const magic = prefix.substring(4, 8) === 'ftyp' || prefix.startsWith('#EXTM3U') || prefix.startsWith('ID3') ||
      prefix.startsWith('OggS') || prefix.startsWith('FLV') || prefix.startsWith('RIFF') ||
      bytes.length >= 4 && bytes[0] === 0x1a && bytes[1] === 0x45 && bytes[2] === 0xdf && bytes[3] === 0xa3 ||
      bytes[0] === 0x47 || bytes.length > 1 && bytes[0] === 0xff && (bytes[1] & 0xe0) === 0xe0
    return magic || status === 206 && /^(?:video|audio)\//i.test(contentType)
  }

  static async check(stream: PlaybackStream): Promise<boolean> {
    const request = http.createHttp()
    let destroyed = false
    const destroy = (): void => { if (!destroyed) { destroyed = true; request.destroy() } }
    let timer: number = -1
    try {
      const headers: Record<string, string> = {}
      for (const name of Object.keys(stream.headers)) if (!/^(range|host|content-length|connection)$/i.test(name)) headers[name] = stream.headers[name]
      if (stream.userAgent && !Object.keys(headers).some((name: string) => name.toLowerCase() === 'user-agent')) headers['User-Agent'] = stream.userAgent
      if (stream.referer && !Object.keys(headers).some((name: string) => name.toLowerCase() === 'referer')) headers['Referer'] = stream.referer
      headers['Range'] = 'bytes=0-4095'
      const probe = request.request(stream.url, { method: http.RequestMethod.GET, header: headers,
        expectDataType: http.HttpDataType.ARRAY_BUFFER, usingCache: false, connectTimeout: 1200, readTimeout: 1200, maxLimit: 8192 })
        .then((response: http.HttpResponse): boolean => response.result instanceof ArrayBuffer &&
          CatStreamProbe.valid(response.responseCode, response.header, response.result as ArrayBuffer)).catch(() => false)
      const deadline = new Promise<boolean>((resolve) => { timer = setTimeout(() => { destroy(); resolve(false) }, 1500) })
      return await Promise.race<boolean>([probe, deadline])
    } finally { if (timer >= 0) clearTimeout(timer); destroy() }
  }
}
