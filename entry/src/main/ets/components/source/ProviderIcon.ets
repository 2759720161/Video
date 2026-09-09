import { ProviderCatalog } from '../../providers/base/ProviderCatalog'

@Component
export struct ProviderIcon {
  @Prop providerType: string = ''

  build() {
    Row() {
      SymbolGlyph(this.iconResource())
        .fontSize(25)
        .fontColor([$r('app.color.accent_blue')])
    }
  }

  private iconResource(): Resource {
    const descriptor = ProviderCatalog.get(this.providerType)
    const iconKind = descriptor === null ? 'media' : descriptor.iconKind
    return iconKind === 'folder' ? $r('sys.symbol.folder') :
      iconKind === 'plus' ? $r('sys.symbol.plus') : $r('sys.symbol.play_round_rectangle')
  }
}
