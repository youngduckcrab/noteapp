// CORE T13 — the blob IndexedDB (6.13) on idb_shim's in-memory factory: the same code
// path as the web (idbFactoryBrowser, test/web/blob_store_browser_test.dart).
@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:idb_shim/idb_client_memory.dart';
import 'package:note_core/note_core.dart';
import 'package:note_core/src/assets/blob_store.dart';
import 'package:note_core/src/assets/idb_blob_store.dart';
import 'package:test/test.dart';

Uint8List _bytes(int length, [int seed = 0]) => Uint8List.fromList([
  for (var i = 0; i < length; i++) (i * 31 + seed) % 251,
]);

PageThumbnail _thumb(String pageId, {int rev = 1, int length = 10}) =>
    PageThumbnail(
      pageId: pageId,
      contentRevision: rev,
      width: 120,
      height: 160,
      mimeType: 'image/png',
      bytes: _bytes(length, rev),
    );

void main() {
  late IdbFactory factory;
  late IdbBlobDatabase db;
  setUp(() {
    factory = newIdbFactoryMemory();
    db = IdbBlobDatabase(factory, 'noteapp_blobs');
  });
  tearDown(() => db.close());

  group('BlobStore (asset_chunks)', () {
    test('put / get / delete', () async {
      final store = db.chunks;
      expect(await store.get('a/000000'), isNull);
      await store.put('a/000000', _bytes(5));
      expect(await store.get('a/000000'), _bytes(5));
      await store.put('a/000000', _bytes(7, 1));
      expect(await store.get('a/000000'), _bytes(7, 1));
      await store.delete('a/000000');
      expect(await store.get('a/000000'), isNull);
      await store.delete('missing'); // no error
    });

    test(
      'keys(prefix) are sorted and limited to the prefix; deletePrefix',
      () async {
        final store = db.chunks;
        for (final k in [
          'b/000001',
          'a/000002',
          'a/000000',
          'a/000001',
          'ab/0',
        ]) {
          await store.put(k, _bytes(1));
        }
        expect(await store.keys('a/'), ['a/000000', 'a/000001', 'a/000002']);
        expect(await store.keys('b/'), ['b/000001']);
        expect(await store.keys('c/'), isEmpty);
        await store.deletePrefix('a/');
        expect(await store.keys('a/'), isEmpty);
        expect(await store.keys('ab/'), ['ab/0']);
        expect(await store.keys('b/'), ['b/000001']);
      },
    );

    test('a value written by one connection is read by the next one', () async {
      await db.chunks.put('k', _bytes(3));
      await db.close();
      db = IdbBlobDatabase(factory, 'noteapp_blobs');
      expect(await db.chunks.get('k'), _bytes(3));
    });

    test('deleteDatabase drops every value', () async {
      await db.chunks.put('k', _bytes(3));
      await db.thumbnails.put(_thumb('p1'));
      await db.close();
      await IdbBlobDatabase.deleteDatabase(factory, 'noteapp_blobs');
      db = IdbBlobDatabase(factory, 'noteapp_blobs');
      expect(await db.chunks.get('k'), isNull);
      expect(await db.thumbnails.get('p1'), isNull);
    });

    test('a closed database refuses operations', () async {
      await db.close();
      await expectLater(db.chunks.get('k'), throwsStateError);
    });
  });

  group('chunks of an asset', () {
    test('chunkCountFor: 4 MiB chunks', () {
      expect(chunkCountFor(0), 0);
      expect(chunkCountFor(1), 1);
      expect(chunkCountFor(kAssetChunkBytes), 1);
      expect(chunkCountFor(kAssetChunkBytes + 1), 2);
      expect(chunkCountFor(9 * 1024 * 1024), 3);
    });

    test('chunk keys: <assetId>/<index, 6 digits>', () {
      expect(chunkKey('abc', 0), 'abc/000000');
      expect(chunkKey('abc', 12), 'abc/000012');
      expect(chunkPrefix('abc'), 'abc/');
    });

    test('9 MiB: 3 chunks written, all present, joined back', () async {
      final bytes = _bytes(9 * 1024 * 1024);
      final count = await writeChunks(db.chunks, 'x', bytes);
      expect(count, 3);
      expect(await db.chunks.keys('x/'), ['x/000000', 'x/000001', 'x/000002']);
      expect((await db.chunks.get('x/000002'))!.length, 1024 * 1024);
      expect(await hasAllChunks(db.chunks, 'x', 3), isTrue);
      expect(await readChunks(db.chunks, 'x', 3, bytes.length), bytes);
    });

    test('a missing chunk: not complete, read is null', () async {
      final bytes = _bytes(kAssetChunkBytes + 10);
      await writeChunks(db.chunks, 'y', bytes);
      await db.chunks.delete('y/000001');
      expect(await hasAllChunks(db.chunks, 'y', 2), isFalse);
      expect(await readChunks(db.chunks, 'y', 2, bytes.length), isNull);
    });

    test('a joined length that is not the size reads as null', () async {
      await writeChunks(db.chunks, 'z', _bytes(10));
      expect(await readChunks(db.chunks, 'z', 1, 11), isNull);
      expect(await readChunks(db.chunks, 'z', 1, 9), isNull);
    });

    test('empty bytes: no chunk, complete, reads as empty', () async {
      expect(await writeChunks(db.chunks, 'e', Uint8List(0)), 0);
      expect(await hasAllChunks(db.chunks, 'e', 0), isTrue);
      expect(await readChunks(db.chunks, 'e', 0, 0), Uint8List(0));
    });
  });

  group('ThumbnailStore (thumbnails)', () {
    test('put / get keeps every field; delete; totalBytes', () async {
      final store = db.thumbnails;
      expect(await store.get('p1'), isNull);
      await store.put(_thumb('p1', length: 10));
      await store.put(_thumb('p2', rev: 3, length: 25));
      final t = (await store.get('p2'))!;
      expect(t.pageId, 'p2');
      expect(t.contentRevision, 3);
      expect(t.width, 120);
      expect(t.height, 160);
      expect(t.mimeType, 'image/png');
      expect(t.bytes, _bytes(25, 3));
      expect(await store.totalBytes(), 35);
      await store.delete(['p1', 'missing']);
      expect(await store.get('p1'), isNull);
      expect(await store.totalBytes(), 25);
    });

    test('thumbnails and asset chunks are separate stores', () async {
      await db.chunks.put('p1', _bytes(4));
      await db.thumbnails.put(_thumb('p1'));
      expect(await db.chunks.get('p1'), _bytes(4));
      expect((await db.thumbnails.get('p1'))!.bytes, _bytes(10, 1));
    });
  });
}
