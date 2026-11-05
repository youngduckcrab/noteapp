// CORE T13 — the blob IndexedDB on the browser's IndexedDB (idbFactoryBrowser, 6.13):
// a 32 MiB asset in 4 MiB chunks round-trips; thumbnails keep their fields.
@TestOn('browser')
library;

import 'dart:typed_data';

import 'package:idb_shim/idb_browser.dart';
import 'package:note_core/note_core.dart';
import 'package:note_core/src/assets/blob_store.dart';
import 'package:note_core/src/assets/content_hasher.dart';
import 'package:note_core/src/assets/idb_blob_store.dart';
import 'package:test/test.dart';

const _mib = 1024 * 1024;

Uint8List _bytes(int length) {
  final b = Uint8List(length);
  for (var i = 0; i < length; i++) {
    b[i] = (i * 13 + i ~/ 4096) % 256;
  }
  return b;
}

void main() {
  late String name;
  late IdbBlobDatabase db;
  setUp(() {
    name = 'note_core_blob_test_${DateTime.now().microsecondsSinceEpoch}';
    db = IdbBlobDatabase(idbFactoryBrowser, name);
  });
  tearDown(() async {
    await db.close();
    await IdbBlobDatabase.deleteDatabase(idbFactoryBrowser, name);
  });

  test('uses the browser IndexedDB', () {
    expect(idbFactoryBrowser.persistent, isTrue);
  });

  test(
    '32 MiB: 8 chunks written, read back byte for byte after reopening',
    () async {
      final bytes = _bytes(32 * _mib);
      final id = await sha256Hex(bytes);
      expect(await writeChunks(db.chunks, id, bytes), 8);
      expect(await db.chunks.keys(chunkPrefix(id)), [
        for (var i = 0; i < 8; i++) chunkKey(id, i),
      ]);
      await db.close();
      db = IdbBlobDatabase(idbFactoryBrowser, name);
      expect(await hasAllChunks(db.chunks, id, 8), isTrue);
      final back = (await readChunks(db.chunks, id, 8, bytes.length))!;
      expect(back.length, bytes.length);
      expect(await sha256Hex(back), id);
      await db.chunks.deletePrefix(chunkPrefix(id));
      expect(await db.chunks.keys(chunkPrefix(id)), isEmpty);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test('thumbnails keep every field', () async {
    final t = PageThumbnail(
      pageId: 'p1',
      contentRevision: 7,
      width: 384,
      height: 512,
      mimeType: 'image/png',
      bytes: _bytes(1000),
    );
    await db.thumbnails.put(t);
    final back = (await db.thumbnails.get('p1'))!;
    expect(back.contentRevision, 7);
    expect(back.width, 384);
    expect(back.height, 512);
    expect(back.mimeType, 'image/png');
    expect(back.bytes, t.bytes);
    expect(await db.thumbnails.totalBytes(), 1000);
    await db.thumbnails.delete(['p1']);
    expect(await db.thumbnails.get('p1'), isNull);
  });
}
