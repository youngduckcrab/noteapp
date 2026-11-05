// CORE T12 — DriftSettingsRepository: the shared settings rules on the SQLite store, plus
// where each scope is stored (synced = settings table + outbox, device = kv, 7.4.6),
// soft reset and damaged stored values.
@TestOn('vm')
library;

import 'package:note_core/note_core.dart';
import 'package:note_core/src/storage/db/note_database.dart';
import 'package:note_core/src/storage/drift_note_store.dart';
import 'package:note_core/src/storage/outbox_writer.dart';
import 'package:note_core/testing_vm.dart';
import 'package:test/test.dart';

import '../shared/preset_contract.dart';

Future<DriftNoteStore> _open({bool seed = false}) async =>
    await openTestNoteStore(seedDefaultPenPresets: seed) as DriftNoteStore;

void main() {
  group('shared contract', () {
    defineSettingsContractTests(
      ({required seedDefaultPenPresets}) => _open(seed: seedDefaultPenPresets),
    );
  });

  late DriftNoteStore store;
  late SettingsRepository settings;
  setUp(() async {
    store = await _open();
    settings = store.settings;
  });
  tearDown(() => store.close());

  Future<List<OutboxEntry>> outbox() => readOutbox(store.db);
  Future<void> ack() => store.db.delete(store.db.outbox).go();

  test('synced: settings row + outbox; reset is a soft delete', () async {
    final key = SettingKey.string('library.viewMode', 'grid');
    final batches = <ChangeBatch>[];
    final sub = store.changes.listen(batches.add);
    await settings.set(key, 'list');
    var row = await (store.db.select(
      store.db.settings,
    )..where((t) => t.key.equals('library.viewMode'))).getSingle();
    expect(row.valueJson, '"list"');
    final first = (await outbox()).single;
    expect(first.kind, EntityKind.setting);
    expect(first.entityId, 'library.viewMode');
    expect(first.changedFields, {kAllFields});
    await ack();
    await settings.set(key, 'table');
    expect((await outbox()).single.changedFields, {'valueJson'});
    await ack();
    await settings.reset(key);
    row = await (store.db.select(
      store.db.settings,
    )..where((t) => t.key.equals('library.viewMode'))).getSingle();
    expect(row.deletedAt, isNotNull, reason: 'the row stays (tombstone)');
    expect((await outbox()).single.changedFields, {'deletedAt'});
    await settings.reset(key);
    expect((await outbox()).single.rev, 1, reason: 'reset twice: no write');
    await ack();
    await settings.set(key, 'table');
    expect((await outbox()).single.changedFields, {'deletedAt'});
    await pumpEventQueue();
    await sub.cancel();
    expect(batches.map((b) => b.changes.single.kind), [
      for (var i = 0; i < 4; i++) EntityKind.setting,
    ]);
    expect(batches.every((b) => b.origin == ChangeOrigin.local), isTrue);
  });

  test('device: kv["setting.<name>"], no outbox, no ChangeBatch', () async {
    final key = SettingKey.boolean(
      'editor.penOnlyMode',
      false,
      scope: SettingScope.device,
    );
    final batches = <ChangeBatch>[];
    final sub = store.changes.listen(batches.add);
    await settings.set(key, true);
    final kv = await (store.db.select(
      store.db.kv,
    )..where((t) => t.key.equals('setting.editor.penOnlyMode'))).getSingle();
    expect(kv.value, 'true');
    expect(await outbox(), isEmpty);
    expect(await store.db.select(store.db.settings).get(), isEmpty);
    await settings.reset(key);
    expect(
      await (store.db.select(
        store.db.kv,
      )..where((t) => t.key.equals('setting.editor.penOnlyMode'))).get(),
      isEmpty,
    );
    await pumpEventQueue();
    await sub.cancel();
    expect(batches, isEmpty);
  });

  test('damaged stored JSON reads as the default', () async {
    await store.db
        .into(store.db.settings)
        .insert(
          SettingsCompanion.insert(
            key: 'editor.broken',
            valueJson: '{not json',
            updatedAt: 1,
            version: Hlc(1, 0, '00000000000000aa').toString(),
          ),
        );
    await store.db
        .into(store.db.kv)
        .insert(
          KvCompanion.insert(key: 'setting.editor.brokenDevice', value: '['),
        );
    expect(await settings.get(SettingKey.integer('editor.broken', 5)), 5);
    expect(
      await settings.get(
        SettingKey.integer(
          'editor.brokenDevice',
          6,
          scope: SettingScope.device,
        ),
      ),
      6,
    );
    final snap = await settings.watchAll().first;
    expect(snap.get(SettingKey.integer('editor.broken', 7)), 7);
  });

  test(
    'a remote setting change re-emits watch (C-1 local or remote)',
    () async {
      final key = SettingKey.integer('editor.count', 0);
      final seen = <int>[];
      final sub = settings.watch(key).listen(seen.add);
      await pumpEventQueue();
      await store.queue.run(
        (tx) => tx.putRemote(
          const SettingValue(key: 'editor.count', valueJson: '4', updatedAt: 2),
          EntityFieldVersions(Hlc(2, 0, 'ffffffffffffffff')),
        ),
        origin: ChangeOrigin.remote,
      );
      await pumpEventQueue();
      expect(seen, [0, 4]);
      await sub.cancel();
    },
  );
}
