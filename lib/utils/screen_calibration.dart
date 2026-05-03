// Screen physical-size calibration.
//
// Browsers and Flutter web do not expose physical mm/pixel via any API
// (removed by W3C as a fingerprinting vector). This module stores a
// user-measured value derived from the credit-card calibration screen.
//
// Fallback constant: 16-inch MacBook Pro (M1/M2/M3)
//   - Native resolution: 3456 × 2234 px at 254 PPI
//   - Retina backing scale: 2×  →  logical PPI = 127
//   - mm per logical pixel = 25.4 / 127 = 0.2
import 'package:shared_preferences/shared_preferences.dart';

/// ISO/IEC 7810 ID-1: standard credit/ID card width in mm.
const double kCreditCardWidthMm = 85.6;

/// Fallback for 16-inch MacBook Pro: 254 native PPI ÷ 2× Retina scale = 127 logical PPI.
const double kMacBookPro16MmPerLogicalPixel = 25.4 / 127.0;

const String _kCalibrationKey = 'screen_mm_per_logical_px_v1';

/// Returns the stored calibrated value, or [kMacBookPro16MmPerLogicalPixel]
/// if no calibration has been performed yet.
Future<double> loadMmPerLogicalPixel() async {
  final prefs = await SharedPreferences.getInstance();
  final stored = prefs.getDouble(_kCalibrationKey);
  return stored ?? kMacBookPro16MmPerLogicalPixel;
}

/// Returns null if no calibration has been saved (so callers can distinguish
/// "calibrated" from "fallback").
Future<double?> loadMmPerLogicalPixelOrNull() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getDouble(_kCalibrationKey);
}

Future<void> saveMmPerLogicalPixel(double value) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setDouble(_kCalibrationKey, value);
}
