import { LengthMetrics, promptAction, uiMaterial } from '@kit.ArkUI'
import { deviceInfo } from '@kit.BasicServicesKit'
import { Logger, extractErrorMsg } from './Logger'
import { getImmersiveMaterialStyleStorageValue, IMMERSIVE_STYLE_THIN, IMMERSIVE_STYLE_ULTRA_THIN,
  resolveImmersiveMaterialStyle } from './HdsPageStyle'

const materialLogger: Logger = new Logger('DetailMaterial')

/** Diagnostic queries must never change the capability decision or break the sheet. */
function logSheetCapability(): void {
  const api = deviceInfo.sdkApiVersion
  if (api < 26) {
    materialLogger.info('sheet capability: sdk=%{public}d reason=api_below_26', api)
    return
  }
  try {
    const available = deviceInfo.apiAvailable('26.0.0')
    if (!available) {
      materialLogger.info('sheet capability: sdk=%{public}d reason=api_unavailable', api)
      return
    }
    const supported = uiMaterial.isImmersiveMaterialSupported()
    const state = uiMaterial.getMaterialInfo().state
    materialLogger.info('sheet capability: sdk=%{public}d supported=%{public}s state=%{public}d',
      api, String(supported), state)
    try {
      const level = uiMaterial.getGlobalMaterialLevel()
      materialLogger.info('sheet device level=%{public}d (EXQUISITE=%{public}d GENTLE=%{public}d SMOOTH=%{public}d)',
        level, uiMaterial.MaterialLevel.EXQUISITE, uiMaterial.MaterialLevel.GENTLE, uiMaterial.MaterialLevel.SMOOTH)
    } catch (err) {
      materialLogger.warn('sheet level query failed: %{public}s', extractErrorMsg(err))
    }
  } catch (err) {
    materialLogger.warn('sheet capability query failed: %{public}s', extractErrorMsg(err))
  }
}

/** Check the runtime before touching API 26 material classes on API 23–25 devices. */
export function supportsDetailMaterial(): boolean {
  if (deviceInfo.sdkApiVersion < 26) return false
  try {
    if (deviceInfo.apiAvailable('26.0.0')) {
      return uiMaterial.isImmersiveMaterialSupported() &&
        uiMaterial.getMaterialInfo().state !== uiMaterial.MaterialState.DISABLE
    }
  } catch (_) {
    return false
  }
  return false
}

/** A single material backs the sheet; its content must remain transparent. */
export function buildDetailSheetMaterial(
  thickness: string = getImmersiveMaterialStyleStorageValue()): uiMaterial.Material | undefined {
  if (deviceInfo.sdkApiVersion < 26) return undefined
  if (deviceInfo.apiAvailable('26.0.0')) {
    if (!supportsDetailMaterial()) return undefined
    return new uiMaterial.ImmersiveMaterial({
      style: resolveImmersiveMaterialStyle(thickness),
      colorInvert: thickness === IMMERSIVE_STYLE_ULTRA_THIN || thickness === IMMERSIVE_STYLE_THIN
    })
  }
  return undefined
}

/** The fallback surface must not cover the active native material backplate. */
export function buildDetailSheetOptions(thickness: string, options: SheetOptions): SheetOptions {
  logSheetCapability()
  materialLogger.info('sheet requested thickness=%{public}s', thickness)
  if (deviceInfo.sdkApiVersion < 26) {
    materialLogger.info('sheet result=fallback reason=api_below_26')
    return options
  }
  if (deviceInfo.apiAvailable('26.0.0')) {
    const material = buildDetailSheetMaterial(thickness)
    if (material !== undefined) {
      options.systemMaterial = material
      options.backgroundColor = Color.Transparent
      materialLogger.info('sheet result=native_configured style=%{public}d background=transparent (not render confirmation)',
        resolveImmersiveMaterialStyle(thickness))
    } else {
      materialLogger.warn('sheet result=fallback reason=capability_unsupported_disabled_or_query_failed')
    }
  } else {
    materialLogger.warn('sheet result=fallback reason=api_unavailable')
  }
  return options
}

export function buildDetailToastOptions(message: string,
  thickness: string = getImmersiveMaterialStyleStorageValue()): promptAction.ShowToastOptions {
  const options: promptAction.ShowToastOptions = { message: message }
  if (deviceInfo.sdkApiVersion < 26) return options
  if (deviceInfo.apiAvailable('26.0.0')) {
    if (!supportsDetailMaterial()) return options
    options.systemMaterial = new uiMaterial.ImmersiveMaterial({
      style: resolveImmersiveMaterialStyle(thickness),
      colorInvert: thickness === IMMERSIVE_STYLE_ULTRA_THIN || thickness === IMMERSIVE_STYLE_THIN
    })
  }
  return options
}

/** Use only in an ArkUI Navigation/NavDestination title bar, where Button material is supported. */
export class DetailTitleButtonMaterialModifier implements AttributeModifier<ButtonAttribute> {
  private thickness: string

  constructor(thickness: string) {
    this.thickness = thickness
  }

