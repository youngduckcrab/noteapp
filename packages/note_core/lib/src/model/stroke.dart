// lib/src/model/stroke.dart (+ PageElement) — contract 00-overview 7.2.3 / CORE 4.2.2, 6.2.5.
// PageElement is sealed, so its subtypes live in this library: (v2.0, 2nd-round contract
// 7.2.2) the new subtypes are `part` files of this library (page_object.dart,
// shape_object.dart, …). A part file cannot import, so their imports are here.
import 'dart:convert';
import 'dart:math' as math;

import 'package:collection/collection.dart';

import '../common/geometry.dart';
import '../common/hlc.dart';
import '../common/ids.dart';
import '../common/json_read.dart';
import 'object_rules.dart';
import 'object_styles.dart';
import 'pen_style.dart';
import 'shape_geometry.dart';
import 'stroke_points.dart';
import 'sync_entity.dart';

part 'page_object.dart';
part 'shape_object.dart';
part 'text_box_object.dart';
part 'image_object.dart';
part 'math_object.dart';
part 'unknown_object.dart';

/// Things placed on a page: Stroke and (v2.0) PageObject — ShapeObject, TextBoxObject,
/// ImageObject, MathObject, UnknownObject (2nd-round contract 7.2.2). Exhaustive
/// switches over it are CORE-internal only (7.0.1 C2-03).
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
  /// (v2.1, C2-38 — m5-7/02-core 6.2.7) A calligraphy stroke's nib angle turns with m.
  Stroke transformed(Affine2 m, {bool scaleWidth = true}) => Stroke(
    id: id,
    pageId: pageId,
    style: _turnNib(
      scaleWidth
          ? style.copyWith(
              width: (style.width * m.uniformScale)
                  .clamp(StrokeStyle.minWidth, StrokeStyle.maxWidth)
                  .toDouble(),
            )
          : style,
      m,
    ),
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

/// (C2-38, CORE 6.2.7) r = fold(deg(m.rotation)), fold(a) = a − 180·⌊a / 180⌋ ∈ [0, 180). r == 0
/// (a move / scale, or a half turn) leaves extras as they are (no key is written); otherwise
/// extras['nibAngleDeg'] = fold(old + r), old = the stored number or 45. A rotation within
/// 1e-9° of 0 or 180 (floating error of Affine2.rotation(pi)) counts as 0.
StrokeStyle _turnNib(StrokeStyle style, Affine2 m) {
  if (style.tool != PenTool.calligraphy) return style;
  final r = _foldDegrees(m.rotation * 180 / math.pi);
  if (r < 1e-9 || 180 - r < 1e-9) return style;
  final old = style.extras[kCalligraphyNibAngleKey];
  final from = old is num && old.isFinite
      ? old.toDouble()
      : kDefaultCalligraphyNibAngleDeg;
  return style.copyWith(
    extras: Map.unmodifiable({
      ...style.extras,
      kCalligraphyNibAngleKey: _foldDegrees(from + r),
    }),
  );
}

double _foldDegrees(double a) => a - 180 * (a / 180).floorToDouble();

// Removed: kDefaultPressure, StrokePoint.pressure, StrokePoints.hasPressure/pressure(i),
//          Stroke.boundsInflationPerWidth.
