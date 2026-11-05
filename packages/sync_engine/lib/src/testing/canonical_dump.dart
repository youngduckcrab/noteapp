// Internal (not exported). The convergence form of local rows and of the server's merged
// state (4.11 canonicalDump, 9.1.1): every entity as {entity JSON, field versions}, keys
// sorted at every level, Note.updatedAt left out (CORE derives it locally — 5.1.2 S-11).
// Field versions are compared per merge unit (6.3.3: a unit's state is decided by its max
// version), not by their base + overrides encoding: the same state can be stored as a
// winner's own versions (TakeRemote / KeepLocal) or as FieldMerge's form (smaller base,
// more overrides) — e.g. the same asset or setting created on two devices.
import 'package:note_core/note_core.dart';

import '../model/field_units.dart';
import '../model/field_versions_ext.dart';

/// Dump key of one entity: `<kind>/<id>`.
String dumpKeyOf(EntityKind kind, String id) => '${kind.name}/$id';

/// One dump value: {'entity': entity.toJson() (Note without updatedAt), 'versions':
/// [unitVersionsOf]}, keys sorted.
Map<String, Object?> dumpValueOf(
  SyncEntity entity,
  EntityFieldVersions versions,
) {
  final json = Map<String, Object?>.of(entity.toJson());
  if (entity.kind == EntityKind.note) json.remove('updatedAt');
  return {
    'entity': sortedJson(json),
    'versions': unitVersionsOf(entity, versions),
  };
}

/// Each merge unit of [entity] (6.3.1 over the kind's CORE keys, its JSON keys and the
/// overridden fields; meta keys excluded) → that unit's version (max of base and its
/// fields). Unit name = its keys sorted, joined by '+'.
Map<String, Object?> unitVersionsOf(
  SyncEntity entity,
  EntityFieldVersions versions,
) {
  final keys = {
    ...FieldUnits.keysOf(entity.kind),
    ...entity.toJson().keys,
    ...versions.overrides.keys,
  };
  return sortedJson({
        for (final unit in FieldUnits.unitsFor(entity.kind, keys))
          (unit.toList()..sort()).join('+'): versions.ofUnit(unit).toString(),
      })!
      as Map<String, Object?>;
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
