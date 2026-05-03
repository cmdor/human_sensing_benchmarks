// One-time screen physical-size calibration.
//
// The user drags the right edge of a rectangle until it matches a credit card
// (ISO ID-1: 85.6 mm wide) held against the screen.
// That gesture gives us:
//
//   mmPerLogicalPixel = kCreditCardWidthMm / rectangleLogicalWidth
//
// The value is stored in SharedPreferences and reused for all future sessions.
import 'package:flutter/material.dart';

import 'screen_calibration.dart';

class ScreenCalibrationPage extends StatefulWidget {
  const ScreenCalibrationPage({super.key});

  @override
  State<ScreenCalibrationPage> createState() => _ScreenCalibrationPageState();
}

class _ScreenCalibrationPageState extends State<ScreenCalibrationPage> {
  // Start the rectangle at the credit-card width as rendered on a 16" MBP
  // (fallback DPI). The user will drag to match the physical card.
  double _rectWidthLogicalPx =
      kCreditCardWidthMm / kMacBookPro16MmPerLogicalPixel;

  bool _saved = false;
  double? _savedMmPerPx;

  static const double _minWidthPx = 40.0;

  double get _derivedMmPerPx => kCreditCardWidthMm / _rectWidthLogicalPx;

  Future<void> _save() async {
    final value = _derivedMmPerPx;
    await saveMmPerLogicalPixel(value);
    setState(() {
      _saved = true;
      _savedMmPerPx = value;
    });
  }

  @override
  void initState() {
    super.initState();
    _loadExisting();
  }

  Future<void> _loadExisting() async {
    final stored = await loadMmPerLogicalPixelOrNull();
    if (stored != null && mounted) {
      setState(() {
        _rectWidthLogicalPx = kCreditCardWidthMm / stored;
        _savedMmPerPx = stored;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final equivalentDpi = 25.4 / _derivedMmPerPx;

    return Scaffold(
      appBar: AppBar(title: const Text('Calibrate Screen')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Hold a credit card (or any ISO ID-1 card) flat against '
                  'your screen. Drag the right edge of the rectangle below '
                  'until it matches the width of the card exactly.',
                  style: theme.textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Standard card width: ${kCreditCardWidthMm.toStringAsFixed(1)} mm',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: theme.colorScheme.outline),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                _DraggableRectangle(
                  widthLogicalPx: _rectWidthLogicalPx,
                  minWidthPx: _minWidthPx,
                  onWidthChanged: (w) => setState(() {
                    _rectWidthLogicalPx = w;
                    _saved = false;
                  }),
                ),
                const SizedBox(height: 24),
                Text(
                  'Current: ${_rectWidthLogicalPx.toStringAsFixed(1)} px  '
                  '→  ${_derivedMmPerPx.toStringAsFixed(4)} mm/px  '
                  '(${equivalentDpi.toStringAsFixed(1)} DPI equivalent)',
                  style: theme.textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _save,
                  child: const Text('Save calibration'),
                ),
                if (_saved && _savedMmPerPx != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Saved: ${_savedMmPerPx!.toStringAsFixed(4)} mm/px  '
                    '(${(25.4 / _savedMmPerPx!).toStringAsFixed(1)} DPI equivalent)',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 24),
                Text(
                  'Why this matters: the visual angle of the E stimulus depends '
                  'on the physical size of a pixel. Without calibration the app '
                  'falls back to a 16-inch MacBook Pro default '
                  '(${kMacBookPro16MmPerLogicalPixel.toStringAsFixed(4)} mm/px).',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DraggableRectangle extends StatelessWidget {
  const _DraggableRectangle({
    required this.widthLogicalPx,
    required this.minWidthPx,
    required this.onWidthChanged,
  });

  final double widthLogicalPx;
  final double minWidthPx;
  final ValueChanged<double> onWidthChanged;

  static const double _handleWidth = 24.0;
  static const double _rectHeight = 54.0;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primaryContainer;
    final handleColor = Theme.of(context).colorScheme.primary;

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth - _handleWidth;
        final clampedWidth = widthLogicalPx.clamp(minWidthPx, maxWidth);

        return SizedBox(
          height: _rectHeight,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // The calibration rectangle
              Positioned(
                left: 0,
                top: 0,
                width: clampedWidth,
                height: _rectHeight,
                child: Container(
                  decoration: BoxDecoration(
                    color: color,
                    border: Border.all(
                      color: handleColor,
                      width: 2,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '← ${kCreditCardWidthMm.toStringAsFixed(1)} mm →',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ),
              // Drag handle on the right edge
              Positioned(
                left: clampedWidth,
                top: 0,
                width: _handleWidth,
                height: _rectHeight,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragUpdate: (details) {
                    final newWidth =
                        (clampedWidth + details.delta.dx).clamp(minWidthPx, maxWidth);
                    onWidthChanged(newWidth);
                  },
                  child: Container(
                    color: handleColor,
                    child: const Icon(Icons.drag_indicator, color: Colors.white, size: 18),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
