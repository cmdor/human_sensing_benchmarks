import 'dart:math';

/// Minimal 2-down 1-up staircase with multiplicative (percent) step sizes.
///
/// Designed to be stored in `TrialRunnerState.custom` as a JSON-friendly map.
class Staircase {
  static const String kGapMs = 'gapMs';
  static const String kConsecutiveCorrect = 'consecutiveCorrect';
  static const String kDirection = 'direction'; // 'up' | 'down' | 'none'
  static const String kLastAnswerCorrect = 'lastAnswerCorrect'; // bool?
  static const String kReversals = 'reversals';
  static const String kReversalCount = 'reversalCount';
  static const String kStepPct = 'stepPct';
  static const String kThresholdMs = 'thresholdMs';
  static const String kThresholdSdMs = 'thresholdSdMs';
  static const String kTrialGapHistory = 'trialGapHistory';
  static const String kTrialCorrectHistory = 'trialCorrectHistory';

  static Map<String, Object?> initialCustom({
    required double initialGapMs,
  }) {
    return <String, Object?>{
      kGapMs: initialGapMs,
      kConsecutiveCorrect: 0,
      kDirection: 'none',
      kLastAnswerCorrect: null,
      kReversals: <double>[],
      kReversalCount: 0,
      kStepPct: 0.20,
      kThresholdMs: null,
      kThresholdSdMs: null,
      kTrialGapHistory: <double>[],
      kTrialCorrectHistory: <bool>[],
    };
  }

  static double stepPctForReversals(int reversalCount) {
    // User-chosen schedule: start 20% decaying toward 5%.
    final pct = 0.20 * pow(0.85, reversalCount).toDouble();
    return max(0.05, pct);
  }

  static StaircaseUpdate update({
    required Map<String, Object?> custom,
    required bool correct,
    required double presentedGapMs,
    required double minGapMs,
    required double maxGapMs,
  }) {
    final gapMs = _asDouble(custom[kGapMs]) ?? presentedGapMs;
    final consecutiveCorrect = _asInt(custom[kConsecutiveCorrect]) ?? 0;
    final prevDirection = (custom[kDirection] as String?) ?? 'none';
    final lastAnswerCorrect = custom[kLastAnswerCorrect] as bool?;
    final reversals = _asDoubleList(custom[kReversals]) ?? <double>[];
    final reversalCount = _asInt(custom[kReversalCount]) ?? reversals.length;

    final gapHistory = _asDoubleList(custom[kTrialGapHistory]) ?? <double>[];
    final correctHistory = _asBoolList(custom[kTrialCorrectHistory]) ?? <bool>[];

    gapHistory.add(presentedGapMs);
    correctHistory.add(correct);

    var nextGap = gapMs;
    var nextConsecutiveCorrect = consecutiveCorrect;
    var steppedDirection = 'none';
    var didStep = false;

    final pct = stepPctForReversals(reversalCount);

    if (correct) {
      nextConsecutiveCorrect += 1;
      if (nextConsecutiveCorrect >= 2) {
        didStep = true;
        steppedDirection = 'down';
        nextGap = nextGap * (1.0 - pct);
        nextConsecutiveCorrect = 0;
      }
    } else {
      didStep = true;
      steppedDirection = 'up';
      nextGap = nextGap * (1.0 + pct);
      nextConsecutiveCorrect = 0;
    }

    nextGap = nextGap.clamp(minGapMs, maxGapMs).toDouble();

    var nextDirection = prevDirection;
    var nextReversals = reversals;
    var nextReversalCount = reversalCount;
    var reversalHappened = false;

    // Reversal definition (per your clarification):
    // A reversal occurs when answers flip correctness sequentially: rw or wr.
    if (lastAnswerCorrect != null && lastAnswerCorrect != correct) {
      reversalHappened = true;
      // Record the gap that was presented on the trial where the flip happened.
      // (This matches the "turnaround point" intuition: performance changed at this level.)
      nextReversals = List<double>.from(reversals)..add(presentedGapMs);
      nextReversalCount = nextReversals.length;
    }

    // Keep direction as an informational field about the last *step* applied.
    if (didStep) {
      nextDirection = steppedDirection;
    }

    final threshold = _meanLastN(nextReversals, 4);
    final thresholdSd = _sdLastN(nextReversals, 4);

    final out = <String, Object?>{
      kGapMs: nextGap,
      kConsecutiveCorrect: nextConsecutiveCorrect,
      kDirection: nextDirection,
      kLastAnswerCorrect: correct,
      kReversals: nextReversals,
      kReversalCount: nextReversalCount,
      kStepPct: pct,
      kThresholdMs: threshold,
      kThresholdSdMs: thresholdSd,
      kTrialGapHistory: gapHistory,
      kTrialCorrectHistory: correctHistory,
    };

    return StaircaseUpdate(
      custom: out,
      didStep: didStep,
      stepDirection: steppedDirection,
      reversalHappened: reversalHappened,
      reversalCount: nextReversalCount,
      thresholdMs: threshold,
      thresholdSdMs: thresholdSd,
      stepPct: pct,
      nextGapMs: nextGap,
    );
  }

  static double? _meanLastN(List<double> values, int n) {
    if (values.length < n) return null;
    final last = values.sublist(values.length - n);
    final sum = last.fold<double>(0.0, (a, b) => a + b);
    return sum / n;
  }

  static double? _sdLastN(List<double> values, int n) {
    final mean = _meanLastN(values, n);
    if (mean == null) return null;
    final last = values.sublist(values.length - n);
    final varSum = last.fold<double>(0.0, (a, x) => a + (x - mean) * (x - mean));
    return sqrt(varSum / n);
  }
}

class StaircaseUpdate {
  const StaircaseUpdate({
    required this.custom,
    required this.didStep,
    required this.stepDirection,
    required this.reversalHappened,
    required this.reversalCount,
    required this.thresholdMs,
    required this.thresholdSdMs,
    required this.stepPct,
    required this.nextGapMs,
  });

  final Map<String, Object?> custom;
  final bool didStep;
  final String stepDirection; // 'up' | 'down' | 'none'
  final bool reversalHappened;
  final int reversalCount;
  final double? thresholdMs;
  final double? thresholdSdMs;
  final double stepPct;
  final double nextGapMs;
}

double? _asDouble(Object? v) {
  if (v is double) return v;
  if (v is int) return v.toDouble();
  if (v is num) return v.toDouble();
  return null;
}

int? _asInt(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return null;
}

List<double>? _asDoubleList(Object? v) {
  if (v is List) {
    final out = <double>[];
    for (final x in v) {
      final d = _asDouble(x);
      if (d != null) out.add(d);
    }
    return out;
  }
  return null;
}

List<bool>? _asBoolList(Object? v) {
  if (v is List) {
    final out = <bool>[];
    for (final x in v) {
      if (x is bool) out.add(x);
    }
    return out;
  }
  return null;
}

