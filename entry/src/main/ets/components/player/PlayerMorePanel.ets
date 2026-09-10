import { PlayerSettingRow } from './PlayerSettingRow'
import { PlayerSettingGroup } from './PlayerSettingGroup'

/** 播放器更多设置的纯 UI 面板。 */
@Component
export struct PlayerMorePanel {
  @Prop autoNextText: string = ''
  @Prop variantText: string = ''
  @Prop subtitleText: string = ''
  @Prop danmakuText: string = ''
  @Prop showVariantRow: boolean = true
  @Prop showDanmakuRows: boolean = false
  @Prop showPipRow: boolean = false
  onAutoNext?: () => void
  onPlaybackVariant?: () => void
  onAspect?: () => void
  onAudio?: () => void
  onSubtitle?: () => void
  onExternalSubtitle?: () => void
  onDualSubtitle?: () => void
  onSubtitleStyle?: () => void
  onSubtitleSettings?: () => void
  onDanmakuSettings?: () => void
  onDanmakuOffset?: () => void
  onLoadDanmaku?: () => void
  onMediaInfo?: () => void
  onPiP?: () => void

  build() {
    Column({ space: 2 }) {
      Text('播放设置').fontSize(18).fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary')).width('100%').margin({ bottom: 8 })
      Scroll() {
        Column({ space: 10 }) {
          PlayerSettingGroup({ title: '播放' }) {
            if (this.showVariantRow) {
              PlayerSettingRow({ title: '播放版本', value: this.variantText, onRowClick: () => {
                if (this.onPlaybackVariant) this.onPlaybackVariant()
              } })
            }
            PlayerSettingRow({ title: '自动下一集', value: this.autoNextText, onRowClick: () => {
              if (this.onAutoNext) this.onAutoNext()
            } })
          }
          PlayerSettingGroup({ title: '画面' }) {
            PlayerSettingRow({ title: '画面比例', onRowClick: () => { if (this.onAspect) this.onAspect() } })
          }
          PlayerSettingGroup({ title: '音频' }) {
            PlayerSettingRow({ title: '音轨', onRowClick: () => { if (this.onAudio) this.onAudio() } })
          }
          PlayerSettingGroup({ title: '字幕' }) {
            PlayerSettingRow({ title: '字幕轨', value: this.subtitleText, onRowClick: () => {
              if (this.onSubtitle) this.onSubtitle()
            } })
            PlayerSettingRow({ title: '外挂字幕', onRowClick: () => {
              if (this.onExternalSubtitle) this.onExternalSubtitle()
            } })
            PlayerSettingRow({ title: '双字幕', onRowClick: () => {
              if (this.onDualSubtitle) this.onDualSubtitle()
            } })
            PlayerSettingRow({ title: '字幕样式', onRowClick: () => {
              if (this.onSubtitleStyle) this.onSubtitleStyle()
            } })
            PlayerSettingRow({ title: '字幕设置', onRowClick: () => {
              if (this.onSubtitleSettings) this.onSubtitleSettings()
            } })
          }
          if (this.showDanmakuRows) {
            PlayerSettingGroup({ title: '弹幕' }) {
              PlayerSettingRow({ title: '弹幕设置', value: this.danmakuText, onRowClick: () => {
                if (this.onDanmakuSettings) this.onDanmakuSettings()
              } })
              PlayerSettingRow({ title: '弹幕时间偏移', onRowClick: () => {
                if (this.onDanmakuOffset) this.onDanmakuOffset()
              } })
              PlayerSettingRow({ title: '加载本地弹幕', onRowClick: () => {
                if (this.onLoadDanmaku) this.onLoadDanmaku()
              } })
            }
          }
          PlayerSettingGroup({ title: '其他' }) {
            PlayerSettingRow({ title: '媒体信息', onRowClick: () => { if (this.onMediaInfo) this.onMediaInfo() } })
            if (this.showPipRow) {
              PlayerSettingRow({ title: '画中画', onRowClick: () => { if (this.onPiP) this.onPiP() } })
            }
          }
        }
        .width('100%')
      }
      .width('100%').layoutWeight(1).scrollBar(BarState.Off)
    }
    .width('100%').height('100%').padding(20)
  }

}
