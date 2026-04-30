import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/outcomes.dart';
import '../utils/session_store.dart';
import '../utils/staircase.dart';
import '../utils/trial_framework.dart';
import '../utils/trial_widgets.dart';

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
        title: const Text('Outcomes'),
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
              final acc = s.summary['accuracy'];
              final total = s.summary['totalScored'];
              return Card(
                child: ListTile(
                  title: Text(started),
                  subtitle: Text('accuracy: $acc  total: $total'),
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
    final custom = (session.summary['custom'] is Map)
        ? Map<String, Object?>.from((session.summary['custom'] as Map).cast<String, Object?>())
        : const <String, Object?>{};
    final gaps = (custom[Staircase.kTrialGapHistory] as List?)
            ?.whereType<num>()
            .map((x) => x.toDouble())
            .toList(growable: false) ??
        const <double>[];
    final correct = (custom[Staircase.kTrialCorrectHistory] as List?)
            ?.whereType<bool>()
            .toList(growable: false) ??
        const <bool>[];
    final thresholdMs = (custom[Staircase.kThresholdMs] as num?)?.toDouble();
    final thresholdSdMs = (custom[Staircase.kThresholdSdMs] as num?)?.toDouble();
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
          if (gaps.isNotEmpty && gaps.length == correct.length) ...[
            const Text(
              'Staircase (gap size)',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            StaircaseChart(
              gapsMs: gaps,
              correct: correct,
              thresholdMs: thresholdMs,
              thresholdSdMs: thresholdSdMs,
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

