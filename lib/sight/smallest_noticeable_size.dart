// https://www.webvision.pitt.edu/book/part-viii-psychophysics-of-vision/visual-acuity/
// Generate the letter 'E' and then gradually decrease the size of the letter until it is not noticeable.
import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/screen_calibration.dart';
import '../utils/session_experiment_meta.dart';
import '../utils/trial_framework.dart';
import '../utils/outcomes.dart';
import '../utils/session_store.dart';
import '../utils/trial_widgets.dart';
import 'angular_resolution.dart';

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

class ERotationTrial {
  const ERotationTrial({
    required this.scale,
    required this.rotationDegrees,
    required this.strokeFraction,
  });

  final double scale;
  final double rotationDegrees;
  final double strokeFraction;
}

class ERotationGuess {
  const ERotationGuess({
    required this.rotationDegrees,
    this.geometry,
  });

  final double rotationDegrees;
  final EGeometry? geometry;
}

class _GuessIntent extends Intent {
  const _GuessIntent(this.rotationDegrees);

  final double rotationDegrees;
}

// Mapping: which direction the E “points” (its prongs).
// With Flutter’s coordinate system (y down), positive rotation is clockwise:
// Right=0°, Down=90°, Left=180°, Up=270°.
const double kRotateRight = 0;
const double kRotateDown = 90;
const double kRotateLeft = 180;
const double kRotateUp = 270;

const List<_DirectionChoice> _kDirectionChoices = <_DirectionChoice>[
  _DirectionChoice(label: 'Up', keyGlyph: '↑', rotationDegrees: kRotateUp),
  _DirectionChoice(label: 'Left', keyGlyph: '←', rotationDegrees: kRotateLeft),
  _DirectionChoice(label: 'Down', keyGlyph: '↓', rotationDegrees: kRotateDown),
  _DirectionChoice(label: 'Right', keyGlyph: '→', rotationDegrees: kRotateRight),
];

class _DirectionChoice {
  const _DirectionChoice({
    required this.label,
    required this.keyGlyph,
    required this.rotationDegrees,
  });

  final String label;
  final String keyGlyph;
  final double rotationDegrees;
}

TrialGenerator<ERotationTrial> buildERotationGenerator(
  Random random, {
  double strokeFraction = 0.2,
}) {
  return (state) {
    final scale = (state.custom['scale'] as double?) ?? 1.0;
    final rotation = _kDirectionChoices[random.nextInt(_kDirectionChoices.length)]
        .rotationDegrees;
    return ERotationTrial(
      scale: scale,
      rotationDegrees: rotation,
      strokeFraction: strokeFraction,
    );
  };
}

TrialScorer<ERotationTrial, ERotationGuess> eRotationScorer() {
  return (trial, guess) {
    final correct = guess.rotationDegrees == trial.rotationDegrees;
    final g = guess.geometry;
    return TrialScore(
      correct: correct,
      valid: true,
      data: <String, Object?>{
        'guessRotationDegrees': guess.rotationDegrees,
        'presentedRotationDegrees': trial.rotationDegrees,
        'scale': trial.scale,
        if (g != null) ...<String, Object?>{
          'tineThickness': g.tineThickness,
          'verticalGap': g.verticalGap,
        },
      },
    );
  };
}

TrialReducer eRotationReducer({
  double scaleStepFactor = 0.9,
  int wrongInARowToFinish = 2,
}) {
  return (state, score) {
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

    final currentScale = (state.custom['scale'] as double?) ?? 1.0;
    final nextScale = currentScale * scaleStepFactor;
    return state.copyWith(
      trialIndex: state.trialIndex + 1,
      totalScored: totalScored,
      correctScored: state.correctScored + 1,
      wrongStreak: 0,
      lastCorrectAt: DateTime.now(),
      custom: <String, Object?>{
        ...state.custom,
        'scale': nextScale,
      },
    );
  };
}

class SmallestNoticeableSizePage extends StatelessWidget {
  const SmallestNoticeableSizePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const _ERotationTrialPage();
  }
}

class _ERotationTrialPage extends StatefulWidget {
  const _ERotationTrialPage();

  @override
  State<_ERotationTrialPage> createState() => _ERotationTrialPageState();
}

class _ERotationTrialPageState extends State<_ERotationTrialPage> {
  final Random _random = Random();
  late TrialRunner<ERotationTrial, ERotationGuess> _runner;
  final FocusNode _keyboardFocus = FocusNode();

  EGeometry? _lastGeometry;
  String _status = 'Which way is the E rotated?';
  List<TrialOutcome> _outcomes = const <TrialOutcome>[];
  bool _savedSession = false;
  final SessionStore _store = SessionStore();

  /// Cached calibration (set before the first trial is presented).
  double? _mmPerLogicalPixel;

  /// False until [loadMmPerLogicalPixel] completes and [_runner.start] runs.
  bool _sessionReady = false;

  /// Live arc-minute history for [StaircaseChart] (updates each guess).
  List<double> _acuityArcMinHistory = const <double>[];
  List<bool> _acuityCorrectHistory = const <bool>[];

