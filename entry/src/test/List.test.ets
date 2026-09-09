import localUnitTest from './LocalUnit.test';
import playbackModelsTest from './PlaybackModels.test';

export default function testsuite() {
  localUnitTest();
  playbackModelsTest();
}
