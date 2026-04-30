import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'session_time.dart';
import 'trial_framework.dart';

class SessionStatsBar extends StatelessWidget {
  const SessionStatsBar({
    super.key,
    required this.runner,
  });

  final TrialRunner<dynamic, dynamic> runner;

  @override
  Widget build(BuildContext context) {
    final s = runner.state;
    final accuracyPct = (s.accuracy * 100).toStringAsFixed(0);
    final last = s.lastCorrectAt == null ? '—' : formatTimeOfDay(s.lastCorrectAt!);

    return Wrap(
      spacing: 12,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        _Chip(label: 'Trial', value: '${s.trialIndex + 1}'),
        _Chip(label: 'Accuracy', value: '$accuracyPct%'),
        _Chip(label: 'WrongStreak', value: '${s.wrongStreak}'),
        _Chip(label: 'LastCorrect', value: last),
        SessionElapsedChip(startedAt: s.startedAt),
      ],
    );
  }
}

class SessionElapsedChip extends StatelessWidget {
  const SessionElapsedChip({
    super.key,
    required this.startedAt,
  });

  final DateTime startedAt;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: Stream<int>.periodic(const Duration(seconds: 1), (i) => i),
      builder: (context, _) {
        final elapsed = DateTime.now().difference(startedAt);
        return _Chip(label: 'Elapsed', value: formatHms(elapsed));
      },
    );
  }
}

class ExportJsonButton extends StatefulWidget {
  const ExportJsonButton({
    super.key,
    required this.runner,
    this.label = 'Export JSON',
  });

  final TrialRunner<dynamic, dynamic> runner;
  final String label;

  @override
  State<ExportJsonButton> createState() => _ExportJsonButtonState();
}

class _ExportJsonButtonState extends State<ExportJsonButton> {
  Timer? _clearTimer;
  String? _copiedText;

  @override
  void dispose() {
    _clearTimer?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    final json = widget.runner.report.toJsonString(summary: widget.runner.summaryJson());
    await Clipboard.setData(ClipboardData(text: json));

    setState(() {
      _copiedText = 'Copied';
    });
    _clearTimer?.cancel();
    _clearTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() {
        _copiedText = null;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonal(
      onPressed: _copy,
      child: Text(_copiedText ?? widget.label),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text('$label: $value'),
      ),
    );
  }
}

