import { AppSpacing } from '../../ui/theme/AppSpacing'
import { AppTypography } from '../../ui/theme/AppTypography'

/** 来源管理页分组标题。 */
@Component
export struct SourceSectionHeader {
  @Prop title: string = ''
  @Prop count: number = 0

  build() {
    Row() {
      Text(this.title)
        .fontSize(AppTypography.BODY)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_secondary'))
        .layoutWeight(1)
      if (this.count > 0) {
        Text(String(this.count))
          .fontSize(AppTypography.CAPTION)
          .fontColor($r('app.color.text_hint'))
      }
    }
    .width('100%')
    .padding({ left: AppSpacing.XS, right: AppSpacing.XS, top: AppSpacing.SM, bottom: AppSpacing.XS })
  }
}
