// lib/src/model/image_object.dart — (v2.0) part of stroke.dart. 2nd-round contract 7.2.2 /
// 02-core 4.2, 4.3.
part of 'stroke.dart';

final class ImageObject extends PageObject {
  ImageObject({
    required this.id,
    required this.pageId,
    required this.frame,
    required this.assetId,
    required this.pixelWidth,
    required this.pixelHeight,
    required this.createdAt,
    int? updatedAt,
    this.deletedAt,
    this.version,
  }) : updatedAt = updatedAt ?? createdAt;
  @override
  String get type => 'image';
  @override
  final ElementFrame frame; // aspect = pixel aspect unless the user unlocks it
  final AssetId assetId; // AssetType.image, mime image/jpeg | image/png (7.2.6)
  final int pixelWidth, pixelHeight; // intrinsic size of the stored bytes
  @override
  PageRect get bounds => frame.bounds;
  @override
  Set<AssetId> get referencedAssets => {assetId};
  ImageObject copyWith({ElementFrame? frame, EpochMillis? updatedAt}) =>
      notYet('T20b', 'ImageObject.copyWith');

  // CORE 4.3: same member set as ShapeObject
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
  PageObject transformed(Affine2 m, {bool scaleWidth = true}) =>
      notYet('T20b', 'ImageObject.transformed');

  @override
  PageObject copyTo({
    required ElementId id,
    required PageId pageId,
    required EpochMillis createdAt,
  }) => notYet('T20b', 'ImageObject.copyTo');

  @override
  PageObject copyWithMeta({
    EpochMillis? updatedAt,
    EpochMillis? deletedAt,
    bool clearDeletedAt = false,
    Hlc? version,
  }) => notYet('T20b', 'ImageObject.copyWithMeta');

  @override
  int get estimatedBytes => notYet('T20b', 'ImageObject.estimatedBytes');

  @override
  Map<String, Object?> toJson() => notYet('T20a', 'ImageObject.toJson');

  // CORE 4.3: ==, hashCode over every field
  @override
  bool operator ==(Object other) =>
      other is ImageObject &&
      other.id == id &&
      other.pageId == pageId &&
      other.frame == frame &&
      other.assetId == assetId &&
      other.pixelWidth == pixelWidth &&
      other.pixelHeight == pixelHeight &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt &&
      other.deletedAt == deletedAt &&
      other.version == version;

  @override
  int get hashCode => Object.hash(
    id,
    pageId,
    frame,
    assetId,
    pixelWidth,
    pixelHeight,
    createdAt,
    updatedAt,
    deletedAt,
    version,
  );

  @override
  String toString() =>
      'ImageObject($id, page: $pageId, ${pixelWidth}x$pixelHeight'
      '${isDeleted ? ', deleted' : ''})';
}
