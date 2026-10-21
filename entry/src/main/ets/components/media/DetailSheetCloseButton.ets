import { HdsTabs, hdsMaterial } from '@kit.UIDesignKit'

/** Reconstructs the measured floating-tab material carrier described in the reference Markdown. */
@Component
export struct DetailSheetCloseButton {
  onClose: () => void = () => {}
  @State private measuredWidth: number = 0
  @State private measuredHeight: number = 0
  @State private offsetY: number = 0

  @Builder
  private CloseButton(): void {
    Button({ type: ButtonType.Normal }) {
      Image($r('sys.media.ohos_ic_public_cancel')).width(20).height(20)
        .fillColor($r('sys.color.font_primary')).opacity(0.88)
    }.width(40).height(40).backgroundColor(Color.Transparent).borderRadius(20)
      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.94 })
      .accessibilityText('关闭').onClick(this.onClose)
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Button({ type: ButtonType.Normal }).width(40).height(40)
        .opacity(0).hitTestBehavior(HitTestMode.None).accessibilityLevel('no')
        .onSizeChange((_oldSize: SizeOptions, size: SizeOptions) => {
          this.measuredWidth = Number(size.width)
          this.measuredHeight = Number(size.height)
        })
      if (canIUse('SystemCapability.UIDesign.HDSComponent.Core') && this.measuredWidth > 0) {
        HdsTabs({ barPosition: BarPosition.End }) {
          TabContent() {}.tabBar(this.CloseButton())
        }.width(this.measuredWidth).height(this.measuredHeight)
          .barOverlap(true).vertical(false).scrollable(false)
          .barHeight(this.measuredHeight).backgroundColor(Color.Transparent)
          .barFloatingStyle({
            barWidth: { smallWidth: this.measuredWidth, mediumWidth: this.measuredWidth,
              largeWidth: this.measuredWidth },
            barSideMargin: 0,
            barBottomMargin: 0,
            systemMaterialEffect: {
              materialType: hdsMaterial.MaterialType.IMMERSIVE,
              materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
            },
            gradientMask: { maskColor: '#00999999' }
          })
          .onAreaChange((_oldArea: Area, area: Area) => {
            this.offsetY = (this.measuredHeight - Number(area.height)) / 2
          })
          .offset({ y: this.offsetY })
      }
    }.width(40).height(40)
  }
}
