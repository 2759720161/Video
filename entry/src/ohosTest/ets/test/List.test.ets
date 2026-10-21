import abilityTest from './Ability.test';
import playbackModelsTest from '../../../test/PlaybackModels.test';
import catNodeRuntimeTest from './CatNodeRuntime.test';

export default function testsuite() {
  abilityTest();
  playbackModelsTest();
  catNodeRuntimeTest();
}
