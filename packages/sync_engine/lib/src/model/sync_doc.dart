import 'package:meta/meta.dart';
import 'package:note_core/note_core.dart';

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
  }) : json = Map.unmodifiable(json);

  /// entity.toJson(). Local-only and derived fields are not in it (contract 7.2.6).
  factory SyncDoc.fromEntity(SyncEntity entity) =>
      throw UnimplementedError('SYNC T2');

  final EntityKind kind;
  final String id;
  final Map<String, Object?> json;

  EntityRef get ref => throw UnimplementedError('SYNC T2');

  /// json['deletedAt'] != null
  bool get isDeleted => throw UnimplementedError('SYNC T2');

  /// json['ownerId'] for folder / note / penPreset / asset; null for other kinds.
  String? get ownerId => throw UnimplementedError('SYNC T2');

  /// json['version'] parsed; null when absent. Throws FormatException when malformed.
  Hlc? get version => throw UnimplementedError('SYNC T2');

  /// Shallow merge of top-level keys.
  SyncDoc withFields(Map<String, Object?> changes) =>
      throw UnimplementedError('SYNC T2');

  /// EntityJson.decode(kind, json). Throws FormatException (the record is skipped, 6.3.5).
  SyncEntity toEntity() => throw UnimplementedError('SYNC T2');
}
