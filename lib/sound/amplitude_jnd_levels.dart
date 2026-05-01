import 'dart:math';

/// Linear peak gains for [AmplitudeJndPage] (SoLoud volume on normalized sine).
///
/// **Invariant:** `minPeakGain < referenceGain < maxPeakGain` so Δgain headroom
/// exists both louder and quieter; breaking this makes [amplitudeMaxDeltaGain]
/// negative and crashes `.clamp`.
/// Centered between min/max so symmetric Δ headroom is large (caps louder envelope near ~6 dB).
const double amplitudeJndReferenceGain = 0.50;
const double amplitudeJndMaxPeakGain = 0.98;
const double amplitudeJndMinPeakGain = 0.02;

/// Target louder-envelope Δ on the first trial (chart Y-axis). Capped by
/// [amplitudeMaxSymmetricLouderEnvelopeDb]: symmetric louder/quieter Δ cannot exceed ~6 dB.
const double amplitudeJndInitialEnvelopeDb = 7.0;

/// Signed amplitude ratio → dB (20·log10), odd peak vs reference peak.
double amplitudePeakDifferenceDb(double targetPeak, double referencePeak) {
  if (referencePeak <= 1e-12 || targetPeak <= 1e-12) return 0;
  return 20 * log(targetPeak / referencePeak) / ln10;
}

/// Staircase stores linear Δgain; plot/heuristic threshold in dB using the same
/// **louder-branch envelope** as peak amplitude (matches upper deviation before max clamp).
double amplitudeLinearDeltaToEnvelopeDb(double linearDelta) {
  return amplitudeLinearDeltaToEnvelopeDbFor(
    linearDelta: linearDelta,
    referenceGain: amplitudeJndReferenceGain,
    maxPeakGain: amplitudeJndMaxPeakGain,
  );
}

/// Same as [amplitudeLinearDeltaToEnvelopeDb] but uses recorded gains (e.g. Outcomes replay).
double amplitudeLinearDeltaToEnvelopeDbFor({
  required double linearDelta,
  required double referenceGain,
  required double maxPeakGain,
}) {
  final target = min(maxPeakGain, referenceGain + linearDelta);
  return amplitudePeakDifferenceDb(target, referenceGain);
}

/// Upper-envelope spread in dB corresponding to linear reversal SD.
double amplitudeThresholdSdEnvelopeDbFor({
  required double thresholdLinear,
  required double sdLinear,
  required double referenceGain,
  required double maxPeakGain,
}) {
  final hi = amplitudeLinearDeltaToEnvelopeDbFor(
    linearDelta: thresholdLinear + sdLinear,
    referenceGain: referenceGain,
    maxPeakGain: maxPeakGain,
  );
  final mid = amplitudeLinearDeltaToEnvelopeDbFor(
    linearDelta: thresholdLinear,
    referenceGain: referenceGain,
    maxPeakGain: maxPeakGain,
  );
  return hi - mid;
}

double amplitudeMaxDeltaGain() => min(
      amplitudeJndReferenceGain - amplitudeJndMinPeakGain,
      amplitudeJndMaxPeakGain - amplitudeJndReferenceGain,
    );

/// Louder-branch envelope (20·log10) when Δ is maxed under symmetric louder/quieter rules.
double amplitudeMaxSymmetricLouderEnvelopeDb() {
  final d = amplitudeMaxDeltaGain();
  if (!(d > 0)) return 0;
  final target = amplitudeJndReferenceGain + d;
  return amplitudePeakDifferenceDb(target, amplitudeJndReferenceGain);
}

/// Linear Δ so envelope aims for [desiredDb], capped by symmetric Δ and peak clamp.
double amplitudeLinearDeltaForLouderEnvelopeDb(double desiredDb) {
  final capDb = amplitudeMaxSymmetricLouderEnvelopeDb();
  final db = min(max(desiredDb, 0), capDb);
  final ratio = pow(10.0, db / 20.0).toDouble();
  final rawTarget = amplitudeJndReferenceGain * ratio;
  final target = min(amplitudeJndMaxPeakGain, rawTarget);
  var delta = max(0.0, target - amplitudeJndReferenceGain);
  delta = min(delta, amplitudeMaxDeltaGain());
  return delta;
}
