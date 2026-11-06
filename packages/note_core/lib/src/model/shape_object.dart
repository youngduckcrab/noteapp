// lib/src/model/shape_object.dart — (v2.0) part of stroke.dart. 2nd-round contract 7.2.2 /
// 02-core 4.2, 4.3, 6.2.4.
part of 'stroke.dart';

final class ShapeObject extends PageObject {
  ShapeObject({
    required this.id,
    required this.pageId,
    required this.shapeKind,
    required this.geometry,
    required this.style,
    required this.createdAt,
    int? updatedAt,
    this.deletedAt,
    this.version,
  }) : updatedAt = updatedAt ?? createdAt;
  @override
  String get type => 'shape';
  final ShapeKind shapeKind; // UI meaning only; geometry is the truth
  final ShapeGeometry geometry;
  final ShapeStyle style;
  @override
  ElementFrame get frame => geometry.frame;

  /// Derived, identical on every device (K-6):
  ///   geometry.frame.bounds.inflate(style.strokeWidth * 0.75
  ///       + (arrowHeads != none && shapeKind is line|arrow ? style.arrowHeadLength : 0))
  /// (CORE 6.2.4) computed once, like Stroke.bounds.
  @override
  late final PageRect bounds = geometry.frame.bounds.inflate(
    style.strokeWidth * 0.75 +
        (style.arrowHeads != ArrowHeads.none &&
                (shapeKind == ShapeKind.line || shapeKind == ShapeKind.arrow)
            ? style.arrowHeadLength
            : 0),
  );
  ShapeObject copyWith({
    ShapeKind? shapeKind,
    ShapeGeometry? geometry,
    ShapeStyle? style,
    EpochMillis? updatedAt,
  }) => ShapeObject(
    id: id,
    pageId: pageId,
    shapeKind: shapeKind ?? this.shapeKind,
    geometry: geometry ?? this.geometry,
    style: style ?? this.style,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt,
    version: version,
  );

  // id, pageId, createdAt, updatedAt, deletedAt, version — as Stroke
  @override
  final ElementId id;
  @override
  final PageId pageId;
  @override
  final EpochMillis createdAt;
  @override
  final EpochMillis updatedAt; // constructor: updatedAt ?? createdAt (as Stroke)
  @override
  final EpochMillis? deletedAt;
  @override
  final Hlc? version;

  @override
  Set<AssetId> get referencedAssets => const {};

  /// (CORE 6.2.5) geometry.transformed(m); strokeWidth × s clamped [0.1, 30] when [scaleWidth].
  @override
  PageObject transformed(Affine2 m, {bool scaleWidth = true}) => copyWith(
    geometry: geometry.transformed(m),
    style: scaleWidth
        ? style.copyWith(
            strokeWidth: _scaled(
              style.strokeWidth,
              m,
              ShapeStyle.minWidth,
              ShapeStyle.maxWidth,
            ),
          )
        : style,
  );

  @override
  PageObject copyTo({
    required ElementId id,
    required PageId pageId,
    required EpochMillis createdAt,
  }) => ShapeObject(
    id: id,
    pageId: pageId,
    shapeKind: shapeKind,
    geometry: geometry,
    style: style,
    createdAt: createdAt,
  );

  @override
  PageObject copyWithMeta({
    EpochMillis? updatedAt,
    EpochMillis? deletedAt,
    bool clearDeletedAt = false,
    Hlc? version,
  }) => ShapeObject(
    id: id,
    pageId: pageId,
    shapeKind: shapeKind,
    geometry: geometry,
    style: style,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: clearDeletedAt ? null : deletedAt ?? this.deletedAt,
    version: version ?? this.version,
  );

  @override
  int get estimatedBytes => switch (geometry) {
    PolylineGeometry(:final points) => 160 + 16 * points.length,
    EllipseGeometry() => 160,
  };

  /// `frame` is written from the geometry and ignored on read (CORE 6.2.6).
  @override
  Map<String, Object?> toJson() => _objectJson(this, {
    'shape': shapeKind.name,
    'geometry': geometry.toJson(),
    'style': style.toJson(),
  });

  factory ShapeObject._fromJson(Map<String, Object?> json) => ShapeObject(
    id: readString(json, 'id'),
    pageId: readString(json, 'pageId'),
    shapeKind: readEnum(json, 'shape', ShapeKind.values),
    geometry: ShapeGeometry.fromJson(readMap(json, 'geometry')),
    style: ShapeStyle.fromJson(readMap(json, 'style')),
    createdAt: readInt(json, 'createdAt'),
    updatedAt: readInt(json, 'updatedAt'),
    deletedAt: readIntOrNull(json, 'deletedAt'),
    version: readVersion(json),
  );

  // CORE 4.3: ==, hashCode over every field
  @override
  bool operator ==(Object other) =>
      other is ShapeObject &&
      other.id == id &&
      other.pageId == pageId &&
      other.shapeKind == shapeKind &&
      other.geometry == geometry &&
      other.style == style &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt &&
      other.deletedAt == deletedAt &&
      other.version == version;

  @override
  int get hashCode => Object.hash(
    id,
    pageId,
    shapeKind,
    geometry,
    style,
    createdAt,
    updatedAt,
    deletedAt,
    version,
  );

  @override
  String toString() =>
      'ShapeObject($id, page: $pageId, ${shapeKind.name}'
      '${isDeleted ? ', deleted' : ''})';
}
