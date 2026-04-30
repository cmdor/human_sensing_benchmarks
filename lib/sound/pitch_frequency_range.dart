import 'dart:math';

import 'package:flutter/material.dart';

import '../utils/outcomes.dart';
import '../utils/session_store.dart';
import '../utils/trial_framework.dart';
import '../utils/trial_widgets.dart';
import 'soloud_tone_player.dart';

class ParameterizedSoundGenerator {
  const ParameterizedSoundGenerator({
    required this.id,
    required this.frequencyHz,
    required this.amplitude,
    required this.duration,
  });

  final String id;
  final double frequencyHz;
  final double amplitude;
  final Duration duration;
}

class SoundTrial {
  const SoundTrial({
    required this.targetId,
    required this.a,
    required this.b,
  });

  final String targetId;
  final ParameterizedSoundGenerator a;
  final ParameterizedSoundGenerator b;
}

class SoundGuess {
  const SoundGuess(this.selectedId);
  final String selectedId;
}

class PitchFrequencyRangePage extends StatefulWidget {
  const PitchFrequencyRangePage({super.key});

  @override
  State<PitchFrequencyRangePage> createState() => _PitchFrequencyRangePageState();
}

class _PitchFrequencyRangePageState extends State<PitchFrequencyRangePage> {
  final Random _random = Random();
  final SessionStore _store = SessionStore();

  late TrialRunner<SoundTrial, SoundGuess> _runner;
  List<TrialOutcome> _outcomes = const <TrialOutcome>[];
  bool _savedSession = false;
  String _status = 'Tap Tone A or Tone B.';

  static const _toneA = ParameterizedSoundGenerator(
    id: 'A',
    frequencyHz: 440,
    amplitude: 0.6,
    duration: Duration(milliseconds: 600),
  );

  static const _toneB = ParameterizedSoundGenerator(
    id: 'B',
    frequencyHz: 880,
    amplitude: 0.6,
    duration: Duration(milliseconds: 600),
  );

  @override
  void initState() {
    super.initState();
    _runner = _newRunner();
    _runner.start();
  }

  TrialRunner<SoundTrial, SoundGuess> _newRunner() {
    return TrialRunner<SoundTrial, SoundGuess>(
      initialState: TrialRunnerState(startedAt: DateTime.now()),
      generateTrial: (state) {
        final target = _random.nextBool() ? 'A' : 'B';
        return SoundTrial(targetId: target, a: _toneA, b: _toneB);
      },
      scoreTrial: (trial, guess) {
        final correct = guess.selectedId == trial.targetId;
        return TrialScore(
          correct: correct,
          valid: true,
          data: <String, Object?>{
            'targetId': trial.targetId,
            'selectedId': guess.selectedId,
            'aHz': trial.a.frequencyHz,
            'bHz': trial.b.frequencyHz,
            'durationMs': trial.a.duration.inMilliseconds,
          },
        );
      },
      reduceState: (state, score) {
        final total = state.totalScored + 1;
        if (!score.correct) {
          final wrongStreak = state.wrongStreak + 1;
          return state.copyWith(
            trialIndex: state.trialIndex + 1,
            totalScored: total,
            correctScored: state.correctScored,
            wrongStreak: wrongStreak,
            finished: wrongStreak >= 2,
          );
        }

        return state.copyWith(
          trialIndex: state.trialIndex + 1,
          totalScored: total,
          correctScored: state.correctScored + 1,
          wrongStreak: 0,
          lastCorrectAt: DateTime.now(),
        );
      },
    );
  }

  Future<void> _play(ParameterizedSoundGenerator g) async {
    await SoLoudTonePlayer.instance.playSine(
      frequencyHz: g.frequencyHz,
      amplitude: g.amplitude,
      duration: g.duration,
    );
  }

  Future<void> _press(String id) async {
    if (_runner.state.finished) return;

    final trial = _runner.currentTrial;
    final generator = id == 'A' ? trial.a : trial.b;

    await _play(generator);

    final score = _runner.submitGuess(SoundGuess(id));
    setState(() {
      _status = score.correct
          ? 'Correct (target was ${trial.targetId}).'
          : 'Wrong (target was ${trial.targetId}).';
    });

    if (_runner.state.finished) {
      _onFinished();
    }
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
      _status = 'Tap Tone A or Tone B.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final trial = _runner.currentTrial;
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
                  'Target: ${trial.targetId} (for now, shown for testing)',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  alignment: WrapAlignment.center,
                  children: [
                    FilledButton(
                      onPressed: _runner.state.finished ? null : () => _press('A'),
                      child: Text('Tone A (${trial.a.frequencyHz.toInt()} Hz)'),
                    ),
                    FilledButton(
                      onPressed: _runner.state.finished ? null : () => _press('B'),
                      child: Text('Tone B (${trial.b.frequencyHz.toInt()} Hz)'),
                    ),
                  ],
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
