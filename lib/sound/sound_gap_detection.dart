import 'dart:math';

import 'package:flutter/material.dart';

import '../utils/outcomes.dart';
import '../utils/session_store.dart';
import '../utils/staircase.dart';
import '../utils/trial_framework.dart';
import '../utils/trial_widgets.dart';
import 'soloud_tone_player.dart';

int? trialRunnerStateCustomInt(Map<String, Object?> custom, String key) {
  final v = custom[key];
  if (v is int) return v;
  if (v is num) return v.toInt();
  return null;
}

class SoundGapTrial {
  const SoundGapTrial({
    required this.targetIndex,
    required this.gapMs,
    required this.totalDuration,
    required this.gapStart,
    required this.gapDuration,
    required this.amplitude,
  });

  final int targetIndex; // 1..3
  final double gapMs;
  final Duration totalDuration;
  final Duration gapStart;
  final Duration gapDuration;
  final double amplitude;
}

class SoundGapGuess {
  const SoundGapGuess(this.selectedIndex);
  final int selectedIndex; // 1..3
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
  late List<int> _playCounts; // index 0..2

  static const int _numOptions = 3;
  static const Duration _totalDuration = Duration(milliseconds: 900);
  static const double _amplitude = 0.7;
  static const double _initialGapMs = 20.0;
  static const double _minGapMs = 2.0;
  static const double _maxGapMs = 400.0;
  static const int _stopAfterReversals = 6;

  @override
  void initState() {
    super.initState();
    _runner = _newRunner();
    _runner.start();
    _playCounts = List<int>.filled(3, 0, growable: false);
  }

  TrialRunner<SoundGapTrial, SoundGapGuess> _newRunner() {
    return TrialRunner<SoundGapTrial, SoundGapGuess>(
      initialState: TrialRunnerState(
        startedAt: DateTime.now(),
        custom: Staircase.initialCustom(initialGapMs: _initialGapMs),
      ),
      generateTrial: (state) {
        final targetIndex = 1 + _random.nextInt(3);
        final gapMs = (state.custom[Staircase.kGapMs] as num?)?.toDouble() ?? _initialGapMs;
        final gapDuration = Duration(milliseconds: gapMs.round().clamp(1, 10000));

        // Place gap around midpoint; adjust so it fits.
        final midMs = (_totalDuration.inMilliseconds / 2).round();
        final int maxStart =
            _totalDuration.inMilliseconds - gapDuration.inMilliseconds - 80;
        final int startMs = (midMs - (gapDuration.inMilliseconds / 2))
            .clamp(80, max(80, maxStart))
            .toInt();

        return SoundGapTrial(
          targetIndex: targetIndex,
          gapMs: gapMs,
          totalDuration: _totalDuration,
          gapStart: Duration(milliseconds: startMs),
          gapDuration: gapDuration,
          amplitude: _amplitude,
        );
      },
      scoreTrial: (trial, guess) {
        final correct = guess.selectedIndex == trial.targetIndex;
        final reversalCount =
            (trialRunnerStateCustomInt(_runner.state.custom, Staircase.kReversalCount) ??
                0);
        return TrialScore(
          correct: correct,
          valid: true,
          data: <String, Object?>{
            // Order matters: OutcomesTable shows only first 4 detail keys.
            'gapMs': trial.gapMs,
            'gapDurationMs': trial.gapDuration.inMilliseconds,
            'selectedIndex': guess.selectedIndex,
            'targetIndex': trial.targetIndex,
            'gapStartMs': trial.gapStart.inMilliseconds,
            'totalMs': trial.totalDuration.inMilliseconds,
            'amplitude': trial.amplitude,
            'reversalCount': reversalCount,
            'playCount1': _playCounts[0],
            'playCount2': _playCounts[1],
            'playCount3': _playCounts[2],
          },
        );
      },
      reduceState: (state, score) {
        final presentedGapMs = (score.data['gapMs'] as num?)?.toDouble() ??
            (state.custom[Staircase.kGapMs] as num?)?.toDouble() ??
            _initialGapMs;

        final update = Staircase.update(
          custom: state.custom,
          correct: score.correct,
          presentedGapMs: presentedGapMs,
          minGapMs: _minGapMs,
          maxGapMs: _maxGapMs,
        );

        final total = state.totalScored + 1;
        final reversalCount = update.reversalCount;
        final finished = reversalCount >= _stopAfterReversals;

        return state.copyWith(
          trialIndex: state.trialIndex + 1,
          totalScored: total,
          correctScored: state.correctScored + (score.correct ? 1 : 0),
          wrongStreak: score.correct ? 0 : (state.wrongStreak + 1),
          lastCorrectAt: score.correct ? DateTime.now() : state.lastCorrectAt,
          finished: finished,
          custom: update.custom,
        );
      },
    );
  }

  Future<void> _playIndex(int index) async {
    final trial = _runner.currentTrial;
    setState(() {
      final i = (index - 1).clamp(0, 2);
      _playCounts[i] = _playCounts[i] + 1;
    });

    final hasGap = index == trial.targetIndex;
    setState(() {
      _status = hasGap ? 'Playing $index (target)' : 'Playing $index';
    });
    await SoLoudTonePlayer.instance.playNoisyWithOptionalGap(
      amplitude: trial.amplitude,
      totalDuration: trial.totalDuration,
      gapStart: hasGap ? trial.gapStart : null,
      gapDuration: hasGap ? trial.gapDuration : null,
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

    final score = _runner.submitGuess(SoundGapGuess(selected));
    setState(() {
      final stepPct = (_runner.state.custom[Staircase.kStepPct] as num?)?.toDouble();
      final reversalCount = (_runner.state.custom[Staircase.kReversalCount] as num?)?.toInt();
      final thresh = (_runner.state.custom[Staircase.kThresholdMs] as num?)?.toDouble();
      final sd = (_runner.state.custom[Staircase.kThresholdSdMs] as num?)?.toDouble();
      final pctText = stepPct == null ? '' : ' stepPct=${(stepPct * 100).toStringAsFixed(1)}%';
      final revText = reversalCount == null ? '' : ' reversals=$reversalCount';
      final threshText = (thresh != null && sd != null)
          ? ' threshold=${thresh.toStringAsFixed(1)}±${sd.toStringAsFixed(1)}ms'
          : '';
      _status = (score.correct ? 'Correct.' : 'Wrong.') + pctText + revText + threshText;
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
      _playCounts = List<int>.filled(3, 0, growable: false);
      _status = 'Press an option to play it and select which one had a gap.';
    });
  }

  @override
  Widget build(BuildContext context) {
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
                StaircaseChart(
                  gapsMs: (( _runner.state.custom[Staircase.kTrialGapHistory] as List?) ?? const [])
                      .whereType<num>()
                      .map((x) => x.toDouble())
                      .toList(growable: false),
                  correct: (( _runner.state.custom[Staircase.kTrialCorrectHistory] as List?) ?? const [])
                      .whereType<bool>()
                      .toList(growable: false),
                  thresholdMs: _runner.state.finished
                      ? (_runner.state.custom[Staircase.kThresholdMs] as num?)?.toDouble()
                      : null,
                  thresholdSdMs: _runner.state.finished
                      ? (_runner.state.custom[Staircase.kThresholdSdMs] as num?)?.toDouble()
                      : null,
                ),
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
                    for (var i = 1; i <= 3; i++)
                      FilledButton.tonal(
                        onPressed: _runner.state.finished ? null : () => _playIndex(i),
                        child: Text('Play $i (${_playCounts[i - 1]})'),
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
                      for (var i = 0; i < _numOptions; i++)
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