import { EpisodeData } from './EpisodeData'

export class PlaybackRoad {
  name: string = ''
  identifier: string[] = []
  data: string[] = []
  episodes: EpisodeData[] = []

  static create(name: string, episodeNames: string[], episodeUrls: string[], sourceId: number, sourceName: string, animeUrl: string): PlaybackRoad {
    const road = new PlaybackRoad()
    road.name = name
    road.identifier = episodeNames
    road.data = episodeUrls
    const episodes: EpisodeData[] = []
    for (let i = 0; i < episodeUrls.length; i++) {
      const ed = new EpisodeData()
      ed.name = i < episodeNames.length ? episodeNames[i] : `第${i + 1}集`
      ed.url = episodeUrls[i]
      ed.sourceId = sourceId
      ed.sourceName = sourceName
      ed.animeUrl = animeUrl
      episodes.push(ed)
    }
    road.episodes = episodes
    return road
  }
}

export class PlaybackSource {
  name: string = ''
  sourceId: number = -1
  animeUrl: string = ''
  status: string = 'pending'
  message: string = ''
  roads: PlaybackRoad[] = []

  getEpisodeCount(): number {
    let count = 0
    for (let i = 0; i < this.roads.length; i++) {
      count += this.roads[i].episodes.length
    }
    return count
  }

  getAllEpisodes(): EpisodeData[] {
    const all: EpisodeData[] = []
    for (let i = 0; i < this.roads.length; i++) {
      for (let j = 0; j < this.roads[i].episodes.length; j++) {
        all.push(this.roads[i].episodes[j])
      }
    }
    return all
  }
}
