// lib/src/storage/drift_pen_preset_repository.dart (internal) — PenPresetRepository on
// SQLite (CORE 4.5, 6.2.2). Same meaning as the fake store's presets
// (test/shared/preset_contract.dart runs on both).
import 'package:collection/collection.dart';
import 'package:drift/drift.dart';

import '../common/errors.dart';
import '../common/hlc.dart';
import '../common/ids.dart';
import '../common/sort_keys.dart';
import '../common/sort_planner.dart';
import '../model/pen_preset.dart';
import '../model/pen_style.dart';
import '../model/sync_entity.dart';
import '../repo/pen_preset_repository.dart';
import '../sync/outbox_types.dart';
import 'db/note_database.dart';
import 'drift_library_repository.dart';
import 'drift_note_store.dart';
import 'entity_diff.dart';
import 'kv_keys.dart';
import 'row_mappers.dart';
import 'watch_hub.dart';
import 'write_queue.dart';

/// Default preset names (contract 7.2.4, CORE 6.2.2), in sortKey order a0..a4.
const Map<PenTool, String> kDefaultPresetNames = {
  PenTool.ballpoint: '볼펜',
  PenTool.fountain: '만년필',
  PenTool.highlighter: '형광펜',
  PenTool.pencil: '연필',
  PenTool.marker: '마커',
};

/// Version (and every field version) of a default preset: two devices that each
/// create them merge into one, and any user edit (a real HLC) wins (6.2.2).
const Hlc kDefaultPresetVersion = Hlc(1, 0, '0000000000000000');

/// The id of the default preset of [tool].
String defaultPresetId(PenTool tool) => 'preset-default-${tool.wireName}';

int _byKey(PenPreset a, PenPreset b) =>
    compareSortKeyThenId(a.sortKey, a.id, b.sortKey, b.id);

final class DriftPenPresetRepository implements PenPresetRepository {
  DriftPenPresetRepository(this.s);
  final DriftNoteStore s;

  NoteDatabase get _db => s.db;
  OwnerId get _owner => s.ownerId;

  Future<List<PenPreset>> _active() async {
    final rows = await (_db.select(
      _db.penPresets,
    )..where((t) => t.ownerId.equals(_owner) & t.deletedAt.isNull())).get();
    return [for (final r in rows) presetOf(r)]..sort(_byKey);
  }

  Future<PenPreset> _preset(PresetId id) async {
    final r =
        await (_db.select(_db.penPresets)..where(
              (t) =>
                  t.id.equals(id) &
                  t.ownerId.equals(_owner) &
                  t.deletedAt.isNull(),
            ))
            .getSingleOrNull();
    if (r == null) throw EntityNotFoundException('Preset $id does not exist');
    return presetOf(r);
  }

  Future<void> _put(WriteTxn tx, PenPreset before, PenPreset next) async {
    final fields = changedJsonKeys(before, next);
    if (fields.isEmpty) return;
    await tx.putLocal(next.copyWith(updatedAt: tx.now), fields);
  }

  @override
  Stream<List<PenPreset>> watchPresets() => s.watches.watch(
    affects: (CommitTouch t) => t.kinds.contains(EntityKind.penPreset),
    query: () async => List<PenPreset>.unmodifiable(await _active()),
    equals: const ListEquality<PenPreset>().equals,
  );

  @override
  Future<List<PenPreset>> getPresets() async =>
      List.unmodifiable(await _active());

  @override
  Future<PenPreset> createPreset({
    required String name,
    required StrokeStyle style,
    String? group,
    bool pinned = true,
    PresetId? after,
  }) async {
    final n = checkLibraryName(name, max: 60);
    return s.queue.run((tx) async {
      final list = await _active();
      var index = list.length;
      if (after != null) {
        final at = list.indexWhere((p) => p.id == after);
        if (at < 0) {
          throw EntityNotFoundException('Preset $after does not exist');
        }
        index = at + 1;
      }
      final plan = planSortKeys(
        [for (final p in list) (key: p.sortKey, id: p.id)],
        index,
        1,
      );
      final byId = {for (final p in list) p.id: p};
      for (final e in plan.rekeyed.entries) {
        final p = byId[e.key]!;
        await _put(tx, p, p.copyWith(sortKey: e.value));
      }
      final p = PenPreset(
        id: s.ids.newId(),
        ownerId: _owner,
        name: n,
        style: style.normalized(),
        group: group,
        pinned: pinned,
        sortKey: plan.keys.single,
        createdAt: tx.now,
        updatedAt: tx.now,
      );
      final v = await tx.putLocal(p, const {kAllFields}, isNew: true);
      return p.copyWith(version: v.max);
    });
  }

