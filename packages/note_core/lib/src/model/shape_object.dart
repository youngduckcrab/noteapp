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
  @override
  PageRect get bounds => notYet('T20b', 'ShapeObject.bounds');
  ShapeObject copyWith({
    ShapeKind? shapeKind,
    ShapeGeometry? geometry,
    ShapeStyle? style,
    EpochMillis? updatedAt,
  }) => notYet('T20b', 'ShapeObject.copyWith');

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

  @override
  PageObject transformed(Affine2 m, {bool scaleWidth = true}) =>
      notYet('T20b', 'ShapeObject.transformed');

  @override
  PageObject copyTo({
    required ElementId id,
    required PageId pageId,
    required EpochMillis createdAt,
  }) => notYet('T20b', 'ShapeObject.copyTo');

  @override
  PageObject copyWithMeta({
    EpochMillis? updatedAt,
    EpochMillis? deletedAt,
    bool clearDeletedAt = false,
    Hlc? version,
  }) => notYet('T20b', 'ShapeObject.copyWithMeta');

  @override
  int get estimatedBytes => notYet('T20b', 'ShapeObject.estimatedBytes');

  @override
  Map<String, Object?> toJson() => notYet('T20a', 'ShapeObject.toJson');

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
