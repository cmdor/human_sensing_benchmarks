import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../utils/outcomes.dart';
import '../utils/screen_calibration.dart';
import '../utils/session_experiment_meta.dart';
import '../utils/session_store.dart';
import '../utils/staircase.dart';
import '../utils/trial_framework.dart';
import '../utils/trial_widgets.dart';
import '../sound/amplitude_jnd_levels.dart';
import 'angular_resolution.dart' show kDefaultViewingDistanceMm;

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
    case _InferredExperimentKind.contrastFinder:
    case _InferredExperimentKind.eRotation:
    case _InferredExperimentKind.pitchFrequencyRange:
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

enum _InferredExperimentKind {
  soundGap,
  pitchJnd,
  amplitudeJnd,
  contrastFinder,
  eRotation,
  pitchFrequencyRange,
  unknown,
}

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
  if (raw == kExperimentContrastFinder) {
    return _InferredExperimentKind.contrastFinder;
  }
  if (raw == kExperimentERotation) {
    return _InferredExperimentKind.eRotation;
  }
  if (raw == kExperimentPitchFrequencyRange) {
    return _InferredExperimentKind.pitchFrequencyRange;
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
    if (m.containsKey('guessRotationDegrees') && m.containsKey('presentedRotationDegrees')) {
      return _InferredExperimentKind.eRotation;
    }
    if (m.containsKey('lowHz') &&
        m.containsKey('highHz') &&
        m.containsKey('minHz') &&
        m.containsKey('maxHz')) {
      return _InferredExperimentKind.pitchFrequencyRange;
    }
    if (m.containsKey('guess') &&
        m.containsKey('expected') &&
        m.containsKey('contrast') &&
        !m.containsKey('amplitudeDeltaGain')) {
      return _InferredExperimentKind.contrastFinder;
    }
  }

  return _InferredExperimentKind.unknown;
}

/// Prefer persisted title from session summary; fallback to inferred short label.
String _trialDisplayTitle(StoredSession session) {
  final t = session.summary[kSessionExperimentTitle];
  if (t is String && t.trim().isNotEmpty) return t.trim();
  return _trialExperimentShortLabel(session);
}

String _sessionListSubtitle(StoredSession s) {
  final acc = s.summary['accuracy'];
  final total = s.summary['totalScored'];
  final label = _trialDisplayTitle(s);
  final base = '$label  ·  accuracy: $acc  total: $total';
  final arcMin = s.summary['visualAngleArcMinutes'];
  if (arcMin is num && _inferExperimentKind(s) == _InferredExperimentKind.eRotation) {
    return '$base  ·  acuity: ${arcMin.toStringAsFixed(2)} arcmin';
  }
  return base;
}

String _sessionMetricsLine(StoredSession s) {
  final acc = s.summary['accuracy'];
  final total = s.summary['totalScored'];
  return 'accuracy: $acc · totalScored: $total';
}

/// Fallback experiment label when [kSessionExperimentTitle] was not stored (older sessions).
String _trialExperimentShortLabel(StoredSession session) {
  return switch (_inferExperimentKind(session)) {
    _InferredExperimentKind.soundGap => 'Sound Gap Detection',
    _InferredExperimentKind.pitchJnd => 'Pitch Just Noticeable Difference',
    _InferredExperimentKind.amplitudeJnd => 'Amplitude Just Noticeable Difference',
    _InferredExperimentKind.contrastFinder => 'Contrast Finder',
    _InferredExperimentKind.eRotation => 'E Rotation Trial',
    _InferredExperimentKind.pitchFrequencyRange => 'Pitch Frequency Range',
    _InferredExperimentKind.unknown => 'Session',
  };
}

