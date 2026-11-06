// m5-7/02-core T35 — the native store through openNoteStore (6.15.3, 공통-1, contract 7.2.6):
// both native paths → a file database (WAL, background isolate) plus file blobs, durable with
// no storage warning; one path → storageUnavailable; the root and its subdirectories (and
// the directory of the database file) are made when missing, a directory that cannot be made
// or written → storageUnavailable; a reopened store keeps its assets, thumbnails, recording
// drafts and search glyph boxes; deleteLocalNoteData removes the database, its v1 copy and
// the blobs (not the root), and refuses while the store is open.
@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:note_core/dev_tools.dart';
import 'package:note_core/note_core.dart';
import 'package:note_core/src/assets/blob_store.dart';
import 'package:note_core/src/assets/file_blob_store_native.dart';
import 'package:note_core/src/storage/drift_note_store.dart';
import 'package:note_core/src/storage/drift_search_index.dart'
    show kSearchBlobRoot;
import 'package:note_core/src/storage/v1_copy/v1_copy_file.dart';
import 'package:test/test.dart';

import '../shared/v1_database.dart';

TypeMatcher<NoteStoreOpenException> _openFailure(NoteStoreOpenFailure reason) =>
    isA<NoteStoreOpenException>().having((e) => e.reason, 'reason', reason);

Uint8List _bytes(int length, [int seed = 0]) => Uint8List.fromList([
  for (var i = 0; i < length; i++) (i * 31 + seed) % 251,
]);

const int _mib = 1024 * 1024;

