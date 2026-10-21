import { abilityDelegatorRegistry } from '@kit.TestKit'
import { fileIo } from '@kit.CoreFileKit'
import { describe, it, expect } from '@ohos/hypium'
import { CatNodeRuntime } from '../../../main/ets/providers/catvod/CatNodeRuntime'
import { CatNodeClient } from '../../../main/ets/providers/catvod/CatNodeClient'
import { CatVodCodec } from '../../../main/ets/providers/catvod/CatVodCodec'
import type { CatNodeNative } from 'libcatnode_napi.so'

interface CatNodeTestModule { default: CatNodeNative }
// Test fixture only. Production code contains no default subscription address.
const TEST_SUBSCRIPTION_URL: string = 'https://9280.kstore.space/ceshi/index.js.md5'

/** Executes the real library and original package inside the application sandbox. */
export default function catNodeRuntimeTest() {
  describe('CatNodeRuntimeDevice', () => {
    it('loadsNativeModuleAndValidatesArguments', 0, async () => {
      const module: CatNodeTestModule = await import('libcatnode_napi.so')
      expect(module.default.isRunning()).assertFalse()
      let rejected = false
      try { module.default.start('', '', (_json: string): void => {}) }
      catch (error) { rejected = error instanceof Error && error.message.includes('参数无效') }
      expect(rejected).assertTrue()
    })
    it('reportsStartupFailureWithoutCrashing', 0, async () => {
      const module: CatNodeTestModule = await import('libcatnode_napi.so')
      const context = abilityDelegatorRegistry.getAbilityDelegator().getAppContext().createModuleContext('entry')
      const root = context.filesDir + '/catnode-missing-program-probe'
      try {
        await new Promise<void>((resolve, reject) => {
          let sawError = false
          const timer = setTimeout(() => reject(new Error('原生启动失败未返回结果')), 30000)
          try {
            module.default.start(root + '/missing.cjs', root, (json: string): void => {
              const event = CatVodCodec.object(JSON.parse(json) as Object)
              if (event === null) return
              if (event['type'] === 'error') sawError = true
              if (event['type'] === 'stopped') {
                clearTimeout(timer)
                if (sawError) resolve()
                else reject(new Error('原生启动未报告失败原因'))
              }
            })
          } catch (error) {
            clearTimeout(timer)
            reject(error instanceof Error ? error : new Error('原生模块调用失败'))
          }
        })
      } finally { module.default.stop() }
    })
    it('runsCoreModulesAndLocalHttpServer', 0, async () => {
      const module: CatNodeTestModule = await import('libcatnode_napi.so')
      const context = abilityDelegatorRegistry.getAbilityDelegator().getAppContext().createModuleContext('entry')
      const root = context.filesDir + '/catnode-core-probe'
      if (!fileIo.accessSync(root)) fileIo.mkdirSync(root, true)
      const script = root + '/probe.cjs'
      const file = fileIo.openSync(script, fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC | fileIo.OpenMode.WRITE_ONLY)
      const code = "const http=require('node:http');const crypto=require('node:crypto');" +
        "const server=http.createServer((req,res)=>res.end('catnode-core-ok'));" +
        "server.listen(0,'127.0.0.1',()=>videoNativeNotify(JSON.stringify({type:'core-ready'," +
        "port:server.address().port,digest:crypto.createHash('sha256').update('hello').digest('hex')})));"
      try { fileIo.writeSync(file.fd, code) } finally { fileIo.closeSync(file) }
      try {
        const port = await new Promise<number>((resolve, reject) => {
          const timer = setTimeout(() => reject(new Error('Node 核心模块探测超时')), 15000)
          module.default.start(script, root, (json: string): void => {
            const event = CatVodCodec.object(JSON.parse(json) as Object)
            if (event === null) return
            if (event['type'] === 'core-ready') {
              clearTimeout(timer)
              if (event['digest'] !== '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824') {
                reject(new Error('Node 加密模块探测失败'))
              } else resolve(Number(event['port']))
            } else if (event['type'] === 'error' || event['type'] === 'stopped') {
              clearTimeout(timer)
              reject(new Error(CatVodCodec.text(event['message']) || 'Node 核心模块探测提前结束'))
            }
          })
        })
        expect(await CatNodeRuntime.request('http://127.0.0.1:' + port, null)).assertEqual('catnode-core-ok')
      } finally {
        module.default.stop()
        for (let attempt = 0; module.default.isRunning(); attempt++) {
          if (attempt > 750) throw new Error('Node 核心模块探测未退出')
          await new Promise<void>(resolve => setTimeout(resolve, 20))
        }
      }
    })
    it('startsOriginalBundleAndReadsDefaultSource', 0, async () => {
      const application = abilityDelegatorRegistry.getAbilityDelegator().getAppContext()
      const context = application.createModuleContext('entry')
      try {
        const address = await CatNodeRuntime.ensure(context, TEST_SUBSCRIPTION_URL)
        expect(address.nodeVersion).assertEqual('v24.2.0')
        expect(address.wasm).assertFalse()
        const health = CatVodCodec.object(JSON.parse(await CatNodeRuntime.request(address.baseUrl() + '/health', null)) as Object)
        expect(health !== null && health['ok'] === true).assertTrue()
        const sites = await CatNodeRuntime.sites(context, TEST_SUBSCRIPTION_URL)
        expect(sites.length > 0).assertTrue()
        expect(sites.some(site => site.key === 'wexaitiantang')).assertTrue()
        const categories = await new CatNodeClient(context, 'wexaitiantang', TEST_SUBSCRIPTION_URL).categories()
        expect(categories.length > 0).assertTrue()
        console.info('CATNODE_DEVICE_RESULT sources=' + sites.length + ' categories=' + categories.length)
      } finally {
        await CatNodeRuntime.shutdown()
      }
    })
    it('readsRemoteCategoryAndResolvesEpisode', 0, async () => {
      const context = abilityDelegatorRegistry.getAbilityDelegator().getAppContext().createModuleContext('entry')
      try {
        const client = new CatNodeClient(context, 'wexaitiantang', TEST_SUBSCRIPTION_URL)
        const page = await client.page('', '', 1)
        expect(page.videos.length > 0).assertTrue()
        if (page.videos.length === 0) throw new Error('默认来源没有返回作品')
        const detail = await client.detail(page.videos[0].id)
        expect(detail !== null).assertTrue()
        if (detail === null) throw new Error('默认来源没有返回对应详情')
        const road = detail.roads.find(value => value.name.toLowerCase().includes('m3u8')) ?? detail.roads[0]
        if (road === undefined || road.episodes.length === 0) throw new Error('默认来源没有返回分集')
        const stream = await client.resolve(road, road.episodes[0])
        expect(CatVodCodec.isPlayableUrl(stream.url)).assertTrue()
        console.info('CATNODE_DEVICE_REMOTE_RESULT videos=' + page.videos.length + ' playbackUrl=true')
      } finally { await CatNodeRuntime.shutdown() }
    })
  })
}
