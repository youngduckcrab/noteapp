import 'package:collection/collection.dart';
import 'package:meta/meta.dart';
import 'package:note_core/note_core.dart';

const DeepCollectionEquality _deepEq = DeepCollectionEquality();

/// JSON view of one entity in CORE's sync/backup wire format (CORE 6.3, contract 7.4.6).
/// Merge and codec work on this map form; the local boundary uses CORE SyncEntity (D10).
@immutable
final class SyncDoc {
  /// [json] is deep-copied and made unmodifiable. json['id'] (setting: json['key']) must
  /// equal [id].
  SyncDoc({
    required this.kind,
    required this.id,
    required Map<String, Object?> json,
  }) : json = _freezeMap(json) {
    final key = kind == EntityKind.setting ? 'key' : 'id';
    if (this.json[key] != id) {
      throw ArgumentError.value(
        this.json[key],
        'json[$key]',
        'must equal the id "$id"',
      );
    }
  }

  /// entity.toJson(). Local-only and derived fields are not in it (contract 7.2.6).
  factory SyncDoc.fromEntity(SyncEntity entity) =>
      SyncDoc(kind: entity.kind, id: entity.id, json: entity.toJson());

  final EntityKind kind;
  final String id;
  final Map<String, Object?> json;

  EntityRef get ref => EntityRef(kind, id);

  /// json['deletedAt'] != null
  bool get isDeleted => json['deletedAt'] != null;

  /// json['ownerId'] for folder / note / penPreset / asset; null for other kinds.
  String? get ownerId => switch (kind) {
    EntityKind.folder ||
    EntityKind.note ||
    EntityKind.penPreset ||
    EntityKind.asset => switch (json['ownerId']) {
      final String owner => owner,
      _ => null,
    },
    _ => null,
  };

  /// json['version'] parsed; null when absent. Throws FormatException when malformed.
  Hlc? get version => switch (json['version']) {
    null => null,
    final String text => Hlc.parse(text),
    final other => throw FormatException('version: HLC text expected', other),
  };

  /// Shallow merge of top-level keys.
  SyncDoc withFields(Map<String, Object?> changes) =>
      SyncDoc(kind: kind, id: id, json: {...json, ...changes});

  /// EntityJson.decode(kind, json). Throws FormatException (the record is skipped, 6.3.5).
  SyncEntity toEntity() {
    final SyncEntity entity;
    try {
      entity = EntityJson.decode(kind, json);
    } on FormatException {
      rethrow;
    } on Object catch (e) {
      // A wrong JSON type can surface as TypeError / ArgumentError inside fromJson.
      throw FormatException('${kind.name} $id: $e');
    }
    if (entity.id != id) {
      throw FormatException('${kind.name}: decoded id ${entity.id} != $id');
    }
    return entity;
  }

  @override
  bool operator ==(Object other) =>
      other is SyncDoc &&
      other.kind == kind &&
      other.id == id &&
      _deepEq.equals(other.json, json);

  @override
  int get hashCode => Object.hash(kind, id, _deepEq.hash(json));

  @override
  String toString() => 'SyncDoc(${kind.name} $id)';
}

Map<String, Object?> _freezeMap(Map<Object?, Object?> map) {
  final out = <String, Object?>{};
  for (final e in map.entries) {
    final key = e.key;
    if (key is! String) {
      throw ArgumentError.value(key, 'json key', 'must be a String');
    }
    out[key] = _freeze(e.value);
  }
  return Map<String, Object?>.unmodifiable(out);
}

Object? _freeze(Object? value) => switch (value) {
  final Map<Object?, Object?> m => _freezeMap(m),
  final List<Object?> l => List<Object?>.unmodifiable(l.map(_freeze)),
  _ => value,
};
