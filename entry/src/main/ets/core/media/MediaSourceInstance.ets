/** 一个具体的媒体来源实例，例如一个 Emby 服务器账号。 */
export class MediaSourceInstance {
  id: string = ''
  providerType: string = ''
  name: string = ''
  enabled: boolean = true
  sortOrder: number = 0
  configJson: string = '{}'
  createdAt: number = 0
  updatedAt: number = 0
}

export function createMediaSourceId(providerType: string): string {
  const normalizedType = providerType.trim().toLowerCase()
  if (normalizedType.length === 0) throw new Error('Provider type cannot be empty')
  return normalizedType + '_' + Date.now() + '_' + Math.floor(Math.random() * 1000000000)
}
