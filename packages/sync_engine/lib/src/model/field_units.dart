import 'package:note_core/note_core.dart';

/// Merge units (6.3.1). Keys not listed in a group form their own unit.
abstract final class FieldUnits {
  /// Never merged by LWW: identity and derived values (CORE never puts them in
  /// changedFields — CORE 6.3).
  static const Set<String> metaKeys = {
    'id',
    'key',
    'version',
    'createdAt',
    'updatedAt',
  };

  static const Set<String> _trash = {'deletedAt', 'trashRootId'};

  /// The JSON keys of each kind (CORE 6.3 key table, meta keys included). The
  /// merge treats every one of them as a unit even when a snapshot lacks it
  /// (an absent key carries the snapshot's base version), which keeps the merge
  /// associative across older writers.
  static Set<String> keysOf(EntityKind kind) => switch (kind) {
    EntityKind.folder => const {
      'id', 'ownerId', 'parentId', 'name', 'color', 'icon', 'sortKey', //
      'createdAt', 'updatedAt', 'deletedAt', 'trashRootId', 'version',
    },
    EntityKind.note => const {
      'id', 'ownerId', 'folderId', 'title', 'cover', 'tags', 'isFavorite', //
      'sortKey', 'schemaVersion', 'createdAt', 'updatedAt', 'deletedAt',
      'trashRootId', 'version',
    },
    EntityKind.page => const {
      'id', 'noteId', 'sortKey', 'size', 'background', 'createdAt', //
      'updatedAt', 'deletedAt', 'version',
    },
    EntityKind.stroke => const {
      'id', 'pageId', 'style', 'points', 'recordingId', 'recordingOffsetMs', //
      'createdAt', 'updatedAt', 'deletedAt', 'version',
    },
    EntityKind.penPreset => const {
      'id', 'ownerId', 'name', 'style', 'group', 'pinned', 'sortKey', //
      'createdAt', 'updatedAt', 'deletedAt', 'version',
    },
    EntityKind.asset => const {
      'id', 'ownerId', 'type', 'mimeType', 'size', 'fileName', 'storagePath', //
      'createdAt', 'deletedAt', 'version',
    },
    EntityKind.recording => const {
      'id', 'noteId', 'assetId', 'durationMs', 'startedAt', 'title', //
      'createdAt', 'updatedAt', 'deletedAt', 'version',
    },
    EntityKind.setting => const {
      'key', 'valueJson', 'updatedAt', 'deletedAt', 'version', //
    },
    // (2nd round, contract 7.2.8) the union of the four known object types (07-sync
    // 6.2.1); the keys of each type are a subset of it.
    EntityKind.pageObject => const {
      'id', 'pageId', 'type', 'frame', 'shape', 'geometry', 'style', 'text', //
      'assetId', 'px', 'latex', 'engine', 'createdAt', 'updatedAt',
      'deletedAt', 'version',
    },
    EntityKind.handwriting => const {
      'id', 'noteId', 'pageId', 'engineId', 'sourceRev', 'lines', //
      'createdAt', 'updatedAt', 'deletedAt', 'version',
    },
  };

  /// Explicit multi-key groups per kind (table 6.3.1).
  static List<Set<String>> groupsOf(EntityKind kind) => switch (kind) {
    EntityKind.folder => const [
      {'parentId', 'sortKey'},
      _trash,
    ],
    EntityKind.note => const [
      {'folderId', 'sortKey'},
      _trash,
    ],
    EntityKind.page => const [
      {'noteId', 'sortKey'},
    ],
    EntityKind.stroke => const [
      {'recordingId', 'recordingOffsetMs'},
    ],
    EntityKind.setting => const [
      {'valueJson', 'deletedAt'},
    ],
    EntityKind.penPreset ||
    EntityKind.asset ||
    EntityKind.recording => const [],
    // (2nd round, R2-B7a) general records for now: every key is a unit of its own.
    // S2-1 replaces this with the one object / result unit (contract 7.2.8, 07-sync 6.2.2).
    EntityKind.pageObject || EntityKind.handwriting => const [],
  };

  /// All units for the keys present in either snapshot (metaKeys excluded).
  static List<Set<String>> unitsFor(EntityKind kind, Iterable<String> keys) {
    final present = {
      for (final k in keys)
        if (!metaKeys.contains(k)) k,
    };
    final units = <Set<String>>[];
    final grouped = <String>{};
    for (final group in groupsOf(kind)) {
      if (group.any(present.contains)) {
        units.add(group);
        grouped.addAll(group);
      }
    }
    final singles = [
      for (final k in present)
        if (!grouped.contains(k)) k,
    ]..sort();
    for (final k in singles) {
      units.add({k});
    }
    return units;
  }
}
