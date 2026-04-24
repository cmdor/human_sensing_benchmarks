import 'dart:math';

/// A single stimulus presentation: a letter at a contrast level.
class Trial {
  const Trial({
    required this.letter,
    required this.contrast,
  });

  /// The letter displayed for this trial (single uppercase A–Z).
  final String letter;

  /// Contrast level in the range [0.0, 1.0].
  final double contrast;
}

/// Random uppercase letter A–Z.
String randomUppercaseLetter(Random random) {
  return String.fromCharCode(65 + random.nextInt(26));
}

/// Builds a [Trial] with a random letter at the given contrast (clamped to [0.0, 1.0]).
Trial randomTrial(Random random, double contrast) {
  final c = contrast.clamp(0.0, 1.0);
  return Trial(letter: randomUppercaseLetter(random), contrast: c);
}

/// First A–Z letter in [raw], uppercased; otherwise null.
String? firstUppercaseLetter(String raw) {
  for (final unit in raw.trim().toUpperCase().codeUnits) {
    if (unit >= 65 && unit <= 90) {
      return String.fromCharCode(unit);
    }
  }
  return null;
}

/// True if the user's text identifies the same letter as the trial.
bool guessEqualsTrialLetter(String rawGuess, Trial trial) {
  final g = firstUppercaseLetter(rawGuess);
  if (g == null) return false;
  return g == trial.letter;
}

/// Contrast after one correct answer: multiply by [stepFactor].
///
/// With 0 < [stepFactor] < 1, `log(contrast)` drops by `-log(stepFactor)` each step,
/// so steps are even in log space and contrast approaches 0 asymptotically.
double contrastAfterCorrectLogStep(
  double current, {
  double stepFactor = 0.85,
}) {
  if (current <= 0) return 0;
  return (current * stepFactor).clamp(0.0, 1.0);
}

