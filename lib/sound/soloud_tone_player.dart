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
  AudioSource? _noisySource;

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

  Future<AudioSource> _ensureNoisySource() async {
    await _ensureInit();
    if (_noisySource != null) return _noisySource!;

    // flutter_soloud does not currently expose a dedicated "white noise" waveform.
    // As a practical stand-in, we use a super filtered saw with detune/scale to
    // produce a broadband, noise-like texture for gap-detection tasks.
    _noisySource = await _soloud.loadWaveform(
      WaveForm.fSaw,
      true, // superWave
      2.0, // scale
      0.18, // detune
    );
    // A high-ish base frequency yields a hiss-like sound.
    _soloud.setWaveformFreq(_noisySource!, 8000.0);
    return _noisySource!;
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

  /// Play a noise-like procedural sound with an optional mid-sound silent gap.
  ///
  /// This is useful for "gap detection" / temporal resolution tasks.
  Future<void> playNoisyWithOptionalGap({
    required double amplitude,
    required Duration totalDuration,
    Duration? gapStart,
    Duration? gapDuration,
  }) async {
    final source = await _ensureNoisySource();
    final handle = _soloud.play(source, volume: amplitude.clamp(0.0, 1.0));

    final start = gapStart;
    final dur = gapDuration;
    if (start != null && dur != null && start > Duration.zero && dur > Duration.zero) {
      unawaited(
        Future<void>.delayed(start, () async {
          _soloud.setVolume(handle, 0.0);
        }),
      );
      unawaited(
        Future<void>.delayed(start + dur, () async {
          _soloud.setVolume(handle, amplitude.clamp(0.0, 1.0));
        }),
      );
    }

    _soloud.fadeVolume(handle, 0.0, totalDuration);
    unawaited(
      Future<void>.delayed(totalDuration, () async {
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
    if (_noisySource != null) {
      await _soloud.disposeSource(_noisySource!);
      _noisySource = null;
    }
    _soloud.deinit();
    _initialized = false;
  }
}

