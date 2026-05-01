import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/outcomes.dart';
import '../utils/session_store.dart';
import '../utils/staircase.dart';
import '../utils/trial_framework.dart';
import '../utils/trial_widgets.dart';
import '../sound/amplitude_jnd_levels.dart';

/// Stored in session [StoredSession.summary] under this key (see sound / pitch JND).
const String kSessionExperimentKind = 'experimentKind';

/// Matches completion-screen staircase for gap detection ([SoundGapDetectionPage]).
const String kExperimentSoundGapDetection = 'sound_gap_detection';

/// Matches completion-screen staircase for pitch JND ([PitchJndPage]).
const String kExperimentPitchJnd = 'pitch_jnd';

/// Matches completion-screen staircase for amplitude JND ([AmplitudeJndPage]).
const String kExperimentAmplitudeJnd = 'amplitude_jnd';

_StaircaseSessionLabels _staircaseLabelsForSession(StoredSession session) {
  final kind = _inferExperimentKind(session);
  switch (kind) {
    case _InferredExperimentKind.soundGap:
      return const _StaircaseSessionLabels(
        sectionTitle: 'Staircase (gap duration)',
        yAxisLabel: 'ms',
      );
    case _InferredExperimentKind.pitchJnd:
      return const _StaircaseSessionLabels(
        sectionTitle: 'Staircase (pitch difference Δf)',
        yAxisLabel: 'Hz',
      );
    case _InferredExperimentKind.amplitudeJnd:
      return const _StaircaseSessionLabels(
        sectionTitle: 'Staircase (amplitude Δ, louder envelope)',
        yAxisLabel: 'dB',
      );
    case _InferredExperimentKind.unknown:
      return const _StaircaseSessionLabels(
        sectionTitle: 'Staircase',
        yAxisLabel: 'level',
      );
  }
}

class _StaircaseSessionLabels {
  const _StaircaseSessionLabels({
    required this.sectionTitle,
    required this.yAxisLabel,
  });

  final String sectionTitle;
  final String yAxisLabel;
}

enum _InferredExperimentKind { soundGap, pitchJnd, amplitudeJnd, unknown }

_InferredExperimentKind _inferExperimentKind(StoredSession session) {
  final raw = session.summary[kSessionExperimentKind];
  if (raw == kExperimentSoundGapDetection) {
    return _InferredExperimentKind.soundGap;
  }
  if (raw == kExperimentPitchJnd) {
    return _InferredExperimentKind.pitchJnd;
  }
  if (raw == kExperimentAmplitudeJnd) {
    return _InferredExperimentKind.amplitudeJnd;
  }

  for (final e in session.events) {
    if ((e['type'] as String?) != 'trial_scored') continue;
    final data = e['data'];
    if (data is! Map) continue;
    final m = Map<String, Object?>.from(data.cast<String, Object?>());
    if (m.containsKey('gapMs')) {
      return _InferredExperimentKind.soundGap;
    }
    if (m.containsKey('deltaHz') && m.containsKey('baseHz')) {
      return _InferredExperimentKind.pitchJnd;
    }
    if (m.containsKey('amplitudeDeltaGain') && m.containsKey('referenceGain')) {
      return _InferredExperimentKind.amplitudeJnd;
    }
  }

  return _InferredExperimentKind.unknown;
}

String _sessionListSubtitle(StoredSession s) {
  final acc = s.summary['accuracy'];
  final total = s.summary['totalScored'];
  final kind = _inferExperimentKind(s);
  final label = switch (kind) {
    _InferredExperimentKind.soundGap => 'Sound gap',
    _InferredExperimentKind.pitchJnd => 'Pitch JND',
    _InferredExperimentKind.amplitudeJnd => 'Amplitude JND',
    _InferredExperimentKind.unknown => 'Session',
  };
  return '$label  ·  accuracy: $acc  total: $total';
}

double? _amplitudeReferenceGainFromSession(StoredSession session) {
  for (final e in session.events) {
    if ((e['type'] as String?) != 'trial_scored') continue;
    final data = e['data'];
    if (data is! Map) continue;
    final m = Map<String, Object?>.from(data.cast<String, Object?>());
    final r = m['referenceGain'];
    if (r is num) return r.toDouble();
  }
  return null;
}

class OutcomesPage extends StatefulWidget {
  const OutcomesPage({super.key});

  @override
  State<OutcomesPage> createState() => _OutcomesPageState();
}

class _OutcomesPageState extends State<OutcomesPage> {
  final SessionStore _store = SessionStore();
  late Future<List<StoredSession>> _sessionsFuture;

  @override
  void initState() {
    super.initState();
    _sessionsFuture = _store.loadSessions();
  }

  Future<void> _reload() async {
    setState(() {
      _sessionsFuture = _store.loadSessions();
    });
  }

