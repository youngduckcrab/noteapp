// Internal (not exported). The convergence form of local rows and of the server's merged
// state (4.11 canonicalDump, 9.1.1): every entity as {entity JSON, field versions}, keys
// sorted at every level, Note.updatedAt left out (CORE derives it locally — 5.1.2 S-11).
import 'package:note_core/note_core.dart';

/// Dump key of one entity: `<kind>/<id>`.
String dumpKeyOf(EntityKind kind, String id) => '${kind.name}/$id';

/// One dump value: {'entity': entity.toJson() (Note without updatedAt), 'versions':
/// versions.toJson()}, keys sorted.
Map<String, Object?> dumpValueOf(
  SyncEntity entity,
  EntityFieldVersions versions,
) {
  final json = Map<String, Object?>.of(entity.toJson());
  if (entity.kind == EntityKind.note) json.remove('updatedAt');
  return {
    'entity': sortedJson(json),
    'versions': sortedJson(versions.toJson()),
  };
}

/// Dump of [rows] (soft-deleted included), keys in ascending order.
Map<String, Object?> canonicalDumpOf(Iterable<VersionedEntity> rows) {
  final entries = [
    for (final row in rows)
      MapEntry(
        dumpKeyOf(row.entity.kind, row.entity.id),
        dumpValueOf(row.entity, row.versions),
      ),
  ]..sort((a, b) => a.key.compareTo(b.key));
  return Map<String, Object?>.unmodifiable(Map.fromEntries(entries));
}

/// [value] with every map's keys in ascending order (lists keep their order).
Object? sortedJson(Object? value) => switch (value) {
  Map<Object?, Object?>() => Map<String, Object?>.unmodifiable({
    for (final k in (value.keys.map((k) => k.toString()).toList()..sort()))
      k: sortedJson(value[k]),
  }),
  List<Object?>() => List<Object?>.unmodifiable(value.map(sortedJson)),
  _ => value,
};
