import { MediaItem } from '../../core/media/MediaItem'
import { CatVodVideo } from '../../providers/catvod/CatVodModels'

/** Display order never changes the provider's playback queue or episode identities. */
export class CatVodDetailPresentation {
  static heroHeight(width: number, topInset: number): number {
    const viewport = Number.isFinite(width) && width > 0 ? width : 360
    const inset = Number.isFinite(topInset) ? Math.max(0, topInset) : 0
    return Math.max(400 + inset, Math.min(620 + inset, viewport * 1.30 + inset))
  }

  static metadata(video: CatVodVideo): string {
    const values: string[] = []
    if (video.year > 0) values.push(String(video.year))
    if (video.remarks.trim().length > 0) values.push(video.remarks.trim())
    return values.join(' · ')
  }

  static ordered(episodes: MediaItem[], descending: boolean): MediaItem[] {
    const result = episodes.slice()
    if (descending) result.reverse()
    return result
  }

  static target(episodes: MediaItem[], selectedId: string): MediaItem | null {
    return episodes.find((item: MediaItem) => item.id === selectedId) ?? episodes[0] ?? null
  }

  static alpha(color: string, opacity: string): string {
    return /^#[0-9a-f]{6}$/i.test(color) && /^[0-9a-f]{2}$/i.test(opacity) ?
      '#' + opacity + color.substring(1) : '#00000000'
  }

  /** A normal gradient scrim reaches the exact page surface before the image's clipping edge. */
  static posterGradient(surface: string): [ResourceColor, number][] {
    const stops: [ResourceColor, number][] = [[CatVodDetailPresentation.alpha(surface, '00'), 0]]
    for (let i = 0; i <= 32; i++) {
      const t = i / 32
      const eased = t * t * t * (t * (t * 6 - 15) + 10)
      const alpha = Math.round(eased * 255).toString(16).padStart(2, '0')
      stops.push([CatVodDetailPresentation.alpha(surface, alpha), 0.24 + 0.64 * t])
    }
    stops.push([CatVodDetailPresentation.alpha(surface, 'ff'), 1])
    return stops
  }
}

export class CatVodEpisodeRow {
  items: MediaItem[] = []
  key: string = ''
}

/** One episode per lazily realized native ListItem. */
export class CatVodEpisodeRows implements IDataSource {
  private rows: CatVodEpisodeRow[] = []
  private listeners: DataChangeListener[] = []

  replace(episodes: MediaItem[], descending: boolean): void {
    const ordered = CatVodDetailPresentation.ordered(episodes, descending)
    const rows: CatVodEpisodeRow[] = []
    for (let i = 0; i < ordered.length; i++) {
      const row = new CatVodEpisodeRow()
      row.items = ordered.slice(i, i + 1)
      row.key = JSON.stringify(row.items.map((item: MediaItem) => item.id))
      rows.push(row)
    }
    this.rows = rows
    for (const listener of this.listeners) listener.onDataReloaded()
  }

  totalCount(): number { return this.rows.length }
  getData(index: number): CatVodEpisodeRow { return this.rows[index] }
  rowOf(id: string): number {
    return this.rows.findIndex((row: CatVodEpisodeRow) => row.items.some((item: MediaItem) => item.id === id))
  }
  registerDataChangeListener(listener: DataChangeListener): void {
    if (!this.listeners.includes(listener)) this.listeners.push(listener)
  }
  unregisterDataChangeListener(listener: DataChangeListener): void {
    const index = this.listeners.indexOf(listener)
    if (index >= 0) this.listeners.splice(index, 1)
  }
}
