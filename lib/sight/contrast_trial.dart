import 'dart:math';

import '../utils/trial_framework.dart';

class ContrastTrial {
  const ContrastTrial({
    required this.letter,
    required this.contrast,
  });

  /// The letter displayed for this trial (single uppercase A–Z).
  final String letter;

  /// Contrast level in the range [0.0, 1.0].
  final double contrast;
}

String randomUppercaseLetter(Random random) {
  return String.fromCharCode(65 + random.nextInt(26));
}

String? firstUppercaseLetter(String raw) {
  for (final unit in raw.trim().toUpperCase().codeUnits) {
    if (unit >= 65 && unit <= 90) {
      return String.fromCharCode(unit);
    }
  }
  return null;
}

double contrastAfterCorrectLogStep(
  double current, {
  double stepFactor = 0.85,
}) {
  if (current <= 0) return 0;
  return (current * stepFactor).clamp(0.0, 1.0);
}

/// Failure-level contrast in [0, 1], [thresholdPct] in percent (0–100),
/// [logContrastSensitivity] = log10(100 / threshold_pct), and [bitDepthEst]
/// from ceil(log2(100 / max(threshold_pct, 1e-6))), floored at 1 bit.
({
  double thresholdContrast,
  double thresholdPct,
  double logContrastSensitivity,
  int bitDepthEst,
}) contrastBitDepthEstimate({
  required double thresholdContrast,
}) {
  final clamped = thresholdContrast.clamp(0.0, 1.0);
  final thresholdPct = clamped * 100.0;
  final safePct = max(thresholdPct, 1e-6);
  final logContrastSensitivity = log(100.0 / safePct) / ln10;
  final bitDepthEst = max(1, (log(100.0 / safePct) / ln2).ceil());
  return (
    thresholdContrast: clamped,
    thresholdPct: thresholdPct,
    logContrastSensitivity: logContrastSensitivity,
    bitDepthEst: bitDepthEst,
  );
}

TrialGenerator<ContrastTrial> buildContrastGenerator(Random random) {
  return (state) {
    final contrast = (state.custom['contrast'] as double?) ?? 1.0;
    return ContrastTrial(
      letter: randomUppercaseLetter(random),
      contrast: contrast,
    );
  };
}

TrialScorer<ContrastTrial, String> contrastScorer() {
  return (trial, rawGuess) {
    final g = firstUppercaseLetter(rawGuess);
    if (g == null) {
      return const TrialScore(correct: false, valid: false);
    }
    final correct = g == trial.letter;
    return TrialScore(
      correct: correct,
      valid: true,
      data: <String, Object?>{
        'guess': g,
        'expected': trial.letter,
        'contrast': trial.contrast,
      },
    );
  };
}

TrialReducer contrastReducer({
  double stepFactor = 0.85,
  int wrongInARowToFinish = 2,
}) {
  return (state, score) {
    if (!score.valid) {
      return state;
    }

    final totalScored = state.totalScored + 1;
    if (!score.correct) {
      final wrongStreak = state.wrongStreak + 1;
      return state.copyWith(
        trialIndex: state.trialIndex + 1,
        totalScored: totalScored,
        correctScored: state.correctScored,
        wrongStreak: wrongStreak,
        finished: wrongStreak >= wrongInARowToFinish,
      );
    }

    final currentContrast = (state.custom['contrast'] as double?) ?? 1.0;
    final nextContrast = contrastAfterCorrectLogStep(
      currentContrast,
      stepFactor: stepFactor,
    );

    return state.copyWith(
      trialIndex: state.trialIndex + 1,
      totalScored: totalScored,
      correctScored: state.correctScored + 1,
      wrongStreak: 0,
      lastCorrectAt: DateTime.now(),
      custom: <String, Object?>{
        ...state.custom,
        'contrast': nextContrast,
      },
    );
  };
}

