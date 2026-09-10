/** V3 surface roles. Components choose a role instead of inventing a color. */
export enum AppSurfaceRole {
  PAGE = 'page',
  MEDIA_PAGE = 'media_page',
  SURFACE = 'surface',
  SURFACE_SECONDARY = 'surface_secondary',
  SURFACE_INTERACTIVE = 'surface_interactive',
  SURFACE_SELECTED = 'surface_selected',
  OVERLAY = 'overlay',
  SCRIM = 'scrim',
  DIVIDER = 'divider'
}

export class AppSurface {
  static readonly PAGE: AppSurfaceRole = AppSurfaceRole.PAGE
  static readonly MEDIA_PAGE: AppSurfaceRole = AppSurfaceRole.MEDIA_PAGE
  static readonly SURFACE: AppSurfaceRole = AppSurfaceRole.SURFACE
  static readonly SURFACE_SECONDARY: AppSurfaceRole = AppSurfaceRole.SURFACE_SECONDARY
  static readonly SURFACE_INTERACTIVE: AppSurfaceRole = AppSurfaceRole.SURFACE_INTERACTIVE
  static readonly SURFACE_SELECTED: AppSurfaceRole = AppSurfaceRole.SURFACE_SELECTED
  static readonly OVERLAY: AppSurfaceRole = AppSurfaceRole.OVERLAY
  static readonly SCRIM: AppSurfaceRole = AppSurfaceRole.SCRIM
  static readonly DIVIDER: AppSurfaceRole = AppSurfaceRole.DIVIDER

  static color(role: AppSurfaceRole): ResourceColor {
    switch (role) {
      case AppSurfaceRole.MEDIA_PAGE: return $r('app.color.page_background_media')
      case AppSurfaceRole.SURFACE: return $r('app.color.card_background')
      case AppSurfaceRole.SURFACE_SECONDARY: return $r('app.color.button_ghost_bg')
      case AppSurfaceRole.SURFACE_INTERACTIVE: return $r('app.color.button_ghost_bg')
      case AppSurfaceRole.SURFACE_SELECTED: return $r('app.color.category_menu_item_selected')
      case AppSurfaceRole.OVERLAY: return $r('app.color.card_background')
      case AppSurfaceRole.SCRIM: return '#66000000'
      case AppSurfaceRole.DIVIDER: return $r('app.color.divider_color')
      default: return $r('app.color.page_background')
    }
  }

  static borderColor(): ResourceColor {
    return $r('app.color.card_specular_border')
  }
}
