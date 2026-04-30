import 'dart:math';

import 'package:flutter/material.dart';

import '../utils/outcomes.dart';
import '../utils/session_store.dart';
import '../utils/trial_framework.dart';
import '../utils/trial_widgets.dart';
import 'soloud_tone_player.dart';

class GapOption {
  const GapOption({
    required this.id,
    required this.hasGap,
  });

  final String id;
  final bool hasGap;
}

class SoundGapTrial {
  const SoundGapTrial({
    required this.options,
    required this.gapOptionId,
    required this.totalDuration,
    required this.gapStart,
    required this.gapDuration,
    required this.amplitude,
  });

  final List<GapOption> options;
  final String gapOptionId;
  final Duration totalDuration;
  final Duration gapStart;
  final Duration gapDuration;
  final double amplitude;
}

class SoundGapGuess {
  const SoundGapGuess(this.selectedOptionId);
  final String selectedOptionId;
}

class SoundGapDetectionPage extends StatefulWidget {
  const SoundGapDetectionPage({super.key});

  @override
  State<SoundGapDetectionPage> createState() => _SoundGapDetectionPageState();
}

class _SoundGapDetectionPageState extends State<SoundGapDetectionPage> {
  final Random _random = Random();
  final SessionStore _store = SessionStore();

  late TrialRunner<SoundGapTrial, SoundGapGuess> _runner;
  List<TrialOutcome> _outcomes = const <TrialOutcome>[];
  bool _savedSession = false;
  String _status = 'Press an option to play it and select which one had a gap.';
  int? _selectedOptionNumber;
  late Map<String, int> _playCounts;

  static const int _numOptions = 3;
  static const Duration _totalDuration = Duration(milliseconds: 900);
  // Start with a clearly noticeable gap for early testing.
  static const Duration _gapDurationBase = Duration(milliseconds: 260);
  static const double _amplitude = 0.7;

  @override
  void initState() {
    super.initState();
    _runner = _newRunner();
    _runner.start();
    _playCounts = <String, int>{};
  }

  TrialRunner<SoundGapTrial, SoundGapGuess> _newRunner() {
    return TrialRunner<SoundGapTrial, SoundGapGuess>(
      initialState: TrialRunnerState(startedAt: DateTime.now()),
      generateTrial: (state) {
        final gapIndex = _random.nextInt(_numOptions);
        final gapId = 'Option ${gapIndex + 1}';

        final options = List<GapOption>.generate(_numOptions, (i) {
          final id = 'Option ${i + 1}';
          return GapOption(id: id, hasGap: i == gapIndex);
        });

        // Vary gap size around a "pretty large" default for early testing.
        // Range derived from base: (base-80) .. (base+60). For 260ms => 180–320ms.
        final int gapMinMs = max(60, _gapDurationBase.inMilliseconds - 80);
        final int gapMaxMs = _gapDurationBase.inMilliseconds + 60;
        final int gapMs = gapMinMs + _random.nextInt((gapMaxMs - gapMinMs) + 1);
        final Duration gapDuration = Duration(milliseconds: gapMs);

        // Put the gap roughly in the middle, but jitter it slightly so it’s not
        // always identical.
        final jitterMs = _random.nextInt(121) - 60; // [-60ms, +60ms]
        final baseStartMs = (_totalDuration.inMilliseconds / 2).round() - 70;
        final int latestStartMs =
            _totalDuration.inMilliseconds - gapDuration.inMilliseconds - 120;
        final int maxStartMs = max(120, latestStartMs);
        final int startMs = (baseStartMs + jitterMs).clamp(120, maxStartMs);

        return SoundGapTrial(
          options: options,
          gapOptionId: gapId,
          totalDuration: _totalDuration,
          gapStart: Duration(milliseconds: startMs),
          gapDuration: gapDuration,
          amplitude: _amplitude,
        );
      },
      scoreTrial: (trial, guess) {
        final correct = guess.selectedOptionId == trial.gapOptionId;
        return TrialScore(
          correct: correct,
          valid: true,
          data: <String, Object?>{
            'selected': guess.selectedOptionId,
            'gapOption': trial.gapOptionId,
            'gapDurationMs': trial.gapDuration.inMilliseconds,
            'gapStartMs': trial.gapStart.inMilliseconds,
            'totalMs': trial.totalDuration.inMilliseconds,
            'amplitude': trial.amplitude,
            'playCountOption1': _playCounts['Option 1'] ?? 0,
            'playCountOption2': _playCounts['Option 2'] ?? 0,
            'playCountOption3': _playCounts['Option 3'] ?? 0,
          },
        );
      },
      reduceState: (state, score) {
        final total = state.totalScored + 1;
        final wrongStreak = score.correct ? 0 : (state.wrongStreak + 1);
        return state.copyWith(
          trialIndex: state.trialIndex + 1,
          totalScored: total,
          correctScored: state.correctScored + (score.correct ? 1 : 0),
          wrongStreak: wrongStreak,
          lastCorrectAt: score.correct ? DateTime.now() : state.lastCorrectAt,
          finished: wrongStreak >= 2,
        );
      },
    );
  }

