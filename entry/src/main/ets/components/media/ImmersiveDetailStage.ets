import { FrameCallback } from '@kit.ArkUI'
import { AppRadius } from '../../ui/theme/AppRadius'
import { AppSpacing } from '../../ui/theme/AppSpacing'
import { AppTypography } from '../../ui/theme/AppTypography'
import { AppSurface } from '../../ui/theme/AppSurface'
import { DetailTrackOption, DetailTrackSelect } from './DetailTrackSelect'
import { DetailToggleButtonMaterialModifier } from '../../utils/DetailMaterial'
import {
  IMMERSIVE_STYLE_DEFAULT,
  PREFS_KEY_IMMERSIVE_MATERIAL_STYLE,
  resolveImmersiveBlurStyle
} from '../../utils/HdsPageStyle'

/** Stable shared poster with identity and track controls beside it. */
@Component
export struct ImmersiveDetailStage {
  @StorageLink(PREFS_KEY_IMMERSIVE_MATERIAL_STYLE) materialThickness: string = IMMERSIVE_STYLE_DEFAULT
  @Prop @Watch('resetArtworkState') posterUrl: string = ''
  @Prop title: string = ''
  @Prop meta: string = ''
  @Prop actionText: string = '播放'
  @Prop actionDescription: string = ''
  @Prop actionEnabled: boolean = true
  @Prop busy: boolean = false
  @Prop variantLabel: string = ''
  @Prop wide: boolean = false
  @Prop contentPadding: number = 16
  @Prop sharedTransitionId: string = ''
  @Prop audioOptions: DetailTrackOption[] = []
  @Prop subtitleOptions: DetailTrackOption[] = []
  @Prop selectedAudioId: number = -1
  @Prop selectedSubtitleId: number = -1
  @Prop tracksLoading: boolean = false
  onAudioSelect: (id: number) => void = () => {}
  onSubtitleSelect: (id: number) => void = () => {}
  @State private posterFailed: boolean = false
  @State private primaryActionSelected: boolean = false
  private primaryActionResetPending: boolean = false
  private actionAreaAlive: boolean = false
  onPrimaryAction?: () => void
  onVariantAction?: () => void

  aboutToAppear(): void {
    this.actionAreaAlive = true
  }

  aboutToDisappear(): void {
    this.actionAreaAlive = false
  }

  @Styles
  private secondaryPressedStyles(): void {
    .opacity(0.82)
    .scale({ x: 0.985, y: 0.985 })
  }

  @Styles
  private disabledActionStyles(): void {
    .opacity(0.5)
  }

