import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_soloud/flutter_soloud.dart';

/// Builds an [AudioSource] containing PCM white noise.
///
/// This uses SoLoud's buffer-stream API so we can feed raw PCM samples
/// (true broadband noise) rather than a tonal procedural waveform.
///
/// Notes:
/// - Callers must ensure `soloud.init()` has completed.
/// - We set [bufferingTimeNeeds] small so short (<2s) streams don't buffer forever.
AudioSource buildWhiteNoiseSource(
  SoLoud soloud, {
  required Duration duration,
  int sampleRate = 44100,
  Channels channels = Channels.mono,
  int? seed,
}) {
  final rng = seed == null ? Random() : Random(seed);
  final frames = (duration.inMilliseconds * sampleRate / 1000).round().clamp(1, 1 << 30);
  final channelCount = channels.count;
  final samples = Float32List(frames * channelCount);
  for (var i = 0; i < samples.length; i++) {
    // Uniform white noise in [-1, 1].
    samples[i] = (rng.nextDouble() * 2.0 - 1.0).toDouble();
  }

  // Float32 little-endian PCM.
  final bytes = samples.buffer.asUint8List();

  final source = soloud.setBufferStream(
    maxBufferSizeDuration: duration,
    bufferingType: BufferingType.preserved,
    bufferingTimeNeeds: 0.0,
    sampleRate: sampleRate,
    channels: channels,
    format: BufferType.f32le,
  );

  soloud.addAudioDataStream(source, bytes);
  soloud.setDataIsEnded(source);
  return source;
}

