import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'trial_framework.dart';

class StoredSession {
  const StoredSession({
    required this.startedAtIso,
    required this.finishedAtIso,
    required this.summary,
    required this.events,
  });

  final String startedAtIso;
  final String? finishedAtIso;
  final Map<String, Object?> summary;
  final List<Map<String, Object?>> events;

  Map<String, Object?> toJson() => <String, Object?>{
        'startedAt': startedAtIso,
        'finishedAt': finishedAtIso,
        'summary': summary,
        'events': events,
      };

  static StoredSession fromJson(Map<String, Object?> json) {
    final eventsRaw = json['events'];
    final List<Map<String, Object?>> events = <Map<String, Object?>>[];
    if (eventsRaw is List) {
      for (final e in eventsRaw) {
        if (e is Map) {
          events.add(Map<String, Object?>.from(e.cast<String, Object?>()));
        }
      }
    }
    return StoredSession(
      startedAtIso: (json['startedAt'] as String?) ?? '',
      finishedAtIso: json['finishedAt'] as String?,
      summary: Map<String, Object?>.from((json['summary'] as Map?)?.cast<String, Object?>() ?? const {}),
      events: events,
    );
  }
}

class SessionStore {
  static const String _key = 'trial_sessions_v1';

  Future<List<StoredSession>> loadSessions() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.trim().isEmpty) return <StoredSession>[];

    final decoded = jsonDecode(raw);
    if (decoded is! List) return <StoredSession>[];

    final List<StoredSession> out = <StoredSession>[];
    for (final item in decoded) {
      if (item is Map) {
        out.add(StoredSession.fromJson(item.cast<String, Object?>()));
      }
    }
    return out;
  }

  Future<void> appendSession(SessionReport report, Map<String, Object?> summary) async {
    final prefs = await SharedPreferences.getInstance();
    final sessions = await loadSessions();

    final sessionJson = report.toJson(summary: summary);
    sessions.add(StoredSession.fromJson(sessionJson));

    final encoded = jsonEncode(sessions.map((s) => s.toJson()).toList(growable: false));
    await prefs.setString(_key, encoded);
  }

  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}