  Future<void> _playOption(GapOption opt) async {
    final trial = _runner.currentTrial;
    setState(() {
      _playCounts[opt.id] = (_playCounts[opt.id] ?? 0) + 1;
    });
    await SoLoudTonePlayer.instance.playNoisyWithOptionalGap(
      amplitude: trial.amplitude,
      totalDuration: trial.totalDuration,
      gapStart: opt.hasGap ? trial.gapStart : null,
      gapDuration: opt.hasGap ? trial.gapDuration : null,
    );
  }

  void _submit() {
    if (_runner.state.finished) return;
    final selected = _selectedOptionNumber;
    if (selected == null) {
      setState(() {
        _status = 'Select an option first, then press Submit.';
      });
      return;
    }

    final score = _runner.submitGuess(SoundGapGuess('Option $selected'));
    setState(() {
      _status = score.correct ? 'Correct.' : 'Not that one—try again.';
      _selectedOptionNumber = null;
    });

    if (_runner.state.finished) _onFinished();
  }

  void _onFinished() {
    if (_savedSession) return;
    _savedSession = true;
    final outcomes = deriveOutcomes(_runner.report);
    setState(() {
      _outcomes = outcomes;
      _status = 'Finished (2 wrong in a row).';
    });
    _store.appendSession(_runner.report, _runner.summaryJson());
  }

  void _restart() {
    setState(() {
      _runner = _newRunner();
      _runner.start();
      _outcomes = const <TrialOutcome>[];
      _savedSession = false;
      _selectedOptionNumber = null;
      _playCounts = <String, int>{};
      _status = 'Press an option to play it and select which one had a gap.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final trial = _runner.currentTrial;
    return Scaffold(
      appBar: AppBar(title: const Text('Sound Gap Detection')),
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
                const Text(
                  'Listen to each option. One has a brief silent gap in the middle.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  alignment: WrapAlignment.center,
                  children: [
                    for (final opt in trial.options)
                      FilledButton.tonal(
                        onPressed: () => _playOption(opt),
                        child: Text(
                          'Play ${opt.id} (${_playCounts[opt.id] ?? 0})',
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Which option had the gap?',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                const SizedBox(height: 8),
                RadioGroup<int>(
                  groupValue: _selectedOptionNumber,
                  onChanged: (v) {
                    if (_runner.state.finished) return;
                    setState(() {
                      _selectedOptionNumber = v;
                    });
                  },
                  child: Column(
                    children: [
                      for (var i = 0; i < trial.options.length; i++)
                        RadioListTile<int>(
                          value: i + 1,
                          title: Text('${i + 1}'),
                          enabled: !_runner.state.finished,
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed:
                      _runner.state.finished ? null : (_selectedOptionNumber == null ? null : _submit),
                  child: const Text('Submit'),
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