import { AppRadius } from '../../ui/theme/AppRadius'
import { AppSurface } from '../../ui/theme/AppSurface'

/** Shared grouped surface for related settings rows. */
@Component
export struct SettingsGroup {
  @BuilderParam content: () => void

  build() {
    Column() {
      this.content()
    }
    .width('100%').borderRadius(AppRadius.SURFACE).clip(true)
    .backgroundColor(AppSurface.color(AppSurface.SURFACE))
    .border({ width: 0.5, color: AppSurface.borderColor() })
  }
}
