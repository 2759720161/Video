import { ServicesContent } from './ServicesContent'

@Entry
@Component
struct SourceManagerPage {
  build() { Column() { ServicesContent() }.width('100%').height('100%') }
}