  applyNormalAttribute(instance: ButtonAttribute): void {
    if (deviceInfo.sdkApiVersion < 26) return
    if (deviceInfo.apiAvailable('26.0.0')) {
      if (!supportsDetailMaterial()) return
      instance.backgroundColor(Color.Transparent)
      instance.systemMaterial(new uiMaterial.ImmersiveMaterial({
        style: resolveImmersiveMaterialStyle(this.thickness),
        colorInvert: this.thickness === IMMERSIVE_STYLE_ULTRA_THIN || this.thickness === IMMERSIVE_STYLE_THIN,
        interactive: true,
        lightEffect: {}
      }))
    }
  }
}

/** Search must be hosted in a navigation title area for generic system material to take effect. */
export class SearchTitleMaterialModifier implements AttributeModifier<SearchAttribute> {
  private thickness: string

  constructor(thickness: string) { this.thickness = thickness }

  applyNormalAttribute(instance: SearchAttribute): void {
    if (!supportsDetailMaterial()) return
    instance.backgroundColor(Color.Transparent)
    instance.systemMaterial(new uiMaterial.ImmersiveMaterial({
      style: resolveImmersiveMaterialStyle(this.thickness),
      colorInvert: this.thickness === IMMERSIVE_STYLE_ULTRA_THIN || this.thickness === IMMERSIVE_STYLE_THIN,
      interactive: true, lightEffect: {}
    }))
  }
}

/** ToggleType.Button supports native material in the detail content area, unlike Button. */
export class DetailToggleButtonMaterialModifier implements AttributeModifier<ToggleAttribute> {
  private thickness: string
  private expanded: boolean
  private diagnosticName: string
  private fallbackBackground: ResourceColor | undefined
  private fallbackSelected: ResourceColor | undefined

  constructor(thickness: string, expanded: boolean = false, diagnosticName: string = '',
    fallbackBackground?: ResourceColor, fallbackSelected?: ResourceColor) {
    this.thickness = thickness
    this.expanded = expanded
    this.diagnosticName = diagnosticName
    this.fallbackBackground = fallbackBackground
    this.fallbackSelected = fallbackSelected
  }

  applyNormalAttribute(instance: ToggleAttribute): void {
    if (this.diagnosticName.length > 0) {
      materialLogger.info('toggle apply name=%{public}s expanded=%{public}s thickness=%{public}s sdk=%{public}d',
        this.diagnosticName, String(this.expanded), this.thickness, deviceInfo.sdkApiVersion)
      if (!supportsDetailMaterial()) {
        if (this.fallbackBackground !== undefined) instance.backgroundColor(this.fallbackBackground)
        if (this.fallbackSelected !== undefined) instance.selectedColor(this.fallbackSelected)
        materialLogger.warn('toggle result=fallback name=%{public}s expanded=%{public}s',
          this.diagnosticName, String(this.expanded))
        return
      }
    }
    if (deviceInfo.sdkApiVersion < 26) return
    if (deviceInfo.apiAvailable('26.0.0')) {
      if (!supportsDetailMaterial()) return
      instance.backgroundColor(Color.Transparent)
      instance.selectedColor(Color.Transparent)
      instance.systemMaterial(new uiMaterial.ImmersiveMaterial({
        style: resolveImmersiveMaterialStyle(this.thickness),
        colorInvert: this.thickness === IMMERSIVE_STYLE_ULTRA_THIN || this.thickness === IMMERSIVE_STYLE_THIN,
        interactive: true,
        lightEffect: {}
      }))
      if (this.diagnosticName.length > 0) {
        materialLogger.info('toggle result=native_configured name=%{public}s expanded=%{public}s style=%{public}d background=transparent (not render confirmation)',
          this.diagnosticName, String(this.expanded), resolveImmersiveMaterialStyle(this.thickness))
      }
    }
  }
}

/** Select's trigger and popup require independent component-level material settings. */
export class DetailSelectMaterialModifier implements AttributeModifier<SelectAttribute> {
  private thickness: string

  constructor(thickness: string) {
    this.thickness = thickness
  }

  applyNormalAttribute(instance: SelectAttribute): void {
    if (deviceInfo.sdkApiVersion < 26) return
    if (deviceInfo.apiAvailable('26.0.0')) {
      if (!supportsDetailMaterial()) return
      const style = resolveImmersiveMaterialStyle(this.thickness)
      const colorInvert = this.thickness === IMMERSIVE_STYLE_ULTRA_THIN || this.thickness === IMMERSIVE_STYLE_THIN
      instance.backgroundColor(Color.Transparent)
      instance.selectedOptionBgColor(Color.Transparent)
      instance.dividerStyle({ strokeWidth: LengthMetrics.vp(0), color: Color.Transparent })
      instance.systemMaterial(new uiMaterial.ImmersiveMaterial({
        style: style, colorInvert: colorInvert, interactive: true, lightEffect: {}
      }))
      instance.menuBackgroundColor(Color.Transparent)
      instance.menuSystemMaterial(new uiMaterial.ImmersiveMaterial({ style: style, colorInvert: colorInvert }))
    }
  }
}
