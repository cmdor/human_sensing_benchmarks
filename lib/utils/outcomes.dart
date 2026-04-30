import 'trial_framework.dart';

class TrialOutcome {
  const TrialOutcome({
    required this.trialIndex,
    required this.correct,
    required this.valid,
    required this.reactionMs,
    required this.details,
  });

  final int trialIndex;
  final bool correct;
  final bool valid;
  final int? reactionMs;

  /// Trial-specific fields (e.g. contrast, rotationDegrees, guess, geometry).
  final Map<String, Object?> details;
}

List<TrialOutcome> deriveOutcomes(SessionReport report) {
  // Collect the last/first reaction time per trialIndex from guess_submitted.
  final Map<int, int?> reactionByTrial = <int, int?>{};
  for (final e in report.events) {
    if (e.type != 'guess_submitted') continue;
    final idx = e.data['trialIndex'];
    if (idx is! int) continue;
    final r = e.data['reactionMs'];
    reactionByTrial[idx] = r is int ? r : null;
  }

  final List<TrialOutcome> out = <TrialOutcome>[];
  for (final e in report.events) {
    if (e.type != 'trial_scored') continue;
    final idx = e.data['trialIndex'];
    if (idx is! int) continue;
    final correct = e.data['correct'] == true;
    final valid = e.data['valid'] == true;

    // Prefer reactionMs from trial_scored (if present), otherwise from guess_submitted.
    final directReaction = e.data['reactionMs'];
    final reactionMs = (directReaction is int) ? directReaction : reactionByTrial[idx];

    final Map<String, Object?> details = Map<String, Object?>.from(e.data);
    details.remove('trialIndex');
    details.remove('correct');
    details.remove('valid');
    details.remove('reactionMs');

    out.add(
      TrialOutcome(
        trialIndex: idx,
        correct: correct,
        valid: valid,
        reactionMs: reactionMs,
        details: details,
      ),
    );
  }

  out.sort((a, b) => a.trialIndex.compareTo(b.trialIndex));
  return out;
}