  /// Horizontal threshold line after run completes (threshold-scale arcmin).
  double? _reportThresholdArcMin;

  @override
  void initState() {
    super.initState();
    _runner = _newRunner();
    unawaited(_loadCalibrationAndStart());
  }

  Future<void> _loadCalibrationAndStart() async {
    final mm = await loadMmPerLogicalPixel();
    if (!mounted) return;
    setState(() {
      _mmPerLogicalPixel = mm;
      _runner.start();
      _sessionReady = true;
    });
  }

  TrialRunner<ERotationTrial, ERotationGuess> _newRunner() {
    return TrialRunner<ERotationTrial, ERotationGuess>(
      initialState: TrialRunnerState(
        startedAt: DateTime.now(),
        custom: const <String, Object?>{'scale': 1.0},
      ),
      generateTrial: buildERotationGenerator(_random, strokeFraction: 0.2),
      scoreTrial: eRotationScorer(),
      reduceState: eRotationReducer(),
    );
  }

  void _submitGuess(double rotationDegrees) {
    if (!_sessionReady || _mmPerLogicalPixel == null) return;
    if (_runner.state.finished) return;

    final trial = _runner.currentTrial;
    final score = _runner.submitGuess(
      ERotationGuess(rotationDegrees: rotationDegrees, geometry: _lastGeometry),
    );

    final mmPerPx = _mmPerLogicalPixel!;
    final arcMinThisTrial = eRotationVisualAngle(
      scale: trial.scale,
      mmPerLogicalPixel: mmPerPx,
    ).arcMinutes;

    setState(() {
      _acuityArcMinHistory = [..._acuityArcMinHistory, arcMinThisTrial];
      _acuityCorrectHistory = [..._acuityCorrectHistory, score.correct];

      if (score.correct) {
        final nextScale = (_runner.state.custom['scale'] as double?) ?? trial.scale;
        _status = 'Correct. Next scale: ${nextScale.toStringAsFixed(4)}';
        return;
      }

      if (_runner.state.finished) {
        _status = 'Wrong again (2 in a row). Run finished.';
        return;
      }

      _status = 'Wrong (1/2). Try the next one.';
    });

    if (_runner.state.finished) {
      unawaited(_onFinished());
    }
  }

  Future<void> _onFinished() async {
    if (_savedSession) return;
    _savedSession = true;

    final outcomes = deriveOutcomes(_runner.report);

    // Compute visual angle at the threshold scale.
    // Scale at finish = the scale the participant failed twice at
    // (reducer never shrinks scale on wrong trials).
    final thresholdScale = (_runner.state.custom['scale'] as double?) ?? 1.0;
    final mmPerLogicalPixel = await loadMmPerLogicalPixel();
    final acuity = eRotationVisualAngle(
      scale: thresholdScale,
      mmPerLogicalPixel: mmPerLogicalPixel,
    );

    if (!mounted) return;
    setState(() {
      _outcomes = outcomes;
      _mmPerLogicalPixel = mmPerLogicalPixel;
      _reportThresholdArcMin = acuity.arcMinutes;
    });

    final baseSummary = _runner.summaryJson();
    final summaryWithAcuity = <String, Object?>{
      ...baseSummary,
      'forkThicknessLogicalPx': acuity.forkThicknessLogPx,
      'forkThicknessMm': acuity.forkThicknessMm,
      'mmPerLogicalPixel': mmPerLogicalPixel,
      'viewingDistanceMm': kDefaultViewingDistanceMm,
      'visualAngleRadians': acuity.angleRadians,
      'visualAngleArcMinutes': acuity.arcMinutes,
    };

    await _store.appendSession(
      _runner.report,
      mergeExperimentIntoSummary(
        summaryWithAcuity,
        experimentKind: kExperimentERotation,
        experimentTitle: 'E Rotation Trial',
      ),
    );
  }

