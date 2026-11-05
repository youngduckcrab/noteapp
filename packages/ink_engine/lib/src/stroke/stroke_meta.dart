// lib/src/stroke/stroke_meta.dart — 03-ink 4.4.
import 'package:meta/meta.dart';

/// Recording link copied into core.Stroke.recordingId / recordingOffsetMs (F-16).
/// Both null when not recording.
@immutable
final class InkStrokeMeta {
  const InkStrokeMeta({this.recordingId, this.recordingOffsetMs});
  final String? recordingId;

  /// ms from recording start to pen down (= Stroke.createdAt; point i at + t(i))
  final int? recordingOffsetMs;

  @override
  bool operator ==(Object other) =>
      other is InkStrokeMeta &&
      other.recordingId == recordingId &&
      other.recordingOffsetMs == recordingOffsetMs;

  @override
  int get hashCode => Object.hash(recordingId, recordingOffsetMs);

  @override
  String toString() => 'InkStrokeMeta($recordingId, $recordingOffsetMs)';
}
