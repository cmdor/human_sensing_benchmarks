//  Contrast Sensitivity: We will loosely follow the Pelli-Robson Contrast Sensitivity Test. More detailed information about the original test can be found here

// Based on this literature, build an app that displays letters with decreasing contrast, and ask the user to identify the letters until they are not legible.

// Through the process, find the user's contrast sensitivity in units of percentage. Based on this result, estimate the bit resolution. (For example, 8-bit resolution means 256 available discrete measurements, which correspond to about 4% range per color difference, meaning the smallest color difference you could discriminate is 4%.)

import 'dart:math';

import 'package:flutter/material.dart';

class Trial {
  const Trial({
    required this.letter,
    required this.contrast,
  });

  /// The letter displayed for this trial (single uppercase A–Z).
  final String letter;

  /// Contrast level in the range [0.0, 1.0].
  final double contrast;
}

// --- Simple top-level helpers (pure where possible) ---

/// Random uppercase letter A–Z.
String randomUppercaseLetter(Random random) {
  return String.fromCharCode(65 + random.nextInt(26));
}

/// Builds a [Trial] with a random letter at the given contrast (clamped to [0.0, 1.0]).
Trial randomTrial(Random random, double contrast) {
  final c = contrast.clamp(0.0, 1.0);
  return Trial(letter: randomUppercaseLetter(random), contrast: c);
}

/// First A–Z letter in [raw], uppercased; otherwise null.
String? firstUppercaseLetter(String raw) {
  for (final unit in raw.trim().toUpperCase().codeUnits) {
    if (unit >= 65 && unit <= 90) {
      return String.fromCharCode(unit);
    }
  }
  return null;
}

/// True if the user's text identifies the same letter as the trial.
bool guessEqualsTrialLetter(String rawGuess, Trial trial) {
  final g = firstUppercaseLetter(rawGuess);
  if (g == null) return false;
  return g == trial.letter;
}

/// Local time as HH:MM:SS for display.
String formatTimeOfDay(DateTime t) {
  final loc = t.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(loc.hour)}:${two(loc.minute)}:${two(loc.second)}';
}

/// Contrast after one correct answer: multiply by [stepFactor].
///
/// With 0 < [stepFactor] < 1, `log(contrast)` drops by `-log(stepFactor)` each step,
/// so steps are even in log space and contrast approaches 0 asymptotically.
double contrastAfterCorrectLogStep(
  double current, {
  double stepFactor = 0.85,
}) {
  if (current <= 0) return 0;
  return (current * stepFactor).clamp(0.0, 1.0);
}

// --- Widget ---

class ContrastFinder extends StatefulWidget {
  const ContrastFinder({super.key});

  @override
  State<ContrastFinder> createState() => _ContrastFinderState();
}

class _ContrastFinderState extends State<ContrastFinder> {
  final Random _random = Random();
  final TextEditingController _guessController = TextEditingController();
  final FocusNode _guessFocus = FocusNode();

  late Trial _currentTrial;
  bool _finished = false;
  String _status = 'Enter the letter you see, then press Enter (or Submit).';

  /// Clock time of the most recent correct guess (after submit).
  DateTime? _lastCorrectAt;

  /// Wrong answers in a row (valid letter, does not match); ends run at 2.
  int _wrongStreak = 0;

  @override
  void initState() {
    super.initState();
    _currentTrial = randomTrial(_random, 1.0);
    _refocusGuessField();
  }

  @override
  void dispose() {
    _guessFocus.dispose();
    _guessController.dispose();
    super.dispose();
  }

  /// Puts the caret in the guess field without an extra click (after frame / trial change).
  void _refocusGuessField() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _finished) return;
      _guessFocus.requestFocus();
    });
  }

  /// Read input, compare to current trial, update status and advance or end.
  void _onSubmitGuess() {
    if (_finished) return;

    final raw = _guessController.text;
    final letter = firstUppercaseLetter(raw);

    if (letter == null) {
      setState(() {
        _status = 'Please enter a letter (A–Z).';
      });
      _refocusGuessField();
      return;
    }

    final wasCorrect = guessEqualsTrialLetter(raw, _currentTrial);

    setState(() {
      if (!wasCorrect) {
        _wrongStreak += 1;
        if (_wrongStreak >= 2) {
          _finished = true;
          _status =
              'Wrong again (2 in a row). You entered "$letter"; displayed was "${_currentTrial.letter}". Run finished.';
          return;
        }

        _status =
            'Wrong (1/2). You entered "$letter"; displayed was "${_currentTrial.letter}". One more wrong ends the run.';
        _guessController.clear();
        _currentTrial = randomTrial(_random, _currentTrial.contrast);
        return;
      }

      _wrongStreak = 0;
      _lastCorrectAt = DateTime.now();
      _status =
          'Correct at ${formatTimeOfDay(_lastCorrectAt!)}. Advancing to lower contrast.';
      _guessController.clear();

      final nextContrast =
          contrastAfterCorrectLogStep(_currentTrial.contrast, stepFactor: 0.85);
      _currentTrial = randomTrial(_random, nextContrast);
    });
    if (!_finished) {
      _refocusGuessField();
    }
  }

  void _restart() {
    setState(() {
      _finished = false;
      _wrongStreak = 0;
      _lastCorrectAt = null;
      _guessController.clear();
      _currentTrial = randomTrial(_random, 1.0);
      _status = 'Enter the letter you see, then press Enter (or Submit).';
    });
    _refocusGuessField();
  }

  @override
  Widget build(BuildContext context) {
    final bg = Theme.of(context).colorScheme.surface;
    final fg = Theme.of(context).colorScheme.onSurface;
    final letterColor = Color.lerp(bg, fg, _currentTrial.contrast) ?? fg;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Contrast Finder'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _currentTrial.letter,
                  style: TextStyle(
                    fontSize: 96,
                    fontWeight: FontWeight.w700,
                    color: letterColor,
                  ),
                ),
                const SizedBox(height: 16),
                Text('Contrast: ${_currentTrial.contrast.toStringAsFixed(2)}'),
                if (_lastCorrectAt != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Last correct: ${formatTimeOfDay(_lastCorrectAt!)}',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ],
                const SizedBox(height: 20),
                TextField(
                  controller: _guessController,
                  focusNode: _guessFocus,
                  autofocus: true,
                  enabled: !_finished,
                  textCapitalization: TextCapitalization.characters,
                  textInputAction: TextInputAction.done,
                  maxLength: 8,
                  decoration: const InputDecoration(
                    labelText: 'Your guess',
                    helperText: 'Press Enter to submit',
                    border: OutlineInputBorder(),
                    counterText: '',
                  ),
                  onSubmitted: (_) => _onSubmitGuess(),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _finished ? null : _onSubmitGuess,
                  child: const Text('Submit'),
                ),
                const SizedBox(height: 20),
                Text(
                  _status,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                if (_finished) ...[
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: _restart,
                    child: const Text('Restart'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
