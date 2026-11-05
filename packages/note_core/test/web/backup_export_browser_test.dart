// CORE T19 / T16 — the backup document is generated and parsed in the browser (web
// compiler): the shared cases of 6.17 on the shared fake (same writer as the SQLite
// store) and on the real web store (drift WasmDatabase, CORE T16).
@TestOn('browser')
library;

import 'package:note_core/note_core.dart';
import 'package:test/test.dart';

import '../shared/backup_cases.dart';
import 'web_store_support.dart';

Future<NoteStore> _openWeb() async {
  final config = freshWebConfig(
    'backup',
    clock: kBackupClock,
    ids: SequentialIdGenerator(),
    seedDefaultPenPresets: false,
  );
  final store = await openWebStoreWithNode(config, kBackupNode);
  closeAndDropAfterTest(store, config);
  return store;
}

Future<void> _seedWeb(NoteStore store, List<VersionedEntity> state) =>
    store.sync.applyRemote([
      for (final v in state) RemoteUpsert(v.entity, v.versions),
    ], policy: (_, _, _) => const TakeRemote());

void main() {
  group('fake store', () {
    defineBackupTests(open: openFakeBackupStore, seed: seedFakeBackupState);
  });

  group('web store (WasmDatabase)', () {
    defineBackupTests(open: _openWeb, seed: _seedWeb);

    test('the same bytes as the fake for the golden state', () async {
      final web = await _openWeb();
      await _seedWeb(web, backupGoldenState());
      final fake = await openFakeBackupStore();
      addTearDown(fake.close);
      await seedFakeBackupState(fake, backupGoldenState());
      expect(await web.exportBackupJson(), await fake.exportBackupJson());
    });
  });
}
