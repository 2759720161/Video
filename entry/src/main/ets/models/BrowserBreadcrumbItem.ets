/** 来源浏览面包屑的安全路由模型，只允许稳定目录身份和展示标题。 */
export class BrowserBreadcrumbItem {
  id: string = ''
  title: string = ''

  constructor(id: string = '', title: string = '') {
    this.id = id.trim()
    this.title = title.trim()
  }
}
