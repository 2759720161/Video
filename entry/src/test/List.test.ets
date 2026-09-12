import localUnitTest from './LocalUnit.test';
import playbackModelsTest from './PlaybackModels.test';
import embyLibraryPresentationTest from './EmbyLibraryPresentation.test';
import embyDetailPresentationTest from './EmbyDetailPresentation.test';

export default function testsuite() {
  localUnitTest();
  playbackModelsTest();
  embyLibraryPresentationTest();
  embyDetailPresentationTest();
}
