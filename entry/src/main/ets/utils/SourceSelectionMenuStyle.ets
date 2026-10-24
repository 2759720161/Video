import { LengthMetrics } from '@kit.ArkUI'
import { deviceInfo } from '@kit.BasicServicesKit'
import { buildDetailSheetMaterial } from './DetailMaterial'

export function buildSourceSelectionMenuOptions(thickness: string, placement: Placement, onDismiss: () => void): MenuOptions {
  const material = buildDetailSheetMaterial(thickness)
  const options: MenuOptions = {
    placement: placement, borderRadius: 24, offset: { x: 0, y: 6 }, showInSubWindow: false,
    backgroundColor: material === undefined ? $r('app.color.card_background') : Color.Transparent,
    onDisappear: onDismiss
  }
  if (material !== undefined) options.systemMaterial = material
  if (deviceInfo.sdkApiVersion >= 26 && deviceInfo.apiAvailable('26.0.0')) {
    options.maxHeight = LengthMetrics.vp(320)
    options.scrollBar = BarState.Off
  }
  return options
}
