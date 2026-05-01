import 'dart:async';

import 'package:flutter_soloud/flutter_soloud.dart';

/// Plays broadband noise with an optional mid-sound silent gap.
///
/// ## Timing strategy
///
/// The gap boundary events are dispatched at two precision levels:
///
/// - **Gap start** and **stop** use [SoLoud.schedulePause] and
///   [SoLoud.scheduleStop], which are inserted into SoLoud's C++ fader queue
///   and fire inside the miniaudio render callback — sample-accurate,
///   independent of the Dart/JS event loop.
///
/// - **Gap end** (unpause) uses a single [Timer], giving one timer's worth
///   of JS-scheduler jitter (~4–16 ms on web) but no accumulated drift,
///   because it is not chained from a prior timer.
///
/// ## Stream-time caveat
///
/// [SoLoud.scheduleStop] counts **stream time**, which freezes while a voice
/// is paused.  To stop at the correct wall-clock time, we pass
/// `totalDuration - gapDuration` so that after the voice is unpaused, stream
/// time only needs to advance the remaining audible portion.
///
/// Parameters:
///   [soloud]         - initialized SoLoud instance
///   [source]         - waveform AudioSource (already loaded)
///   [amplitude]      - playback volume 0.0..1.0
///   [totalDurationMs]- total wall-clock length of the sound in milliseconds
///   [baseHz]         - base oscillator frequency (determines static texture)
///   [gapStartMs]     - ms from t=0 at which silence begins (null = no gap)
///   [gapDurationMs]  - length of silence in ms (null = no gap)
Future<void> playNoiseWithGap(
  SoLoud soloud,
  AudioSource source, {
  required double amplitude,
  required int totalDurationMs,
  required double baseHz,
  int? gapStartMs,
  int? gapDurationMs,
}) async {
  soloud.setWaveformFreq(source, baseHz);
  final vol = amplitude.clamp(0.0, 1.0);

  // t=0: start playback.
  final handle = soloud.play(source, volume: vol);

  final hasGap =
      gapStartMs != null && gapDurationMs != null && gapDurationMs > 0;

  if (hasGap) {
    // --- Gap path ---
    //
    // schedulePause fires at stream time gapStartMs: audio-thread accurate.
    soloud.schedulePause(handle, Duration(milliseconds: gapStartMs!));

    // scheduleStop counts stream time (pauses while voice is paused).
    // Pass totalDurationMs - gapDurationMs so that after the unpause, stream
    // time only needs to advance the remaining audible portion, making the
    // wall-clock stop land at totalDurationMs.
    final audibleDuration = (totalDurationMs - gapDurationMs!).clamp(1, totalDurationMs);
    soloud.scheduleStop(handle, Duration(milliseconds: audibleDuration));

    // Unpause after the gap using a single Dart Timer (no accumulated drift).
    Timer(Duration(milliseconds: gapStartMs + gapDurationMs), () {
      if (soloud.getIsValidVoiceHandle(handle)) {
        soloud.setPause(handle, false);
      }
    });
  } else {
    // --- No-gap path ---
    //
    // scheduleStop fires at stream time totalDurationMs: audio-thread accurate.
    soloud.scheduleStop(handle, Duration(milliseconds: totalDurationMs));
  }
}
