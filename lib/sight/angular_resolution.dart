// Visual angle / angular resolution computation for the E Rotation trial.
//
// Each step is a separate function so the pipeline can be read, tested,
// and debugged independently. The wrapper returns a Dart record with every
// intermediate value named, so call sites stay readable without having to
// recompute or shadow variables.
//
// Formula source:
//   "Normal visual acuity (20/20) is the ability to resolve a spatial
//    pattern separated by a visual angle of one minute of arc."
//   — Iowa State NDE-Ed, Visual Acuity of the Human Eye
//     https://www.nde-ed.org/NDETechniques/PenetrantTest/Introduction/visualacuity.xhtml
import 'dart:math';

// ── Shared constants ─────────────────────────────────────────────────────────

/// Canvas size used by the E Rotation trial (logical pixels, square).
const double kERotationCanvasSize = 240.0;

/// Fraction of canvas side used for each bar/stem of the block E.
const double kERotationStrokeFraction = 0.2;

/// Default viewing distance: 24 inches expressed in mm.
const double kDefaultViewingDistanceMm = 609.6;

// ── Step 1 ───────────────────────────────────────────────────────────────────

/// Returns the tine (fork) thickness of the drawn E in logical pixels.
///
/// Mirrors the first two lines of [drawBlockE] exactly so the physics
/// computation stays in sync with the painter geometry.
///
///   baseThickness   = canvasShortestSide × strokeFraction
///   scaledThickness = baseThickness × scale
double forkThicknessLogicalPx({
  required double canvasShortestSide,
  required double strokeFraction,
  required double scale,
}) {
  final baseThickness = canvasShortestSide * strokeFraction;
  final scaledThickness = baseThickness * scale;
  return scaledThickness;
}

// ── Step 2 ───────────────────────────────────────────────────────────────────

/// Returns the visual angle subtended by [sizeMm] at distance [distanceMm],
/// in radians, using the exact arctangent (not the small-angle approximation).
///
///   θ = atan(sizeMm / distanceMm)
double atanAngleRadians({
  required double sizeMm,
  required double distanceMm,
}) {
  final angleRadians = atan(sizeMm / distanceMm);
  return angleRadians;
}

// ── Step 3 ───────────────────────────────────────────────────────────────────

/// Converts an angle in radians to arc minutes.
///
///   angleDegrees = angleRadians × (180 / π)
///   arcMinutes   = angleDegrees × 60
double radiansToArcMinutes(double angleRadians) {
  const degreesPerRadian = 180.0 / pi;
  const arcMinutesPerDegree = 60.0;
  final angleDegrees = angleRadians * degreesPerRadian;
  final arcMinutes = angleDegrees * arcMinutesPerDegree;
  return arcMinutes;
}

// ── Wrapper ──────────────────────────────────────────────────────────────────

/// Runs the three steps in sequence and returns all intermediate values.
///
/// [mmPerLogicalPixel] must be supplied explicitly — use [loadMmPerLogicalPixel]
/// from screen_calibration.dart so the caller is always aware of the source.
({
  double forkThicknessLogPx,
  double forkThicknessMm,
  double angleRadians,
  double arcMinutes,
}) eRotationVisualAngle({
  required double scale,
  required double mmPerLogicalPixel,
  double viewingDistanceMm = kDefaultViewingDistanceMm,
  double strokeFraction = kERotationStrokeFraction,
  double canvasShortestSide = kERotationCanvasSize,
}) {
  final forkThicknessLogPx = forkThicknessLogicalPx(
    canvasShortestSide: canvasShortestSide,
    strokeFraction: strokeFraction,
    scale: scale,
  );
  final forkThicknessMm = forkThicknessLogPx * mmPerLogicalPixel;
  final angleRadians = atanAngleRadians(
    sizeMm: forkThicknessMm,
    distanceMm: viewingDistanceMm,
  );
  final arcMinutes = radiansToArcMinutes(angleRadians);

  return (
    forkThicknessLogPx: forkThicknessLogPx,
    forkThicknessMm: forkThicknessMm,
    angleRadians: angleRadians,
    arcMinutes: arcMinutes,
  );
}
