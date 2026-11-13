import 'package:note_core/note_core.dart';

/// Merge units (6.3.1). Keys not listed in a group form their own unit.
/// (2nd round, contract 7.2.8, 07-sync 6.2.2) pageObject and handwriting are merged
/// as one unit instead: every non-meta key except [wholeUnitExcept].
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
    // 6.2.1); the keys of each type are a subset of it. (math pen) `ink` of math: in the
    // one object unit with frame / latex / style (wholeUnitExcept), so a formula and the
    // handwriting it came from always win together.
    EntityKind.pageObject => const {
      'id', 'pageId', 'type', 'frame', 'shape', 'geometry', 'style', 'text', //
      'assetId', 'px', 'latex', 'engine', 'ink', 'createdAt', 'updatedAt',
      'deletedAt', 'version',
    },
    EntityKind.handwriting => const {
      'id', 'noteId', 'pageId', 'engineId', 'sourceRev', 'lines', //
      'createdAt', 'updatedAt', 'deletedAt', 'version',
    },
  };

  /// Explicit multi-key groups per kind (table 6.3.1). pageObject / handwriting →
  /// const []: they are merged by [wholeUnitExcept] instead.
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
    EntityKind.pageObject || EntityKind.handwriting => const [],
  };

  /// (2nd round) Kinds merged as ONE unit: every non-meta key present in either
  /// snapshot (unknown keys included) except these, which are units of their own.
  /// null for the v1.4 kinds.
  ///   pageObject  → {'pageId', 'deletedAt', 'engine'}
  ///   handwriting → {'noteId', 'pageId', 'deletedAt'}
  ///
  /// A key added to either kind in a later round joins the one unit, so apps of
  /// different versions pick the same winner (07-sync 6.2.2 counter-example).
  static Set<String>? wholeUnitExcept(EntityKind kind) => switch (kind) {
    EntityKind.pageObject => const {'pageId', 'deletedAt', 'engine'},
    EntityKind.handwriting => const {'noteId', 'pageId', 'deletedAt'},
    EntityKind.folder ||
    EntityKind.note ||
    EntityKind.page ||
    EntityKind.stroke ||
    EntityKind.penPreset ||
    EntityKind.asset ||
    EntityKind.recording ||
    EntityKind.setting => null,
  };

  /// All units for the keys present in either snapshot (metaKeys excluded). For a
  /// [wholeUnitExcept] kind: the rest (if not empty) + each present excepted key as
  /// its own unit. Keys inside a unit and the order of units are deterministic.
  static List<Set<String>> unitsFor(EntityKind kind, Iterable<String> keys) {
    final present = {
      for (final k in keys)
        if (!metaKeys.contains(k)) k,
    };
    final except = wholeUnitExcept(kind);
    if (except != null) {
      final rest = [
        for (final k in present)
          if (!except.contains(k)) k,
      ]..sort();
      final own = [
        for (final k in present)
          if (except.contains(k)) k,
      ]..sort();
      return [
        if (rest.isNotEmpty) rest.toSet(),
        for (final k in own) {k},
      ];
    }
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
