/** 媒体来源的敏感凭据。凭据不属于 MediaSourceInstance.configJson。 */
export class SourceCredential {
  sourceId: string = ''
  providerType: string = ''
  values: Record<string, string> = {}

  copy(): SourceCredential {
    const result = new SourceCredential()
    result.sourceId = this.sourceId
    result.providerType = this.providerType
    const keys = Object.keys(this.values)
    for (let i = 0; i < keys.length; i++) {
      const key = keys[i]
      const value = this.values[key]
      if (typeof value === 'string') result.values[key] = value
    }
    return result
  }
}
