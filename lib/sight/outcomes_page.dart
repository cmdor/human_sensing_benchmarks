import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/outcomes.dart';
import '../utils/session_store.dart';
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

