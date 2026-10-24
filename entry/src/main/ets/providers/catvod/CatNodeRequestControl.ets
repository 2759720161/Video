/** Per-search cancellation; never stops the shared Node engine. */
export class CatNodeRequestControl {
  cancelled: boolean = false
  private actions: (() => void)[] = []

  check(): void { if (this.cancelled) throw new Error('搜索已停止') }
  onCancel(action: () => void): void {
    if (this.cancelled) action()
    else this.actions.push(action)
  }
  offCancel(action: () => void): void { this.actions = this.actions.filter((value: () => void) => value !== action) }
  cancel(): void {
    if (this.cancelled) return
    this.cancelled = true
    const actions = this.actions; this.actions = []
    for (let i = 0; i < actions.length; i++) {
      try { actions[i]() } catch (_) {}
    }
  }
}
