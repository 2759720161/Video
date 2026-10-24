import { PlaybackQueueItem } from '../../core/playback/PlaybackQueueItem'
import { PlaybackVariant } from '../../core/playback/PlaybackVariant'
import { PlaybackQueueGroup } from '../../core/playback/PlaybackQueueGroup'
import { PlayerEpisodePresentation } from './PlayerEpisodePresentation'

/** Native dialog provides the only material backplate. Content stays transparent. */
@CustomDialog
export struct PlayerEpisodePanel {
  controller?: CustomDialogController
  @Link queue: PlaybackQueueItem[]
  @Link groups: PlaybackQueueGroup[]
  @Link currentIndex: number
  @Link busy: boolean
  @Link error: string
  onSelect: (index: number) => void = () => {}
  onVariant: (id: string) => void = () => {}
  onGroupSelect: (groupId: string, index: number) => void = () => {}
  onClose: () => void = () => {}
  @State private reversed: boolean = false
  @State private browsedGroupId: string = ''
  private scroller: Scroller = new Scroller()

  private current(): PlaybackQueueItem | null {
    return this.currentIndex >= 0 && this.currentIndex < this.queue.length ? this.queue[this.currentIndex] : null
  }

  private locateCurrent(): void {
    const visible = this.visibleQueue()
    const index = visible.findIndex((item: PlaybackQueueItem) => this.isPlaying(item))
    if (index < 0) return
    this.scroller.scrollToIndex(this.reversed ? visible.length - 1 - index : index,
      false, ScrollAlign.CENTER)
  }

  private visibleGroup(): PlaybackQueueGroup | undefined {
    const id = this.browsedGroupId || this.current()?.variantId || ''
    return this.groups.find((group: PlaybackQueueGroup) => group.id === id) ?? this.groups[0]
  }

  private visibleQueue(): PlaybackQueueItem[] { return this.visibleGroup()?.items ?? this.queue }

  private isPlaying(item: PlaybackQueueItem): boolean {
    const current = this.current()
    return current !== null && item.sourceId === current.sourceId && item.mediaId === current.mediaId &&
      item.variantId === current.variantId
  }

  @Builder
  private Groups(): void {
    Scroll() {
      Row({ space: 8 }) {
        ForEach(this.groups, (group: PlaybackQueueGroup) => {
          Button(group.name).fontSize(13).fontWeight(FontWeight.Medium).height(36)
            .padding({ left: 14, right: 14 }).borderRadius(18).stateEffect(false).enabled(!this.busy)
            .fontColor(group.id === this.visibleGroup()?.id ? $r('app.color.accent_blue') : $r('sys.color.font_primary'))
            .backgroundColor(group.id === this.visibleGroup()?.id ? $r('app.color.button_ghost_bg') : '#127F7F7F')
            .onClick(() => { this.browsedGroupId = group.id; this.scroller.scrollEdge(Edge.Top) })
        }, (group: PlaybackQueueGroup) => group.id)
      }
    }.width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
  }

  @Builder
  private Variants(): void {
    Scroll() {
      Row({ space: 8 }) {
        ForEach(this.current()?.variants ?? [], (variant: PlaybackVariant) => {
          Button(variant.name || variant.quality)
            .fontSize(13).fontWeight(FontWeight.Medium).height(36).padding({ left: 14, right: 14 })
            .borderRadius(18).stateEffect(false).enabled(!this.busy)
            .fontColor(variant.id === this.current()?.variantId ? $r('app.color.accent_blue') : $r('sys.color.font_primary'))
            .backgroundColor(variant.id === this.current()?.variantId ? $r('app.color.button_ghost_bg') : '#127F7F7F')
            .onClick(() => this.onVariant(variant.id))
        }, (variant: PlaybackVariant) => variant.id)
      }
    }.width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
  }

