import { promptAction } from '@kit.ArkUI'
import { BusinessError } from '@kit.BasicServicesKit'

export enum SourceActionKind {
  EDIT = 'edit',
  TEST = 'test',
  TOGGLE = 'toggle',
  REORDER = 'reorder',
  DELETE = 'delete'
}

/** 来源卡片的低频操作入口，避免把危险操作长期放在卡片一级。 */
@Component
export struct SourceActionSheet {
  @Prop title: string = ''
  @Prop isEnabled: boolean = true
  @Prop showEdit: boolean = true
  @Prop userToggleable: boolean = true
  @Prop userReorderable: boolean = true
  @Prop userRemovable: boolean = true
  onAction?: (action: SourceActionKind) => void

  build() {
    SymbolGlyph($r('sys.symbol.more'))
      .fontSize(22)
      .fontColor([$r('app.color.text_secondary')])
      .width(44)
      .height(44)
      .hitTestBehavior(HitTestMode.Block)
      .onClick(() => this.openActionMenu())
  }

  private openActionMenu(): void {
    try {
      const buttons: [promptAction.Button, promptAction.Button?, promptAction.Button?, promptAction.Button?,
        promptAction.Button?, promptAction.Button?] = [
        { text: '测试连接', color: $r('app.color.text_primary') }
      ]
      const actions: SourceActionKind[] = [SourceActionKind.TEST]
      if (this.showEdit) {
        buttons.unshift({ text: '编辑', color: $r('app.color.text_primary') })
        actions.unshift(SourceActionKind.EDIT)
      }
      if (this.userToggleable) {
        buttons.push({ text: this.isEnabled ? '停用媒体源' : '启用媒体源', color: $r('app.color.text_primary') })
        actions.push(SourceActionKind.TOGGLE)
      }
      if (this.userReorderable) {
        buttons.push({ text: '调整顺序', color: $r('app.color.text_primary') })
        actions.push(SourceActionKind.REORDER)
      }
      if (this.userRemovable) {
        buttons.push({ text: '删除媒体源', color: $r('app.color.status_error') })
        actions.push(SourceActionKind.DELETE)
      }
      this.getUIContext().getPromptAction().showActionMenu({
        title: this.title,
        buttons: buttons
      }, (err: BusinessError, result: promptAction.ActionMenuSuccessResponse) => {
        if (err !== undefined) return
        if (result.index >= 0 && result.index < actions.length && this.onAction) {
          this.onAction(actions[result.index])
        }
      })
    } catch (_) {
      // 操作菜单失败时不影响来源卡片本身的浏览入口。
    }
  }
}
