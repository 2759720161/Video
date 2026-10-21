import { common } from '@kit.AbilityKit'
import { fileIo } from '@kit.CoreFileKit'
import { http } from '@kit.NetworkKit'
import { promptAction } from '@kit.ArkUI'
import type { CatNodeNative } from 'libcatnode_napi.so'
import { CatVodCodec } from './CatVodCodec'
import { CatNodeSubscription, CatNodeSubscriptionCodec, CatNodeSubscriptionStage } from './CatNodeSubscription'
import { buildDetailToastOptions } from '../../utils/DetailMaterial'

export class CatNodeAddress {
  port: number = 0
  hostPort: number = 0
  token: string = ''
  nodeVersion: string = ''
  wasm: boolean = false
  baseUrl(): string { return 'http://127.0.0.1:' + this.port }
}

export class CatNodeSite {
  key: string = ''
  name: string = ''
  type: number = 3
  ext: Object = ''
}

interface CatNodeNativeModule { default: CatNodeNative }

/** One long-lived engine per application process; loading is deferred until used. */
export class CatNodeRuntime {
  private static native: CatNodeNative | null = null
  private static address: CatNodeAddress | null = null
  private static hostAddress: CatNodeAddress | null = null
  private static pending: Promise<CatNodeAddress> | null = null
  private static stopping: Promise<void> | null = null
  private static resolveReady: ((value: CatNodeAddress) => void) | null = null
  private static rejectReady: ((reason: Error) => void) | null = null
  private static timeout: number = -1
  private static generation: number = 0
  private static subscriptionUrl: string = ''
  private static selection: Promise<void> = Promise.resolve()

  static ensure(context: common.Context, md5Url: string = '',
    onStage: (stage: CatNodeSubscriptionStage) => void = () => {}): Promise<CatNodeAddress> {
    const normalized = CatNodeSubscriptionCodec.normalizeUrl(md5Url)
    const task = CatNodeRuntime.selection.then(() => CatNodeRuntime.ensureSelected(context, normalized, onStage))
    CatNodeRuntime.selection = task.then(() => {}, () => {})
    return task
  }

  private static async ensureSelected(context: common.Context, md5Url: string,
    onStage: (stage: CatNodeSubscriptionStage) => void): Promise<CatNodeAddress> {
    if (CatNodeRuntime.stopping !== null) await CatNodeRuntime.stopping
    if (CatNodeRuntime.subscriptionUrl !== md5Url) {
      if (CatNodeRuntime.subscriptionUrl.length > 0) await CatNodeRuntime.shutdown()
      CatNodeRuntime.subscriptionUrl = md5Url
    }
    if (CatNodeRuntime.address === null && CatNodeRuntime.pending === null && CatNodeRuntime.native?.isRunning()) {
      await CatNodeRuntime.shutdown()
    }
    CatNodeRuntime.subscriptionUrl = md5Url
    if (CatNodeRuntime.address !== null) return CatNodeRuntime.address
    if (CatNodeRuntime.pending !== null) return CatNodeRuntime.pending
    const generation = ++CatNodeRuntime.generation
    const ready = new Promise<CatNodeAddress>((resolve, reject) => {
      CatNodeRuntime.resolveReady = resolve
      CatNodeRuntime.rejectReady = reject
    })
    CatNodeRuntime.pending = ready
    void CatNodeRuntime.launch(context, generation, md5Url, onStage).catch((error: Error) => {
      if (generation === CatNodeRuntime.generation) CatNodeRuntime.fail(error)
    })
    return ready
  }

  private static async launch(context: common.Context, generation: number, md5Url: string,
    onStage: (stage: CatNodeSubscriptionStage) => void): Promise<void> {
    const bundle = await CatNodeSubscription.prepare(context, md5Url, onStage)
    if (generation !== CatNodeRuntime.generation) throw new Error('Cat 订阅启动已取消')
    onStage(CatNodeSubscriptionStage.STARTING)
    const root = bundle.root
    const scripts = root + '/program'
    if (!fileIo.accessSync(scripts)) fileIo.mkdirSync(scripts, true)
    const names = ['host.cjs', 'bootstrap.cjs']
    for (let i = 0; i < names.length; i++) {
      const bytes = await context.resourceManager.getRawFileContent('catnode/' + names[i])
      if (generation !== CatNodeRuntime.generation) throw new Error('猫源启动已取消')
      const file = fileIo.openSync(scripts + '/' + names[i], fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC | fileIo.OpenMode.WRITE_ONLY)
      try {
        const length = fileIo.writeSync(file.fd, bytes.slice().buffer)
        if (length !== bytes.byteLength) throw new Error('猫源程序准备失败，请重试')
      } finally { fileIo.closeSync(file) }
    }
    const module: CatNodeNativeModule = await import('libcatnode_napi.so')
    if (generation !== CatNodeRuntime.generation) throw new Error('猫源启动已取消')
    CatNodeRuntime.native = module.default
    CatNodeRuntime.timeout = setTimeout(() => {
      CatNodeRuntime.native?.stop()
      CatNodeRuntime.fail(new Error('猫源启动超时，请稍后重试'))
    }, 60000)
    CatNodeRuntime.native.start(scripts + '/bootstrap.cjs', root, (json: string): void => {
      if (generation === CatNodeRuntime.generation) CatNodeRuntime.onEvent(json)
    })
  }