  @override
  Future<void> updatePreset(PenPreset preset) async {
    final n = checkLibraryName(preset.name, max: 60);
    return s.queue.run((tx) async {
      final cur = await _preset(preset.id);
      await _put(
        tx,
        cur,
        cur.copyWith(
          name: n,
          style: preset.style.normalized(),
          group: preset.group,
          clearGroup: preset.group == null,
          pinned: preset.pinned,
        ),
      );
    });
  }

  @override
  Future<void> reorderPreset(
    PresetId id, {
    PresetId? after,
    PresetId? before,
  }) => s.queue.run((tx) async {
    final cur = await _preset(id);
    final rest = [
      for (final p in await _active())
        if (p.id != id) p,
    ];
    var index = rest.length;
    final anchor = after ?? before;
    if (anchor != null) {
      final at = rest.indexWhere((p) => p.id == anchor);
      if (at < 0) {
        throw ArgumentError.value(anchor, 'anchor', 'not an active preset');
      }
      index = after != null ? at + 1 : at;
    }
    final plan = planSortKeys(
      [for (final p in rest) (key: p.sortKey, id: p.id)],
      index,
      1,
    );
    final byId = {for (final p in rest) p.id: p};
    for (final e in plan.rekeyed.entries) {
      final p = byId[e.key]!;
      await _put(tx, p, p.copyWith(sortKey: e.value));
    }
    await _put(tx, cur, cur.copyWith(sortKey: plan.keys.single));
  });

  @override
  Future<void> reorderPresets(List<PresetId> orderedIds) => s.queue.run((
    tx,
  ) async {
    final active = await _active();
    final byId = {for (final p in active) p.id: p};
    final listed = <PenPreset>[];
    for (final id in orderedIds) {
      final p = byId.remove(id);
      if (p != null) listed.add(p);
    }
    final order = [...listed, ...active.where((p) => byId.containsKey(p.id))];
    final keys = SortKeys.nBetween(null, null, order.length);
    for (var i = 0; i < order.length; i++) {
      await _put(tx, order[i], order[i].copyWith(sortKey: keys[i]));
    }
  });

  @override
  Future<void> deletePreset(PresetId id) => s.queue.run((tx) async {
    final p = await _preset(id);
    await _put(tx, p, p.copyWith(deletedAt: tx.now));
  });

  @override
  Future<void> ensureDefaults() => s.queue.run((tx) async {
    final seeded = await (_db.select(
      _db.kv,
    )..where((t) => t.key.equals(KvKeys.seedPresetsV1))).getSingleOrNull();
    if (seeded != null) return;
    final keys = SortKeys.nBetween(null, null, kDefaultPresetNames.length);
    var i = 0;
    for (final e in kDefaultPresetNames.entries) {
      final id = defaultPresetId(e.key);
      final exists =
          await (_db.selectOnly(_db.penPresets)
                ..addColumns([_db.penPresets.id])
                ..where(_db.penPresets.id.equals(id)))
              .getSingleOrNull();
      if (exists == null) {
        await tx.putLocal(
          PenPreset(
            id: id,
            ownerId: _owner,
            name: e.value,
            style: StrokeStyle.defaultsFor(e.key),
            sortKey: keys[i],
            createdAt: tx.now,
            updatedAt: tx.now,
          ),
          const {kAllFields},
          isNew: true,
          fixedVersion: kDefaultPresetVersion,
        );
      }
      i++;
    }
    await _db
        .into(_db.kv)
        .insertOnConflictUpdate(
          KvCompanion.insert(key: KvKeys.seedPresetsV1, value: '1'),
        );
    tx.touchKv(KvKeys.seedPresetsV1);
  });
}
