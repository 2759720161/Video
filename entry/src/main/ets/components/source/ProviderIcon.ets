import { ProviderCatalog } from '../../providers/base/ProviderCatalog'

@Component
export struct ProviderIcon {
  @Prop imageUri: string = ''
  @Prop providerType: string = ''
  @Prop iconSize: number = 25

  build() {
    Row() {
      if (this.imageUri.length > 0) Image(this.imageUri).width(this.iconSize + 8).height(this.iconSize + 8)
        .objectFit(ImageFit.Cover).borderRadius(10)
      else SymbolGlyph(this.iconResource())
        .fontSize(this.iconSize)
        .fontColor([this.iconColor()])
    }
  }

  private iconResource(): Resource {
    const descriptor = ProviderCatalog.get(this.providerType)
    const iconKind = descriptor === null ? 'media' : descriptor.iconKind
    return iconKind === 'folder' ? $r('sys.symbol.folder') :
      iconKind === 'plus' ? $r('sys.symbol.plus') : $r('sys.symbol.play_round_rectangle')
  }

  private iconColor(): ResourceColor {
    const descriptor = ProviderCatalog.get(this.providerType)
    if (descriptor !== null && descriptor.iconKind === 'folder') return $r('app.color.status_warning')
    if (descriptor !== null && descriptor.brandKind === 'emby') return $r('app.color.status_error')
    return $r('app.color.accent_blue')
  }
}
