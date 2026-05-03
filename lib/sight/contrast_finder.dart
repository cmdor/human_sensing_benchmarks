//  Contrast Sensitivity: We will loosely follow the Pelli-Robson Contrast Sensitivity Test. More detailed information about the original test can be found here

// Based on this literature, build an app that displays letters with decreasing contrast, and ask the user to identify the letters until they are not legible.

// Through the process, find the user's contrast sensitivity in units of percentage. Based on this result, estimate the bit resolution. (For example, 8-bit resolution means 256 available discrete measurements, which correspond to about 4% range per color difference, meaning the smallest color difference you could discriminate is 4%.)

import 'package:flutter/material.dart';

import 'dart:math';

import '../utils/session_experiment_meta.dart';
import '../utils/trial_framework.dart';
import '../utils/outcomes.dart';
import '../utils/session_store.dart';
import '../utils/trial_widgets.dart';
import 'contrast_trial.dart';

// --- Widget ---

class ContrastFinder extends StatefulWidget {
  const ContrastFinder({super.key});

  @override
  State<ContrastFinder> createState() => _ContrastFinderState();
}

class _ContrastFinderState extends State<ContrastFinder> {
  final Random _random = Random();
  final TextEditingController _guessController = TextEditingController();
  final FocusNode _guessFocus = FocusNode();

  late TrialRunner<ContrastTrial, String> _runner;
  String _status = 'Enter the letter you see, then press Enter (or Submit).';
  List<TrialOutcome> _outcomes = const <TrialOutcome>[];
  bool _savedSession = false;
  final SessionStore _store = SessionStore();

  /// Per-trial contrast (% of full letter–background mix) for [StaircaseChart].
  List<double> _contrastPctHistory = const <double>[];
  List<bool> _contrastCorrectHistory = const <bool>[];

  /// Filled when the run ends (failure-level contrast in state).
  double? _reportThresholdPct;
  int? _reportBitDepthEst;
  double? _reportThresholdContrast;
  double? _reportLogContrastSensitivity;

  @override
  void initState() {
    super.initState();
    _runner = _newRunner();
    _runner.start();
    _refocusGuessField();
  }

  @override
  void dispose() {
    _guessFocus.dispose();
    _guessController.dispose();
    super.dispose();
  }

  TrialRunner<ContrastTrial, String> _newRunner() {
    return TrialRunner<ContrastTrial, String>(
      initialState: TrialRunnerState(
        startedAt: DateTime.now(),
        custom: const <String, Object?>{'contrast': 1.0},
      ),
      generateTrial: buildContrastGenerator(_random),
      scoreTrial: contrastScorer(),
      reduceState: contrastReducer(),
    );
  }

