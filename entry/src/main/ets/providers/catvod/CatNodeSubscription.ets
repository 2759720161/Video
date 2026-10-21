import { common } from '@kit.AbilityKit'
import { buffer, url, util } from '@kit.ArkTS'
import { fileIo } from '@kit.CoreFileKit'
import { cryptoFramework } from '@kit.CryptoArchitectureKit'
import { http } from '@kit.NetworkKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { CatVodCodec } from './CatVodCodec'

export class CatNodeSourceConfig {
  md5Url: string = ''
  spiderKey: string = ''
  legacySpiderKey: string = ''
  iconUri: string = ''
}

export class CatNodeBundle {
  root: string = ''
  file: string = ''
  md5: string = ''
  sha256: string = ''
}

class CatNodeHttpFailure extends Error {}

export enum CatNodeSubscriptionStage {
  STOPPING = 'stopping',
  CHECKING = 'checking',
  DOWNLOADING = 'downloading',
  VERIFYING = 'verifying',
  STARTING = 'starting',
  READING = 'reading',
  SAVING = 'saving'
}

export class CatNodeSubscriptionCodec {
  static normalizeUrl(value: string): string {
    const text = value.trim()
    if (text.length === 0) throw new Error('请填写 index.js.md5 地址')
    if (text.length > 4096 || /[\s\u0000-\u001f]/.test(text)) throw new Error('订阅地址格式无效')
    try {
      const parsed = url.URL.parseURL(text)
      if ((parsed.protocol !== 'https:' && parsed.protocol !== 'http:') || !parsed.hostname ||
        parsed.username || parsed.password || parsed.hash || !/\/index\.js\.md5$/i.test(parsed.pathname)) {
        throw new Error('invalid')
      }
      return parsed.href
    } catch (_) { throw new Error('请填写有效的 HTTP 或 HTTPS index.js.md5 地址') }
  }

  static scriptUrl(value: string): string {
    const parsed = url.URL.parseURL(CatNodeSubscriptionCodec.normalizeUrl(value))
    parsed.pathname = parsed.pathname.substring(0, parsed.pathname.length - 4)
    return parsed.href
  }

  static parseMd5(value: string): string {
    const match = value.trim().match(/^([0-9a-fA-F]{32})(?:[ \t]+\*?(?:index\.js))?$/)
    if (match === null) throw new Error('订阅没有返回有效的 MD5 校验值')
    return match[1].toLowerCase()
  }

  static decode(text: string): CatNodeSourceConfig {
    const raw = CatVodCodec.object(JSON.parse(text) as Object)
    const config = new CatNodeSourceConfig()
    if (raw !== null) {
      config.md5Url = CatVodCodec.text(raw['md5Url'])
      config.spiderKey = CatVodCodec.text(raw['spiderKey'])
      config.legacySpiderKey = CatVodCodec.text(raw['legacySpiderKey'])
      config.iconUri = CatVodCodec.text(raw['iconUri'])
    }
    return config
  }
}

/** Downloaded programs and profiles are isolated by subscription URL. */
export class CatNodeSubscription {
  private static tail: Promise<void> = Promise.resolve()

  static async prepare(context: common.Context, md5Url: string,
    onStage: (stage: CatNodeSubscriptionStage) => void = () => {}): Promise<CatNodeBundle> {
    const normalized = CatNodeSubscriptionCodec.normalizeUrl(md5Url)
    const task = CatNodeSubscription.tail.then(() => CatNodeSubscription.prepareInternal(context, normalized, onStage))
    CatNodeSubscription.tail = task.then(() => {}, () => {})
    return task
  }

  static async digest(bytes: Uint8Array, algorithm: string): Promise<string> {
    const digest = cryptoFramework.createMd(algorithm)
    await digest.update({ data: bytes })
    const data = (await digest.digest()).data
    let result = ''
    for (let i = 0; i < data.length; i++) result += data[i].toString(16).padStart(2, '0')
    return result
  }

