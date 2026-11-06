// lib/src/render/playback_index.dart — INTERNAL (m5-7/03-ink 6.19, T40).
//
// The playback index: for every recording id, the strokes linked to it
// (source.recordingId == id and source.recordingOffsetMs set) as entries
// (stroke, offset = recordingOffsetMs, tLast = the last point's t) in offset
// order (equal offsets: content z order). A content change regroups the strokes
// (O(n)) and drops only the tracks whose stroke list changed; a track is built
// when it is first asked for (O(m log m) for that recording).
//
// R-4 at the audio position p (ms) and the recent window W:
//   written    offset + tLast ≤ p
//   writing    offset ≤ p < offset + tLast   (the points with offset + t(i) > p
//                                             are still to be written)
//   unwritten  offset > p
//   recent     p − W < offset ≤ p            (on top of written / writing)
// Strokes of other recordings and strokes without one are not in the track.
import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../model/ink_stroke.dart';
import 'ink_page_content.dart';

/// R-4 state of one track entry at a position.
enum PlaybackState { written, writing, unwritten }

/// One stroke of a recording.
@immutable
final class PlaybackEntry {
  const PlaybackEntry(this.stroke, this.offsetMs, this.durationMs);

  final InkStroke stroke;

  /// source.recordingOffsetMs — the audio time of Stroke.createdAt.
  final int offsetMs;

  /// The last point's t (ms since createdAt) — 0 for a one-point stroke.
  final double durationMs;

  /// The audio time of the last point.
  double get endMs => offsetMs + durationMs;
}

/// The entries of one recording, offset order.
final class PlaybackTrack {
  PlaybackTrack._(this.recordingId, this.entries, this._offsets, this._maxMs);

  /// Builds the track from [zOrdered] (the recording's strokes in content z order).
  factory PlaybackTrack.build(String recordingId, List<InkStroke> zOrdered) {
    final order = List<int>.generate(zOrdered.length, (i) => i);
    int offsetOf(int i) => zOrdered[i].source.recordingOffsetMs ?? 0;
    order.sort((a, b) {
      final c = offsetOf(a).compareTo(offsetOf(b));
      return c != 0 ? c : a.compareTo(b);
    });
    final entries = <PlaybackEntry>[];
    final offsets = Int64List(order.length);
    var maxMs = 0.0;
    for (var k = 0; k < order.length; k++) {
      final s = zOrdered[order[k]];
      final points = s.points;
      final last = points.length == 0 ? 0.0 : points.t(points.length - 1);
      final duration = last.isFinite && last > 0 ? last : 0.0;
      if (duration > maxMs) maxMs = duration;
      offsets[k] = offsetOf(order[k]);
      entries.add(PlaybackEntry(s, offsets[k], duration));
    }
    return PlaybackTrack._(
      recordingId,
      List.unmodifiable(entries),
      offsets,
      maxMs,
    );
  }

  final String recordingId;

  /// Offset order (ties: z order). Unmodifiable.
  final List<PlaybackEntry> entries;
  final Int64List _offsets;
  final double _maxMs;

  int get length => entries.length;

  /// The longest tLast of the track (bounds the writing scan).
  double get maxDurationMs => _maxMs;

  /// The first index whose offset is greater than [ms] (binary search).
  int upperBound(num ms) {
    var lo = 0, hi = _offsets.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_offsets[mid] <= ms) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  /// The boundary k at [positionMs]: the first unwritten entry (entries ≥ k are
  /// unwritten, entries < k are written or writing).
  int boundary(int positionMs) => upperBound(positionMs);

  /// The recent entries [start, end): positionMs − windowMs < offset ≤ positionMs.
  (int, int) recentRange(int positionMs, int windowMs) =>
      (upperBound(positionMs - windowMs), upperBound(positionMs));

  /// The writing entries (offset ≤ p < offset + tLast), ascending. Scans back from the
  /// boundary while an entry could still be writing (offset + maxDurationMs > p).
  List<int> writing(int positionMs) {
    final out = <int>[];
    for (var i = boundary(positionMs) - 1; i >= 0; i--) {
      if (_offsets[i] + _maxMs <= positionMs) break;
      if (entries[i].endMs > positionMs) out.add(i);
    }
    return out.reversed.toList(growable: false);
  }

  PlaybackState stateAt(int i, int positionMs) {
    final e = entries[i];
    if (e.offsetMs > positionMs) return PlaybackState.unwritten;
    return e.endMs > positionMs ? PlaybackState.writing : PlaybackState.written;
  }

  bool isRecent(int i, int positionMs, int windowMs) {
    final o = entries[i].offsetMs;
    return o <= positionMs && o > positionMs - windowMs;
  }

  /// The first point of entry [i] still to be written at [positionMs]
  /// (offset + t(j) > p); the point count when every point is written.
  int firstUnwrittenPoint(int i, int positionMs) {
    final e = entries[i];
    final points = e.stroke.points;
    final local = positionMs - e.offsetMs;
    var lo = 0, hi = points.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (points.t(mid) <= local) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }
}

/// The tracks of one page's content.
final class PlaybackIndex {
  InkPageContent? _content;
  Map<String, List<InkStroke>> _groups = const {};
  final Map<String, PlaybackTrack> _tracks = {};
  final Map<String, int> _builds = {};

  /// (tests) How many times the track of [recordingId] was built.
  int buildsOf(String recordingId) => _builds[recordingId] ?? 0;

  /// The recording ids with at least one linked stroke.
  Iterable<String> get recordingIds => _groups.keys;

  /// Regroups [content]'s strokes; keeps the tracks whose stroke list is the same
  /// instances in the same order.
  void update(InkPageContent? content) {
    if (identical(content, _content)) return;
    _content = content;
    final groups = <String, List<InkStroke>>{};
    if (content != null) {
      for (final s in content.strokes) {
        final id = s.source.recordingId;
        if (id == null || s.source.recordingOffsetMs == null) continue;
        (groups[id] ??= []).add(s);
      }
    }
    _tracks.removeWhere((id, _) {
      final before = _groups[id];
      final now = groups[id];
      return before == null || now == null || !_sameList(before, now);
    });
    _groups = groups;
  }

  /// The track of [recordingId], built on first use; null when no stroke links to it.
  PlaybackTrack? trackOf(String recordingId) {
    final hit = _tracks[recordingId];
    if (hit != null) return hit;
    final group = _groups[recordingId];
    if (group == null) return null;
    _builds[recordingId] = buildsOf(recordingId) + 1;
    return _tracks[recordingId] = PlaybackTrack.build(recordingId, group);
  }

  static bool _sameList(List<InkStroke> a, List<InkStroke> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!identical(a[i].source, b[i].source)) return false;
    }
    return true;
  }
}
