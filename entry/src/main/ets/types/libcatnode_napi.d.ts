declare module 'libcatnode_napi.so' {
  export interface CatNodeNative {
    start(scriptPath: string, dataRoot: string, onEvent: (json: string) => void): void
    stop(): void
    isRunning(): boolean
  }
  const native: CatNodeNative
  export default native
}