/// Session id, trial type, and chart title — rasterized with each chart for exports.
Widget _chartCaptureHeading(
  BuildContext context,
  StoredSession session,
  String chartTitle,
) {
  final theme = Theme.of(context).textTheme;
  final scheme = Theme.of(context).colorScheme;
  return Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          session.startedAtIso,
          style: theme.labelSmall?.copyWith(color: scheme.outline),
        ),
        Text(
          _trialDisplayTitle(session),
          style: theme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        Text(
          chartTitle,
          style: theme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );
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

/// Staircase + outcomes derived consistently for UI and PDF export.
class _DerivedSessionView {
  const _DerivedSessionView({
    required this.outcomes,
    required this.hasStaircase,
    required this.staircaseLabels,
    required this.chartLevels,
    required this.correct,
    required this.chartThreshold,
    required this.chartThresholdSd,
    required this.chartYAxis,
  });

  final List<TrialOutcome> outcomes;
  final bool hasStaircase;
  final _StaircaseSessionLabels staircaseLabels;
  final List<double> chartLevels;
  final List<bool> correct;
  final double? chartThreshold;
  final double? chartThresholdSd;
  final String chartYAxis;
}

_DerivedSessionView _deriveSessionView(StoredSession session) {
  final outcomes = deriveOutcomes(_sessionReportFromStored(session));
  final staircaseLabels = _staircaseLabelsForSession(session);
  final custom = _customMap(session);
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

  List<double> chartLevels = List<double>.from(levelHistory);
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

  final hasStaircase =
      levelHistory.isNotEmpty && levelHistory.length == correct.length;

  return _DerivedSessionView(
    outcomes: outcomes,
    hasStaircase: hasStaircase,
    staircaseLabels: staircaseLabels,
    chartLevels: chartLevels,
    correct: correct,
    chartThreshold: chartThreshold,
    chartThresholdSd: chartSd,
    chartYAxis: chartYAxis,
  );
}

/// On Flutter Web, [Printing.layoutPdf] drives the browser print dialog from a
/// hidden iframe; it does not save a file. [Printing.sharePdf] uses a download
/// link and produces an actual `.pdf` download in typical desktop browsers.
Future<void> _sharePdfDownloadOrPrint({
  required Uint8List bytes,
  required String filename,
}) async {
  if (bytes.isEmpty) return;
  final hasPdfSuffix = filename.toLowerCase().endsWith('.pdf');
  final downloadName = hasPdfSuffix ? filename : '$filename.pdf';
  final layoutName =
      hasPdfSuffix ? filename.substring(0, filename.length - 4) : filename;

  if (kIsWeb) {
    await Printing.sharePdf(bytes: bytes, filename: downloadName);
  } else {
    await Printing.layoutPdf(
      name: layoutName,
      dynamicLayout: false,
      onLayout: (_) async => bytes,
    );
  }
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

  Future<void> _exportAllSessionsPdf() async {
    List<StoredSession> sessions;
    try {
      sessions = await _store.loadSessions();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load sessions: $e')),
      );
      return;
    }
    if (!mounted) return;
    if (sessions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No sessions to export.')),
      );
      return;
    }

    final reversed = sessions.reversed.toList(growable: false);

    final chartImages = <List<Uint8List>>[];
    for (final s in reversed) {
      if (!mounted) return;
      chartImages.add(await _captureSessionChartPngs(context, s));
    }
    if (!mounted) return;

    final doc = pw.Document();

    for (var i = 0; i < reversed.length; i++) {
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(28),
          build: (_) => _pdfSingleSessionSummaryAndChartsPage(
            session: reversed[i],
            pngs: chartImages[i],
          ),
        ),
      );
    }

    final safeDay =
        DateTime.now().toUtc().toIso8601String().split('T').first.replaceAll(RegExp(r'[/:]'), '-');
    await _sharePdfDownloadOrPrint(
      bytes: await doc.save(),
      filename: 'all_sessions_$safeDay.pdf',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('All Outcomes'),
        actions: [
          IconButton(
            onPressed: _exportAllSessionsPdf,
            tooltip: 'Export all sessions (PDF)',
            icon: const Icon(Icons.picture_as_pdf_outlined),
          ),
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
            separatorBuilder: (context, index) => const SizedBox(height: 12),
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

class SessionDetailPage extends StatefulWidget {
  const SessionDetailPage({super.key, required this.session});

  final StoredSession session;

  @override
  State<SessionDetailPage> createState() => _SessionDetailPageState();
}

class _SessionDetailPageState extends State<SessionDetailPage> {
  final GlobalKey _staircaseChartKey = GlobalKey();
  final GlobalKey _outcomesChartKey = GlobalKey();

  Future<void> _printGraphsOnlyToPdf() async {
    await Future<void>.delayed(const Duration(milliseconds: 32));
    if (!mounted) return;

    final pngs = <Uint8List>[];
    final hasStaircase = _hasStaircaseData;

    if (hasStaircase) {
      final b = await _repaintBoundaryToPng(_staircaseChartKey);
      if (b != null) pngs.add(b);
    }
    final outcomesPng = await _repaintBoundaryToPng(_outcomesChartKey);
    if (outcomesPng != null) pngs.add(outcomesPng);

    if (pngs.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not capture charts for PDF.')),
      );
      return;
    }

    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (_) => _pdfSingleSessionSummaryAndChartsPage(
          session: widget.session,
          pngs: pngs,
        ),
      ),
    );

    if (!mounted) return;
    final safeName = widget.session.startedAtIso.replaceAll(RegExp(r'[/:]'), '-');
    await _sharePdfDownloadOrPrint(
      bytes: await doc.save(),
      filename: 'session_graphs_$safeName.pdf',
    );
  }

  bool get _hasStaircaseData => _deriveSessionView(widget.session).hasStaircase;

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final v = _deriveSessionView(session);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Session detail'),
        actions: [
          IconButton(
            tooltip: 'Export summary and graphs (PDF)',
            icon: const Icon(Icons.picture_as_pdf_outlined),
            onPressed: _printGraphsOnlyToPdf,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('startedAt: ${session.startedAtIso}'),
          Text('finishedAt: ${session.finishedAtIso ?? '—'}'),
          const SizedBox(height: 12),
          if (_inferExperimentKind(session) == _InferredExperimentKind.eRotation)
            _ERotationAcuityCard(session: session),
          const Text(
            'Per-trial outcomes',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          if (v.hasStaircase) ...[
            RepaintBoundary(
              key: _staircaseChartKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _chartCaptureHeading(context, session, v.staircaseLabels.sectionTitle),
                  StaircaseChart(
                    levelsHistory: v.chartLevels,
                    correct: v.correct,
                    threshold: v.chartThreshold,
                    thresholdSd: v.chartThresholdSd,
                    yAxisLabel: v.chartYAxis,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          RepaintBoundary(
            key: _outcomesChartKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                _chartCaptureHeading(context, session, 'Reaction time'),
                OutcomesChart(outcomes: v.outcomes),
              ],
            ),
          ),
          const SizedBox(height: 12),
          OutcomesTable(outcomes: v.outcomes),
        ],
      ),
    );
  }
}

