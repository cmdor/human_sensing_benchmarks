import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

import '../utils/outcomes.dart';
import '../utils/session_store.dart';
import '../utils/staircase.dart';
import '../utils/trial_framework.dart';
import '../utils/trial_widgets.dart';
import 'soloud_tone_player.dart';
import 'white_noise_source.dart';

class PitchJndTrial {
  const PitchJndTrial({
    required this.trialId,
    required this.targetIndex,
    required this.baseHz,
    required this.deltaHz,
    required this.targetIsHigher,
    required this.toneDuration,
    required this.amplitude,
  });

  final int trialId;
  final int targetIndex; // 1..3
  final double baseHz;
  /// Magnitude of pitch shift from [baseHz] for the odd-one-out tone (always positive).
  final double deltaHz;
  /// If true, odd tone is [baseHz] + [deltaHz]; if false, [baseHz] - [deltaHz].
  final bool targetIsHigher;
  final Duration toneDuration;
  final double amplitude;
}

class PitchJndGuess {
  const PitchJndGuess(this.selectedIndex);
  final int selectedIndex; // 1..3
}

/// Cached PCM data for one trial.
/// [reference] is a tone at [baseHz]; [target] is shifted by ±[deltaHz].
class _TrialTones {
  const _TrialTones({required this.reference, required this.target});

  final Float32List reference;
  final Float32List target;
}

class PitchJndPage extends StatefulWidget {
  const PitchJndPage({super.key});

  @override
  State<PitchJndPage> createState() => _PitchJndPageState();
}

class _PitchJndPageState extends State<PitchJndPage> {
  final Random _random = Random();
  final SessionStore _store = SessionStore();

  static const List<double> _baseOptions = [220.0, 440.0];
  static const Duration _toneDuration = Duration(milliseconds: 700);
  static const double _amplitude = 0.7;
  static const double _minDeltaHz = 0.5;
  static const double _maxDeltaHz = 50.0;
  static const int _stopAfterReversals = 6;

  double _baseHz = 440.0;

  late TrialRunner<PitchJndTrial, PitchJndGuess> _runner;
  final Map<int, _TrialTones> _tonesByTrialId = <int, _TrialTones>{};
  List<TrialOutcome> _outcomes = const <TrialOutcome>[];
  bool _savedSession = false;
  String _status =
      'Press an option to play it and select which tone sounds different.';
  int? _selectedOptionNumber;
  late List<int> _playCounts;

  static const int _numOptions = 3;

  double get _initialDeltaHz => _baseHz * 0.05;

  static const StaircaseConfig _staircaseConfig = StaircaseConfig(
    downInitialPct: 0.50,
    upInitialPct: 0.20,
    decayFactor: 0.85,
    downMinPct: 0.05,
    upMinPct: 0.05,
    nDown: 2,
    thresholdLastN: 4,
  );

  @override
  void initState() {
    super.initState();
    _runner = _newRunner();
    _runner.start();
    _playCounts = List<int>.filled(3, 0, growable: false);
  }

