import 'dart:math';

import 'package:flutter/material.dart';

import '../utils/outcomes.dart';
import '../utils/session_experiment_meta.dart';
import '../utils/session_store.dart';
import '../utils/trial_framework.dart';
import '../utils/trial_widgets.dart';
import 'soloud_tone_player.dart';

class PitchRangeTrial {
  const PitchRangeTrial({
    required this.minHz,
    required this.maxHz,
    required this.previewAmplitude,
    required this.previewDuration,
  });

  final double minHz;
  final double maxHz;
  final double previewAmplitude;
  final Duration previewDuration;
}

class PitchRangeGuess {
  const PitchRangeGuess({
    required this.lowHz,
    required this.highHz,
  });

  final double lowHz;
  final double highHz;
}

class PitchFrequencyRangePage extends StatefulWidget {
  const PitchFrequencyRangePage({super.key});

  @override
  State<PitchFrequencyRangePage> createState() => _PitchFrequencyRangePageState();
}

class _PitchFrequencyRangePageState extends State<PitchFrequencyRangePage> {
  final SessionStore _store = SessionStore();

  late TrialRunner<PitchRangeTrial, PitchRangeGuess> _runner;
  List<TrialOutcome> _outcomes = const <TrialOutcome>[];
  bool _savedSession = false;
  String _status = 'Adjust the sliders to find your lowest/highest audible pitch.';

  // Defaults for a typical hearing-range exploration (not a diagnosis tool).
  static const double _defaultMinHz = 20;
  static const double _defaultMaxHz = 20000;
  static const double _defaultLowHz = 200;
  static const double _defaultHighHz = 4000;
  static const double _minGapHz = 1;
  static const double _previewAmplitude = 0.6;
  static const Duration _previewDuration = Duration(milliseconds: 450);

  late double _lowHz;
  late double _highHz;

  @override
  void initState() {
    super.initState();
    _lowHz = _defaultLowHz;
    _highHz = _defaultHighHz;
    _runner = _newRunner();
    _runner.start();
  }

  TrialRunner<PitchRangeTrial, PitchRangeGuess> _newRunner() {
    return TrialRunner<PitchRangeTrial, PitchRangeGuess>(
      initialState: TrialRunnerState(startedAt: DateTime.now()),
      generateTrial: (state) {
        // Add small randomization to reduce anchored defaults in repeated runs.
        final minHz = _defaultMinHz;
        final maxHz = _defaultMaxHz;
        final amplitude = _previewAmplitude;
        final duration = _previewDuration;
        return PitchRangeTrial(
          minHz: minHz,
          maxHz: maxHz,
          previewAmplitude: amplitude,
          previewDuration: duration,
        );
      },
      scoreTrial: (trial, guess) {
        final lowHz = guess.lowHz;
        final highHz = guess.highHz;
        final valid = lowHz >= trial.minHz &&
            highHz <= trial.maxHz &&
            lowHz + _minGapHz <= highHz;
        return TrialScore(
          // No ground truth: we treat submission as “correct” when it's valid.
          correct: valid,
          valid: valid,
          data: <String, Object?>{
            'lowHz': lowHz,
            'highHz': highHz,
            'minHz': trial.minHz,
            'maxHz': trial.maxHz,
            'previewAmplitude': trial.previewAmplitude,
            'previewDurationMs': trial.previewDuration.inMilliseconds,
          },
        );
      },
      reduceState: (state, score) {
        final total = state.totalScored + 1;
        // One-shot trial: finish after submit (even if invalid, to keep flow simple).
        return state.copyWith(
          trialIndex: state.trialIndex + 1,
          totalScored: total,
          correctScored: state.correctScored + (score.correct ? 1 : 0),
          wrongStreak: score.correct ? 0 : (state.wrongStreak + 1),
          lastCorrectAt: score.correct ? DateTime.now() : state.lastCorrectAt,
          finished: true,
        );
      },
    );
  }

  static double _hzToUnit(double hz, {required double minHz, required double maxHz}) {
    final ratio = maxHz / minHz;
    if (ratio <= 1) return 0;
    return log(hz / minHz) / log(ratio);
  }

  static double _unitToHz(double t, {required double minHz, required double maxHz}) {
    final ratio = maxHz / minHz;
    if (ratio <= 1) return minHz;
    return minHz * pow(ratio, t);
  }

  double _clampLow(double low) {
    final trial = _runner.currentTrial;
    final clamped = low.clamp(trial.minHz, trial.maxHz - _minGapHz);
    return clamped.toDouble();
  }

  double _clampHigh(double high) {
    final trial = _runner.currentTrial;
    final clamped = high.clamp(trial.minHz + _minGapHz, trial.maxHz);
    return clamped.toDouble();
  }

  Future<void> _playHz(double hz) async {
    final trial = _runner.currentTrial;
    await SoLoudTonePlayer.instance.playSine(
      frequencyHz: hz,
      amplitude: trial.previewAmplitude,
      duration: trial.previewDuration,
    );
  }

  Future<void> _previewLow() async {
    if (_runner.state.finished) return;
    await _playHz(_lowHz);
  }

  Future<void> _previewHigh() async {
    if (_runner.state.finished) return;
    await _playHz(_highHz);
  }

