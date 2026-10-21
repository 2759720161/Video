import { EmbyItem } from '../../providers/emby/EmbyModels'

export class EmbyHomeSection {
  id: string = ''
  title: string = ''
  collectionType: string = ''
  items: EmbyItem[] = []
  loading: boolean = false
  error: string = ''
}

export class EmbyHomeSnapshot {
  libraries: EmbyItem[] = []
  resumeItems: EmbyItem[] = []
  nextUpItems: EmbyItem[] = []
  latestItems: EmbyItem[] = []
  sections: EmbyHomeSection[] = []
  timestamp: number = 0
  librariesLoading: boolean = true
  resumeLoading: boolean = true
  librariesError: string = ''
  resumeError: string = ''
}