Map<String, Object?> _customMap(StoredSession session) {
  return (session.summary['custom'] is Map)
      ? Map<String, Object?>.from((session.summary['custom'] as Map).cast<String, Object?>())
      : const <String, Object?>{};
}

SessionReport _sessionReportFromStored(StoredSession s) {
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

Future<Uint8List?> _repaintBoundaryToPng(GlobalKey key) async {
  final boundary = key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
  if (boundary == null) return null;
  final image = await boundary.toImage(pixelRatio: 2);
  final bd = await image.toByteData(format: ui.ImageByteFormat.png);
  return bd?.buffer.asUint8List();
}

/// Renders session charts off-screen and captures PNGs (same widgets as session detail).
Future<List<Uint8List>> _captureSessionChartPngs(
  BuildContext context,
  StoredSession session,
) async {
  final v = _deriveSessionView(session);
  final staircaseKey = GlobalKey();
  final outcomesKey = GlobalKey();

  final overlayState = Overlay.of(context, rootOverlay: true);

  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (ctx) => Positioned(
      left: -4000,
      top: 0,
      width: 560,
      child: IgnorePointer(
        child: Material(
          color: Colors.transparent,
          child: Theme(
            data: Theme.of(context),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (v.hasStaircase)
                  RepaintBoundary(
                    key: staircaseKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _chartCaptureHeading(context, session, v.staircaseLabels.sectionTitle),
                        StaircaseChart(
                          levelsHistory: v.chartLevels,
                          correct: v.correct,
                          threshold: v.chartThreshold,
                          thresholdSd: v.chartThresholdSd,
                          yAxisLabel: v.chartYAxis,
                        ),
                      ],
                    ),
                  ),
                RepaintBoundary(
                  key: outcomesKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _chartCaptureHeading(context, session, 'Reaction time'),
                      OutcomesChart(outcomes: v.outcomes),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  overlayState.insert(entry);
  await Future<void>.delayed(Duration.zero);
  await WidgetsBinding.instance.endOfFrame;
  await Future<void>.delayed(const Duration(milliseconds: 64));

  final out = <Uint8List>[];
  try {
    if (v.hasStaircase) {
      final b = await _repaintBoundaryToPng(staircaseKey);
      if (b != null) out.add(b);
    }
    final o = await _repaintBoundaryToPng(outcomesKey);
    if (o != null) out.add(o);
  } finally {
    entry.remove();
  }

  return out;
}

String _sessionToPrettyJson(StoredSession s) {
  // StoredSession is already JSON-like; just render it.
  return const JsonEncoder.withIndent('  ').convert(s.toJson());
}

List<pw.Widget> _pdfSessionMetadataOnlyWidgets(StoredSession session) {
  final v = _deriveSessionView(session);
  const cellStyle = pw.TextStyle(fontSize: 9);

  final sortedKeys = session.summary.keys.map((k) => k.toString()).toList()..sort();

  final blocks = <pw.Widget>[
    pw.Header(level: 1, text: session.startedAtIso),
    pw.Text(
      'Experiment',
      style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11),
    ),
    pw.Text(_trialDisplayTitle(session)),
    pw.SizedBox(height: 6),
    pw.Text(_sessionMetricsLine(session), style: cellStyle),
    pw.SizedBox(height: 4),
    pw.Text('finishedAt: ${session.finishedAtIso ?? '—'}', style: cellStyle),
    pw.SizedBox(height: 10),
    pw.Text(
      'Summary',
      style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11),
    ),
    for (final key in sortedKeys)
      if (key != 'custom')
        pw.Text(
          '$key: ${session.summary[key]}',
          style: cellStyle,
        ),
  ];

  if (v.hasStaircase && v.chartThreshold != null) {
    blocks.add(pw.SizedBox(height: 8));
    final sd = v.chartThresholdSd != null ? ' ± ${v.chartThresholdSd}' : '';
    blocks.add(
      pw.Text(
        'Threshold: ${v.chartThreshold} ${v.chartYAxis}$sd',
        style: cellStyle,
      ),
    );
  }

  return blocks;
}

/// One PDF page: session summary plus all chart images sharing remaining height.
pw.Widget _pdfSingleSessionSummaryAndChartsPage({
  required StoredSession session,
  required List<Uint8List> pngs,
}) {
  final meta = _pdfSessionMetadataOnlyWidgets(session);

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      ...meta,
      pw.SizedBox(height: 8),
      if (pngs.isEmpty)
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 8),
          child: pw.Text(
            'No charts captured for this session.',
            style: pw.TextStyle(fontStyle: pw.FontStyle.italic),
          ),
        )
      else
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              for (final png in pngs)
                pw.Expanded(
                  flex: 1,
                  child: pw.Padding(
                    padding: const pw.EdgeInsets.only(top: 4),
                    child: pw.Center(
                      child: pw.Image(
                        pw.MemoryImage(png),
                        fit: pw.BoxFit.contain,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
    ],
  );
}

// ── E Rotation: visual acuity metric card ────────────────────────────────────

class _ERotationAcuityCard extends StatelessWidget {
  const _ERotationAcuityCard({required this.session});

  final StoredSession session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = session.summary;

    final arcMin = s['visualAngleArcMinutes'];
    final tLogPx = s['forkThicknessLogicalPx'];
    final tMm = s['forkThicknessMm'];
    final mmPerPx = s['mmPerLogicalPixel'];
    final angleRad = s['visualAngleRadians'];
    final distMm = s['viewingDistanceMm'] ?? kDefaultViewingDistanceMm;

    final hasData = arcMin is num &&
        tLogPx is num &&
        tMm is num &&
        mmPerPx is num &&
        angleRad is num;

    final isDefaultCalibration =
        mmPerPx is num && (mmPerPx - kMacBookPro16MmPerLogicalPixel).abs() < 1e-9;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Visual acuity threshold',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            if (!hasData) ...[
              Text(
                'Acuity data not available for this session.\n'
                'Re-run the E Rotation trial to record arc-minute results.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
            ] else ...[
              _AcuityRow(
                label: 'Tine thickness',
                value:
                    '${(tLogPx as num).toStringAsFixed(2)} px'
                    '  ×  ${(mmPerPx as num).toStringAsFixed(4)} mm/px'
                    '  =  ${(tMm as num).toStringAsFixed(3)} mm',
              ),
              _AcuityRow(
                label: 'Visual angle',
                value:
                    'atan(${(tMm as num).toStringAsFixed(3)} / ${(distMm as num).toStringAsFixed(1)})'
                    '  =  ${(angleRad as num).toStringAsExponential(3)} rad',
              ),
              _AcuityRow(
                label: 'Arc minutes',
                value: '${(arcMin as num).toStringAsFixed(2)} arcmin',
                bold: true,
              ),
              const SizedBox(height: 8),
              Text(
                'Viewing distance: ${(distMm as num).toStringAsFixed(1)} mm'
                '  (${((distMm as num) / 25.4).toStringAsFixed(1)} in)'
                '    ·    ${(mmPerPx as num).toStringAsFixed(4)} mm/px'
                '${isDefaultCalibration ? '  (MacBook Pro 16" default)' : '  (calibrated)'}',
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AcuityRow extends StatelessWidget {
  const _AcuityRow({required this.label, required this.value, this.bold = false});

  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: bold ? FontWeight.w700 : FontWeight.normal,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

