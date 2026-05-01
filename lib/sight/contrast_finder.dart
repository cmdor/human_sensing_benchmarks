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
    setState(() {
      _outcomes = outcomes;
    });
    // Fire-and-forget persist.
    _store.appendSession(
      _runner.report,
      mergeExperimentIntoSummary(
        _runner.summaryJson(),
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
                Text('Contrast: ${trial.contrast.toStringAsFixed(4)}'),
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
