/// Keys stored on each persisted session [summary] map.
const String kSessionExperimentKind = 'experimentKind';
const String kSessionExperimentTitle = 'experimentTitle';

const String kExperimentSoundGapDetection = 'sound_gap_detection';
const String kExperimentPitchJnd = 'pitch_jnd';
const String kExperimentAmplitudeJnd = 'amplitude_jnd';
const String kExperimentContrastFinder = 'contrast_finder';
const String kExperimentERotation = 'e_rotation';
const String kExperimentPitchFrequencyRange = 'pitch_frequency_range';

/// Ensures exports and outcomes list always see a stable experiment id + human title.
Map<String, Object?> mergeExperimentIntoSummary(
  Map<String, Object?> summaryJson, {
  required String experimentKind,
  required String experimentTitle,
}) {
  return <String, Object?>{
    ...summaryJson,
    kSessionExperimentKind: experimentKind,
    kSessionExperimentTitle: experimentTitle,
  };
}
