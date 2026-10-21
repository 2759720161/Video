/** Editable address parts; no credentials or tokens are accepted in the URL. */
export class EmbyConnectionAddress {
  protocol: string = 'http'
  host: string = ''
  port: string = ''
  path: string = ''

  static parse(value: string, defaultProtocol: string = 'http'): EmbyConnectionAddress {
    let address = value.trim()
    if (address.length === 0) throw new Error('请输入主机地址')
    if (!/^[a-z][a-z0-9+.-]*:\/\//i.test(address)) address = defaultProtocol + '://' + address
    const parts = address.match(/^(https?):\/\/(\[[0-9a-f:.]+\]|[^\s/:?#@]+)(?::([0-9]+))?(\/[^\s?#]*)?\/?$/i)
    if (parts === null) throw new Error('请输入有效的 HTTP 或 HTTPS 服务器地址')
    const result = new EmbyConnectionAddress()
    result.protocol = parts[1].toLowerCase()
    result.host = parts[2].toLowerCase()
    result.port = parts[3] ?? ''
    result.path = parts[4] ?? ''
    if (result.port.length > 0) {
      const port = Number(result.port)
      if (port < 1 || port > 65535) throw new Error('端口范围为 1–65535')
      result.port = String(port)
    }
    while (result.path.endsWith('/')) result.path = result.path.substring(0, result.path.length - 1)
    return result
  }

  static build(protocol: string, host: string, port: string, path: string): string {
    const normalizedHost = host.trim()
    const normalizedPort = port.trim()
    const normalizedPath = path.trim()
    if (normalizedHost.length === 0) throw new Error('请输入主机地址')
    if (protocol !== 'http' && protocol !== 'https') throw new Error('请选择 HTTP 或 HTTPS 协议')
    if (!/^(\[[0-9a-f:.]+\]|[^\s/:?#@]+)$/i.test(normalizedHost)) {
      throw new Error('主机地址不应包含协议、端口或路径')
    }
    if (normalizedPort.length > 0 && !/^[0-9]+$/.test(normalizedPort)) throw new Error('端口只能填写数字')
    const address = protocol + '://' + normalizedHost + (normalizedPort.length > 0 ? ':' + normalizedPort : '') +
      (normalizedPath.length > 0 ? (normalizedPath.startsWith('/') ? '' : '/') + normalizedPath : '')
    const parsed = EmbyConnectionAddress.parse(address)
    return parsed.protocol + '://' + parsed.host + (parsed.port.length > 0 ? ':' + parsed.port : '') + parsed.path
  }
}
