// CORE T19 — exportBackupJson of the shared fake (contract 7.6): the shared cases of
// 6.17 and the same golden bytes as the SQLite store for the same state.
@TestOn('vm')
library;

import 'dart:convert';

import 'package:note_core/testing.dart';
import 'package:test/test.dart';

import '../backup/backup_golden.dart';
import '../shared/backup_cases.dart';

void main() {
  defineBackupTests(open: openFakeBackupStore, seed: seedFakeBackupState);

  test('the golden state exports the golden bytes', tags: ['golden'], () async {
    final store = await openFakeBackupStore();
    addTearDown(store.close);
    await seedFakeBackupState(store, backupGoldenState());
    expectBackupGolden(await store.exportBackupJson());
  });

  test('the default presets are exported', () async {
    final store = createFakeNoteStore(clock: kBackupClock);
    addTearDown(store.close);
    final text = utf8.decode(await store.exportBackupJson());
    expect(RegExp('"kind":"penPreset"').allMatches(text), hasLength(5));
  });
}
