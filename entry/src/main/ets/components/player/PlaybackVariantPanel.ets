import { PlaybackVariant } from '../../core/playback/PlaybackVariant'

/** 播放版本选择面板，页面只消费统一 PlaybackVariant 模型。 */
@Component
export struct PlaybackVariantPanel {
  @Prop variants: PlaybackVariant[] = []
  @Prop selectedId: string = ''
  onSelect?: (variant: PlaybackVariant) => void

  build() {
    Column({ space: 4 }) {
      Text('播放版本').fontSize(18).fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary')).width('100%').margin({ bottom: 8 })
      ForEach(this.variants, (variant: PlaybackVariant) => {
        Row({ space: 8 }) {
          SymbolGlyph(variant.id === this.selectedId ? $r('sys.symbol.checkmark') : $r('sys.symbol.circle'))
            .fontSize(18).fontColor([variant.id === this.selectedId ? $r('app.color.accent_blue') : $r('app.color.text_hint')])
          Text(variant.name.length > 0 ? variant.name : variant.quality)
            .fontSize(14).fontColor($r('app.color.text_primary')).layoutWeight(1)
          if (variant.quality.length > 0) Text(variant.quality).fontSize(12).fontColor($r('app.color.text_secondary'))
        }
        .width('100%').height(44)
        .onClick(() => { if (this.onSelect) this.onSelect(variant) })
      }, (variant: PlaybackVariant) => 'playback_variant_' + variant.id)
    }
    .width('100%').padding(20)
  }
}
