import { LengthMetrics } from '@kit.ArkUI'

export interface SourceMenuEntry {
  key: string
  value: ResourceStr
  action: () => void
}

/** Shared directory/service menu; current selection is indicated by text color only. */
@Component
export struct SourceSelectionMenu {
  @Prop entries: SourceMenuEntry[] = []
  @Prop selectedKey: string = ''
  @Prop disabled: boolean = false
  @StorageLink('menuViewportWidthVp') viewportWidth: number = 360

  private menuWidth(): number {
    const viewport = Number.isFinite(this.viewportWidth) && this.viewportWidth > 0 ? this.viewportWidth : 360
    const available = Math.max(1, viewport - 32)
    const maximum = Math.floor(Math.min(360, available, Math.max(176, viewport * 0.78)))
    let width = Math.min(176, maximum)
    const context = this.getUIContext()
    for (const entry of this.entries) {
      let textWidth = typeof entry.value === 'string' ? entry.value.length * 16 : 0
      try {
        // Measure the heavier selection style for every item so selecting one cannot resize the menu.
        const measured = context.px2vp(context.getMeasureUtils().measureText({
          textContent: entry.value, fontSize: 16, fontWeight: FontWeight.Medium
        }))
        if (Number.isFinite(measured) && measured > 0) textWidth = measured
      } catch (_) {}
      width = Math.max(width, textWidth + 64)
      if (width >= maximum) return maximum
    }
    return Math.min(maximum, Math.ceil(width))
  }

  build() {
    Menu() {
      ForEach(this.entries, (entry: SourceMenuEntry) => {
        MenuItem(this.EntryRow(entry)).selected(entry.key === this.selectedKey).selectIcon(false)
          .enabled(!this.disabled).onClick(() => entry.action())
      }, (entry: SourceMenuEntry) => entry.key)
    }.width(this.menuWidth()).borderRadius(24)
      .menuItemDivider({ strokeWidth: LengthMetrics.vp(0.5), color: $r('app.color.category_menu_divider'),
        startMargin: LengthMetrics.vp(16), endMargin: LengthMetrics.vp(16) })
  }

  @Builder
  private EntryRow(entry: SourceMenuEntry): void {
    Text(entry.value).fontSize(16)
      .fontWeight(entry.key === this.selectedKey ? FontWeight.Medium : FontWeight.Regular)
      .fontColor(entry.key === this.selectedKey ? $r('app.color.accent_blue') : $r('app.color.text_primary'))
      .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
      .constraintSize({ minHeight: 50 }).padding({ left: 14, right: 14, top: 10, bottom: 10 })
  }
}
