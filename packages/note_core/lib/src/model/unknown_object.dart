// lib/src/model/unknown_object.dart — (v2.0) part of stroke.dart. 2nd-round contract 7.2.2
// / 02-core 4.2, 4.3, 6.2.6 (C-12).
part of 'stroke.dart';

/// What [UnknownObject.new] reads from its rawJson (02-core 6.2.6) — CORE T20a.
typedef _UnknownParts = ({
  Map<String, Object?> rawJson,
  String type,
  ElementFrame frame,
  ElementId id,
  PageId pageId,
  EpochMillis createdAt,
  EpochMillis updatedAt,
  EpochMillis? deletedAt,
  Hlc? version,
});

/// The frame drawn for an UnknownObject whose `frame` key cannot be read (7.2.2).
const ElementFrame _kUnknownFramePlaceholder = ElementFrame(
  PageRect(0, 0, 1, 1),
);

/// An AssetId: 64 lowercase hex (1차 ids.dart — the SHA-256 of the bytes).
final RegExp _assetIdPattern = RegExp(r'^[0-9a-f]{64}$');

_UnknownParts _readUnknownParts(Map<String, Object?> rawJson) {
  final copy = jsonDeepCopy(rawJson, 'rawJson')! as Map<String, Object?>;
  final frameJson = copy['frame'];
  var frame = _kUnknownFramePlaceholder;
  if (frameJson is List<Object?>) {
    try {
      frame = ElementFrame.fromJson(frameJson);
    } on FormatException {
      frame = _kUnknownFramePlaceholder;
    }
  }
  return (
    rawJson: copy,
    type: readString(copy, 'type'),
    frame: frame,
    id: readString(copy, 'id'),
    pageId: readString(copy, 'pageId'),
    createdAt: readInt(copy, 'createdAt'),
    updatedAt: readInt(copy, 'updatedAt'),
    deletedAt: readIntOrNull(copy, 'deletedAt'),
    version: readVersion(copy),
  );
}

/// Object written by a newer app (or, v2.1 CP-6, a known type with an unknown enum name). It can
/// be selected, deleted and copied as a whole and is synced unchanged; it cannot be transformed or
/// edited. JSON round-trips key-for-key (C-12).
final class UnknownObject extends PageObject {
  /// (v2.1, CP-4) rawJson must carry id, pageId, type, createdAt, updatedAt (FormatException
  /// otherwise); kept as an unmodifiable deep copy; frame / deletedAt / version read from it.
  UnknownObject(Map<String, Object?> rawJson)
    : this._parts(_readUnknownParts(rawJson));

  UnknownObject._parts(_UnknownParts p)
    : rawJson = p.rawJson,
      type = p.type,
      frame = p.frame,
      id = p.id,
      pageId = p.pageId,
      createdAt = p.createdAt,
      updatedAt = p.updatedAt,
      deletedAt = p.deletedAt,
      version = p.version;

  @override
  final String type;
  final Map<String, Object?> rawJson;

  /// From rawJson['frame'] when decodable, else ElementFrame(PageRect(0, 0, 1, 1)).
  @override
  final ElementFrame frame;
  @override
  PageRect get bounds => frame.bounds;

  /// (v2.1) A string `assetId` key in rawJson is reported (so a later asset GC keeps it).
  /// (contract: '(v2.1) A string assetId key in rawJson is reported') Top-level key 'assetId'
  /// only, and only when it is an AssetId (64 lowercase hex — 1차 ids.dart); otherwise {}.
  /// The same value goes to page_objects.asset_id (6.11) so a later asset GC keeps it (검토 S-13).
  @override
  Set<AssetId> get referencedAssets {
    final assetId = rawJson['assetId'];
    return assetId is String && _assetIdPattern.hasMatch(assetId)
        ? {assetId}
        : const {};
  }

  /// (v2.1) rawJson with the meta keys (id, pageId, createdAt, updatedAt, deletedAt, version) set
  /// to the current values; every other key as read. ==, hashCode: deep equality of toJson().
  @override
  Map<String, Object?> toJson() => {
    ...rawJson,
    'id': id,
    'pageId': pageId,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    'deletedAt': deletedAt,
    'version': version?.toString(),
  };

  // Meta values read from rawJson (02-core 6.2.6).
  @override
  final ElementId id;
  @override
  final PageId pageId;
  @override
  final EpochMillis createdAt;
  @override
  final EpochMillis updatedAt;
  @override
  final EpochMillis? deletedAt;
  @override
  final Hlc? version;

  /// Cannot be transformed: the same instance (the resolver skips it — CORE 6.2.5).
  @override
  PageObject transformed(Affine2 m, {bool scaleWidth = true}) => this;

  /// rawJson with only the meta keys changed (CORE 6.2.5).
  @override
  PageObject copyTo({
    required ElementId id,
    required PageId pageId,
    required EpochMillis createdAt,
  }) => UnknownObject({
    ...rawJson,
    'id': id,
    'pageId': pageId,
    'createdAt': createdAt,
    'updatedAt': createdAt,
    'deletedAt': null,
    'version': null,
  });

  @override
  PageObject copyWithMeta({
    EpochMillis? updatedAt,
    EpochMillis? deletedAt,
    bool clearDeletedAt = false,
    Hlc? version,
  }) => UnknownObject({
    ...toJson(),
    'updatedAt': updatedAt ?? this.updatedAt,
    'deletedAt': clearDeletedAt ? null : deletedAt ?? this.deletedAt,
    'version': (version ?? this.version)?.toString(),
  });

  /// 160 B + 2 × the UTF-16 length of jsonEncode(rawJson) (CORE 4.3).
  @override
  late final int estimatedBytes = 160 + 2 * jsonEncode(rawJson).length;

  @override
  bool operator ==(Object other) =>
      other is UnknownObject &&
      const DeepCollectionEquality().equals(other.toJson(), toJson());

  @override
  int get hashCode => const DeepCollectionEquality().hash(toJson());

  @override
  String toString() =>
      'UnknownObject($id, page: $pageId, type: $type'
      '${isDeleted ? ', deleted' : ''})';
}
