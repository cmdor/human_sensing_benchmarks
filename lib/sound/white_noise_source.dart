import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_soloud/flutter_soloud.dart';


/// Deterministic white-noise PCM generator.
///
/// Returns interleaved f32 samples in the range [-1, 1].
Float32List buildWhiteNoisePcm({
  required Duration duration,
  int sampleRate = 44100,
  Channels channels = Channels.mono,
  required int seed,
}) {
  // Tiny deterministic PRNG (xorshift32) so we don't rely on dart:math Random
  // algorithm details for reproducibility.
  var x = seed == 0 ? 0x12345678 : seed;
  int nextU32() {
    x ^= (x << 13);
    x ^= (x >> 17);
    x ^= (x << 5);
    return x;
  }

  double nextF() => ((nextU32() & 0xFFFFFFFF) / 0xFFFFFFFF) * 2.0 - 1.0;

  final frames =
      (duration.inMilliseconds * sampleRate / 1000).round().clamp(1, 1 << 30);
  final channelCount = channels.count;
  final out = Float32List(frames * channelCount);
  for (var i = 0; i < out.length; i++) {
    out[i] = nextF().toDouble();
  }
  return out;
}

/// Returns a copy of [pcm] with a silent gap inserted.
///
/// A half-cosine ramp of [rampMs] ms is applied at both gap edges to avoid
/// the click that an instantaneous step to/from zero would produce.
///
/// Layout (time →):
///   noise | fade-out (rampMs) | silence (gapDurationMs) | fade-in (rampMs) | noise
///
/// Contract: the region \([gapStartMs, gapStartMs + gapDurationMs)\) is written
/// as **literal zeros** (full silence). The ramps happen immediately before and
/// after that interval so the ramps do not “steal” time from the silence.
Float32List withGapZeros({
  required Float32List pcm,
  int sampleRate = 44100,
  Channels channels = Channels.mono,
  required int gapStartMs,
  required int gapDurationMs,
  int rampMs = 2,
}) {
  final channelCount = channels.count;
  final totalFrames = pcm.length ~/ channelCount;
  final out = Float32List.fromList(pcm);

  int msToFramesFloor(int ms) =>
      ((ms / 1000.0) * sampleRate).floor().clamp(0, totalFrames);
  int msToFramesCeil(int ms) =>
      ((ms / 1000.0) * sampleRate).ceil().clamp(0, totalFrames);

  // Use floor for start and ceil for end so the silent region is never shorter
  // than requested due to rounding.
  final rampFrames = msToFramesCeil(rampMs);
  final gapStartFrame = msToFramesFloor(gapStartMs);
  final gapEndFrame = msToFramesCeil(gapStartMs + gapDurationMs);

  final gapStart = gapStartFrame.clamp(0, totalFrames);
  final gapEnd = gapEndFrame.clamp(gapStart, totalFrames);

  // --- fade-out ramp before the gap ---
  // Starts at gapStart - rampFrames (or 0), amplitude goes 1 → 0.
  final fadeOutStart = (gapStart - rampFrames).clamp(0, totalFrames);
  for (var f = fadeOutStart; f < gapStart; f++) {
    final denom = (gapStart - fadeOutStart).clamp(1, 1 << 30);
    final phase = (f - fadeOutStart) / denom;
    // half-cosine: 1 at phase=0, 0 at phase=1
    final gain = 0.5 * (1.0 + math.cos(math.pi * phase));
    for (var c = 0; c < channelCount; c++) {
      out[f * channelCount + c] *= gain;
    }
  }

  // --- silence in the gap ---
  for (var f = gapStart; f < gapEnd; f++) {
    for (var c = 0; c < channelCount; c++) {
      out[f * channelCount + c] = 0.0;
    }
  }

  // --- fade-in ramp after the gap ---
  // Ends at gapEnd + rampFrames (or totalFrames), amplitude goes 0 → 1.
  final fadeInEnd = (gapEnd + rampFrames).clamp(0, totalFrames);
  for (var f = gapEnd; f < fadeInEnd; f++) {
    final denom = (fadeInEnd - gapEnd).clamp(1, 1 << 30);
    final phase = (f - gapEnd) / denom;
    // half-cosine: 0 at phase=0, 1 at phase=1
    final gain = 0.5 * (1.0 - math.cos(math.pi * phase));
    for (var c = 0; c < channelCount; c++) {
      out[f * channelCount + c] *= gain;
    }
  }

  return out;
}

/// Generates a pure sine tone as interleaved f32 PCM.
///
/// A half-cosine amplitude ramp of [rampMs] ms is applied at both ends so
/// that the onset and offset are click-free regardless of where in the cycle
/// the waveform starts or stops.
Float32List buildSineTonePcm({
  required double frequencyHz,
  required Duration duration,
  int sampleRate = 44100,
  Channels channels = Channels.mono,
  int rampMs = 10,
}) {
  final frames =
      (duration.inMilliseconds * sampleRate / 1000).round().clamp(1, 1 << 30);
  final channelCount = channels.count;
  final out = Float32List(frames * channelCount);
  final rampFrames =
      ((rampMs / 1000.0) * sampleRate).ceil().clamp(0, frames ~/ 2);

  for (var f = 0; f < frames; f++) {
    final t = f / sampleRate;
    final sample = math.sin(2.0 * math.pi * frequencyHz * t);

    double gain;
    if (f < rampFrames && rampFrames > 0) {
      final phase = f / rampFrames;
      gain = 0.5 * (1.0 - math.cos(math.pi * phase));
    } else if (f >= frames - rampFrames && rampFrames > 0) {
      final phase = (f - (frames - rampFrames)) / rampFrames;
      gain = 0.5 * (1.0 + math.cos(math.pi * phase));
    } else {
      gain = 1.0;
    }

    for (var c = 0; c < channelCount; c++) {
      out[f * channelCount + c] = (sample * gain).toDouble();
    }
  }
  return out;
}

/// Builds a SoLoud buffer stream AudioSource from f32le PCM.
///
/// Notes:
/// - Callers must ensure `soloud.init()` has completed.
/// - We set [bufferingTimeNeeds] to 0 so sub-2s clips don't buffer indefinitely.
AudioSource buildPcmStreamSource(
  SoLoud soloud, {
  required Float32List pcm,
  int sampleRate = 44100,
  Channels channels = Channels.mono,
}) {
  final bytes = pcm.buffer.asUint8List();
  final durationMs =
      ((pcm.length / channels.count) / sampleRate * 1000.0).round().clamp(1, 1 << 30);
  final duration = Duration(milliseconds: durationMs);

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

