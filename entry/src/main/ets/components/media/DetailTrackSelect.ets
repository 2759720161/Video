import { DetailSelectMaterialModifier } from '../../utils/DetailMaterial'
import { IMMERSIVE_STYLE_DEFAULT, PREFS_KEY_IMMERSIVE_MATERIAL_STYLE } from '../../utils/HdsPageStyle'

export class DetailTrackOption {
  id: number = -1
  title: string = ''
  detail: string = ''
  summary: string = ''
}

@Component
export struct DetailTrackSelect {
  @StorageLink(PREFS_KEY_IMMERSIVE_MATERIAL_STYLE) thickness: string = IMMERSIVE_STYLE_DEFAULT
  @Prop options: DetailTrackOption[] = []
  @Prop selectedId: number = -1
  @Prop label: string = ''
  @Prop selectionEnabled: boolean = true
  onSelect: (id: number) => void = () => {}

  private selectedIndex(): number {
    return this.options.findIndex((option: DetailTrackOption) => option.id === this.selectedId)
  }

  private value(): string {
    const option = this.options[this.selectedIndex()]
    return option === undefined ? this.label : option.title + (option.summary.length > 0 ? ' ' + option.summary : '')
  }

  build() {
    Select(this.options.map((option: DetailTrackOption): SelectOption => ({
      value: option.title + (option.detail.length > 0 ? ' · ' + option.detail : '')
    })))
      .selected(this.selectedIndex()).value(this.value())
      .font({ size: 15, weight: FontWeight.Medium })
      .fontColor($r('sys.color.font_primary'))
      .optionFontColor($r('sys.color.font_primary'))
      .selectedOptionBgColor(Color.Transparent)
      .selectedOptionFontColor($r('sys.color.brand'))
      .attributeModifier(new DetailSelectMaterialModifier(this.thickness))
      .constraintSize({ minHeight: 44, maxWidth: '100%' })
      .enabled(this.selectionEnabled && this.options.length > 0)
      .accessibilityText(this.label + '，' + this.value())
      .onSelect((index: number) => {
        if (index >= 0 && index < this.options.length) this.onSelect(this.options[index].id)
      })
  }
}
