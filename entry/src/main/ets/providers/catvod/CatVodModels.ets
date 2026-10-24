export class CatVodCategory {
  id: string = ''
  name: string = ''
  parentId: string = ''
}

export class CatVodEpisode {
  name: string = ''
  url: string = ''
  occurrence: number = 0
}

export class CatVodRoad {
  spiderKey: string = ''
  id: string = ''
  name: string = ''
  episodes: CatVodEpisode[] = []
}

export class CatVodVideo {
  id: string = ''
  name: string = ''
  poster: string = ''
  searchOnly: boolean = false
  remarks: string = ''
  overview: string = ''
  year: number = 0
  roads: CatVodRoad[] = []
}

export class CatVodPage {
  page: number = 1
  pageCount: number = 1
  categories: CatVodCategory[] = []
  videos: CatVodVideo[] = []
}

export class CatVodEpisodeIdentity {
  videoId: string = ''
  name: string = ''
  occurrence: number = 0
}

/** 原生采集来源的能力边界；不执行远端 Node.js 包。 */
export interface CatVodDataSource {
  categories(): Promise<CatVodCategory[]>
  page(categoryId: string, keyword: string, page: number): Promise<CatVodPage>
  detail(videoId: string): Promise<CatVodVideo | null>
}