  private static onEvent(json: string): void {
    try {
      const event = CatVodCodec.object(JSON.parse(json) as Object)
      if (event === null) return
      const type = CatVodCodec.text(event['type'])
      if (type === 'host-ready') {
        const host = new CatNodeAddress()
        host.hostPort = Number(event['hostPort']); host.token = CatVodCodec.text(event['token'])
        if (!Number.isInteger(host.hostPort) || host.hostPort <= 0 || host.hostPort > 65535 || !/^[0-9a-f]{48}$/.test(host.token)) {
          throw new Error('猫源通信状态无效')
        }
        CatNodeRuntime.hostAddress = host
      } else if (type === 'ready') {
        const address = new CatNodeAddress()
        address.port = Number(event['port']); address.hostPort = Number(event['hostPort'])
        address.token = CatVodCodec.text(event['token']); address.nodeVersion = CatVodCodec.text(event['nodeVersion'])
        address.wasm = event['wasm'] === true
        if (!Number.isInteger(address.port) || address.port <= 0 || address.port > 65535 ||
          !Number.isInteger(address.hostPort) || address.hostPort <= 0 || address.hostPort > 65535 ||
          !/^[0-9a-f]{48}$/.test(address.token)) throw new Error('猫源启动状态无效')
        CatNodeRuntime.address = address
        CatNodeRuntime.hostAddress = address
        if (CatNodeRuntime.timeout >= 0) clearTimeout(CatNodeRuntime.timeout)
        CatNodeRuntime.timeout = -1
        CatNodeRuntime.resolveReady?.(address)
        CatNodeRuntime.resolveReady = null; CatNodeRuntime.rejectReady = null; CatNodeRuntime.pending = null
      } else if (type === 'error') {
        CatNodeRuntime.native?.stop()
        CatNodeRuntime.fail(new Error(CatVodCodec.text(event['message']) || '猫源启动失败'))
      } else if (type === 'engine-stopped') {
        CatNodeRuntime.native?.stop()
      } else if (type === 'stopped') {
        CatNodeRuntime.fail(new Error('猫源服务已停止，请重新打开来源'))
      } else if (type === 'webview') {
        // Login sniffing needs a result-bearing WebView adapter. Until available,
        // complete the request explicitly instead of pretending to have logged in.
        const result: Record<string, Object> = { 'success': false, 'code': -1, 'message': '该来源的网页登录暂未支持' }
        const reply: Record<string, Object> = { 'id': CatVodCodec.text(event['id']), 'result': result }
        void CatNodeRuntime.control('/runtime/host-reply', reply).catch(() => {})
      } else if (type === 'toast') {
        const opt = CatVodCodec.object(event['opt'])
        const message = opt === null ? CatVodCodec.text(event['opt']) :
          CatVodCodec.text(opt['msg']) || CatVodCodec.text(opt['text']) || CatVodCodec.text(opt['content'])
        if (message.length > 0) promptAction.showToast(buildDetailToastOptions(message.substring(0, 240)))
      }
    } catch (error) {
      CatNodeRuntime.native?.stop()
      CatNodeRuntime.fail(new Error(error instanceof Error ? error.message : '猫源通信失败'))
    }
  }

  private static fail(error: Error): void {
    if (CatNodeRuntime.timeout >= 0) clearTimeout(CatNodeRuntime.timeout)
    CatNodeRuntime.timeout = -1
    CatNodeRuntime.address = null
    CatNodeRuntime.hostAddress = null
    CatNodeRuntime.rejectReady?.(error)
    CatNodeRuntime.resolveReady = null; CatNodeRuntime.rejectReady = null; CatNodeRuntime.pending = null
  }

