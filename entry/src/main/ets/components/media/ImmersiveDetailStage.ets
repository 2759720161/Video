import { AppRadius } from '../../ui/theme/AppRadius'
import { AppSpacing } from '../../ui/theme/AppSpacing'
import { AppTypography } from '../../ui/theme/AppTypography'
import { AppSurface } from '../../ui/theme/AppSurface'

/** Artwork stays expressive; text and actions use semantic resources. */
@Component
export struct ImmersiveDetailStage {
  @Prop @Watch('resetArtworkState') backdropUrl: string = ''
  @Prop @Watch('resetArtworkState') posterUrl: string = ''
  @Prop title: string = ''
  @Prop meta: string = ''
  @Prop artworkMode: string = 'none'
  @Prop actionText: string = '播放'
  @Prop actionDescription: string = ''
  @Prop actionEnabled: boolean = true
  @Prop busy: boolean = false
  @Prop progress: number = 0
  @Prop variantLabel: string = ''
  @Prop wide: boolean = false
  @Prop contentPadding: number = 16
  @Prop sharedTransitionId: string = ''
  @State private artworkFailed: boolean = false
  @State private posterFailed: boolean = false
  onPrimaryAction?: () => void
  onVariantAction?: () => void

  build() {
    Column({ space: AppSpacing.MD }) {
      if (this.hasLandscapeArtwork()) {
        Stack({ alignContent: Alignment.Bottom }) {
          Image(this.backdropUrl).width('100%').height(this.wide ? 240 : 216)
            .objectFit(ImageFit.Cover).draggable(false)
            .onError(() => this.artworkFailed = true).accessibilityLevel('no')
          Column().width('100%').height(112)
            .linearGradient({ direction: GradientDirection.Bottom,
              colors: [['#00000000', 0], [$r('app.color.page_background'), 1]] })
        }.width('100%').clip(true)
      }
      Column({ space: AppSpacing.MD }) {
        if (!this.hasLandscapeArtwork()) {
          Row({ space: AppSpacing.MD }) {
            this.Poster()
            Column() { this.Identity() }.layoutWeight(1)
          }.width('100%').alignItems(VerticalAlign.Center)
        } else {
          this.Identity()
        }
        if (this.actionText.length > 0 && this.onPrimaryAction) {
          Button({ type: ButtonType.Capsule }) {
            Row({ space: AppSpacing.SM }) {
              if (this.busy) {
                LoadingProgress().width(20).height(20).color($r('app.color.text_on_primary'))
              } else {
                SymbolGlyph($r('sys.symbol.play_fill')).fontSize(20)
                  .fontColor([$r('app.color.text_on_primary')]).accessibilityLevel('no')
              }
              Text(this.busy ? '正在准备播放' : this.actionText)
                .fontSize(AppTypography.BODY_LARGE).fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_on_primary'))
            }.padding({ top: 12, bottom: 12 })
          }.width('100%').constraintSize({ minHeight: 48 })
            .backgroundColor($r('app.color.accent_blue')).enabled(this.actionEnabled && !this.busy)
            .accessibilityText(this.actionText + '，' + this.actionDescription)
            .onClick(() => { if (this.onPrimaryAction) this.onPrimaryAction() })
          if (this.actionDescription.length > 0) {
            Text(this.actionDescription).fontSize(AppTypography.META)
              .fontColor($r('app.color.text_secondary')).width('100%').textAlign(TextAlign.Center)
          }
          if (this.progress > 0 && this.progress < 100) {
            Progress({ value: this.progress, total: 100, type: ProgressType.Linear })
              .width('100%').color($r('app.color.accent_blue'))
              .backgroundColor($r('app.color.divider_color'))
              .accessibilityText('已观看 ' + Math.round(this.progress) + '%')
          }
        }
        if (this.variantLabel.length > 0 && this.onVariantAction) {
          Button({ type: ButtonType.Normal }) {
            Row({ space: AppSpacing.SM }) {
              Text('播放版本').fontSize(AppTypography.BODY).fontColor($r('app.color.text_secondary'))
              Text(this.variantLabel).fontSize(AppTypography.BODY).fontColor($r('app.color.text_primary'))
                .layoutWeight(1).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).textAlign(TextAlign.End)
              SymbolGlyph($r('sys.symbol.chevron_down')).fontSize(14)
                .fontColor([$r('app.color.text_secondary')]).accessibilityLevel('no')
            }.width('100%').padding(12)
          }.width('100%').constraintSize({ minHeight: 48 }).borderRadius(AppRadius.SURFACE)
            .backgroundColor(AppSurface.color(AppSurface.SURFACE)).enabled(!this.busy)
            .onClick(() => { if (this.onVariantAction) this.onVariantAction() })
        }
      }.width('100%').alignItems(HorizontalAlign.Start)
        .padding({ left: this.contentPadding, right: this.contentPadding,
          top: this.hasLandscapeArtwork() ? 0 : AppSpacing.LG, bottom: AppSpacing.SM })
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  private Identity(): void {
    Column({ space: AppSpacing.SM }) {
      Text(this.title).fontSize(AppTypography.HERO_TITLE).fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary')).width('100%')
      if (this.meta.length > 0) {
        Text(this.meta).fontSize(AppTypography.META).fontColor($r('app.color.text_secondary')).width('100%')
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  private Poster(): void {
    Stack() {
      if (this.posterUrl.length > 0 && !this.posterFailed) {
        Image(this.posterUrl).width(96).height(144).objectFit(ImageFit.Cover)
          .sharedTransition(this.sharedTransitionId, { duration: 300, curve: Curve.FastOutSlowIn })
          .onError(() => this.posterFailed = true).accessibilityLevel('no')
      } else {
        SymbolGlyph($r('sys.symbol.play_round_rectangle')).fontSize(32)
          .fontColor([$r('app.color.text_secondary')]).accessibilityLevel('no')
      }
    }.width(96).height(144).borderRadius(AppRadius.MEDIA_POSTER)
      .backgroundColor(AppSurface.color(AppSurface.SURFACE_SECONDARY)).clip(true)
  }

  private hasLandscapeArtwork(): boolean {
    return !this.artworkFailed && this.backdropUrl.length > 0 &&
      (this.artworkMode === 'backdrop' || this.artworkMode === 'thumbnail')
  }

  private resetArtworkState(): void {
    this.artworkFailed = false
    this.posterFailed = false
  }
}
