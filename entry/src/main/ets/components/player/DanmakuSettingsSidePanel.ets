import { DanmakuSettingsPanelContent } from './DanmakuSettingsPanel'
import { createConfiguredImmersiveMaterial } from '../../utils/ImmersiveMaterial'

@Component
export struct DanmakuSettingsSidePanel {
  @Prop showPanel: boolean = false
  @Prop isDanmakuEnabled: boolean = true
  @Prop isFullScreen: boolean = true
  @Prop settingsVersion: number = 0
  onPanelClose: () => void = () => {}
  onSetDanmakuEnabled: (enabled: boolean) => void = () => {}
  onPauseAutoHide: () => void = () => {}
  onResumeAutoHide: () => void = () => {}

  @State private panelOffsetX: number = 0

  build() {
    Stack({ alignContent: Alignment.End }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#80000000')
        .opacity(this.showPanel ? 1 : 0)
        .hitTestBehavior(this.showPanel ? HitTestMode.Default : HitTestMode.None)
        .onClick(() => {
          this.onPanelClose()
        })

      Column() {
        DanmakuSettingsPanelContent({
          isDanmakuEnabled: this.isDanmakuEnabled,
          isFullScreen: this.isFullScreen,
          settingsVersion: this.settingsVersion,
          onSetDanmakuEnabled: (enabled: boolean) => {
            this.onSetDanmakuEnabled(enabled)
          },
          onPanelClose: () => {
            this.onPanelClose()
          },
          onPauseAutoHide: () => {
            this.onPauseAutoHide()
          },
          onResumeAutoHide: () => {
            this.onResumeAutoHide()
          }
        })
      }
      .width('40%')
      .height('100%')
      .backgroundColor($r('app.color.page_background'))
      .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
      .border({ width: { left: 0.5 }, color: $r('app.color.divider_color') })
      .systemMaterial(createConfiguredImmersiveMaterial())
      .translate({ x: this.showPanel ? this.panelOffsetX : '100%' })
      .animation({ duration: 300, curve: Curve.EaseInOut })
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(this.showPanel ? HitTestMode.Default : HitTestMode.None)
  }
}