  Widget _audibleRangeViz({
    required double minHz,
    required double maxHz,
    required double lowHz,
    required double highHz,
  }) {
    final lowT = _hzToUnit(lowHz, minHz: minHz, maxHz: maxHz).clamp(0.0, 1.0);
    final highT = _hzToUnit(highHz, minHz: minHz, maxHz: maxHz).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Audible range (approx.)',
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            final lowX = w * lowT;
            final highX = w * highT;

            return SizedBox(
              height: 36,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        gradient: const LinearGradient(
                          colors: [
                            Color(0xFF8B00FF), // violet
                            Color(0xFF4B0082), // indigo
                            Color(0xFF0000FF), // blue
                            Color(0xFF00FF00), // green
                            Color(0xFFFFFF00), // yellow
                            Color(0xFFFF7F00), // orange
                            Color(0xFFFF0000), // red
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: lowX - 1,
                    top: 0,
                    bottom: 0,
                    child: Container(width: 2, color: Colors.black),
                  ),
                  Positioned(
                    left: highX - 1,
                    top: 0,
                    bottom: 0,
                    child: Container(width: 2, color: Colors.black),
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('${minHz.toStringAsFixed(0)} Hz'),
            Text('${maxHz.toStringAsFixed(0)} Hz'),
          ],
        ),
      ],
    );
  }

  void _submit() {
    if (_runner.state.finished) return;

    final low = _clampLow(min(_lowHz, _highHz - _minGapHz));
    final high = _clampHigh(max(_highHz, _lowHz + _minGapHz));

    final score = _runner.submitGuess(
      PitchRangeGuess(lowHz: low, highHz: high),
      guessData: <String, Object?>{
        'lowHz': low,
        'highHz': high,
      },
    );

    setState(() {
      _lowHz = low;
      _highHz = high;
      _status = score.valid
          ? 'Submitted range.'
          : 'Submitted range is invalid. Try again with a wider gap.';
    });

    if (_runner.state.finished) _onFinished();
  }

  void _onFinished() {
    if (_savedSession) return;
    _savedSession = true;
    final outcomes = deriveOutcomes(_runner.report);
    setState(() {
      _outcomes = outcomes;
      _status = 'Finished.';
    });
    _store.appendSession(
      _runner.report,
      mergeExperimentIntoSummary(
        _runner.summaryJson(),
        experimentKind: kExperimentPitchFrequencyRange,
        experimentTitle: 'Pitch Frequency Range',
      ),
    );
  }

  void _restart() {
    setState(() {
      _lowHz = _defaultLowHz;
      _highHz = _defaultHighHz;
      _runner = _newRunner();
      _runner.start();
      _outcomes = const <TrialOutcome>[];
      _savedSession = false;
      _status = 'Adjust the sliders to find your lowest/highest audible pitch.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final trial = _runner.currentTrial;
    final lowT = _hzToUnit(_lowHz, minHz: trial.minHz, maxHz: trial.maxHz).clamp(0.0, 1.0);
    final highT =
        _hzToUnit(_highHz, minHz: trial.minHz, maxHz: trial.maxHz).clamp(0.0, 1.0);
    return Scaffold(
      appBar: AppBar(title: const Text('Pitch Frequency Range')),
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
                Text(
                  'Move each slider until the tone is just barely audible.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                _audibleRangeViz(
                  minHz: trial.minHz,
                  maxHz: trial.maxHz,
                  lowHz: _lowHz,
                  highHz: _highHz,
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Low: ${_lowHz.toStringAsFixed(0)} Hz',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Slider(
                  value: lowT,
                  onChanged: _runner.state.finished
                      ? null
                      : (t) {
                          final hz = _unitToHz(t, minHz: trial.minHz, maxHz: trial.maxHz);
                          setState(() {
                            _lowHz = _clampLow(hz);
                            if (_lowHz + _minGapHz > _highHz) {
                              _highHz = _clampHigh(_lowHz + _minGapHz);
                            }
                          });
                        },
                  onChangeEnd: _runner.state.finished ? null : (_) => _previewLow(),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'High: ${_highHz.toStringAsFixed(0)} Hz',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Slider(
                  value: highT,
                  onChanged: _runner.state.finished
                      ? null
                      : (t) {
                          final hz = _unitToHz(t, minHz: trial.minHz, maxHz: trial.maxHz);
                          setState(() {
                            _highHz = _clampHigh(hz);
                            if (_lowHz + _minGapHz > _highHz) {
                              _lowHz = _clampLow(_highHz - _minGapHz);
                            }
                          });
                        },
                  onChangeEnd: _runner.state.finished ? null : (_) => _previewHigh(),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _runner.state.finished ? null : _submit,
                  child: const Text('Submit range'),
                ),
                const SizedBox(height: 12),
                ExportJsonButton(runner: _runner),
                const SizedBox(height: 16),
                Text(_status, textAlign: TextAlign.center),
                if (_runner.state.finished) OutcomesSummary(outcomes: _outcomes),
                if (_runner.state.finished) ...[
                  const SizedBox(height: 12),
                  TextButton(onPressed: _restart, child: const Text('Restart')),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
