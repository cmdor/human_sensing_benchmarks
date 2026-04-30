// https://www.webvision.pitt.edu/book/part-viii-psychophysics-of-vision/visual-acuity/
// Generate the letter 'E' and then gradually decrease the size of the letter until it is not noticeable.
import 'dart:math';

import 'package:flutter/material.dart';

class EGeometry {
  const EGeometry({
    required this.tineThickness,
    required this.verticalGap,
    required this.scale,
    required this.rotationDegrees,
  });

  /// Thickness of each bar/stem (in logical pixels after scaling).
  final double tineThickness;

  /// Vertical gap between bars (top↔middle and middle↔bottom), in logical pixels
  /// after scaling.
  final double verticalGap;

  final double scale;
  final double rotationDegrees;
}

double degreesToRadians(double degrees) => degrees * (pi / 180.0);

// Draw a capital letter 'E' on a canvas (simple block style).
//
// This draws:
// - one vertical stem on the left
// - three horizontal bars (top/middle/bottom)
EGeometry drawBlockE(
  Canvas canvas,
  Rect bounds,
  Paint paint, {
  double strokeFraction = 0.2,
  double scale = 1.0,
  double rotationDegrees = 0.0,
  double middleBarWidthFraction = 1.0, // NOTE: the experiment could be done with varying widths of the middle bar
}) {
  final baseThickness =
      (bounds.shortestSide * strokeFraction).clamp(1.0, bounds.shortestSide);
  final t = baseThickness * scale;

  // In the untransformed bounds, the vertical gaps are:
  // gap = (h/2 - 1.5t_base). After scaling, both h and t scale by `scale`.
  final baseGap = (bounds.height / 2.0) - (1.5 * baseThickness);
  final gap = (baseGap * scale).clamp(0.0, double.infinity);

  // Apply transforms around the bounds center so callers can vary scale/rotation
  // without redoing layout.
  canvas.save();
  final c = bounds.center;
  canvas.translate(c.dx, c.dy);
  if (rotationDegrees != 0.0) {
    canvas.rotate(degreesToRadians(rotationDegrees));
  }
  if (scale != 1.0) {
    canvas.scale(scale, scale);
  }
  canvas.translate(-c.dx, -c.dy);

  // Left stem
  canvas.drawRect(
    Rect.fromLTWH(bounds.left, bounds.top, baseThickness, bounds.height),
    paint,
  );

  // Top bar
  canvas.drawRect(
    Rect.fromLTWH(bounds.left, bounds.top, bounds.width, baseThickness),
    paint,
  );

  // Middle bar (slightly shorter looks more like a typical E)
  canvas.drawRect(
    Rect.fromLTWH(
      bounds.left,
      bounds.center.dy - baseThickness / 2,
      bounds.width * middleBarWidthFraction,
      baseThickness,
    ),
    paint,
  );

  // Bottom bar
  canvas.drawRect(
    Rect.fromLTWH(
      bounds.left,
      bounds.bottom - baseThickness,
      bounds.width,
      baseThickness,
    ),
    paint,
  );

  canvas.restore();

  return EGeometry(
    tineThickness: t,
    verticalGap: gap,
    scale: scale,
    rotationDegrees: rotationDegrees,
  );
}

class SmallestNoticeableSizePage extends StatelessWidget {
  const SmallestNoticeableSizePage({super.key});

  @override
  Widget build(BuildContext context) {
    final paint = Paint()
      ..color = Theme.of(context).colorScheme.onSurface
      ..style = PaintingStyle.fill;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Smallest Noticeable Size'),
      ),
      body: Center(
        child: Container(
          color: Theme.of(context).colorScheme.surface,
          padding: const EdgeInsets.all(24),
          child: CustomPaint(
            size: const Size(240, 240),
            painter: _BlockEPainter(fillPaint: paint),
          ),
        ),
      ),
    );
  }
}

class _BlockEPainter extends CustomPainter {
  const _BlockEPainter({required this.fillPaint});

  final Paint fillPaint;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    drawBlockE(
      canvas,
      bounds,
      fillPaint,
      strokeFraction: 0.2,
      scale: 1,
      rotationDegrees: 0,
    );
  }

  @override
  bool shouldRepaint(covariant _BlockEPainter oldDelegate) {
    return oldDelegate.fillPaint.color != fillPaint.color ||
        oldDelegate.fillPaint.style != fillPaint.style;
  }
}


// Gradually redue the size


// Calculate the dimensions of the letter 'E' at the smallest noticeable size.


// Calculate the angular resolution of the eye, in arc minutes. (1/60 of a degree)