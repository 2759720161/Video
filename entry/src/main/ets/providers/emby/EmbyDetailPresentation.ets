import { EmbyItem } from './EmbyModels'

/** One watch-state interpretation shared by the hero, rows and playback selection. */
export class EmbyDetailPresentation {
  static progress(item: EmbyItem): number {
    if (item.userData.played) return 100
    const reported = item.userData.playedPercentage
    if (Number.isFinite(reported) && reported > 0) return Math.min(100, reported)
    return item.durationMs() > 0 ? Math.min(100, Math.max(0, item.resumePositionMs() / item.durationMs() * 100)) : 0
  }

  static watched(item: EmbyItem): boolean {
    return item.userData.played || EmbyDetailPresentation.progress(item) >= 95
  }

  static canResume(item: EmbyItem): boolean {
    return !EmbyDetailPresentation.watched(item) && item.resumePositionMs() > 0
  }

  static preferred(items: EmbyItem[], initialId: string = ''): EmbyItem | null {
    if (initialId.length > 0) {
      for (const item of items) { if (item.id === initialId) return item }
    }
    for (const item of items) { if (EmbyDetailPresentation.canResume(item)) return item }
    for (const item of items) { if (!EmbyDetailPresentation.watched(item)) return item }
    return items.length > 0 ? items[0] : null
  }

  static actionLabel(item: EmbyItem): string {
    if (EmbyDetailPresentation.canResume(item)) return '继续播放'
    if (EmbyDetailPresentation.watched(item)) return '重新观看'
    return item.type === 'Episode' && item.indexNumber > 0 ? '播放第 ' + item.indexNumber + ' 集' : '播放'
  }

  static actionDescription(item: EmbyItem): string {
    const parts: string[] = []
    if (item.type === 'Episode') {
      if (item.parentIndexNumber > 0) parts.push('第 ' + item.parentIndexNumber + ' 季')
      if (item.indexNumber > 0) parts.push('第 ' + item.indexNumber + ' 集')
    }
    if (EmbyDetailPresentation.canResume(item) && item.durationMs() > item.resumePositionMs()) {
      parts.push('剩余 ' + Math.ceil((item.durationMs() - item.resumePositionMs()) / 60000) + ' 分钟')
    } else if (item.durationMs() > 0) {
      parts.push(Math.ceil(item.durationMs() / 60000) + ' 分钟')
    }
    return parts.join(' · ')
  }
}