  /// Puts the caret in the guess field without an extra click (after frame / trial change).
  void _refocusGuessField() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _runner.state.finished) return;
      _guessFocus.requestFocus();
    });
  }

  /// Read input, compare to current trial, update status and advance or end.
  void _onSubmitGuess() {
    if (_runner.state.finished) return;

    final raw = _guessController.text;
    final letter = firstUppercaseLetter(raw);

    if (letter == null) {
      setState(() {
        _status = 'Please enter a letter (A–Z).';
      });
      _refocusGuessField();
      return;
    }

    final trial = _runner.currentTrial;
    final score = _runner.submitGuess(raw, guessData: <String, Object?>{'raw': raw});

    setState(() {
      if (!score.valid) {
        _status = 'Please enter a letter (A–Z).';
        return;
      }

      _contrastPctHistory = [..._contrastPctHistory, trial.contrast * 100.0];
      _contrastCorrectHistory = [..._contrastCorrectHistory, score.correct];

      if (!score.correct) {
        final wrongStreak = _runner.state.wrongStreak;
        if (_runner.state.finished) {
          _status =
              'Wrong again (2 in a row). You entered "$letter"; displayed was "${trial.letter}". Run finished.';
          return;
        }
        _status =
            'Wrong ($wrongStreak/2). You entered "$letter"; displayed was "${trial.letter}".';
        _guessController.clear();
        return;
      }

      final nextContrast = (_runner.state.custom['contrast'] as double?) ?? trial.contrast;
      _status = 'Correct. Next contrast: ${nextContrast.toStringAsFixed(2)}';
      _guessController.clear();
    });

    if (_runner.state.finished) {
      _onFinished();
    }

    if (!_runner.state.finished) _refocusGuessField();
  }

  void _onFinished() {
    if (_savedSession) return;
    _savedSession = true;
    final outcomes = deriveOutcomes(_runner.report);
    final thresholdContrast = (_runner.state.custom['contrast'] as double?) ?? 1.0;
    final est = contrastBitDepthEstimate(thresholdContrast: thresholdContrast);
    setState(() {
      _outcomes = outcomes;
      _reportThresholdContrast = est.thresholdContrast;
      _reportThresholdPct = est.thresholdPct;
      _reportLogContrastSensitivity = est.logContrastSensitivity;
      _reportBitDepthEst = est.bitDepthEst;
    });
    final baseSummary = _runner.summaryJson();
    final summaryWithContrast = <String, Object?>{
      ...baseSummary,
      'thresholdContrast': est.thresholdContrast,
      'thresholdPct': est.thresholdPct,
      'logContrastSensitivity': est.logContrastSensitivity,
      'bitDepthEst': est.bitDepthEst,
    };
    // Fire-and-forget persist.
    _store.appendSession(
      _runner.report,
      mergeExperimentIntoSummary(
        summaryWithContrast,
        experimentKind: kExperimentContrastFinder,
        experimentTitle: 'Contrast Finder',
      ),
    );
  }

  void _restart() {
    setState(() {
      _guessController.clear();
      _runner = _newRunner();
      _runner.start();
      _status = 'Enter the letter you see, then press Enter (or Submit).';
      _outcomes = const <TrialOutcome>[];
      _savedSession = false;
      _contrastPctHistory = const <double>[];
      _contrastCorrectHistory = const <bool>[];
      _reportThresholdPct = null;
      _reportBitDepthEst = null;
      _reportThresholdContrast = null;
      _reportLogContrastSensitivity = null;
    });
    _refocusGuessField();
  }

  @override
  Widget build(BuildContext context) {
    final trial = _runner.currentTrial;
    final bg = Theme.of(context).colorScheme.surface;
    final fg = Theme.of(context).colorScheme.onSurface;
    final letterColor = Color.lerp(bg, fg, trial.contrast) ?? fg;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Contrast Finder'),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SessionStatsBar(runner: _runner),
                const SizedBox(height: 16),
                Text(
                  trial.letter,
                  style: TextStyle(
                    fontSize: 96,
                    fontWeight: FontWeight.w700,
                    color: letterColor,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Contrast: ${(trial.contrast * 100).toStringAsFixed(2)}%',
                ),
                if (_contrastPctHistory.isNotEmpty &&
                    _contrastPctHistory.length == _contrastCorrectHistory.length) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Contrast staircase (% per trial)',
                    style: Theme.of(context).textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  StaircaseChart(
                    levelsHistory: _contrastPctHistory,
                    correct: _contrastCorrectHistory,
                    threshold: _runner.state.finished ? _reportThresholdPct : null,
                    thresholdAnnotation: _runner.state.finished && _reportBitDepthEst != null
                        ? 'bit depth $_reportBitDepthEst'
                        : null,
                    yAxisLabel: '%',
                  ),
                ],
                if (_runner.state.finished &&
                    _reportThresholdContrast != null &&
                    _reportThresholdPct != null &&
                    _reportLogContrastSensitivity != null &&
                    _reportBitDepthEst != null) ...[
                  const SizedBox(height: 12),
                  _ContrastBitDepthCard(
                    thresholdContrast: _reportThresholdContrast!,
                    thresholdPct: _reportThresholdPct!,
                    logContrastSensitivity: _reportLogContrastSensitivity!,
                    bitDepthEst: _reportBitDepthEst!,
                  ),
                ],
                const SizedBox(height: 20),
                TextField(
                  controller: _guessController,
                  focusNode: _guessFocus,
                  autofocus: true,
                  enabled: !_runner.state.finished,
                  textCapitalization: TextCapitalization.characters,
                  textInputAction: TextInputAction.done,
                  maxLength: 8,
                  decoration: const InputDecoration(
                    labelText: 'Your guess',
                    helperText: 'Press Enter to submit',
                    border: OutlineInputBorder(),
                    counterText: '',
                  ),
                  onSubmitted: (_) => _onSubmitGuess(),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _runner.state.finished ? null : _onSubmitGuess,
                  child: const Text('Submit'),
                ),
                const SizedBox(height: 12),
                ExportJsonButton(runner: _runner),
                const SizedBox(height: 20),
                Text(
                  _status,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
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
    );
  }
}

/// Summary of threshold contrast, log contrast sensitivity, and estimated bit depth.
class _ContrastBitDepthCard extends StatelessWidget {
  const _ContrastBitDepthCard({
    required this.thresholdContrast,
    required this.thresholdPct,
    required this.logContrastSensitivity,
    required this.bitDepthEst,
  });

  final double thresholdContrast;
  final double thresholdPct;
  final double logContrastSensitivity;
  final int bitDepthEst;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final levels = 1 << bitDepthEst;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Contrast threshold and bit depth',
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            _ContrastMetricRow(
              label: 'Threshold contrast',
              value:
                  '${thresholdPct.toStringAsFixed(2)}%  (${thresholdContrast.toStringAsFixed(4)} mix)',
            ),
            _ContrastMetricRow(
              label: 'log10(100 / threshold%)',
              value: logContrastSensitivity.toStringAsFixed(3),
            ),
            _ContrastMetricRow(
              label: 'Bit depth (est.)',
              value: '$bitDepthEst',
              bold: true,
            ),
            const SizedBox(height: 8),
            Text(
              'Roughly $levels distinguishable contrast levels (2^$bitDepthEst).',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContrastMetricRow extends StatelessWidget {
  const _ContrastMetricRow({
    required this.label,
    required this.value,
    this.bold = false,
  });

  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 160,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: bold ? FontWeight.w700 : FontWeight.normal,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
