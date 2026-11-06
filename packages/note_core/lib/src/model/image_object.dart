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
      ImageObject(
        id: id,
        pageId: pageId,
        frame: frame ?? this.frame,
        assetId: assetId,
        pixelWidth: pixelWidth,
        pixelHeight: pixelHeight,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        deletedAt: deletedAt,
        version: version,
      );

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

  /// (CORE 6.2.5) frame only.
  @override
  PageObject transformed(Affine2 m, {bool scaleWidth = true}) =>
      copyWith(frame: frame.transformed(m));

  @override
  PageObject copyTo({
    required ElementId id,
    required PageId pageId,
    required EpochMillis createdAt,
  }) => ImageObject(
    id: id,
    pageId: pageId,
    frame: frame,
    assetId: assetId,
    pixelWidth: pixelWidth,
    pixelHeight: pixelHeight,
    createdAt: createdAt,
  );

  @override
  PageObject copyWithMeta({
    EpochMillis? updatedAt,
    EpochMillis? deletedAt,
    bool clearDeletedAt = false,
    Hlc? version,
  }) => ImageObject(
    id: id,
    pageId: pageId,
    frame: frame,
    assetId: assetId,
    pixelWidth: pixelWidth,
    pixelHeight: pixelHeight,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: clearDeletedAt ? null : deletedAt ?? this.deletedAt,
    version: version ?? this.version,
  );

  /// The image bytes are an asset, not history (CORE 6.4.4).
  @override
  int get estimatedBytes => 160;

  @override
  Map<String, Object?> toJson() => _objectJson(this, {
    'assetId': assetId,
    'px': [pixelWidth, pixelHeight],
  });

  factory ImageObject._fromJson(Map<String, Object?> json) {
    final px = readList(json, 'px');
    if (px.length != 2) {
      throw FormatException('JSON key "px": expected [w, h], got $px');
    }
    return ImageObject(
      id: readString(json, 'id'),
      pageId: readString(json, 'pageId'),
      frame: _readFrame(json),
      assetId: readString(json, 'assetId'),
      pixelWidth: asInt(px[0], 'px'),
      pixelHeight: asInt(px[1], 'px'),
      createdAt: readInt(json, 'createdAt'),
      updatedAt: readInt(json, 'updatedAt'),
      deletedAt: readIntOrNull(json, 'deletedAt'),
      version: readVersion(json),
    );
  }

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
