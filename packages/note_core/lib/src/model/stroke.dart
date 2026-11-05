// lib/src/model/stroke.dart (+ PageElement) — contract 00-overview 7.2.3 / CORE 4.2.2, 6.2.5.
// PageElement is sealed, so its subtypes live in this library.
import 'dart:math' as math;

import '../common/geometry.dart';
import '../common/hlc.dart';
import '../common/ids.dart';
import '../common/json_read.dart';
import 'pen_style.dart';
import 'stroke_points.dart';
import 'sync_entity.dart';

/// Things placed on a page. Only Stroke exists now; Shape, TextBox, MathObject
/// and ImageObject are added in M5/M7 (exhaustive switches will then fail to
/// compile on purpose).
sealed class PageElement implements SyncEntity {
  const PageElement();
  @override
  ElementId get id;
  PageId get pageId;
  PageRect get bounds;
  EpochMillis get createdAt;
  EpochMillis get updatedAt;
}

// CORE 4.2 approved, with the changes below
final class Stroke extends PageElement {
  Stroke({
    required this.id,
    required this.pageId,
    required this.style,
    required this.points,
    this.recordingId,
    this.recordingOffsetMs,
    required this.createdAt,
    int? updatedAt,
    this.deletedAt,
    this.version,
  }) : updatedAt = updatedAt ?? createdAt;

  /// Wall-clock ms of the first input sample (INK InkCoreServices.nowMillis at pen down).
  @override
  final EpochMillis createdAt;

  /// Derived, never serialized, identical on every device:
  ///   points.pointBounds.inflate(style.width * max(2 * points.maxWidthQ, 0.75))
  /// (0.75 covers highlighter square caps: width/2 * sqrt(2)). INK guarantees that every
  /// rendered pixel of the stroke lies inside it (7.3.2 K-1).
  @override
  late final PageRect bounds = points.pointBounds.inflate(
    style.width * math.max(2 * points.maxWidthQ, 0.75),
  );

  /// Z-order: createdAt ascending, then id ascending (later = on top).
  static int compareOrder(PageElement a, PageElement b) {
    final c = a.createdAt.compareTo(b.createdAt);
    return c != 0 ? c : a.id.compareTo(b.id);
  }

  /// Partial-eraser piece: new id; same style, createdAt, recordingId/Offset; points keep t.
  Stroke fragment({required ElementId id, required StrokePoints points}) =>
      Stroke(
        id: id,
        pageId: pageId,
        style: style,
        points: points,
        recordingId: recordingId,
        recordingOffsetMs: recordingOffsetMs,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

  /// Points transformed; if scaleWidth: width = clamp(width * m.uniformScale, 0.1, 30.0).
  Stroke transformed(Affine2 m, {bool scaleWidth = true}) => Stroke(
    id: id,
    pageId: pageId,
    style: scaleWidth
        ? style.copyWith(
            width: (style.width * m.uniformScale)
                .clamp(StrokeStyle.minWidth, StrokeStyle.maxWidth)
                .toDouble(),
          )
        : style,
    points: points.transformed(m),
    recordingId: recordingId,
    recordingOffsetMs: recordingOffsetMs,
    createdAt: createdAt,
    updatedAt: updatedAt,
    deletedAt: deletedAt,
  );

  /// `id` parameter added (paste / duplicate).
  /// The result's version is [version] (null unless given): CORE fills it when it stores
  /// the stroke (CORE 4.2.2).
  Stroke copyWith({
    ElementId? id,
    PageId? pageId,
    StrokeStyle? style,
    StrokePoints? points,
    RecordingId? recordingId,
    int? recordingOffsetMs,
    EpochMillis? createdAt,
    EpochMillis? updatedAt,
    EpochMillis? deletedAt,
    bool clearDeletedAt = false,
    Hlc? version,
  }) => Stroke(
    id: id ?? this.id,
    pageId: pageId ?? this.pageId,
    style: style ?? this.style,
    points: points ?? this.points,
    recordingId: recordingId ?? this.recordingId,
    recordingOffsetMs: recordingOffsetMs ?? this.recordingOffsetMs,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: clearDeletedAt ? null : deletedAt ?? this.deletedAt,
    version: version,
  );

  // CORE 4.2 members (unchanged):
  @override
  final ElementId id;
  @override
  final PageId pageId;
  final StrokeStyle style;
  final StrokePoints points;
  final RecordingId? recordingId;
  // ms from recording start to createdAt (point i: + t(i))
  final int? recordingOffsetMs;
  @override
  final EpochMillis updatedAt; // defaults to createdAt
  @override
  final EpochMillis? deletedAt;
  @override
  final Hlc? version;
  @override
  EntityKind get kind => EntityKind.stroke;
  @override
  bool get isDeleted => deletedAt != null;

  /// Approximate retained memory: 96 + points.length * 24 bytes.
  int get estimatedBytes => 96 + points.length * 24;

  @override
  Map<String, Object?> toJson() => {
    'id': id,
    'pageId': pageId,
    'style': style.toJson(),
    'points': StrokePointsCodec.encodeBase64(points),
    'recordingId': recordingId,
    'recordingOffsetMs': recordingOffsetMs,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    'deletedAt': deletedAt,
    'version': version?.toString(),
  };

  factory Stroke.fromJson(Map<String, Object?> json) => Stroke(
    id: readString(json, 'id'),
    pageId: readString(json, 'pageId'),
    style: StrokeStyle.fromJson(readMap(json, 'style')),
    points: StrokePointsCodec.decodeBase64(readString(json, 'points')),
    recordingId: readStringOrNull(json, 'recordingId'),
    recordingOffsetMs: readIntOrNull(json, 'recordingOffsetMs'),
    createdAt: readInt(json, 'createdAt'),
    updatedAt: readInt(json, 'updatedAt'),
    deletedAt: readIntOrNull(json, 'deletedAt'),
    version: readVersion(json),
  );

  @override
  bool operator ==(Object other) =>
      other is Stroke &&
      other.id == id &&
      other.pageId == pageId &&
      other.style == style &&
      other.points.contentEquals(points) &&
      other.recordingId == recordingId &&
      other.recordingOffsetMs == recordingOffsetMs &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt &&
      other.deletedAt == deletedAt &&
      other.version == version;

  @override
  int get hashCode => Object.hash(
    id,
    pageId,
    style,
    points,
    recordingId,
    recordingOffsetMs,
    createdAt,
    updatedAt,
    deletedAt,
    version,
  );

  @override
  String toString() =>
      'Stroke($id, page: $pageId, ${style.tool.name}, ${points.length} points'
      '${isDeleted ? ', deleted' : ''})';
}
// Removed: kDefaultPressure, StrokePoint.pressure, StrokePoints.hasPressure/pressure(i),
//          Stroke.boundsInflationPerWidth.
