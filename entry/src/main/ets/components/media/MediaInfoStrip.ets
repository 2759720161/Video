import { AppRadius } from '../../ui/theme/AppRadius'
import { AppSpacing } from '../../ui/theme/AppSpacing'
import { AppSurface } from '../../ui/theme/AppSurface'
import { AppTypography } from '../../ui/theme/AppTypography'

export class MediaInfoMetric {
  value: string = ''
  label: string = ''

  constructor(value: string = '', label: string = '') {
    this.value = value
    this.label = label
  }
}

/** 聚合媒体统计信息，避免把每个指标拆成独立卡片。 */
@Component
export struct MediaInfoStrip {
  @Prop metrics: MediaInfoMetric[] = []
  @Prop ambientColor: string = ''

  build() {
    Stack() {
      Column()
        .width('100%').height('100%')
        .backgroundColor(AppSurface.color(AppSurface.SURFACE))
      if (this.ambientColor.length > 0) {
        Column()
          .width('100%').height('100%')
          .backgroundColor(this.ambientColor)
          .opacity(0.08)
      }
      Row({ space: 0 }) {
        ForEach(this.metrics, (metric: MediaInfoMetric, index: number) => {
          Column({ space: AppSpacing.XS }) {
            Text(metric.value)
              .fontSize(AppTypography.BODY_LARGE)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(metric.label)
              .fontSize(AppTypography.META)
              .fontColor($r('app.color.text_secondary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Center)
          .padding({ left: AppSpacing.SM, right: AppSpacing.SM })
          if (index < this.metrics.length - 1) {
            Divider()
              .vertical(true)
              .height(32)
              .strokeWidth(0.5)
              .color($r('app.color.divider_color'))
          }
        }, (metric: MediaInfoMetric, index: number) => metric.label + '_' + index)
      }
      .width('100%')
      .height(72)
      .padding({ left: AppSpacing.SM, right: AppSpacing.SM })
      .borderRadius(AppRadius.SURFACE)
      .border({ width: 0.5, color: this.ambientColor.length > 0 ? this.ambientColor : $r('app.color.divider_color') })
    }
    .width('100%')
    .height(72)
    .borderRadius(AppRadius.SURFACE)
    .clip(true)
  }
}
