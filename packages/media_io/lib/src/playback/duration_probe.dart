// lib/src/playback/duration_probe.dart — (v2.1) the native recording length from the decoder
// (m5-7/06-pdf 6.6.4): a separate player (not the playback service's — a stop never cuts the
// user's playback) opens the file (already on disk — no memory copy) and reports its length,
// then is disposed. `record` writes the moov, so the decoder length is the file timeline. At most
// MediaTuning.durationProbeTimeout; a null / zero / unbounded length is null (the caller uses the
// clock and the developer overlay says 'duration from clock'). The web never probes (6.6.4 — the
// length comes from WebmTimeline / Mp4Duration). Internal.
import 'dart:async';

import '../tuning.dart';
import 'player_port.dart';

/// The length of the audio file at [path] in ms, or null.
Future<int?> probeDurationMs(
  String path, {
  PlayerPort Function()? player,
  Duration timeout = MediaTuning.durationProbeTimeout,
}) async {
  final port = (player ?? JustAudioPlayerPort.new)();
  try {
    final length = await port
        .load(PlayerFileSource(path))
        .timeout(timeout, onTimeout: () => null);
    final ms = length?.inMilliseconds;
    // Duration has no infinity; a length a player reports for 'unbounded' is past a day.
    if (ms == null || ms <= 0 || ms > const Duration(days: 1).inMilliseconds) {
      return null;
    }
    return ms;
  } on PlayerFailure {
    return null;
  } finally {
    unawaited(port.dispose().catchError((Object _) {}));
  }
}
