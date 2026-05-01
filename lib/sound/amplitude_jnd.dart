import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

import '../utils/outcomes.dart';
import '../utils/session_experiment_meta.dart';
import '../utils/session_store.dart';
import '../utils/staircase.dart';
import '../utils/trial_framework.dart';
import '../utils/trial_widgets.dart';
import 'amplitude_jnd_levels.dart';
import 'soloud_tone_player.dart';
import 'white_noise_source.dart';

class AmplitudeJndTrial {
  const AmplitudeJndTrial({
    required this.trialId,
    required this.targetIndex,
    required this.baseHz,
    required this.referenceGain,
    required this.deltaGain,
    required this.targetIsLouder,
    required this.toneDuration,
  });

  final int trialId;
  final int targetIndex;
  final double baseHz;
  /// Linear playback gain for the two reference intervals (SoLoud volume).
  final double referenceGain;
  /// Positive magnitude; odd interval uses reference ± delta (clamped).
  final double deltaGain;
  final bool targetIsLouder;
  final Duration toneDuration;

  double get targetPeakGain {
    if (targetIsLouder) {
      return min(amplitudeJndMaxPeakGain, referenceGain + deltaGain);
    }
    return max(amplitudeJndMinPeakGain, referenceGain - deltaGain);
  }

  /// Signed dB difference odd vs reference (20·log10).
  double get deltaDb =>
      amplitudePeakDifferenceDb(targetPeakGain, referenceGain);
}

class AmplitudeJndGuess {
  const AmplitudeJndGuess(this.selectedIndex);
  final int selectedIndex;
}

class AmplitudeJndPage extends StatefulWidget {
  const AmplitudeJndPage({super.key});

  @override
  State<AmplitudeJndPage> createState() => _AmplitudeJndPageState();
}

class _AmplitudeJndPageState extends State<AmplitudeJndPage> {
  final Random _random = Random();
  final SessionStore _store = SessionStore();

  static const List<double> _baseOptions = [220.0, 440.0];
  static const Duration _toneDuration = Duration(milliseconds: 700);

  static const double _minDeltaGain = 0.004;
  static const int _stopAfterReversals = 6;

  double _baseHz = 440.0;

  late TrialRunner<AmplitudeJndTrial, AmplitudeJndGuess> _runner;
  final Map<int, Float32List> _pcmByTrialId = <int, Float32List>{};
  List<TrialOutcome> _outcomes = const <TrialOutcome>[];
  bool _savedSession = false;
  String _status =
      'Press an option to play it and select which tone sounds different.';
  int? _selectedOptionNumber;
  late List<int> _playCounts;

  static const int _numOptions = 3;

  double get _initialDeltaGain {
    final hi = amplitudeMaxDeltaGain();
    if (!(hi > 0)) {
      return _minDeltaGain;
    }
    final lo = min(_minDeltaGain, hi);
    final fromDb =
        amplitudeLinearDeltaForLouderEnvelopeDb(amplitudeJndInitialEnvelopeDb);
    return fromDb.clamp(lo, hi);
  }

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

