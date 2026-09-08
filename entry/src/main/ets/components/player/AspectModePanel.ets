import { VideoAspectMode, VideoAspectModeHelper } from '../../core/player/IPlayerEngine'

class AspectModeItem {
  mode: VideoAspectMode = VideoAspectMode.contain
  label: string = ''
}

@Component
export struct AspectModePanel {
  @Prop currentMode: VideoAspectMode = VideoAspectMode.contain
  onSelectMode?: (mode: VideoAspectMode) => void

  private modeItems: AspectModeItem[] = []

  aboutToAppear(): void {
    const items: AspectModeItem[] = []
    let item0 = new AspectModeItem()
    item0.mode = VideoAspectMode.contain
    item0.label = '自动适应'
    items.push(item0)
    let item1 = new AspectModeItem()
    item1.mode = VideoAspectMode.cover
    item1.label = '裁切填充'
    items.push(item1)
    let item2 = new AspectModeItem()
    item2.mode = VideoAspectMode.fill
    item2.label = '拉伸填充'
    items.push(item2)
    this.modeItems = items
  }

  build() {
    Column() {
      ForEach(this.modeItems, (item: AspectModeItem) => {
        Row() {
          Text(item.label)
            .fontSize(15)
            .fontWeight(this.currentMode === item.mode ? FontWeight.Bold : FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)

          if (this.currentMode === item.mode) {
            SymbolGlyph($r('sys.symbol.checkmark'))
              .fontSize(18)
              .fontColor([$r('sys.color.brand')])
          }
        }
        .width('100%')
        .height(44)
        .padding({ left: 16, right: 16 })
        .borderRadius(8)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          if (this.onSelectMode) {
            this.onSelectMode(item.mode)
          }
        })
      })
    }
    .width(160)
    .padding({ top: 8, bottom: 8 })
    .borderRadius(16)
    .clip(true)
    .backgroundColor($r('app.color.speed_menu_surface'))
    .backgroundBlurStyle(BlurStyle.BACKGROUND_THICK)
    .border({ width: 0.5, color: $r('app.color.category_menu_divider') })
    .shadow({ radius: 20, color: $r('app.color.shadow_surface'), offsetY: 8 })
  }
}
