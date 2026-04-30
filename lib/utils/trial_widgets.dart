import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'outcomes.dart';
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

class OutcomesSummary extends StatelessWidget {
  const OutcomesSummary({
    super.key,
    required this.outcomes,
    this.maxItems = 12,
  });

  final List<TrialOutcome> outcomes;
  final int maxItems;

  @override
  Widget build(BuildContext context) {
    if (outcomes.isEmpty) return const SizedBox.shrink();
    final items = outcomes.length <= maxItems
        ? outcomes
        : outcomes.sublist(outcomes.length - maxItems);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        const Text(
          'Outcomes',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        OutcomesChart(outcomes: items),
        const SizedBox(height: 12),
        OutcomesTable(outcomes: items),
      ],
    );
  }
}

class OutcomesChart extends StatelessWidget {
  const OutcomesChart({
    super.key,
    required this.outcomes,
    this.height = 160,
  });

  final List<TrialOutcome> outcomes;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: CustomPaint(
            painter: _OutcomesChartPainter(
              outcomes: outcomes,
              axisColor: Theme.of(context).colorScheme.outline,
              correctColor: Theme.of(context).colorScheme.primary,
              wrongColor: Theme.of(context).colorScheme.error,
              textStyle: Theme.of(context).textTheme.labelSmall ??
                  const TextStyle(fontSize: 11),
            ),
          ),
        ),
      ),
    );
  }
}

class _OutcomesChartPainter extends CustomPainter {
  _OutcomesChartPainter({
    required this.outcomes,
    required this.axisColor,
    required this.correctColor,
    required this.wrongColor,
    required this.textStyle,
  });

  final List<TrialOutcome> outcomes;
  final Color axisColor;
  final Color correctColor;
  final Color wrongColor;
  final TextStyle textStyle;

  @override
  void paint(Canvas canvas, Size size) {
    final rts = outcomes
        .map((o) => o.reactionMs)
        .whereType<int>()
        .toList(growable: false);
    if (rts.isEmpty) {
      _drawLabel(canvas, size, 'No reaction time data');
      return;
    }

    final minRt = rts.reduce((a, b) => a < b ? a : b);
    final maxRt = rts.reduce((a, b) => a > b ? a : b);
    final span = (maxRt - minRt).clamp(1, 1 << 30);

    final leftPad = 34.0;
    final bottomPad = 18.0;
    final topPad = 10.0;
    final chart = Rect.fromLTWH(
      leftPad,
      topPad,
      (size.width - leftPad).clamp(0, double.infinity),
      (size.height - topPad - bottomPad).clamp(0, double.infinity),
    );

    final axisPaint = Paint()
      ..color = axisColor
      ..strokeWidth = 1;
    canvas.drawLine(chart.bottomLeft, chart.bottomRight, axisPaint);
    canvas.drawLine(chart.bottomLeft, chart.topLeft, axisPaint);

    // Y labels: min/max
    _drawText(
      canvas,
      Offset(0, chart.bottom - 8),
      '${minRt}ms',
    );
    _drawText(
      canvas,
      Offset(0, chart.top - 4),
      '${maxRt}ms',
    );

    final n = outcomes.length;
    if (n == 1) {
      final o = outcomes.first;
      final rt = o.reactionMs;
      if (rt == null) return;
      final y = chart.bottom - ((rt - minRt) / span) * chart.height;
      final p = Offset(chart.left + chart.width / 2, y);
      canvas.drawCircle(
        p,
        3,
        Paint()..color = o.correct ? correctColor : wrongColor,
      );
      return;
    }

    final points = <Offset>[];
    for (var i = 0; i < n; i++) {
      final o = outcomes[i];
      final rt = o.reactionMs;
      if (rt == null) continue;
      final x = chart.left + (i / (n - 1)) * chart.width;
      final y = chart.bottom - ((rt - minRt) / span) * chart.height;
      points.add(Offset(x, y));
    }

    final linePaint = Paint()
      ..color = axisColor
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    if (points.length >= 2) {
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (var i = 1; i < points.length; i++) {
        path.lineTo(points[i].dx, points[i].dy);
      }
      canvas.drawPath(path, linePaint);
    }

    for (var i = 0; i < n; i++) {
      final o = outcomes[i];
      final rt = o.reactionMs;
      if (rt == null) continue;
      final x = chart.left + (i / (n - 1)) * chart.width;
      final y = chart.bottom - ((rt - minRt) / span) * chart.height;
      canvas.drawCircle(
        Offset(x, y),
        3,
        Paint()..color = o.correct ? correctColor : wrongColor,
      );
    }
  }

  void _drawLabel(Canvas canvas, Size size, String text) {
    _drawText(canvas, Offset(0, size.height / 2 - 6), text);
  }

  void _drawText(Canvas canvas, Offset offset, String text) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: textStyle),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 80);
    tp.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _OutcomesChartPainter oldDelegate) {
    return oldDelegate.outcomes != outcomes ||
        oldDelegate.axisColor != axisColor ||
        oldDelegate.correctColor != correctColor ||
        oldDelegate.wrongColor != wrongColor ||
        oldDelegate.textStyle != textStyle;
  }
}

class OutcomesTable extends StatelessWidget {
  const OutcomesTable({
    super.key,
    required this.outcomes,
  });

  final List<TrialOutcome> outcomes;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Trial')),
          DataColumn(label: Text('Correct')),
          DataColumn(label: Text('Reaction (ms)')),
          DataColumn(label: Text('Details')),
        ],
        rows: [
          for (final o in outcomes)
            DataRow(
              cells: [
                DataCell(Text('${o.trialIndex}')),
                DataCell(Text(o.correct ? 'yes' : 'no')),
                DataCell(Text(o.reactionMs?.toString() ?? '—')),
                DataCell(Text(_detailsCompact(o.details))),
              ],
            ),
        ],
      ),
    );
  }

  static String _detailsCompact(Map<String, Object?> details) {
    if (details.isEmpty) return '';
    final keys = details.keys.take(4).toList(growable: false);
    return keys.map((k) => '$k=${details[k]}').join('  ');
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

