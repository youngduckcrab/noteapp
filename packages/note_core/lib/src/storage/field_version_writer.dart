// lib/src/storage/field_version_writer.dart (internal) — CORE 6.10.2 local stamping.
import '../common/hlc.dart';
import '../sync/field_versions.dart';
import '../sync/outbox_types.dart';

/// Field versions after a local write of [fields] (synced JSON keys) at [stamp]:
/// `*` (or no current row) → EntityFieldVersions(stamp) (column NULL); otherwise the
/// current base with [fields] overridden by [stamp]. Either way max == [stamp].
EntityFieldVersions localVersionsAfter(
  EntityFieldVersions? current,
  Set<String> fields,
  Hlc stamp,
) {
  if (current == null || fields.contains(kAllFields)) {
    return EntityFieldVersions(stamp);
  }
  return EntityFieldVersions(current.base, {
    for (final e in current.overrides.entries)
      if (e.value > current.base) e.key: e.value,
    for (final f in fields) f: stamp,
  });
}
