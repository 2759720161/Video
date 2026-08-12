declare module 'libmpv_napi.so' {
  export interface MpvEventData {
    eventId: number
    errorCode: number
    propertyName: string
    propertyValueStr: string
    propertyValueDouble: number
    reason: number
    logPrefix: string
    logLevel: string
    logText: string
  }

  export interface MpvNapiModule {
    nativeCreate: () => number
    nativeInitialize: (ctxId: number) => number
    nativeCommand: (ctxId: number, args: string[]) => number
    nativeCommandAsync: (ctxId: number, args: string[]) => number
    nativeLoadSubtitleMemory: (ctxId: number, data: ArrayBuffer, extension: string) => number
    nativeSetProperty: (ctxId: number, name: string, value: string) => number
    nativeGetProperty: (ctxId: number, name: string) => string | null
    nativeObserveProperty: (ctxId: number, replyUserdata: number, name: string, format: number) => number
    nativeDestroy: (ctxId: number) => void
    nativeSetSurfaceId: (ctxId: number, surfaceId: string) => number
    nativeApiVersion: () => number
  nativeOnEvent: (ctxId: number, callback: (event: MpvEventData) => void) => number
  nativeVpCreate: (qualityLevel: number) => number
  nativeVpSetOutputSurface: (surfaceId: string) => number
  nativeVpGetInputSurfaceId: () => string | null
  nativeVpSetQualityLevel: (qualityLevel: number) => number
  nativeVpStart: () => number
  nativeVpStop: () => number
  nativeVpDestroy: () => void
  }

  const mpvNapi: MpvNapiModule
  export default mpvNapi

  export const nativeCreate: () => number
  export const nativeInitialize: (ctxId: number) => number
  export const nativeCommand: (ctxId: number, args: string[]) => number
  export const nativeCommandAsync: (ctxId: number, args: string[]) => number
  export const nativeLoadSubtitleMemory: (ctxId: number, data: ArrayBuffer, extension: string) => number
  export const nativeSetProperty: (ctxId: number, name: string, value: string) => number
  export const nativeGetProperty: (ctxId: number, name: string) => string | null
  export const nativeObserveProperty: (ctxId: number, replyUserdata: number, name: string, format: number) => number
  export const nativeDestroy: (ctxId: number) => void
  export const nativeSetSurfaceId: (ctxId: number, surfaceId: string) => number
  export const nativeApiVersion: () => number
export const nativeOnEvent: (ctxId: number, callback: (event: MpvEventData) => void) => number
export const nativeVpCreate: (qualityLevel: number) => number
export const nativeVpSetOutputSurface: (surfaceId: string) => number
export const nativeVpGetInputSurfaceId: () => string | null
export const nativeVpSetQualityLevel: (qualityLevel: number) => number
export const nativeVpStart: () => number
export const nativeVpStop: () => number
export const nativeVpDestroy: () => void
}
