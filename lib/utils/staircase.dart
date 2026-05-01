import 'dart:math';

/// Configuration for the adaptive staircase algorithm.
///
/// All fields are experiment-agnostic — they describe the step schedule and
/// stopping policy only.  Domain-specific details (what "level" means, its
/// units, its bounds) are supplied by the calling experiment.
class StaircaseConfig {
  const StaircaseConfig({
    this.downInitialPct = 0.20,
    this.upInitialPct = 0.20,
    this.decayFactor = 0.85,
    this.downMinPct = 0.05,
    this.upMinPct = 0.05,
    this.nDown = 2,
    this.thresholdLastN = 4,
  });

  /// Starting multiplicative step size for stepping DOWN (harder).
  /// Example: 0.20 = 20%.
  final double downInitialPct;

  /// Starting multiplicative step size for stepping UP (easier).
  final double upInitialPct;

  /// Factor by which the step shrinks after each reversal.
  final double decayFactor;

  /// Floor for the DOWN step size — never goes below this.
  final double downMinPct;

  /// Floor for the UP step size — never goes below this.
  final double upMinPct;

  /// Number of consecutive correct answers required to step down (harder).
  /// Classic 2-down 1-up = 2.
  final int nDown;

  /// How many reversal values to average when computing the threshold.
  final int thresholdLastN;

  double downStepPctForReversals(int reversalCount) {
    final pct = downInitialPct * pow(decayFactor, reversalCount).toDouble();
    return max(downMinPct, pct);
  }

  double upStepPctForReversals(int reversalCount) {
    final pct = upInitialPct * pow(decayFactor, reversalCount).toDouble();
    return max(upMinPct, pct);
  }
}

/// Minimal N-down 1-up staircase with multiplicative step sizes.
///
/// All state is stored in a JSON-friendly [Map] so it can be kept inside
/// [TrialRunnerState.custom] and persisted to the session report without
/// extra serialization work.
///
/// The algorithm is deliberately parameter-agnostic: "level" can mean gap
/// duration (ms), pitch delta (Hz or cents), amplitude delta (dB), etc.
/// The calling experiment supplies the bounds, initial value, and config.
class Staircase {
  // ── State-map keys ────────────────────────────────────────────────────────
  static const String kLevel = 'level';
  static const String kConsecutiveCorrect = 'consecutiveCorrect';
  static const String kDirection = 'direction'; // 'up' | 'down' | 'none'
  static const String kLastAnswerCorrect = 'lastAnswerCorrect'; // bool?
  static const String kReversals = 'reversals';
  static const String kReversalCount = 'reversalCount';
  static const String kStepPct = 'stepPct';
  static const String kThreshold = 'threshold';
  static const String kThresholdSd = 'thresholdSd';
  static const String kLevelHistory = 'levelHistory';
  static const String kCorrectHistory = 'correctHistory';

  static Map<String, Object?> initialCustom({
    required double initialLevel,
    StaircaseConfig config = const StaircaseConfig(),
  }) {
    return <String, Object?>{
      kLevel: initialLevel,
      kConsecutiveCorrect: 0,
      kDirection: 'none',
      kLastAnswerCorrect: null,
      kReversals: <double>[],
      kReversalCount: 0,
      kStepPct: config.downInitialPct,
      kThreshold: null,
      kThresholdSd: null,
      kLevelHistory: <double>[],
      kCorrectHistory: <bool>[],
    };
  }

  static StaircaseUpdate update({
    required Map<String, Object?> custom,
    required bool correct,
    required double presentedLevel,
    required double minLevel,
    required double maxLevel,
    StaircaseConfig config = const StaircaseConfig(),
  }) {
    final level = _asDouble(custom[kLevel]) ?? presentedLevel;
    final consecutiveCorrect = _asInt(custom[kConsecutiveCorrect]) ?? 0;
    final prevDirection = (custom[kDirection] as String?) ?? 'none';
    final lastAnswerCorrect = custom[kLastAnswerCorrect] as bool?;
    final reversals = _asDoubleList(custom[kReversals]) ?? <double>[];
    final reversalCount = _asInt(custom[kReversalCount]) ?? reversals.length;

    final levelHistory = _asDoubleList(custom[kLevelHistory]) ?? <double>[];
    final correctHistory = _asBoolList(custom[kCorrectHistory]) ?? <bool>[];

    levelHistory.add(presentedLevel);
    correctHistory.add(correct);

    var nextLevel = level;
    var nextConsecutiveCorrect = consecutiveCorrect;
    var steppedDirection = 'none';
    var didStep = false;
    final downPct = config.downStepPctForReversals(reversalCount);
    final upPct = config.upStepPctForReversals(reversalCount);

    if (correct) {
      nextConsecutiveCorrect += 1;
      if (nextConsecutiveCorrect >= config.nDown) {
        didStep = true;
        steppedDirection = 'down';
        nextLevel = nextLevel * (1.0 - downPct);
        nextConsecutiveCorrect = 0;
      }
    } else {
      didStep = true;
      steppedDirection = 'up';
      nextLevel = nextLevel * (1.0 + upPct);
      nextConsecutiveCorrect = 0;
    }

    nextLevel = nextLevel.clamp(minLevel, maxLevel).toDouble();

    var nextDirection = prevDirection;
    var nextReversals = reversals;
    var nextReversalCount = reversalCount;
    var reversalHappened = false;

    // A reversal occurs when answers flip correctness sequentially: rw or wr.
    if (lastAnswerCorrect != null && lastAnswerCorrect != correct) {
      reversalHappened = true;
      nextReversals = List<double>.from(reversals)..add(presentedLevel);
      nextReversalCount = nextReversals.length;
    }

    if (didStep) {
      nextDirection = steppedDirection;
    }

    final threshold = _meanLastN(nextReversals, config.thresholdLastN);
    final thresholdSd = _sdLastN(nextReversals, config.thresholdLastN);

    final out = <String, Object?>{
      kLevel: nextLevel,
      kConsecutiveCorrect: nextConsecutiveCorrect,
      kDirection: nextDirection,
      kLastAnswerCorrect: correct,
      kReversals: nextReversals,
      kReversalCount: nextReversalCount,
      kStepPct: steppedDirection == 'up' ? upPct : downPct,
      kThreshold: threshold,
      kThresholdSd: thresholdSd,
      kLevelHistory: levelHistory,
      kCorrectHistory: correctHistory,
    };

    return StaircaseUpdate(
      custom: out,
      didStep: didStep,
      stepDirection: steppedDirection,
      reversalHappened: reversalHappened,
      reversalCount: nextReversalCount,
      threshold: threshold,
      thresholdSd: thresholdSd,
      stepPct: steppedDirection == 'up' ? upPct : downPct,
      nextLevel: nextLevel,
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
    required this.threshold,
    required this.thresholdSd,
    required this.stepPct,
    required this.nextLevel,
  });

  final Map<String, Object?> custom;
  final bool didStep;
  final String stepDirection; // 'up' | 'down' | 'none'
  final bool reversalHappened;
  final int reversalCount;
  final double? threshold;
  final double? thresholdSd;
  final double stepPct;
  final double nextLevel;
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
