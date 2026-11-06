// lib/src/render/playback.dart — contract 7.2.9 (m5-7/03-ink 4.3). Value types final (T24);
// foundation step R2-B3 keeps the focus as state only (no drawing — T40).
import 'package:meta/meta.dart';

@immutable
final class InkPlaybackFocus {
  const InkPlaybackFocus({
    required this.recordingId,
    required this.positionMs,
    this.style = InkPlaybackStyle.dimUnwritten,
    this.recentWindowMs = 2000,
  });
  final String recordingId;

  /// audio timeline, same scale as Stroke.recordingOffsetMs
  final int positionMs;
  final InkPlaybackStyle style;

  /// Strokes that started in (positionMs − recentWindowMs, positionMs] get the emphasis outline
  /// (both styles). dimUnwritten also draws unwritten ink-layer strokes at
  /// InkTuning.playbackDimOpacity ((v2.1, CP-INK-8) highlighter / tape strokes are not dimmed —
  /// emphasis outline only). Drawn in layer 4′, never over annotation / cover (K-9).
  /// Strokes of other recordings / without a recording: unchanged.
  final int recentWindowMs;

  @override
  bool operator ==(Object other) =>
      other is InkPlaybackFocus &&
      other.recordingId == recordingId &&
      other.positionMs == positionMs &&
      other.style == style &&
      other.recentWindowMs == recentWindowMs;

  @override
  int get hashCode =>
      Object.hash(recordingId, positionMs, style, recentWindowMs);

  @override
  String toString() =>
      'InkPlaybackFocus($recordingId @ $positionMs ms, ${style.name}, '
      'window $recentWindowMs ms)';
}

enum InkPlaybackStyle { dimUnwritten, highlightRecent }

/// INTERNAL: the drawing side's normalized copy (03-ink 4.10): positionMs < 0 → 0,
/// recentWindowMs clamped to [0, 60000]. The controller's getter keeps the value as set.
@internal
InkPlaybackFocus normalizedPlaybackFocus(InkPlaybackFocus f) {
  final position = f.positionMs < 0 ? 0 : f.positionMs;
  final window = f.recentWindowMs < 0
      ? 0
      : (f.recentWindowMs > 60000 ? 60000 : f.recentWindowMs);
  if (position == f.positionMs && window == f.recentWindowMs) return f;
  return InkPlaybackFocus(
    recordingId: f.recordingId,
    positionMs: position,
    style: f.style,
    recentWindowMs: window,
  );
}