  private static async prepareInternal(context: common.Context, md5Url: string,
    onStage: (stage: CatNodeSubscriptionStage) => void): Promise<CatNodeBundle> {
    onStage(CatNodeSubscriptionStage.CHECKING)
    hilog.info(0, 'CatSubscription', 'prepare_begin')
    // Harmony Buffer.byteOffset refers to its pool, not to the exported buffer.
    // Encode directly so the hash never reapplies a pool offset to copied bytes.
    const urlBytes = new util.TextEncoder('utf-8').encodeInto(md5Url)
    const identity = await CatNodeSubscription.digest(urlBytes, 'SHA256')
    const root = context.filesDir + '/catnode/subscriptions/' + identity
    const program = root + '/program'
    if (!fileIo.accessSync(program)) fileIo.mkdirSync(program, true)
    const cached = await CatNodeSubscription.readCached(root)
    let checksumBytes: Uint8Array
    try { checksumBytes = await CatNodeSubscription.download(md5Url, 4096) }
    catch (error) {
      // Only transport failure may use an existing, rechecked cache. Invalid or
      // mismatched published checksums never silently replace the active version.
      if (cached !== null && !(error instanceof CatNodeHttpFailure)) {
        hilog.warn(0, 'CatSubscription', 'checksum_unreachable using_verified_cache')
        return cached
      }
      throw new Error(error instanceof Error ? error.message : '订阅下载失败，请检查网络连接')
    }
    const expected = CatNodeSubscriptionCodec.parseMd5(buffer.from(checksumBytes).toString('utf-8'))
    if (cached !== null && cached.md5 === expected) {
      hilog.info(0, 'CatSubscription', 'checksum_unchanged using_verified_cache')
      return cached
    }
    onStage(CatNodeSubscriptionStage.DOWNLOADING)
    const bytes = await CatNodeSubscription.download(CatNodeSubscriptionCodec.scriptUrl(md5Url), 32 * 1024 * 1024)
    if (bytes.length === 0) throw new Error('订阅脚本为空')
    onStage(CatNodeSubscriptionStage.VERIFYING)
    const actual = await CatNodeSubscription.digest(bytes, 'MD5')
    if (actual !== expected) throw new Error('订阅脚本 MD5 校验失败，请稍后重试')
    const bundle = new CatNodeBundle()
    bundle.root = root; bundle.md5 = actual; bundle.file = 'index.' + actual + '.cjs'
    bundle.sha256 = await CatNodeSubscription.digest(bytes, 'SHA256')
    CatNodeSubscription.atomicWrite(program + '/' + bundle.file, bytes.buffer)
    CatNodeSubscription.atomicWrite(root + '/bundle.json', JSON.stringify(bundle))
    hilog.info(0, 'CatSubscription', 'program_verified bytes=%{public}d', bytes.length)
    return bundle
  }

  private static async readCached(root: string): Promise<CatNodeBundle | null> {
    try {
      const raw = CatVodCodec.object(JSON.parse(fileIo.readTextSync(root + '/bundle.json')) as Object)
      if (raw === null) return null
      const bundle = new CatNodeBundle()
      bundle.root = root; bundle.file = CatVodCodec.text(raw['file'])
      bundle.md5 = CatVodCodec.text(raw['md5']); bundle.sha256 = CatVodCodec.text(raw['sha256'])
      if (!/^[0-9a-f]{32}$/.test(bundle.md5) || !/^[0-9a-f]{64}$/.test(bundle.sha256) ||
        bundle.file !== 'index.' + bundle.md5 + '.cjs') return null
      const path = root + '/program/' + bundle.file
      const size = fileIo.statSync(path).size
      if (size <= 0 || size > 32 * 1024 * 1024) return null
      const bytes = new ArrayBuffer(size)
      const file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY)
      try { if (fileIo.readSync(file.fd, bytes) !== size) return null }
      finally { fileIo.closeSync(file) }
      if (await CatNodeSubscription.digest(new Uint8Array(bytes), 'SHA256') !== bundle.sha256 ||
        await CatNodeSubscription.digest(new Uint8Array(bytes), 'MD5') !== bundle.md5) return null
      return bundle
    } catch (_) { return null }
  }

  static atomicWrite(path: string, value: ArrayBuffer | string): void {
    const temporary = path + '.pending.' + Date.now() + '.' + Math.floor(Math.random() * 1000000)
    try {
      const file = fileIo.openSync(temporary, fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC | fileIo.OpenMode.WRITE_ONLY)
      try {
        const expected = typeof value === 'string' ? buffer.byteLength(value, 'utf-8') : value.byteLength
        if (fileIo.writeSync(file.fd, value) !== expected) throw new Error('订阅文件保存不完整')
      } finally { fileIo.closeSync(file) }
      fileIo.renameSync(temporary, path)
    } finally { if (fileIo.accessSync(temporary)) fileIo.unlinkSync(temporary) }
  }

  private static async download(address: string, limit: number): Promise<Uint8Array> {
    const request = http.createHttp()
    const kind = limit === 4096 ? 'checksum' : 'script'
    hilog.info(0, 'CatSubscription', 'download_begin kind=%{public}s', kind)
    try {
      const response = await request.request(address, {
        method: http.RequestMethod.GET, expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: 15000, readTimeout: 60000, maxLimit: limit, usingCache: false
      })
      hilog.info(0, 'CatSubscription', 'download_response kind=%{public}s status=%{public}d', kind, response.responseCode)
      if (response.responseCode !== 200) {
        throw new CatNodeHttpFailure('订阅下载失败（HTTP ' + response.responseCode + '）')
      }
      if (!(response.result instanceof ArrayBuffer)) throw new CatNodeHttpFailure('订阅响应格式无效，请检查地址')
      const bytes = new Uint8Array(response.result)
      if (bytes.length > limit) throw new Error('订阅文件超过大小限制')
      hilog.info(0, 'CatSubscription', 'download_complete kind=%{public}s bytes=%{public}d', kind, bytes.length)
      return bytes
    } catch (error) {
      const record = error as Record<string, Object>
      const code = record === null || record === undefined ? '' : CatVodCodec.text(record['code'])
      const message = error instanceof Error ? error.message :
        (record === null || record === undefined ? '' : CatVodCodec.text(record['message']))
      hilog.error(0, 'CatSubscription', 'download_failed kind=%{public}s code=%{public}s message=%{public}s', kind, code, message)
      if (error instanceof CatNodeHttpFailure) throw error
      throw new Error('订阅下载失败' + (code.length > 0 ? '（错误码 ' + code + '）' : '') +
        (message.length > 0 ? '：' + message : '，请检查网络连接'))
    } finally { request.destroy() }
  }
}
