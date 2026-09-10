import { AppRadius } from '../../ui/theme/AppRadius'
import { AppSpacing } from '../../ui/theme/AppSpacing'
import { AppTypography } from '../../ui/theme/AppTypography'
import { AppSurface } from '../../ui/theme/AppSurface'

/** Group Surface used by the player's More panel. */
@Component
export struct PlayerSettingGroup {
  @Prop title: string = ''
  @BuilderParam content: () => void

  build() {
    Column() {
      if (this.title.length > 0) {
        Text(this.title)
          .fontSize(AppTypography.CAPTION)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .padding({ left: AppSpacing.MD, right: AppSpacing.MD, top: AppSpacing.SM, bottom: AppSpacing.XS })
      }
      Column() {
        this.content()
      }
      .width('100%')
    }
    .width('100%')
    .borderRadius(AppRadius.SURFACE)
    .clip(true)
    .backgroundColor(AppSurface.color(AppSurface.SURFACE))
    .border({ width: 0.5, color: AppSurface.borderColor() })
  }
}
