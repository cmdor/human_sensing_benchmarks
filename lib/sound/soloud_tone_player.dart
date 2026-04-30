import 'dart:async';

import 'package:flutter_soloud/flutter_soloud.dart';

/// Minimal helper to play short procedural sine tones via SoLoud.
///
/// This keeps SoLoud init + waveform creation out of the UI layer.
class SoLoudTonePlayer {
  SoLoudTonePlayer._();

  static final SoLoudTonePlayer instance = SoLoudTonePlayer._();

  final SoLoud _soloud = SoLoud.instance;
  bool _initialized = false;

  AudioSource? _sineSource;

  Future<void> _ensureInit() async {
    if (_initialized) return;
    await _soloud.init();
    _initialized = true;
  }

  Future<AudioSource> _ensureSineSource() async {
    await _ensureInit();
    if (_sineSource != null) return _sineSource!;

    // Load a procedural sine waveform. We reuse a single source and just set
    // frequency before each play.
    _sineSource = await _soloud.loadWaveform(
      WaveForm.sin,
      false, // superWave
      1.0, // scale
      0.0, // detune
    );
    return _sineSource!;
  }

  /// Play a sine tone. Returns once playback has been started.
  ///
  /// Note: `duration` is enforced by fading to 0 and stopping.
  Future<void> playSine({
    required double frequencyHz,
    required double amplitude,
    required Duration duration,
  }) async {
    final source = await _ensureSineSource();
    _soloud.setWaveformFreq(source, frequencyHz);

    final handle = _soloud.play(source, volume: amplitude.clamp(0.0, 1.0));
    // Fade out and stop after duration to simulate a tone length.
    _soloud.fadeVolume(handle, 0.0, duration);
    unawaited(
      Future<void>.delayed(duration, () async {
        await _soloud.stop(handle);
      }),
    );
  }

  Future<void> dispose() async {
    if (!_initialized) return;
    if (_sineSource != null) {
      await _soloud.disposeSource(_sineSource!);
      _sineSource = null;
    }
    _soloud.deinit();
    _initialized = false;
  }
}