  build() {
    Column({ space: AppSpacing.MD }) {
      Column({ space: AppSpacing.MD }) {
        Row({ space: AppSpacing.MD }) {
          this.Poster()
          Column({ space: AppSpacing.SM }) {
            this.Identity()
            if (this.tracksLoading) {
              Column().width('100%').height(40).borderRadius(20)
                .backgroundColor(AppSurface.color(AppSurface.SURFACE_SECONDARY))
              Column().width('80%').height(40).borderRadius(20)
                .backgroundColor(AppSurface.color(AppSurface.SURFACE_SECONDARY))
            } else {
              if (this.audioOptions.length > 0) {
                DetailTrackSelect({ options: this.audioOptions, selectedId: this.selectedAudioId,
                  label: '音轨', selectionEnabled: !this.busy, onSelect: this.onAudioSelect })
              }
              if (this.subtitleOptions.length > 0) {
                DetailTrackSelect({ options: this.subtitleOptions, selectedId: this.selectedSubtitleId,
                  label: '字幕', selectionEnabled: !this.busy, onSelect: this.onSubtitleSelect })
              }
            }
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        }.width('100%').alignItems(VerticalAlign.Top)
        this.ActionArea()
      }.width('100%').alignItems(HorizontalAlign.Start)
        .padding({ left: this.contentPadding, right: this.contentPadding,
          top: AppSpacing.LG, bottom: AppSpacing.SM })
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  private handlePrimaryActionChange(isOn: boolean): void {
    if (!isOn || this.primaryActionResetPending) return
    this.primaryActionResetPending = true
    // Reset after rendering so the native toggle also receives the false state.
    this.getUIContext().postFrameCallback(new DetailPlayActionReset(() => {
      if (!this.actionAreaAlive) return
      this.primaryActionSelected = false
      this.primaryActionResetPending = false
    }))
    if (this.actionEnabled && !this.busy && this.onPrimaryAction) this.onPrimaryAction()
  }

  @Builder
  private ActionArea(): void {
    Column({ space: AppSpacing.SM }) {
      if (this.actionText.length > 0 && this.onPrimaryAction) {
        Toggle({ type: ToggleType.Button, isOn: $$this.primaryActionSelected }) {
          Row({ space: AppSpacing.SM }) {
            if (this.busy) {
              LoadingProgress().width(20).height(20).color(Color.Black)
            } else {
              SymbolGlyph($r('sys.symbol.play_fill')).fontSize(20)
                .fontColor([Color.Black]).accessibilityLevel('no')
            }
            Text(this.busy ? '正在准备播放' : this.actionText)
              .fontSize(AppTypography.BODY_LARGE).fontWeight(FontWeight.Medium)
              .fontColor(Color.Black)
          }.padding({ top: 12, bottom: 12 })
        }.width('100%').constraintSize({ minHeight: 48 }).borderRadius(999)
          .backgroundColor(AppSurface.color(AppSurface.SURFACE))
          .selectedColor(AppSurface.color(AppSurface.SURFACE))
          .attributeModifier(new DetailToggleButtonMaterialModifier(this.materialThickness))
          .enabled(this.actionEnabled && !this.busy)
          .stateStyles({
            disabled: this.disabledActionStyles
          })
          .accessibilityText(this.actionText + '，' + this.actionDescription)
          .onChange((isOn: boolean) => this.handlePrimaryActionChange(isOn))
        if (this.actionDescription.length > 0) {
          Text(this.actionDescription).fontSize(AppTypography.META)
            .fontColor($r('app.color.detail_text_secondary')).width('100%').textAlign(TextAlign.Center)
        }
      }
      if (this.variantLabel.length > 0 && this.onVariantAction) {
        Button({ type: ButtonType.Normal }) {
          Row({ space: AppSpacing.SM }) {
            Text('播放版本').fontSize(AppTypography.BODY).fontColor($r('app.color.detail_text_secondary'))
            Text(this.variantLabel).fontSize(AppTypography.BODY).fontColor($r('app.color.text_primary'))
              .layoutWeight(1).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).textAlign(TextAlign.End)
            SymbolGlyph($r('sys.symbol.chevron_down')).fontSize(14)
              .fontColor([$r('app.color.detail_text_secondary')]).accessibilityLevel('no')
          }.width('100%').padding(12)
        }.width('100%').constraintSize({ minHeight: 48 }).borderRadius(AppRadius.SURFACE)
          .backgroundColor(Color.Transparent)
          .backgroundBlurStyle(resolveImmersiveBlurStyle(this.materialThickness))
          .border({ width: 0.5, color: AppSurface.borderColor() })
          .shadow({ radius: 14, color: $r('app.color.shadow_surface'), offsetY: 4 })
          .enabled(!this.busy)
          .stateStyles({
            pressed: this.secondaryPressedStyles,
            disabled: this.disabledActionStyles
          })
          .accessibilityText('播放版本，当前为 ' + this.variantLabel)
          .onClick(() => { if (this.onVariantAction) this.onVariantAction() })
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  private Identity(): void {
    Column({ space: AppSpacing.SM }) {
      Text(this.title).fontSize(AppTypography.HERO_TITLE).fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary')).width('100%')
      if (this.meta.length > 0) {
        Text(this.meta).fontSize(AppTypography.META).fontColor($r('app.color.detail_text_secondary')).width('100%')
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  private Poster(): void {
    Stack() {
      Stack() {
        if (this.posterUrl.length > 0 && !this.posterFailed) {
          Image(this.posterUrl).width(this.posterWidth()).height(this.posterHeight()).objectFit(ImageFit.Cover)
            .borderRadius(AppRadius.MEDIA_POSTER).clip(true)
            .sharedTransition(this.sharedTransitionId, { duration: 360, curve: Curve.FastOutSlowIn })
            .onError(() => this.posterFailed = true).accessibilityLevel('no')
        } else {
          SymbolGlyph($r('sys.symbol.play_round_rectangle')).fontSize(32)
            .fontColor([$r('app.color.detail_text_secondary')]).accessibilityLevel('no')
        }
      }.width(this.posterWidth()).height(this.posterHeight()).borderRadius(AppRadius.MEDIA_POSTER)
        .backgroundColor(AppSurface.color(AppSurface.SURFACE_SECONDARY))
        .clip(true)
    }.width(this.posterWidth()).height(this.posterHeight()).borderRadius(AppRadius.MEDIA_POSTER)
      .border({ width: 0.5, color: AppSurface.borderColor() })
      .shadow({ radius: 24, color: $r('app.color.shadow_surface'), offsetY: 9 })
  }

  private posterWidth(): number {
    return this.wide ? 144 : 112
  }

  private posterHeight(): number {
    return this.wide ? 216 : 168
  }

  private resetArtworkState(): void {
    this.posterFailed = false
  }
}

/** An action-style toggle must not retain its selection after the interaction. */
class DetailPlayActionReset extends FrameCallback {
  private reset: () => void

  constructor(reset: () => void) {
    super()
    this.reset = reset
  }

  onIdle(_timeLeftInNano: number): void {
    this.reset()
  }
}
