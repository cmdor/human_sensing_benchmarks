import 'dart:convert';

class TrialEvent {
  TrialEvent({
    required this.ts,
    required this.type,
    Map<String, Object?>? data,
  }) : data = data ?? <String, Object?>{};

  final DateTime ts;
  final String type;
  final Map<String, Object?> data;

  Map<String, Object?> toJson() => {
        'ts': ts.toIso8601String(),
        'type': type,
        'data': data,
      };
}

class SessionReport {
  SessionReport({DateTime? startedAt}) : startedAt = startedAt ?? DateTime.now();

  final DateTime startedAt;
  DateTime? finishedAt;
  final List<TrialEvent> events = <TrialEvent>[];

  void addEvent(String type, {Map<String, Object?>? data, DateTime? ts}) {
    events.add(
      TrialEvent(
        ts: ts ?? DateTime.now(),
        type: type,
        data: data,
      ),
    );
  }

  Map<String, Object?> toJson({Map<String, Object?>? summary}) => {
        'startedAt': startedAt.toIso8601String(),
        'finishedAt': finishedAt?.toIso8601String(),
        'summary': summary ?? <String, Object?>{},
        'events': events.map((e) => e.toJson()).toList(growable: false),
      };

  String toJsonString({Map<String, Object?>? summary}) {
    return const JsonEncoder.withIndent('  ').convert(toJson(summary: summary));
  }
}

class TrialRunnerState {
  const TrialRunnerState({
    required this.startedAt,
    this.trialIndex = 0,
    this.totalScored = 0,
    this.correctScored = 0,
    this.wrongStreak = 0,
    this.lastCorrectAt,
    this.finished = false,
    this.custom = const <String, Object?>{},
  });

  final DateTime startedAt;
  final int trialIndex;
  final int totalScored;
  final int correctScored;
  final int wrongStreak;
  final DateTime? lastCorrectAt;
  final bool finished;

  /// Trial-specific state (e.g. contrast, size scale).
  final Map<String, Object?> custom;

  Duration get elapsed => DateTime.now().difference(startedAt);

  double get accuracy {
    if (totalScored == 0) return 0;
    return correctScored / totalScored;
  }

  TrialRunnerState copyWith({
    int? trialIndex,
    int? totalScored,
    int? correctScored,
    int? wrongStreak,
    DateTime? lastCorrectAt,
    bool? finished,
    Map<String, Object?>? custom,
  }) {
    return TrialRunnerState(
      startedAt: startedAt,
      trialIndex: trialIndex ?? this.trialIndex,
      totalScored: totalScored ?? this.totalScored,
      correctScored: correctScored ?? this.correctScored,
      wrongStreak: wrongStreak ?? this.wrongStreak,
      lastCorrectAt: lastCorrectAt ?? this.lastCorrectAt,
      finished: finished ?? this.finished,
      custom: custom ?? this.custom,
    );
  }
}

class TrialScore {
  const TrialScore({
    required this.correct,
    required this.valid,
    this.data = const <String, Object?>{},
  });

  final bool correct;
  final bool valid;
  final Map<String, Object?> data;
}

typedef TrialGenerator<TTrial> = TTrial Function(TrialRunnerState state);
typedef TrialScorer<TTrial, TGuess> = TrialScore Function(TTrial trial, TGuess guess);
typedef TrialReducer = TrialRunnerState Function(TrialRunnerState state, TrialScore score);

class TrialRunner<TTrial, TGuess> {
  TrialRunner({
    required TrialGenerator<TTrial> generateTrial,
    required TrialScorer<TTrial, TGuess> scoreTrial,
    required TrialReducer reduceState,
    TrialRunnerState? initialState,
    SessionReport? report,
  })  : _generateTrial = generateTrial,
        _scoreTrial = scoreTrial,
        _reduceState = reduceState,
        report = report ?? SessionReport(startedAt: initialState?.startedAt),
        state = initialState ?? TrialRunnerState(startedAt: DateTime.now());

  final TrialGenerator<TTrial> _generateTrial;
  final TrialScorer<TTrial, TGuess> _scoreTrial;
  final TrialReducer _reduceState;

  TrialRunnerState state;
  final SessionReport report;

  late TTrial currentTrial;

  void start() {
    report.addEvent('session_started');
    currentTrial = _generateTrial(state);
    report.addEvent(
      'trial_presented',
      data: <String, Object?>{
        'trialIndex': state.trialIndex,
      },
    );
  }

  TrialScore submitGuess(TGuess guess, {Map<String, Object?>? guessData}) {
    if (state.finished) {
      return const TrialScore(correct: false, valid: false);
    }

    report.addEvent(
      'guess_submitted',
      data: <String, Object?>{
        'trialIndex': state.trialIndex,
        if (guessData != null) ...guessData,
      },
    );

    final score = _scoreTrial(currentTrial, guess);
    report.addEvent(
      'trial_scored',
      data: <String, Object?>{
        'trialIndex': state.trialIndex,
        'correct': score.correct,
        'valid': score.valid,
        ...score.data,
      },
    );

    state = _reduceState(state, score);

    if (state.finished) {
      report.finishedAt = DateTime.now();
      report.addEvent('session_finished');
      return score;
    }

    currentTrial = _generateTrial(state);
    report.addEvent(
      'trial_presented',
      data: <String, Object?>{
        'trialIndex': state.trialIndex,
      },
    );
    return score;
  }

  Map<String, Object?> summaryJson() {
    return <String, Object?>{
      'trialIndex': state.trialIndex,
      'totalScored': state.totalScored,
      'correctScored': state.correctScored,
      'accuracy': state.accuracy,
      'wrongStreak': state.wrongStreak,
      'lastCorrectAt': state.lastCorrectAt?.toIso8601String(),
      'elapsedMs': state.elapsed.inMilliseconds,
      'finished': state.finished,
      'custom': state.custom,
    };
  }
}

