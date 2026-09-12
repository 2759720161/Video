import { describe, it, expect } from '@ohos/hypium'
import { EmbyItem } from '../main/ets/providers/emby/EmbyModels'
import { EmbyDetailPresentation } from '../main/ets/providers/emby/EmbyDetailPresentation'

function episode(id: string, index: number, positionMinutes: number = 0): EmbyItem {
  const item = new EmbyItem()
  item.id = id
  item.type = 'Episode'
  item.indexNumber = index
  item.parentIndexNumber = 2
  item.runTimeTicks = 40 * 60000 * 10000
  item.userData.playbackPositionTicks = positionMinutes * 60000 * 10000
  return item
}

export default function embyDetailPresentationTest(): void {
  describe('EmbyDetailPresentation', () => {
    it('completed_items_with_stale_positions_are_rewatched_not_resumed', 0, () => {
      const completed = episode('done', 1, 12)
      completed.userData.played = true
      expect(EmbyDetailPresentation.canResume(completed)).assertFalse()
      expect(EmbyDetailPresentation.actionLabel(completed)).assertEqual('重新观看')
      expect(EmbyDetailPresentation.progress(completed)).assertEqual(100)
    })

    it('near_completion_has_the_same_state_in_hero_and_rows', 0, () => {
      const completed = episode('credits', 1, 39)
      const next = episode('next', 2)
      expect(EmbyDetailPresentation.watched(completed)).assertTrue()
      expect(EmbyDetailPresentation.preferred([completed, next])!.id).assertEqual('next')
      expect(EmbyDetailPresentation.actionLabel(next)).assertEqual('播放第 2 集')
    })

    it('explicit_episode_and_button_label_describe_the_same_target', 0, () => {
      const first = episode('first', 1)
      const requested = episode('requested', 7)
      const target = EmbyDetailPresentation.preferred([first, requested], 'requested')!
      expect(target.id).assertEqual('requested')
      expect(EmbyDetailPresentation.actionLabel(target)).assertEqual('播放第 7 集')
    })

    it('resume_reports_season_episode_and_remaining_time', 0, () => {
      const current = episode('resume', 7, 18)
      expect(EmbyDetailPresentation.actionLabel(current)).assertEqual('继续播放')
      expect(EmbyDetailPresentation.actionDescription(current)).assertEqual('第 2 季 · 第 7 集 · 剩余 22 分钟')
      expect(EmbyDetailPresentation.progress(current)).assertEqual(45)
    })

    it('invalid_reported_progress_falls_back_to_the_resume_position', 0, () => {
      const current = episode('invalid', 3, 10)
      current.userData.playedPercentage = Number.NaN
      expect(EmbyDetailPresentation.progress(current)).assertEqual(25)
      current.userData.playedPercentage = 150
      expect(EmbyDetailPresentation.progress(current)).assertEqual(100)
    })

    it('handles_empty_and_unknown_duration_without_invented_time', 0, () => {
      expect(EmbyDetailPresentation.preferred([]) === null).assertTrue()
      const unknown = episode('unknown', 5)
      unknown.runTimeTicks = 0
      expect(EmbyDetailPresentation.progress(unknown)).assertEqual(0)
      expect(EmbyDetailPresentation.actionDescription(unknown)).assertEqual('第 2 季 · 第 5 集')
    })
  })
}
