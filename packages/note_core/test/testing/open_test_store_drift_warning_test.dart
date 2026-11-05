// CORE integration stage — openTestNoteStore turns off drift's debug-only "database class
// created multiple times" warning (SYNC request: two real CORE stores in one isolate, the
// two-device use, printed it with a stack trace on every open after the first). A file of
// its own: drift counts open databases per isolate, and the control below needs a count
// that no earlier test has reset.
@TestOn('vm')
library;

import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:note_core/note_core.dart';
import 'package:note_core/testing_vm.dart';
import 'package:test/test.dart';

const String _warning = 'WARNING (drift)';

void main() {
  test('several test stores open at once print no drift multiple-database '
      'warning', () async {
    final printed = <String>[];
    final print = driftRuntimeOptions.debugPrint;
    final dontWarn = driftRuntimeOptions.dontWarnAboutMultipleDatabases;
    addTearDown(() {
      driftRuntimeOptions.debugPrint = print;
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = dontWarn;
    });
    driftRuntimeOptions.debugPrint = printed.add;
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = false;

    // Control: drift's check is on here (asserts) and its output is captured.
    final a = await openNoteStore(const NoteStoreConfig(inMemory: true));
    final b = await openNoteStore(const NoteStoreConfig(inMemory: true));
    await a.close();
    await b.close();
    expect(printed.where((line) => line.contains(_warning)), isNotEmpty);
    printed.clear();

    final dir = Directory.systemTemp.createTempSync('note_core_test_store_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final stores = [
      await openTestNoteStore(deviceNodeId: '00000000000000aa'),
      await openTestNoteStore(deviceNodeId: '00000000000000bb'),
      await openTestNoteStore(filePath: '${dir.path}/c.db'),
    ];
    for (final store in stores) {
      addTearDown(store.close);
    }
    expect(printed.where((line) => line.contains(_warning)), isEmpty);
    // Each store is its own database.
    final note = await stores[0].library.createNote(title: 'only in a');
    for (final store in stores.skip(1)) {
      expect(await store.library.getNote(note.id), isNull);
    }
  });
}