  Future<void> _clear() async {
    await _store.clearAll();
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('All Outcomes'),
        actions: [
          IconButton(
            onPressed: _reload,
            tooltip: 'Reload',
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            onPressed: _clear,
            tooltip: 'Clear all',
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: FutureBuilder<List<StoredSession>>(
        future: _sessionsFuture,
        builder: (context, snap) {
          if (snap.hasError) {
            final err = snap.error;
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Failed to load outcomes.',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '$err',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'If you recently added shared_preferences, do a Hot Restart (or restart flutter run).',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _reload,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }

          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final sessions = snap.data!;
          if (sessions.isEmpty) {
            return const Center(child: Text('No sessions saved yet.'));
          }

          final reversed = sessions.reversed.toList(growable: false);
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: reversed.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, i) {
              final s = reversed[i];
              final started = s.startedAtIso;
              return Card(
                child: ListTile(
                  title: Text(started),
                  subtitle: Text(_sessionListSubtitle(s)),
                  trailing: IconButton(
                    tooltip: 'Copy JSON',
                    icon: const Icon(Icons.copy),
                    onPressed: () async {
                      final json = _sessionToPrettyJson(s);
                      await Clipboard.setData(ClipboardData(text: json));
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Copied JSON')),
                      );
                    },
                  ),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => SessionDetailPage(session: s),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class SessionDetailPage extends StatelessWidget {
  const SessionDetailPage({super.key, required this.session});

  final StoredSession session;

  @override
  Widget build(BuildContext context) {
    final outcomes = deriveOutcomes(_asReport(session));
    final staircaseLabels = _staircaseLabelsForSession(session);
    final custom = (session.summary['custom'] is Map)
        ? Map<String, Object?>.from((session.summary['custom'] as Map).cast<String, Object?>())
        : const <String, Object?>{};
    final levelHistory = (custom[Staircase.kLevelHistory] as List?)
            ?.whereType<num>()
            .map((x) => x.toDouble())
            .toList(growable: false) ??
        const <double>[];
    final correct = (custom[Staircase.kCorrectHistory] as List?)
            ?.whereType<bool>()
            .toList(growable: false) ??
        const <bool>[];
    final thresholdLin = (custom[Staircase.kThreshold] as num?)?.toDouble();
    final thresholdSdLin = (custom[Staircase.kThresholdSd] as num?)?.toDouble();
    final experimentKind = _inferExperimentKind(session);

    List<double> chartLevels = levelHistory;
    double? chartThreshold = thresholdLin;
    double? chartSd = thresholdSdLin;
    var chartYAxis = staircaseLabels.yAxisLabel;

    if (experimentKind == _InferredExperimentKind.amplitudeJnd) {
      final refGain =
          _amplitudeReferenceGainFromSession(session) ?? amplitudeJndReferenceGain;
      chartLevels = levelHistory
          .map(
            (d) => amplitudeLinearDeltaToEnvelopeDbFor(
              linearDelta: d,
              referenceGain: refGain,
              maxPeakGain: amplitudeJndMaxPeakGain,
            ),
          )
          .toList(growable: false);
      chartThreshold = thresholdLin != null
          ? amplitudeLinearDeltaToEnvelopeDbFor(
              linearDelta: thresholdLin,
              referenceGain: refGain,
              maxPeakGain: amplitudeJndMaxPeakGain,
            )
          : null;
      chartSd = thresholdLin != null && thresholdSdLin != null
          ? amplitudeThresholdSdEnvelopeDbFor(
              thresholdLinear: thresholdLin,
              sdLinear: thresholdSdLin,
              referenceGain: refGain,
              maxPeakGain: amplitudeJndMaxPeakGain,
            )
          : null;
      chartYAxis = 'dB';
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Session detail'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('startedAt: ${session.startedAtIso}'),
          Text('finishedAt: ${session.finishedAtIso ?? '—'}'),
          const SizedBox(height: 12),
          const Text(
            'Per-trial outcomes',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          if (levelHistory.isNotEmpty && levelHistory.length == correct.length) ...[
            Text(
              staircaseLabels.sectionTitle,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            StaircaseChart(
              levelsHistory: chartLevels,
              correct: correct,
              threshold: chartThreshold,
              thresholdSd: chartSd,
              yAxisLabel: chartYAxis,
            ),
            const SizedBox(height: 16),
            const Text(
              'Reaction time',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
          ],
          OutcomesChart(outcomes: outcomes),
          const SizedBox(height: 12),
          OutcomesTable(outcomes: outcomes),
        ],
      ),
    );
  }

  SessionReport _asReport(StoredSession s) {
    // Re-hydrate only what deriveOutcomes needs: event types + data.
    final report = SessionReport(startedAt: DateTime.tryParse(s.startedAtIso));
    report.finishedAt = s.finishedAtIso == null ? null : DateTime.tryParse(s.finishedAtIso!);
    for (final e in s.events) {
      report.addEvent(
        (e['type'] as String?) ?? '',
        ts: DateTime.tryParse((e['ts'] as String?) ?? '') ?? DateTime.now(),
        data: Map<String, Object?>.from((e['data'] as Map?)?.cast<String, Object?>() ?? const {}),
      );
    }
    return report;
  }
}

String _sessionToPrettyJson(StoredSession s) {
  // StoredSession is already JSON-like; just render it.
  return const JsonEncoder.withIndent('  ').convert(s.toJson());
}