  static async sites(context: common.Context, md5Url: string = '',
    onStage: (stage: CatNodeSubscriptionStage) => void = () => {}): Promise<CatNodeSite[]> {
    const address = await CatNodeRuntime.ensure(context, md5Url, onStage)
    onStage(CatNodeSubscriptionStage.READING)
    return CatNodeRuntime.parseSites(await CatNodeRuntime.request(address.baseUrl() + '/config', null), address.baseUrl())
  }

  static parseSites(text: string, baseUrl: string): CatNodeSite[] {
    const raw = CatVodCodec.object(JSON.parse(text) as Object)
    const video = raw === null ? null : CatVodCodec.object(raw['video'])
    const group = video ?? raw
    const values = group !== null && Array.isArray(group['sites']) ? group['sites'] as Object[] : []
    const sites: CatNodeSite[] = []
    const seen: Set<string> = new Set()
    for (let i = 0; i < values.length; i++) {
      const value = CatVodCodec.object(values[i])
      if (value === null) continue
      const site = new CatNodeSite()
      site.name = CatVodCodec.text(value['name'])
      site.type = Number(value['type']); site.ext = value['ext'] ?? ''
      // The config key is nodejs_<key>, but HTTP routes use the underlying key.
      let api = CatVodCodec.text(value['api'])
      if (api.startsWith(baseUrl + '/spider/')) api = api.substring(baseUrl.length)
      const route = api.match(/^\/spider\/([^/]+)\/(\d+)$/)
      if (route === null) continue
      try { site.key = decodeURIComponent(route[1]) } catch (_) { continue }
      if (site.key.length > 0 && !/[\\/?#\u0000-\u001f]/.test(site.key) && site.name.length > 0 &&
        Number.isInteger(site.type) && site.type >= 0 && site.type < 10 && Number(route[2]) === site.type && !seen.has(site.key)) {
        sites.push(site); seen.add(site.key)
      }
    }
    if (sites.length === 0) throw new Error('完整猫源没有返回可用来源')
    return sites
  }

  static async control(route: string, body: Record<string, Object>): Promise<void> {
    const address = CatNodeRuntime.hostAddress
    if (address === null) return
    await CatNodeRuntime.request('http://127.0.0.1:' + address.hostPort + route, body, address.token)
  }

  static async shutdown(): Promise<void> {
    if (CatNodeRuntime.stopping !== null) return CatNodeRuntime.stopping
    const stopping = CatNodeRuntime.stopEngine()
    CatNodeRuntime.stopping = stopping
    try { await stopping }
    finally { if (CatNodeRuntime.stopping === stopping) CatNodeRuntime.stopping = null }
  }

  private static async stopEngine(): Promise<void> {
    const native: CatNodeNative | null = CatNodeRuntime.native
    const address = CatNodeRuntime.hostAddress
    CatNodeRuntime.generation++
    CatNodeRuntime.subscriptionUrl = ''
    CatNodeRuntime.fail(new Error('猫源服务已停止'))
    const body: Record<string, Object> = {}
    if (address !== null) {
      try {
        await CatNodeRuntime.request('http://127.0.0.1:' + address.hostPort + '/runtime/stop', body, address.token)
      }
      catch (_) {}
    }
    native?.stop()
    if (native !== null) {
      for (let attempt = 0; native.isRunning(); attempt++) {
        if (attempt >= 750) throw new Error('猫源仍在退出，请稍后重试')
        await new Promise<void>(resolve => setTimeout(resolve, 20))
      }
    }
  }

  static async request(url: string, body: Record<string, Object> | null, token: string = ''): Promise<string> {
    const request = http.createHttp()
    try {
      const headers: Record<string, string> = { 'Content-Type': 'application/json', 'Accept': 'application/json' }
      if (token.length > 0) headers['X-Video-Token'] = token
      const response = await request.request(url, {
        method: body === null ? http.RequestMethod.GET : http.RequestMethod.POST,
        header: headers, extraData: body === null ? '' : JSON.stringify(body),
        expectDataType: http.HttpDataType.STRING, connectTimeout: 10000, readTimeout: 30000,
        maxLimit: 8 * 1024 * 1024, usingCache: false
      })
      if (response.responseCode < 200 || response.responseCode >= 300 || typeof response.result !== 'string') {
        throw new Error('来源请求失败（HTTP ' + response.responseCode + '）')
      }
      return response.result
    } finally { request.destroy() }
  }
}
