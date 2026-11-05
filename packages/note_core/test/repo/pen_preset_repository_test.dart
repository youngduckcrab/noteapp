// CORE T12 — DriftPenPresetRepository: the shared preset rules on the SQLite store, plus
// the outbox, the seed version, once-per-database seeding and one-commit reorders.
@TestOn('vm')
library;

import 'dart:io';

import 'package:clock/clock.dart';
import 'package:note_core/note_core.dart';
import 'package:note_core/src/storage/drift_note_store.dart';
import 'package:note_core/src/storage/kv_keys.dart';
import 'package:note_core/src/storage/outbox_writer.dart';
import 'package:note_core/src/storage/row_mappers.dart';
import 'package:note_core/testing_vm.dart';
import 'package:test/test.dart';

import '../shared/preset_contract.dart';

const _seed = Hlc(1, 0, '0000000000000000');

Future<DriftNoteStore> _open({
  bool seed = true,
  String? filePath,
  Clock? clock,
  String node = '00000000000000aa',
}) async => await openTestNoteStore(
  seedDefaultPenPresets: seed,
  filePath: filePath,
  clock: clock,
  deviceNodeId: node,
) as DriftNoteStore;

void main() {
  group('shared contract', () {
    definePresetContractTests(
      ({required seedDefaultPenPresets}) => _open(seed: seedDefaultPenPresets),
    );
  });

  late DriftNoteStore store;
  setUp(() async => store = await _open());
  tearDown(() => store.close());

  Future<List<OutboxEntry>> outbox() => readOutbox(store.db);
  Future<void> ack() => store.db.delete(store.db.outbox).go();

  test(
    'defaults: outbox {*} with the seed HLC, no field overrides, kv marker',
    () async {
      final entries = await outbox();
      expect(entries.map((e) => e.entityId), kDefaultPresetIds);
      for (final e in entries) {
        expect(e.kind, EntityKind.penPreset);
        expect(e.op, OutboxOp.upsert);
        expect(e.changedFields, {kAllFields});
        expect(e.hlc, _seed);
      }
      final rows = await store.db.select(store.db.penPresets).get();
      expect(rows.every((r) => r.version == _seed.toString()), isTrue);
      expect(rows.every((r) => r.fieldVersions == null), isTrue);
      final kv = await (store.db.select(
        store.db.kv,
      )..where((t) => t.key.equals(KvKeys.seedPresetsV1))).getSingle();
      expect(kv.value, '1');
    },
  );

  test('two databases create the same versioned defaults', () async {
    final clock = Clock.fixed(DateTime.utc(2026, 11, 5));
    final a = await _open(clock: clock, node: '00000000000000a1');
    final b = await _open(clock: clock, node: '00000000000000b2');
    addTearDown(a.close);
    addTearDown(b.close);
    for (final id in kDefaultPresetIds) {
      final ref = EntityRef(EntityKind.penPreset, id);
      final va = (await readVersionedRow(a.db, ref))!;
      final vb = (await readVersionedRow(b.db, ref))!;
      expect(va, vb, reason: id);
      expect(va.versions, const EntityFieldVersions(_seed));
    }
  });

  test('a file database seeds once; a deleted default stays deleted', () async {
    final dir = await Directory.systemTemp.createTemp('note_core_presets_');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}/notes.db';
    final first = await _open(filePath: path);
    await first.penPresets.deletePreset('preset-default-highlighter');
    await first.close();
    final second = await _open(filePath: path);
    final ids = (await second.penPresets.getPresets()).map((p) => p.id);
    await second.close();
    expect(ids, hasLength(4));
    expect(ids, isNot(contains('preset-default-highlighter')));
  });

  test(
    'reorderPresets writes only the presets whose key changed, in ONE commit',
    () async {
      await ack();
      final batches = <ChangeBatch>[];
      final sub = store.changes.listen(batches.add);
      final before = store.queue.debugTransactionCount;
      await store.penPresets.reorderPresets([
        'preset-default-ballpoint',
        'preset-default-fountain',
        'preset-default-highlighter',
        'preset-default-marker',
        'preset-default-pencil',
      ]);
      await pumpEventQueue();
      await sub.cancel();
      expect(store.queue.debugTransactionCount, before + 1);
      expect(batches, hasLength(1));
      final entries = await outbox();
      expect(entries.map((e) => e.entityId).toSet(), {
        'preset-default-marker',
        'preset-default-pencil',
      });
      expect(entries.every((e) => e.changedFields.single == 'sortKey'), isTrue);
      final edited = (await store.penPresets.getPresets()).firstWhere(
        (p) => p.id == 'preset-default-marker',
      );
      expect(edited.version! > _seed, isTrue, reason: 'a user edit wins');
    },
  );

  test('update / delete record the changed fields; delete is soft', () async {
    final p = await store.penPresets.createPreset(
      name: 'mine',
      style: StrokeStyle.defaultsFor(PenTool.fountain),
    );
    expect(
      (await outbox()).singleWhere((e) => e.entityId == p.id).changedFields,
      {kAllFields},
    );
    await ack();
    await store.penPresets.updatePreset(p.copyWith(name: 'renamed'));
    expect((await outbox()).single.changedFields, {'name'});
    await ack();
    await store.penPresets.updatePreset(
      p.copyWith(
        name: 'renamed',
        style: StrokeStyle.defaultsFor(PenTool.fountain).copyWith(width: 3),
      ),
    );
    expect((await outbox()).single.changedFields, {'style'});
    await ack();
    final stored = (await store.penPresets.getPresets()).last;
    await store.penPresets.updatePreset(stored.copyWith(name: ' renamed '));
    expect(await outbox(), isEmpty, reason: 'nothing changed');
    await store.penPresets.deletePreset(p.id);
    expect((await outbox()).single.changedFields, {'deletedAt'});
    final row = await (store.db.select(
      store.db.penPresets,
    )..where((t) => t.id.equals(p.id))).getSingle();
    expect(row.deletedAt, isNotNull);
  });
}
