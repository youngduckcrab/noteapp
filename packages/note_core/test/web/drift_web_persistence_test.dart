// CORE T16 — the real web store (6.12): openNoteStore on drift WasmDatabase reports
// its StorageInfo.backend; data written, closed and reopened under the same name is
// the same (every entity with its versions, stroke points, asset bytes); the device
// node and the HLC carry on.
@TestOn('browser')
library;

import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:note_core/note_core.dart';
import 'package:note_core/testing.dart';
import 'package:test/test.dart';

import 'web_store_support.dart';

final _clock = Clock.fixed(DateTime.utc(2026, 11, 5, 9));

Future<NoteStore> _open(NoteStoreConfig config) async {
  final store = await openNoteStore(config);
  addTearDown(store.close);
  return store;
}

void main() {
  // Two stores at once below (different databases, on purpose).
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test('openNoteStore reports a durable browser backend', () async {
    final config = freshWebConfig('backend');
    dropAfterTest(config);
    final store = await _open(config);
    final info = store.storageInfo;
    printOnFailure('$info, missing: ${info.missingBrowserFeatures}');
    expect(durableWebBackends, contains(info.backend));
    expect(info.isDurable, isTrue);
    expect(storageWarningOf(info, store.persistenceStatus), isNull);
    expect(
      info.missingBrowserFeatures,
      [...info.missingBrowserFeatures]..sort(),
    );
    // A new database: the default presets and nothing else.
    expect(await store.penPresets.getPresets(), hasLength(5));
    expect(await store.sync.pendingChanges(), hasLength(5));
  });

  test('write, close, reopen with the same name: the same data', () async {
    final config = freshWebConfig('reopen', clock: _clock);
    dropAfterTest(config);
    var store = await openNoteStore(config);
    final folder = await store.library.createFolder(name: '수학');
    final note = await store.library.createNote(
      title: '미적분 노트',
      folderId: folder.id,
      pages: [PageDraft.blankA4, PageDraft.blankA4],
    );
    final session = await store.openSession(note.id);
    final page = session.pages.first;
    await session.openPage(page.id);
    final strokes = [
      for (var i = 0; i < 3; i++)
        StrokeFixtures.synthetic(
          pageId: page.id,
          ids: store.ids,
          seed: i,
          pointCount: 40,
          createdAt: 1000 + i, // drawing order = this order
        ),
    ];
    session.execute(AddStrokes(pageId: page.id, strokes: strokes));
    await session.close();
    await store.settings.set(SettingKey.integer('editor.count', 3), 7);
    final bytes = Uint8List.fromList([for (var i = 0; i < 5000; i++) i % 251]);
    final asset = await store.assets.put(
      bytes,
      type: AssetType.image,
      mimeType: 'image/png',
      fileName: '그림.png',
    );
    final node = store.sync.deviceNodeId;
    final backup = await store.exportBackupJson();
    final pending = await store.sync.pendingChanges();
    final noteVersion = (await store.library.getNote(note.id))!.version!;
    await store.close();

    store = await _open(config);
    expect(store.sync.deviceNodeId, node);
    // Every entity with its field versions (6.17 covers the whole database).
    expect(await store.exportBackupJson(), backup);
    expect(
      [for (final c in await store.sync.pendingChanges()) c.seq],
      [for (final c in pending) c.seq],
    );
    final reopened = await store.openSession(note.id);
    expect(reopened.pages, hasLength(2));
    final content = await reopened.openPage(page.id);
    expect(content.strokes, hasLength(3));
    for (var i = 0; i < 3; i++) {
      final back = content.strokes[i];
      expect(back.id, strokes[i].id);
      expect(back.style, strokes[i].style);
      expect(back.points.contentEquals(strokes[i].points), isTrue);
    }
    await reopened.close();
    expect(await store.settings.get(SettingKey.integer('editor.count', 3)), 7);
    expect(await store.assets.readBytes(asset.id), bytes);
    expect(await store.assets.hasBytes(asset.id), isTrue);
    expect(await store.penPresets.getPresets(), hasLength(5));

    // The clock carries on: a new write gets a later version.
    await store.library.renameNote(note.id, '미적분 2');
    final renamed = (await store.library.getNote(note.id))!.version!;
    expect(renamed.compareTo(noteVersion), greaterThan(0));
    expect(renamed.nodeId, node);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('two stores of different names do not see each other', () async {
    final a = freshWebConfig('a');
    final b = freshWebConfig('b');
    dropAfterTest(a);
    dropAfterTest(b);
    final storeA = await _open(a);
    final storeB = await _open(b);
    await storeA.library.createNote(title: 'only in a');
    final listing = await storeB.library
        .watchListing(const LibraryQuery())
        .first;
    expect(listing.notes, isEmpty);
  });
}
