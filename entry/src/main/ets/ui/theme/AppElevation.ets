/** Small, finite elevation vocabulary for V3 surfaces. */
export enum AppElevationLevel {
  NONE = 'none',
  LOW = 'low',
  FLOATING = 'floating',
  MODAL = 'modal'
}

export class AppElevation {
  static readonly NONE: AppElevationLevel = AppElevationLevel.NONE
  static readonly LOW: AppElevationLevel = AppElevationLevel.LOW
  static readonly FLOATING: AppElevationLevel = AppElevationLevel.FLOATING
  static readonly MODAL: AppElevationLevel = AppElevationLevel.MODAL
}
