import { AppMotion } from '../../ui/theme/AppMotion'
import { AppRadius } from '../../ui/theme/AppRadius'
import { AppSpacing } from '../../ui/theme/AppSpacing'
import { AppSurface } from '../../ui/theme/AppSurface'
import { AppTypography } from '../../ui/theme/AppTypography'

/** V3 empty home hero for a library without playback history. */
@Component
export struct EmptyLibraryHero {
  @Prop minHeight: number = 280
  @State private isPrimaryPressed: boolean = false
  onOpenVideo?: () => void
  onOpenLocal?: () => void
  onConnectSource?: () => void

  build() {
    Column({ space: AppSpacing.LG }) {
      Column({ space: AppSpacing.SM }) {
        SymbolGlyph($r('sys.symbol.play_fill'))
          .fontSize(34)
          .fontColor([$r('app.color.accent_blue')])
        Text('开始你的媒体库')
          .fontSize(AppTypography.HERO_TITLE)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text('播放本地视频，或连接你的 Emby / WebDAV 媒体源')
          .fontSize(AppTypography.BODY)
          .fontColor($r('app.color.text_secondary'))
          .textAlign(TextAlign.Center)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)

      Button('打开视频')
        .height(48)
        .constraintSize({ minWidth: 148 })
        .fontSize(AppTypography.BODY_LARGE)
        .fontColor($r('app.color.text_on_primary'))
        .backgroundColor($r('app.color.accent_blue'))
        .borderRadius(AppRadius.BUTTON)
        .scale({ x: this.isPrimaryPressed ? AppMotion.NAVIGATION_PRESS_SCALE : 1,
          y: this.isPrimaryPressed ? AppMotion.NAVIGATION_PRESS_SCALE : 1 })
        .animation({ duration: AppMotion.TOUCH_FEEDBACK_MS, curve: Curve.EaseOut })
        .onTouch((event: TouchEvent) => {
          if (event.type === TouchType.Down) this.isPrimaryPressed = true
          else if (event.type === TouchType.Up || event.type === TouchType.Cancel) this.isPrimaryPressed = false
        })
        .onClick(() => {
          if (this.onOpenVideo) this.onOpenVideo()
        })

      Row({ space: AppSpacing.SM }) {
        this.SecondaryAction('folder', '本地媒体', () => {
          if (this.onOpenLocal) this.onOpenLocal()
        })
        this.SecondaryAction('server', '连接媒体源', () => {
          if (this.onConnectSource) this.onConnectSource()
        })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
    .constraintSize({ minHeight: this.minHeight })
    .padding({ top: AppSpacing.XL, bottom: AppSpacing.XL, left: AppSpacing.LG, right: AppSpacing.LG })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private SecondaryAction(iconKind: string, title: string, action: () => void): void {
    Column({ space: AppSpacing.XS }) {
      SymbolGlyph(iconKind === 'folder' ? $r('sys.symbol.folder') : $r('sys.symbol.plus'))
        .fontSize(20)
        .fontColor([$r('app.color.accent_blue')])
      Text(title)
        .fontSize(AppTypography.BODY)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .height(48)
    .constraintSize({ minWidth: 132 })
    .padding({ left: AppSpacing.MD, right: AppSpacing.MD })
    .justifyContent(FlexAlign.Center)
    .borderRadius(AppRadius.SMALL_BUTTON)
    .backgroundColor(AppSurface.color(AppSurface.SURFACE_INTERACTIVE))
    .onClick(action)
  }
}