  TrialRunner<AmplitudeJndTrial, AmplitudeJndGuess> _newRunner() {
    return TrialRunner<AmplitudeJndTrial, AmplitudeJndGuess>(
      initialState: TrialRunnerState(
        startedAt: DateTime.now(),
        custom: Staircase.initialCustom(
          initialLevel: _initialDeltaGain,
          config: _staircaseConfig,
        ),
      ),
      generateTrial: (state) {
        final targetIndex = 1 + _random.nextInt(3);
        final deltaGain =
            (state.custom[Staircase.kLevel] as num?)?.toDouble() ??
                _initialDeltaGain;
        final targetIsLouder = _random.nextBool();
        return AmplitudeJndTrial(
          trialId: state.trialIndex,
          targetIndex: targetIndex,
          baseHz: _baseHz,
          referenceGain: amplitudeJndReferenceGain,
          deltaGain: deltaGain,
          targetIsLouder: targetIsLouder,
          toneDuration: _toneDuration,
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
            'deltaDb': trial.deltaDb,
            'targetIndex': trial.targetIndex,
            'selectedIndex': guess.selectedIndex,
            'amplitudeDeltaGain': trial.deltaGain,
            'referenceGain': trial.referenceGain,
            'targetPeakGain': trial.targetPeakGain,
            'targetIsLouder': trial.targetIsLouder,
            'reversalCount': reversalCount,
            'playCount1': _playCounts[0],
            'playCount2': _playCounts[1],
            'playCount3': _playCounts[2],
          },
        );
      },
      reduceState: (state, score) {
        final presentedDelta =
            (score.data['amplitudeDeltaGain'] as num?)?.toDouble() ??
                (state.custom[Staircase.kLevel] as num?)?.toDouble() ??
                _initialDeltaGain;

        final update = Staircase.update(
          custom: state.custom,
          correct: score.correct,
          presentedLevel: presentedDelta,
          minLevel: _minDeltaGain,
          maxLevel: amplitudeMaxDeltaGain(),
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

  Float32List _ensureTrialPcm(AmplitudeJndTrial trial) {
    final existing = _pcmByTrialId[trial.trialId];
    if (existing != null) return existing;

    const sampleRate = 44100;
    const channels = Channels.mono;

    final pcm = buildSineTonePcm(
      frequencyHz: trial.baseHz,
      duration: trial.toneDuration,
      sampleRate: sampleRate,
      channels: channels,
    );
    _pcmByTrialId[trial.trialId] = pcm;
    return pcm;
  }

  Future<void> _playIndex(int index) async {
    final trial = _runner.currentTrial;
    setState(() {
      final i = (index - 1).clamp(0, 2);
      _playCounts[i] = _playCounts[i] + 1;
      _status = 'Playing $index…';
    });

    final pcm = _ensureTrialPcm(trial);
    final isTarget = index == trial.targetIndex;
    final gain =
        isTarget ? trial.targetPeakGain : trial.referenceGain;

    await SoLoudTonePlayer.instance.playCachedPcm(
      pcm: pcm,
      amplitude: gain,
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

    final score = _runner.submitGuess(AmplitudeJndGuess(selected));
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
          ? ' threshold=${amplitudeLinearDeltaToEnvelopeDb(thresh).toStringAsFixed(2)}±${_thresholdSdDb(thresh, sd).toStringAsFixed(2)} dB'
          : '';

      _status =
          (score.correct ? 'Correct.' : 'Wrong.') + pctText + revText + threshText;
      _selectedOptionNumber = null;
    });

    if (_runner.state.finished) _onFinished();
  }

  double _thresholdSdDb(double thresholdLinear, double sdLinear) {
    return amplitudeThresholdSdEnvelopeDbFor(
      thresholdLinear: thresholdLinear,
      sdLinear: sdLinear,
      referenceGain: amplitudeJndReferenceGain,
      maxPeakGain: amplitudeJndMaxPeakGain,
    );
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
      mergeExperimentIntoSummary(
        _runner.summaryJson(),
        experimentKind: kExperimentAmplitudeJnd,
        experimentTitle: 'Amplitude JND',
      ),
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
    _pcmByTrialId.clear();
  }

  void _onBaseHzChanged(double hz) {
    if (hz == _baseHz) return;
    setState(() {
      _baseHz = hz;
    });
    _restart();
  }

  List<double> _staircaseHistoryDb(List<double> linear) {
    return linear
        .map(amplitudeLinearDeltaToEnvelopeDb)
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final linearHistory =
        ((_runner.state.custom[Staircase.kLevelHistory] as List?) ??
                const [])
            .whereType<num>()
            .map((x) => x.toDouble())
            .toList(growable: false);

    final threshLin = _runner.state.finished
        ? (_runner.state.custom[Staircase.kThreshold] as num?)?.toDouble()
        : null;
    final sdLin = _runner.state.finished
        ? (_runner.state.custom[Staircase.kThresholdSd] as num?)?.toDouble()
        : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Amplitude JND')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SessionStatsBar(runner: _runner),
                const SizedBox(height: 8),
                Text(
                  'Quiet levels: peak capped at '
                  '${amplitudeJndMaxPeakGain.toStringAsFixed(2)} '
                  '(reference ${amplitudeJndReferenceGain.toStringAsFixed(2)}). '
                  'Chart shows staircase step as Δ dB for louder-branch envelope.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                StaircaseChart(
                  levelsHistory: _staircaseHistoryDb(linearHistory),
                  correct: ((_runner.state.custom[Staircase.kCorrectHistory]
                              as List?) ??
                          const [])
                      .whereType<bool>()
                      .toList(growable: false),
                  threshold: threshLin != null
                      ? amplitudeLinearDeltaToEnvelopeDb(threshLin)
                      : null,
                  thresholdSd: threshLin != null && sdLin != null
                      ? _thresholdSdDb(threshLin, sdLin)
                      : null,
                  yAxisLabel: 'dB',
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('Tone frequency: '),
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
                  'Listen to each option. Same pitch; one tone is slightly louder or quieter than the other two.',
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