void main() {
  late Directory tmp;
  late String dbPath;
  late String blobRoot;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('note_core_native_');
    dbPath = '${tmp.path}/db/notes.db';
    blobRoot = '${tmp.path}/files/assets';
  });
  tearDown(() {
    if (tmp.existsSync()) {
      Process.runSync('chmod', ['-R', '0755', tmp.path]);
      tmp.deleteSync(recursive: true);
    }
  });

  NoteStoreConfig config({String? db, String? blobs}) => NoteStoreConfig(
    nativeDatabasePath: db ?? dbPath,
    nativeAssetDirectoryPath: blobs ?? blobRoot,
    seedDefaultPenPresets: false,
  );

  Future<DriftNoteStore> open([NoteStoreConfig? c]) async =>
      await openNoteStore(c ?? config()) as DriftNoteStore;

  group('open (6.15.3)', () {
    test('both paths → nativeFile, durable, no storage warning; file blobs and '
        'a WAL file database', () async {
      final store = await open();
      addTearDown(store.close);
      expect(store.storageInfo.backend, StorageBackend.nativeFile);
      expect(store.storageInfo.isDurable, isTrue);
      expect(
        storageWarningOf(store.storageInfo, store.persistenceStatus),
        isNull,
      );
      expect(store.blobs, isA<FileBlobDatabase>());
      expect((store.blobs as FileBlobDatabase).root, blobRoot);
      final mode = await store.db
          .customSelect('PRAGMA journal_mode')
          .getSingle();
      expect(mode.read<String>('journal_mode'), 'wal');
    });

    test(
      'missing root, subdirectories and database directory are made',
      () async {
        expect(Directory('${tmp.path}/db').existsSync(), isFalse);
        expect(Directory('${tmp.path}/files').existsSync(), isFalse);
        final store = await open();
        await store.close();
        expect(File(dbPath).existsSync(), isTrue);
        expect(Directory('$blobRoot/blobs').existsSync(), isTrue);
        expect(Directory('$blobRoot/thumbs').existsSync(), isTrue);
      },
    );

    test('only one path → storageUnavailable, nothing is made', () async {
      await expectLater(
        openNoteStore(NoteStoreConfig(nativeDatabasePath: dbPath)),
        throwsA(_openFailure(NoteStoreOpenFailure.storageUnavailable)),
      );
      await expectLater(
        openNoteStore(NoteStoreConfig(nativeAssetDirectoryPath: blobRoot)),
        throwsA(_openFailure(NoteStoreOpenFailure.storageUnavailable)),
      );
      expect(Directory('${tmp.path}/db').existsSync(), isFalse);
      expect(Directory('${tmp.path}/files').existsSync(), isFalse);
    });

    test('inMemory needs neither path (1st round) and ignores them', () async {
      final store = await openNoteStore(
        NoteStoreConfig(inMemory: true, nativeAssetDirectoryPath: blobRoot),
      );
      addTearDown(store.close);
      expect(store.storageInfo.backend, StorageBackend.nativeMemory);
      expect(Directory(blobRoot).existsSync(), isFalse);
    });

    test('a blob root that cannot be made → storageUnavailable; the database '
        'file is released (it can be deleted)', () async {
      File('${tmp.path}/plain').writeAsBytesSync([1]);
      final bad = config(blobs: '${tmp.path}/plain/assets');
      await expectLater(
        openNoteStore(bad),
        throwsA(
          _openFailure(NoteStoreOpenFailure.storageUnavailable)
              .having((e) => e.cause, 'cause', isA<FileSystemException>()),
        ),
      );
      await deleteLocalNoteData(bad);
    });

    test(
      "a 'blobs' entry that is not a directory → storageUnavailable",
      () async {
        Directory(blobRoot).createSync(recursive: true);
        File('$blobRoot/thumbs').writeAsBytesSync([1]);
        await expectLater(
          openNoteStore(config()),
          throwsA(_openFailure(NoteStoreOpenFailure.storageUnavailable)),
        );
      },
    );

    test(
      'a database directory that cannot be made → storageUnavailable',
      () async {
        File('${tmp.path}/plain').writeAsBytesSync([1]);
        await expectLater(
          openNoteStore(config(db: '${tmp.path}/plain/notes.db')),
          throwsA(_openFailure(NoteStoreOpenFailure.storageUnavailable)),
        );
      },
    );

    test('a read-only blob root → storageUnavailable (where the system '
        'enforces the mode)', () async {
      Directory('$blobRoot/blobs').createSync(recursive: true);
      Directory('$blobRoot/thumbs').createSync();
      Process.runSync('chmod', [
        '0555',
        blobRoot,
        '$blobRoot/blobs',
        '$blobRoot/thumbs',
      ]);
      final probe = File('$blobRoot/blobs/.probe');
      try {
        probe.writeAsBytesSync([1]);
        probe.deleteSync();
        markTestSkipped('this process writes into 0555 directories (root)');
        return;
      } on FileSystemException {
        // Enforced: the open must fail.
      }
      await expectLater(
        openNoteStore(config()),
        throwsA(_openFailure(NoteStoreOpenFailure.storageUnavailable)),
      );
    });

    test('left-over temporary files are deleted at open', () async {
      final store = await open();
      await store.close();
      final left = File('$blobRoot/blobs/.x.tmp-1')..writeAsBytesSync([1]);
      final again = await open();
      addTearDown(again.close);
      expect(left.existsSync(), isFalse);
    });
  });

  group('the blobs are files and survive a reopen', () {
    test('assets (9 MiB = 3 chunk files), thumbnails, recording drafts and '
        'search glyph boxes', () async {
      final first = await open();
      final bytes = _bytes(9 * _mib, 3);
      final asset = await first.assets.put(
        bytes,
        type: AssetType.pdf,
        mimeType: 'application/pdf',
      );
      expect(
        [
          for (var i = 0; i < 3; i++)
            File('$blobRoot/blobs/${chunkKey(asset.id, i)}').lengthSync(),
        ],
        [4 * _mib, 4 * _mib, _mib],
      );
      final note = await first.library.createNote(title: 'n');
      final pageId = (await first.content.pagesOf(note.id)).single.id;
      await first.thumbnails.write(
        PageThumbnail(
          pageId: pageId,
          contentRevision: 0,
          width: 64,
          height: 48,
          mimeType: 'image/png',
          bytes: _bytes(100),
        ),
      );
      expect(
        File('$blobRoot/thumbs/${thumbnailFileNameOf(pageId)}').existsSync(),
        isTrue,
      );
      final draft = await first.recordingDrafts.begin(
        recordingId: 'rec-1',
        noteId: note.id,
        mimeType: 'audio/webm',
        startedAt: 1000,
      );
      await first.recordingDrafts.append(
        draft.draftId,
        _bytes(300, 1),
        activeMs: 1000,
      );
      await first.recordingDrafts.append(
        draft.draftId,
        _bytes(200, 2),
        activeMs: 2000,
      );
      const body = '네이티브 파일 블롭';
      await first.search.replaceUnits(SearchSource.pdf, '${asset.id}#0', [
        SearchUnitDraft(
          body: body,
          rects: [
            for (var i = 0; i < body.length; i++)
              PageRect.fromLTWH(i * 0.05, 0.1, 0.04, 0.02),
          ],
          pdfPageAspect: 0.75,
        ),
      ], sourceRev: '${asset.id}:${SearchText.normalizerVersion}');
      final glyphKeys = await first.blobs.chunks.keys(kSearchBlobRoot);
      expect(glyphKeys, hasLength(1));
      await first.close();

      final again = await open();
      addTearDown(again.close);
      expect(await again.assets.hasBytes(asset.id), isTrue);
      expect(await again.assets.readBytes(asset.id), bytes);
      expect((await again.thumbnails.read(pageId))!.bytes, _bytes(100));
      final drafts = await again.recordingDrafts.listDrafts();
      expect(drafts.single.draftId, draft.draftId);
      expect(drafts.single.chunkCount, 2);
      expect(drafts.single.bytes, 500);
      expect(await again.recordingDrafts.readAll(draft.draftId), [
        ..._bytes(300, 1),
        ..._bytes(200, 2),
      ]);
      expect(await again.blobs.chunks.keys(kSearchBlobRoot), glyphKeys);
      final usage = await again.assets.usage();
      expect(usage.thumbnailBytes, 100);
    });
  });

  group('deleteLocalNoteData (6.15.3, 6.12.4)', () {
    test('StateError while open; then the database, its v1 copy and the '
        'blobs / thumbs directories are gone and the root stays', () async {
      // A v1 file database: the open upgrades it and makes the v1 copy next to it.
      Directory('${tmp.path}/db').createSync();
      await createV1Database(NativeDatabase(File(dbPath)));
      final store = await open();
      expect(File(v1CopyPathOf(dbPath)).existsSync(), isTrue);
      expect(await v1DatabaseCopyInfo(store), isNotNull);
      final asset = await store.assets.put(
        _bytes(10),
        type: AssetType.pdf,
        mimeType: 'application/pdf',
      );
      await store.thumbnails.write(
        PageThumbnail(
          pageId: 'p1',
          contentRevision: 0,
          width: 1,
          height: 1,
          mimeType: 'image/png',
          bytes: _bytes(4),
        ),
      );
      await expectLater(deleteLocalNoteData(config()), throwsStateError);
      expect(
        File('$blobRoot/blobs/${chunkKey(asset.id, 0)}').existsSync(),
        isTrue,
      );
      await store.close();

      File('$blobRoot/other.txt').writeAsStringSync('not ours');
      await deleteLocalNoteData(config());
      for (final p in [
        dbPath,
        '$dbPath-wal',
        '$dbPath-shm',
        v1CopyPathOf(dbPath),
      ]) {
        expect(File(p).existsSync(), isFalse, reason: p);
      }
      expect(Directory('$blobRoot/blobs').existsSync(), isFalse);
      expect(Directory('$blobRoot/thumbs').existsSync(), isFalse);
      expect(Directory(blobRoot).existsSync(), isTrue);
      expect(File('$blobRoot/other.txt').existsSync(), isTrue);

      final fresh = await open();
      addTearDown(fresh.close);
      expect(await fresh.assets.getAsset(asset.id), isNull);
      expect(await fresh.blobs.chunks.keys(''), isEmpty);
      expect(await fresh.thumbnails.read('p1'), isNull);
      expect(await v1DatabaseCopyInfo(fresh), isNull);
    });

    test('with nothing stored yet: no error', () async {
      await deleteLocalNoteData(config());
      expect(Directory(blobRoot).existsSync(), isFalse);
    });
  });
}