  @Builder
  private Episode(item: PlaybackQueueItem, index: number): void {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 8 }) {
        if (this.isPlaying(item)) {
          SymbolGlyph($r('sys.symbol.play_fill')).fontSize(12).fontColor([$r('app.color.accent_blue')])
        } else {
          Text(String(index + 1).padStart(2, '0')).fontSize(12).fontColor($r('sys.color.font_secondary'))
        }
        Text(PlayerEpisodePresentation.label(item)).fontSize(14)
          .fontWeight(this.isPlaying(item) ? FontWeight.Bold : FontWeight.Medium)
          .fontColor(this.isPlaying(item) ? $r('app.color.accent_blue') : $r('sys.color.font_primary'))
          .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
      }.width('100%')
    }.width('100%').height(66).padding(12).borderRadius(16).stateEffect(false).enabled(!this.busy)
      .backgroundColor(this.isPlaying(item) ? $r('app.color.button_ghost_bg') : '#127F7F7F')
      .accessibilityText(PlayerEpisodePresentation.label(item))
      .onClick(() => {
        const group = this.visibleGroup()
        if (group !== undefined) this.onGroupSelect(group.id, index)
        else this.onSelect(index)
      })
  }

  build() {
    Column({ space: 14 }) {
      Row({ space: 8 }) {
        Column({ space: 4 }) {
          Text($r('app.string.player_episode_title')).fontSize(21).fontWeight(FontWeight.Bold)
            .fontColor($r('sys.color.font_primary'))
          Text($r('app.string.player_episode_count', this.visibleQueue().length)).fontSize(12)
            .fontColor($r('sys.color.font_secondary'))
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        Button(this.reversed ? $r('app.string.player_episode_ascending') : $r('app.string.player_episode_descending'))
          .height(36).padding({ left: 12, right: 12 }).fontSize(12).borderRadius(18)
          .fontColor($r('sys.color.font_secondary')).backgroundColor('#127F7F7F')
          .onClick(() => { this.reversed = !this.reversed })
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.xmark')).fontSize(17).fontColor([$r('sys.color.icon_primary')])
        }.width(36).height(36).backgroundColor('#127F7F7F')
          .accessibilityText($r('app.string.player_episode_close')).onClick(() => this.onClose())
      }.width('100%')
      Text(this.current()?.title ?? '').fontSize(14).fontColor($r('sys.color.font_secondary'))
        .width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      if (this.groups.length > 0) this.Groups()
      else if ((this.current()?.variants.length ?? 0) > 0) this.Variants()
      if (this.busy) {
        Row({ space: 8 }) {
          LoadingProgress().width(16).height(16).color($r('app.color.accent_blue'))
          Text($r('app.string.player_episode_switching')).fontSize(12).fontColor($r('sys.color.font_secondary'))
        }.width('100%')
      }
      if (this.error.length > 0) {
        Text(this.error).width('100%').fontSize(12).fontColor($r('app.color.text_error')).maxLines(3)
      }
      if (this.visibleQueue().length === 0) {
        Text($r('app.string.player_episode_empty')).fontSize(14).fontColor($r('sys.color.font_secondary'))
          .width('100%').layoutWeight(1).textAlign(TextAlign.Center)
      } else {
        Grid(this.scroller) {
          ForEach(PlayerEpisodePresentation.indices(this.visibleQueue().length, this.reversed), (index: number) => {
            GridItem() { this.Episode(this.visibleQueue()[index], index) }
          }, (index: number) => this.visibleGroup()?.id + ':' + index + ':' + this.visibleQueue()[index].sourceId + ':' +
            this.visibleQueue()[index].mediaId)
        }.columnsTemplate('1fr 1fr').columnsGap(10).rowsGap(10).width('100%').layoutWeight(1)
          .scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring)
          .onAreaChange(() => this.locateCurrent())
      }
    }.width('100%').height('100%').padding(20).borderRadius(24).backgroundColor(Color.Transparent)
  }
}
