import 'dart:async';
import 'dart:math';

import 'package:flutter_soloud/flutter_soloud.dart';
import 'gap_player.dart';
import 'white_noise_source.dart';

/// Minimal helper to play short procedural sine tones via SoLoud.
///
/// This keeps SoLoud init + waveform creation out of the UI layer.
class SoLoudTonePlayer {
  SoLoudTonePlayer._();

  static final SoLoudTonePlayer instance = SoLoudTonePlayer._();
  static final Random _rng = Random();

  final SoLoud _soloud = SoLoud.instance;
  bool _initialized = false;

  AudioSource? _sineSource;
  AudioSource? _noisySource;
  AudioSource? _whiteNoiseSource;
  Duration? _whiteNoiseDuration;

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
    // As a practical stand-in, we use a harsh super square with heavy detune/scale.
    // We also randomize the base frequency per play to avoid a stable pitch.
    _noisySource = await _soloud.loadWaveform(
      WaveForm.square,
      true, // superWave
      8.0, // scale
      0.65, // detune
    );
    return _noisySource!;
  }

  Future<AudioSource> _ensureWhiteNoiseSource(Duration duration) async {
    await _ensureInit();
    if (_whiteNoiseSource != null && _whiteNoiseDuration == duration) {
      return _whiteNoiseSource!;
    }
    if (_whiteNoiseSource != null) {
      await _soloud.disposeSource(_whiteNoiseSource!);
      _whiteNoiseSource = null;
      _whiteNoiseDuration = null;
    }
    _whiteNoiseSource = buildWhiteNoiseSource(
      _soloud,
      duration: duration,
      sampleRate: 44100,
      channels: Channels.mono,
    );
    _whiteNoiseDuration = duration;
    return _whiteNoiseSource!;
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
    double? baseHz,
    Duration? gapStart,
    Duration? gapDuration,
  }) async {
    final source = await _ensureNoisySource();
    await playNoiseWithGap(
      _soloud,
      source,
      amplitude: amplitude,
      totalDurationMs: totalDuration.inMilliseconds,
      baseHz: baseHz ?? (3000.0 + _rng.nextDouble() * 12000.0),
      gapStartMs: gapStart?.inMilliseconds,
      gapDurationMs: gapDuration?.inMilliseconds,
    );
  }

  /// Play true PCM white noise with an optional mid-sound silent gap.
  Future<void> playWhiteNoiseWithOptionalGap({
    required double amplitude,
    required Duration totalDuration,
    Duration? gapStart,
    Duration? gapDuration,
  }) async {
    final source = await _ensureWhiteNoiseSource(totalDuration);
    await playNoiseWithGap(
      _soloud,
      source,
      amplitude: amplitude,
      totalDurationMs: totalDuration.inMilliseconds,
      baseHz: null,
      gapStartMs: gapStart?.inMilliseconds,
      gapDurationMs: gapDuration?.inMilliseconds,
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
    if (_whiteNoiseSource != null) {
      await _soloud.disposeSource(_whiteNoiseSource!);
      _whiteNoiseSource = null;
      _whiteNoiseDuration = null;
    }
    _soloud.deinit();
    _initialized = false;
  }
}