  TrialRunner<PitchJndTrial, PitchJndGuess> _newRunner() {
    return TrialRunner<PitchJndTrial, PitchJndGuess>(
      initialState: TrialRunnerState(
        startedAt: DateTime.now(),
        custom: Staircase.initialCustom(
          initialLevel: _initialDeltaHz,
          config: _staircaseConfig,
        ),
      ),
      generateTrial: (state) {
        final targetIndex = 1 + _random.nextInt(3);
        final deltaHz =
            (state.custom[Staircase.kLevel] as num?)?.toDouble() ??
                _initialDeltaHz;
        final targetIsHigher = _random.nextBool();
        return PitchJndTrial(
          trialId: state.trialIndex,
          targetIndex: targetIndex,
          baseHz: _baseHz,
          deltaHz: deltaHz,
          targetIsHigher: targetIsHigher,
          toneDuration: _toneDuration,
          amplitude: _amplitude,
        );
      },
      scoreTrial: (trial, guess) {
        final correct = guess.selectedIndex == trial.targetIndex;
        final reversalCount =
            (_runner.state.custom[Staircase.kReversalCount] as num?)?.toInt() ??
                0;
        return TrialScore(
          correct: correct,
          valid: true,
          data: <String, Object?>{
            // Order matters: OutcomesSummary compact row shows first 4 keys.
            'baseHz': trial.baseHz,
            'deltaHz': trial.deltaHz,
            'targetIndex': trial.targetIndex,
            'selectedIndex': guess.selectedIndex,
            'targetIsHigher': trial.targetIsHigher,
            'reversalCount': reversalCount,
            'playCount1': _playCounts[0],
            'playCount2': _playCounts[1],
            'playCount3': _playCounts[2],
          },
        );
      },
      reduceState: (state, score) {
        final presentedDelta =
            (score.data['deltaHz'] as num?)?.toDouble() ??
                (state.custom[Staircase.kLevel] as num?)?.toDouble() ??
                _initialDeltaHz;

        final update = Staircase.update(
          custom: state.custom,
          correct: score.correct,
          presentedLevel: presentedDelta,
          minLevel: _minDeltaHz,
          maxLevel: _maxDeltaHz,
          config: _staircaseConfig,
        );

        final total = state.totalScored + 1;
        final finished = update.reversalCount >= _stopAfterReversals;

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

  _TrialTones _ensureTrialTones(PitchJndTrial trial) {
    final existing = _tonesByTrialId[trial.trialId];
    if (existing != null) return existing;

    const sampleRate = 44100;
    const channels = Channels.mono;

    final reference = buildSineTonePcm(
      frequencyHz: trial.baseHz,
      duration: trial.toneDuration,
      sampleRate: sampleRate,
      channels: channels,
    );
    final shiftedHz = trial.targetIsHigher
        ? trial.baseHz + trial.deltaHz
        : trial.baseHz - trial.deltaHz;
    final target = buildSineTonePcm(
      frequencyHz: shiftedHz.clamp(20.0, 20000.0),
      duration: trial.toneDuration,
      sampleRate: sampleRate,
      channels: channels,
    );

    final tones = _TrialTones(reference: reference, target: target);
    _tonesByTrialId[trial.trialId] = tones;
    return tones;
  }

  Future<void> _playIndex(int index) async {
    final trial = _runner.currentTrial;
    setState(() {
      final i = (index - 1).clamp(0, 2);
      _playCounts[i] = _playCounts[i] + 1;
      _status = 'Playing $index…';
    });

    final isTarget = index == trial.targetIndex;
    final tones = _ensureTrialTones(trial);
    await SoLoudTonePlayer.instance.playCachedPcm(
      pcm: isTarget ? tones.target : tones.reference,
      amplitude: trial.amplitude,
      totalDuration: trial.toneDuration,
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

    final score = _runner.submitGuess(PitchJndGuess(selected));
    setState(() {
      final stepPct =
          (_runner.state.custom[Staircase.kStepPct] as num?)?.toDouble();
      final reversalCount =
          (_runner.state.custom[Staircase.kReversalCount] as num?)?.toInt();
      final thresh =
          (_runner.state.custom[Staircase.kThreshold] as num?)?.toDouble();
      final sd =
          (_runner.state.custom[Staircase.kThresholdSd] as num?)?.toDouble();

      final pctText = stepPct == null
          ? ''
          : ' stepPct=${(stepPct * 100).toStringAsFixed(1)}%';
      final revText =
          reversalCount == null ? '' : ' reversals=$reversalCount';
      final threshText = (thresh != null && sd != null)
          ? ' threshold=${thresh.toStringAsFixed(2)}±${sd.toStringAsFixed(2)}Hz'
          : '';

      _status =
          (score.correct ? 'Correct.' : 'Wrong.') + pctText + revText + threshText;
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
      _status = 'Finished. Threshold estimated from last $_stopAfterReversals reversals.';
    });
    _store.appendSession(
      _runner.report,
      <String, Object?>{
        ..._runner.summaryJson(),
        'experimentKind': 'pitch_jnd',
      },
    );
  }

  void _restart() {
    setState(() {
      _runner = _newRunner();
      _runner.start();
      _outcomes = const <TrialOutcome>[];
      _savedSession = false;
      _selectedOptionNumber = null;
      _playCounts = List<int>.filled(3, 0, growable: false);
      _status =
          'Press an option to play it and select which tone sounds different.';
    });
    _tonesByTrialId.clear();
  }

  void _onBaseHzChanged(double hz) {
    if (hz == _baseHz) return;
    setState(() {
      _baseHz = hz;
    });
    _restart();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pitch JND')),
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
                  levelsHistory: ((_runner.state.custom[Staircase.kLevelHistory]
                              as List?) ??
                          const [])
                      .whereType<num>()
                      .map((x) => x.toDouble())
                      .toList(growable: false),
                  correct: ((_runner.state.custom[Staircase.kCorrectHistory]
                              as List?) ??
                          const [])
                      .whereType<bool>()
                      .toList(growable: false),
                  threshold: _runner.state.finished
                      ? (_runner.state.custom[Staircase.kThreshold] as num?)
                          ?.toDouble()
                      : null,
                  thresholdSd: _runner.state.finished
                      ? (_runner.state.custom[Staircase.kThresholdSd] as num?)
                          ?.toDouble()
                      : null,
                  yAxisLabel: 'Hz',
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('Base frequency: '),
                    const SizedBox(width: 8),
                    SegmentedButton<double>(
                      segments: _baseOptions
                          .map(
                            (hz) => ButtonSegment<double>(
                              value: hz,
                              label: Text('${hz.toInt()} Hz'),
                            ),
                          )
                          .toList(growable: false),
                      selected: {_baseHz},
                      onSelectionChanged: (s) => _onBaseHzChanged(s.first),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text(
                  'Listen to each option. One tone is slightly higher or lower than the other two.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  alignment: WrapAlignment.center,
                  children: [
                    for (var i = 1; i <= _numOptions; i++)
                      FilledButton.tonal(
                        onPressed:
                            _runner.state.finished ? null : () => _playIndex(i),
                        child: Text('Play $i'),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Which option sounded different?',
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
                  onPressed: _runner.state.finished
                      ? null
                      : (_selectedOptionNumber == null ? null : _submit),
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
