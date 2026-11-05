// lib/src/storage/entity_diff.dart (internal) — changed fields of a local write
// (CORE 6.7.6, 6.10.1: the outbox lists the JSON keys that really differ).
import 'package:collection/collection.dart';

import '../model/sync_entity.dart';

const DeepCollectionEquality _deep = DeepCollectionEquality();

/// JSON keys (6.3 wire names) whose values differ between [before] and [after].
/// Meta keys (updatedAt, version, ...) are filtered later by the write path.
Set<String> changedJsonKeys(SyncEntity before, SyncEntity after) {
  final a = before.toJson();
  final b = after.toJson();
  return {
    for (final k in {...a.keys, ...b.keys})
      if (!_deep.equals(a[k], b[k])) k,
  };
}
