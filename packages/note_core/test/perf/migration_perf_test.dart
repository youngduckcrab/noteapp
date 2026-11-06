// m5-7/02-core T25b — PF-8 (6.19): the V7 fixture (a v1 database of the 1st-round code, 2 MB —
// 3 notes, 20 pages, 2,000 strokes) upgraded to v2 by openNoteStore on the VM, the v1 copy
// (VACUUM INTO, 6.12.4) included: median ≤ 1 s. Each run opens a fresh copy of the fixture as
// the native app does (file database + file blobs); the same upgrade without the copy step is
// recorded beside it (what the copy costs). The Chrome figures are recorded by
// test/web/v1_fixture_migration_browser_test.dart.
@TestOn('vm')
@Tags(['perf'])
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:note_core/note_core.dart';
import 'package:note_core/src/storage/db/note_database.dart';
import 'package:note_core/src/storage/drift_note_store.dart';
import 'package:test/test.dart';

import '../shared/v7_fixture_checks.dart';
import 'perf_support.dart';

const String _fixture = 'test/fixtures/db_v1/noteapp_v1.sqlite';

void main() {
  test('PF-8: V7 fixture v1 → v2 with the v1 copy: median ≤ 1 s', () async {
    final dir = await Directory.systemTemp.createTemp('note_core_perf_pf8_');
    addTearDown(() => dir.delete(recursive: true));
    final withCopy = <Duration>[];
    final withoutCopy = <Duration>[];
    for (var i = 0; i < 6; i++) {
      final run = Directory('${dir.path}/run$i')..createSync();
      final path = '${run.path}/noteapp.db';
      File(_fixture).copySync(path);
      final config = NoteStoreConfig(
        nativeDatabasePath: path,
        nativeAssetDirectoryPath: '${run.path}/assets',
        clock: v7Clock(),
      );
      final (store, took) = await timed(() => openNoteStore(config));
      expect(
        File('$path-v1-backup').existsSync(),
        isTrue,
        reason: 'the copy is part of the measured open',
      );
      await store.close();

      // The same upgrade with no copy maker (the step-0 cost left out).
      final bare = '${run.path}/bare.db';
      File(_fixture).copySync(bare);
      final (bareStore, bareTook) = await timed(
        () => DriftNoteStore.open(
          executor: NativeDatabase.createInBackground(File(bare)),
          storageInfo: const StorageInfo(backend: StorageBackend.nativeFile),
          config: NoteStoreConfig(nativeDatabasePath: bare, clock: v7Clock()),
          databaseFactory: (e, _) => NoteDatabase(e),
        ),
      );
      expect(File('$bare-v1-backup').existsSync(), isFalse);
      await bareStore.close();
      if (i == 0) continue; // warm-up
      withCopy.add(took);
      withoutCopy.add(bareTook);
    }
    record(
      'PF-8 V7 upgrade without the copy step (median of 5)',
      median(withoutCopy),
    );
    record(
      'PF-8 V7 upgrade with the v1 copy, openNoteStore (median of 5)',
      median(withCopy),
      budget: const Duration(seconds: 1),
      note:
          'fixture ${File(_fixture).lengthSync()} B; runs '
          '${[for (final d in withCopy) ms(d)].join(', ')} ms',
    );
  }, timeout: const Timeout(Duration(minutes: 5)));
}