  void _restart() {
    setState(() {
      _lastGeometry = null;
      _runner = _newRunner();
      _runner.start();
      _sessionReady = true;
      _status = 'Which way is the E rotated?';
      _outcomes = const <TrialOutcome>[];
      _savedSession = false;
      _acuityArcMinHistory = const <double>[];
      _acuityCorrectHistory = const <bool>[];
      _reportThresholdArcMin = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_sessionReady) {
      return Scaffold(
        appBar: AppBar(title: const Text('E Rotation Trial')),
        body: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Loading screen calibration…'),
            ],
          ),
        ),
      );
    }

    final trial = _runner.currentTrial;
    final paint = Paint()
      ..color = Theme.of(context).colorScheme.onSurface
      ..style = PaintingStyle.fill;

    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        const SingleActivator(LogicalKeyboardKey.arrowUp): const _GuessIntent(kRotateUp),
        const SingleActivator(LogicalKeyboardKey.arrowDown): const _GuessIntent(kRotateDown),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): const _GuessIntent(kRotateLeft),
        const SingleActivator(LogicalKeyboardKey.arrowRight): const _GuessIntent(kRotateRight),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _GuessIntent: CallbackAction<_GuessIntent>(
            onInvoke: (intent) {
              _submitGuess(intent.rotationDegrees);
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          focusNode: _keyboardFocus,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('E Rotation Trial'),
            ),
            body: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SessionStatsBar(runner: _runner),
                      const SizedBox(height: 16),
                      CustomPaint(
                        size: const Size(240, 240),
                        painter: _BlockEPainter(
                          fillPaint: paint,
                          trial: trial,
                          onGeometry: (g) {
                            _lastGeometry = g;
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _status,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Use arrow keys, or click a direction below.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      _KeypadDirections(
                        enabled: !_runner.state.finished,
                        onGuess: _submitGuess,
                      ),
                      if (_acuityArcMinHistory.isNotEmpty &&
                          _acuityArcMinHistory.length ==
                              _acuityCorrectHistory.length) ...[
                        const SizedBox(height: 16),
                        Text(
                          'Visual acuity (arcmin)',
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        StaircaseChart(
                          levelsHistory: _acuityArcMinHistory,
                          correct: _acuityCorrectHistory,
                          threshold: _reportThresholdArcMin,
                          yAxisLabel: 'arcmin',
                        ),
                      ],
                      const SizedBox(height: 12),
                      ExportJsonButton(runner: _runner),
                      if (_runner.state.finished) OutcomesSummary(outcomes: _outcomes),
                      if (_runner.state.finished) ...[
                        const SizedBox(height: 16),
                        TextButton(
                          onPressed: _restart,
                          child: const Text('Restart'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DirectionButton extends StatelessWidget {
  const _DirectionButton({
    required this.enabled,
    required this.choice,
    required this.onPressed,
  });

  final bool enabled;
  final _DirectionChoice choice;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final paint = Paint()
      ..color = Theme.of(context).colorScheme.onSurface
      ..style = PaintingStyle.fill;

    return FilledButton.tonal(
      onPressed: enabled ? onPressed : null,
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CustomPaint(
            size: const Size(44, 44),
            painter: _LegendEPainter(
              fillPaint: paint,
              rotationDegrees: choice.rotationDegrees,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '${choice.keyGlyph}  ${choice.label}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _KeypadDirections extends StatelessWidget {
  const _KeypadDirections({
    required this.enabled,
    required this.onGuess,
  });

  final bool enabled;
  final ValueChanged<double> onGuess;

  _DirectionChoice _choice(double deg) =>
      _kDirectionChoices.firstWhere((c) => c.rotationDegrees == deg);

  @override
  Widget build(BuildContext context) {
    final up = _choice(kRotateUp);
    final left = _choice(kRotateLeft);
    final right = _choice(kRotateRight);
    final down = _choice(kRotateDown);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _DirectionButton(
          enabled: enabled,
          choice: up,
          onPressed: () => onGuess(up.rotationDegrees),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _DirectionButton(
              enabled: enabled,
              choice: left,
              onPressed: () => onGuess(left.rotationDegrees),
            ),
            const SizedBox(width: 12),
            _DirectionButton(
              enabled: enabled,
              choice: right,
              onPressed: () => onGuess(right.rotationDegrees),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _DirectionButton(
          enabled: enabled,
          choice: down,
          onPressed: () => onGuess(down.rotationDegrees),
        ),
      ],
    );
  }
}

class _LegendEPainter extends CustomPainter {
  const _LegendEPainter({
    required this.fillPaint,
    required this.rotationDegrees,
  });

  final Paint fillPaint;
  final double rotationDegrees;

  @override
  void paint(Canvas canvas, Size size) {
    drawBlockE(
      canvas,
      Offset.zero & size,
      fillPaint,
      strokeFraction: 0.25,
      scale: 0.95,
      rotationDegrees: rotationDegrees,
    );
  }

  @override
  bool shouldRepaint(covariant _LegendEPainter oldDelegate) {
    return oldDelegate.fillPaint.color != fillPaint.color ||
        oldDelegate.rotationDegrees != rotationDegrees;
  }
}

class _BlockEPainter extends CustomPainter {
  const _BlockEPainter({
    required this.fillPaint,
    required this.trial,
    required this.onGeometry,
  });

  final Paint fillPaint;
  final ERotationTrial trial;
  final ValueChanged<EGeometry> onGeometry;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    final geom = drawBlockE(
      canvas,
      bounds,
      fillPaint,
      strokeFraction: trial.strokeFraction,
      scale: trial.scale,
      rotationDegrees: trial.rotationDegrees,
    );
    onGeometry(geom);
  }

  @override
  bool shouldRepaint(covariant _BlockEPainter oldDelegate) {
    return oldDelegate.fillPaint.color != fillPaint.color ||
        oldDelegate.fillPaint.style != fillPaint.style ||
        oldDelegate.trial.scale != trial.scale ||
        oldDelegate.trial.rotationDegrees != trial.rotationDegrees ||
        oldDelegate.trial.strokeFraction != trial.strokeFraction;
  }
}
