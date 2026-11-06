// m5-7/02-core T35 — the native file blobs (6.15.3, 공통-1) in a temporary directory: the
// BlobStore / ThumbnailStore meaning of the 1st-round IndexedDB store (the same cases run on
// both, blob_store_test.dart is the 1st-round one), and what only files have — the layout,
// atomic writes through a temporary file, the clean-up of left-over temporary files at open,
// keys that cannot be files, and a root that cannot be made or written.
@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:idb_shim/idb_client_memory.dart';
import 'package:note_core/note_core.dart';
import 'package:note_core/src/assets/blob_store.dart';
import 'package:note_core/src/assets/file_blob_store_native.dart';
import 'package:note_core/src/assets/idb_blob_store.dart';
import 'package:test/test.dart';

Uint8List _bytes(int length, [int seed = 0]) => Uint8List.fromList([
  for (var i = 0; i < length; i++) (i * 31 + seed) % 251,
]);

PageThumbnail _thumb(
  String pageId, {
  int rev = 1,
  int length = 10,
  String mime = 'image/png',
}) => PageThumbnail(
  pageId: pageId,
  contentRevision: rev,
  width: 120,
  height: 160,
  mimeType: mime,
  bytes: _bytes(length, rev),
);

const int _mib = 1024 * 1024;

/// The cases both blob databases answer the same way.
void _sharedCases(
  String name,
  Future<BlobDatabase> Function() open,
  Future<BlobDatabase> Function() reopen,
) {
  group(name, () {
    late BlobDatabase db;
    setUp(() async => db = await open());
    tearDown(() => db.close());

    test('put / get / delete, a missing key, overwrite', () async {
      final store = db.chunks;
      expect(await store.get('a/000000'), isNull);
      await store.put('a/000000', _bytes(5));
      expect(await store.get('a/000000'), _bytes(5));
      await store.put('a/000000', _bytes(7, 1));
      expect(await store.get('a/000000'), _bytes(7, 1));
      await store.delete('a/000000');
      expect(await store.get('a/000000'), isNull);
      await store.delete('missing'); // no error
      await store.delete('a/000000'); // twice: no error
    });

    test('keys(prefix): ascending, only the prefix — with and without a '
        "trailing '/', nested keys, '' = every key; deletePrefix", () async {
      final store = db.chunks;
      for (final k in [
        'b/000001',
        'a/000002',
        'a/000000',
        'a/000001',
        'ab/0',
        'rd/d1/meta',
        'rd/d1/000001',
        'rd/d1/000000',
        'rd/d2/meta',
        'si/pdf/x/0/t-1',
        'si/pdf/x/10/t-1',
        'si/pdf/x/2/t-1',
        'top',
      ]) {
        await store.put(k, _bytes(1));
      }
      expect(await store.keys('a/'), ['a/000000', 'a/000001', 'a/000002']);
      expect(await store.keys('a'), [
        'a/000000',
        'a/000001',
        'a/000002',
        'ab/0',
      ]);
      expect(await store.keys('b/'), ['b/000001']);
      expect(await store.keys('c/'), isEmpty);
      expect(await store.keys('rd/d1/'), [
        'rd/d1/000000',
        'rd/d1/000001',
        'rd/d1/meta',
      ]);
      expect(await store.keys('rd/'), [
        'rd/d1/000000',
        'rd/d1/000001',
        'rd/d1/meta',
        'rd/d2/meta',
      ]);
      expect(await store.keys('si/pdf/x/'), [
        'si/pdf/x/0/t-1',
        'si/pdf/x/10/t-1',
        'si/pdf/x/2/t-1',
      ]);
      expect(await store.keys('rd/d1/m'), ['rd/d1/meta']);
      expect(await store.keys(''), hasLength(13));
      expect(await store.keys('to'), ['top']);

      await store.deletePrefix('a/');
      expect(await store.keys('a/'), isEmpty);
      expect(await store.keys('ab/'), ['ab/0']);
      expect(await store.keys('b/'), ['b/000001']);
      await store.deletePrefix('rd/d1/');
      expect(await store.keys('rd/'), ['rd/d2/meta']);
      await store.deletePrefix('si/');
      expect(await store.keys('si/'), isEmpty);
      await store.deletePrefix('missing/');
      await store.deletePrefix('a'); // 'ab/0' too
      expect(await store.keys(''), ['b/000001', 'rd/d2/meta', 'top']);
      await store.deletePrefix('');
      expect(await store.keys(''), isEmpty);
    });

    test('getMany: values in key order, null for a missing key', () async {
      await db.chunks.put('g/1', _bytes(2, 1));
      await db.chunks.put('g/2', _bytes(3, 2));
      expect(await db.chunks.getMany(const []), isEmpty);
      expect(await db.chunks.getMany(['g/2', 'none', 'g/1']), [
        _bytes(3, 2),
        null,
        _bytes(2, 1),
      ]);
    });

    test('9 MiB asset: 3 chunks written, all present, joined back', () async {
      final bytes = _bytes(9 * _mib);
      final count = await writeChunks(db.chunks, 'x', bytes);
      expect(count, 3);
      expect(await db.chunks.keys('x/'), ['x/000000', 'x/000001', 'x/000002']);
      expect((await db.chunks.get('x/000002'))!.length, _mib);
      expect(await hasAllChunks(db.chunks, 'x', 3), isTrue);
      expect(await readChunks(db.chunks, 'x', 3, bytes.length), bytes);
    });

    test('a value written before close is read after reopening', () async {
      await db.chunks.put('k/0', _bytes(3));
      await db.thumbnails.put(_thumb('p1', rev: 7));
      await db.close();
      db = await reopen();
      expect(await db.chunks.get('k/0'), _bytes(3));
      expect((await db.thumbnails.get('p1'))!.contentRevision, 7);
    });

    test('a closed database refuses operations', () async {
      await db.close();
      await expectLater(db.chunks.get('k'), throwsStateError);
      await expectLater(db.chunks.put('k', _bytes(1)), throwsStateError);
      await expectLater(db.thumbnails.get('p1'), throwsStateError);
      await db.close(); // twice: no error
    });

    test('thumbnails: every field round trips; delete; totalBytes', () async {
      final store = db.thumbnails;
      expect(await store.get('p1'), isNull);
      expect(await store.totalBytes(), 0);
      await store.put(_thumb('p1', length: 10));
      await store.put(_thumb('p2', rev: 3, length: 25, mime: 'image/webp'));
      final t = (await store.get('p2'))!;
      expect(t.pageId, 'p2');
      expect(t.contentRevision, 3);
      expect(t.width, 120);
      expect(t.height, 160);
      expect(t.mimeType, 'image/webp');
      expect(t.bytes, _bytes(25, 3));
      expect(await store.totalBytes(), 35);
      await store.put(_thumb('p1', rev: 2, length: 4));
      expect((await store.get('p1'))!.bytes, _bytes(4, 2));
      expect(await store.totalBytes(), 29);
      await store.delete(['p1', 'missing']);
      await store.delete(const []);
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

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('note_core_fblob_'));
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  String root() => '${tmp.path}/assets';

  _sharedCases(
    'FileBlobDatabase',
    () => FileBlobDatabase.open(root()),
    () => FileBlobDatabase.open(root()),
  );

  late IdbFactory factory;
  _sharedCases('IdbBlobDatabase (same meaning — 1st round)', () async {
    factory = newIdbFactoryMemory();
    return IdbBlobDatabase(factory, 'noteapp_blobs');
  }, () async => IdbBlobDatabase(factory, 'noteapp_blobs'));

  group('FileBlobDatabase files (6.15.3)', () {
    test('open makes the missing root and its blobs / thumbs directories '
        '(nested)', () async {
      final r = '${tmp.path}/a/b/c';
      final db = await FileBlobDatabase.open(r);
      addTearDown(db.close);
      expect(Directory('$r/blobs').existsSync(), isTrue);
      expect(Directory('$r/thumbs').existsSync(), isTrue);
      // The write probe left nothing behind.
      expect(Directory('$r/blobs').listSync(), isEmpty);
      expect(Directory('$r/thumbs').listSync(), isEmpty);
    });

    test("layout: <dir>/blobs/<key> ('/' = subdirectories), "
        '<dir>/thumbs/<pageId>.bin with the 6.15.3 header', () async {
      final db = await FileBlobDatabase.open(root());
      addTearDown(db.close);
      await db.chunks.put('abc/000003', _bytes(6));
      await db.chunks.put('rd/d1/000012', _bytes(2));
      expect(File('${root()}/blobs/abc/000003').readAsBytesSync(), _bytes(6));
      expect(File('${root()}/blobs/rd/d1/000012').existsSync(), isTrue);
      await db.thumbnails.put(
        PageThumbnail(
          pageId: 'page-1',
          contentRevision: 0x01020304,
          width: 640,
          height: 480,
          mimeType: 'image/png',
          bytes: Uint8List.fromList([9, 8, 7]),
        ),
      );
      final file = File('${root()}/thumbs/page-1.bin').readAsBytesSync();
      final head = ByteData.sublistView(file);
      expect(head.getUint32(0, Endian.little), 0x01020304);
      expect(head.getUint32(4, Endian.little), 640);
      expect(head.getUint32(8, Endian.little), 480);
      expect(head.getUint16(12, Endian.little), 'image/png'.length);
      expect(String.fromCharCodes(file.sublist(14, 23)), 'image/png');
      expect(file.sublist(23), [9, 8, 7]);
    });

    test(
      'a page id with / or a leading dot stays one file in thumbs/',
      () async {
        final db = await FileBlobDatabase.open(root());
        addTearDown(db.close);
        for (final id in ['a/b', '../x', '.hidden', '%25']) {
          await db.thumbnails.put(_thumb(id, length: 3));
          expect((await db.thumbnails.get(id))!.pageId, id);
        }
        final names = _names('${root()}/thumbs');
        expect(names, hasLength(4));
        expect(names.every((n) => !n.startsWith('.')), isTrue);
        expect(Directory('${tmp.path}/x.bin').existsSync(), isFalse);
        expect(await db.thumbnails.totalBytes(), 12);
      },
    );

    test('atomic write: the value goes through a .<name>.tmp-* file in the '
        'same directory and replaces the old one whole', () async {
      final db = await FileBlobDatabase.open(root());
      addTearDown(db.close);
      await db.chunks.put('w/000000', _bytes(4 * _mib, 1));
      final dir = Directory('${root()}/blobs/w');
      final seen = <String>{};
      final watch = dir.watch().listen((e) => seen.add(e.path));
      await db.chunks.put('w/000000', _bytes(4 * _mib, 2));
      // Let the watcher deliver.
      await Future<void>.delayed(Duration.zero);
      await watch.cancel();
      expect(await db.chunks.get('w/000000'), _bytes(4 * _mib, 2));
      expect(_names(dir.path), ['000000']);
      // Only the temporary file of this write and the target were touched.
      for (final p in seen) {
        final name = p.substring(p.lastIndexOf('/') + 1);
        expect(
          name == '000000' ||
              (name.startsWith('.000000') && name.contains('.tmp-')),
          isTrue,
          reason: name,
        );
      }
    });

    test('put keeps the bytes of the call (the caller may reuse them, as '
        "with the browser's IndexedDB clone; idb_shim's memory store keeps the "
        'reference)', () async {
      final db = await FileBlobDatabase.open(root());
      addTearDown(db.close);
      final bytes = _bytes(8);
      final done = db.chunks.put('k/0', bytes);
      bytes.fillRange(0, 8, 0);
      await done;
      expect(await db.chunks.get('k/0'), _bytes(8));
    });

    test('a failed write leaves the old value and no temporary file', () async {
      final db = await FileBlobDatabase.open(root());
      addTearDown(db.close);
      await db.chunks.put('f/000000', _bytes(3));
      // A directory where the target file of another key must go: the rename fails.
      Directory('${root()}/blobs/f/000001').createSync(recursive: true);
      File('${root()}/blobs/f/000001/keep').writeAsBytesSync([1]);
      await expectLater(
        db.chunks.put('f/000001', _bytes(2)),
        throwsA(isA<FileSystemException>()),
      );
      expect(await db.chunks.get('f/000000'), _bytes(3));
      expect(_names('${root()}/blobs/f'), ['000000', '000001']);
      // The directory in the way is not a key.
      expect(await db.chunks.get('f/000001'), isNull);
    });

    test('open deletes temporary files an interrupted write left, keys never '
        'list them', () async {
      final db = await FileBlobDatabase.open(root());
      await db.chunks.put('t/000000', _bytes(3));
      await db.thumbnails.put(_thumb('p1'));
      await db.close();
      final left = [
        '${root()}/blobs/t/.000001.tmp-abc',
        '${root()}/blobs/.top.tmp-1',
        '${root()}/thumbs/.p2.bin.tmp-9',
      ];
      for (final p in left) {
        File(p).writeAsBytesSync([1, 2, 3]);
      }
      // A dot file that is not a temporary file stays (not ours, not a key).
      File('${root()}/blobs/.keep').writeAsBytesSync([1]);
      final again = await FileBlobDatabase.open(root());
      addTearDown(again.close);
      for (final p in left) {
        expect(File(p).existsSync(), isFalse, reason: p);
      }
      expect(File('${root()}/blobs/.keep').existsSync(), isTrue);
      expect(await again.chunks.keys(''), ['t/000000']);
      expect(await again.chunks.get('t/000000'), _bytes(3));
      expect(await again.thumbnails.totalBytes(), 10);
    });

    test(
      'keys never list dot names (a temporary file of a running write)',
      () async {
        final db = await FileBlobDatabase.open(root());
        addTearDown(db.close);
        await db.chunks.put('d/000000', _bytes(1));
        File('${root()}/blobs/d/.000001.tmp-x').writeAsBytesSync([1]);
        expect(await db.chunks.keys('d/'), ['d/000000']);
        expect(await db.chunks.keys(''), ['d/000000']);
      },
    );

    test('deletePrefix removes the directory and empty parents; delete of the '
        'last key removes its empty directories', () async {
      final db = await FileBlobDatabase.open(root());
      addTearDown(db.close);
      await db.chunks.put('si/pdf/x/0/t-1', _bytes(1));
      await db.chunks.put('si/pdf/y/0/t-1', _bytes(1));
      await db.chunks.delete('si/pdf/x/0/t-1');
      expect(Directory('${root()}/blobs/si/pdf/x').existsSync(), isFalse);
      expect(Directory('${root()}/blobs/si/pdf/y/0').existsSync(), isTrue);
      await db.chunks.deletePrefix('si/pdf/y/');
      expect(Directory('${root()}/blobs/si').existsSync(), isFalse);
      expect(Directory('${root()}/blobs').existsSync(), isTrue);
      await db.chunks.put('rd/d/000000', _bytes(1));
      await db.chunks.deletePrefix('rd/d/');
      expect(Directory('${root()}/blobs/rd').existsSync(), isFalse);
      await db.chunks.put('e/1', _bytes(1));
      await db.chunks.deletePrefix('');
      expect(Directory('${root()}/blobs').listSync(), isEmpty);
    });

    test('keys that cannot be files: put → ArgumentError, get null, '
        'delete / deletePrefix / keys touch nothing outside', () async {
      final db = await FileBlobDatabase.open(root());
      addTearDown(db.close);
      File('${tmp.path}/outside').writeAsBytesSync([1]);
      for (final bad in ['', '../outside', 'a//b', '.a', 'a/.tmp', r'a\b']) {
        await expectLater(
          db.chunks.put(bad, _bytes(1)),
          throwsArgumentError,
          reason: bad,
        );
        expect(await db.chunks.get(bad), isNull, reason: bad);
        await db.chunks.delete(bad);
      }
      await db.chunks.deletePrefix('../');
      await db.chunks.deletePrefix('../out');
      expect(await db.chunks.keys('../'), isEmpty);
      expect(await db.chunks.getMany(['../outside', 'none']), [null, null]);
      expect(File('${tmp.path}/outside').existsSync(), isTrue);
    });

    test(
      'a thumbnail field outside uint32 → ArgumentError before writing',
      () async {
        final db = await FileBlobDatabase.open(root());
        addTearDown(db.close);
        await expectLater(
          db.thumbnails.put(_thumb('p1', rev: -1)),
          throwsArgumentError,
        );
        expect(Directory('${root()}/thumbs').listSync(), isEmpty);
      },
    );

    test('a thumbnail file that is not one reads as no thumbnail', () async {
      final db = await FileBlobDatabase.open(root());
      addTearDown(db.close);
      File('${root()}/thumbs/p1.bin').writeAsBytesSync([1, 2, 3]);
      final bad = Uint8List(14);
      ByteData.sublistView(bad).setUint16(12, 500, Endian.little);
      File('${root()}/thumbs/p2.bin').writeAsBytesSync(bad);
      expect(await db.thumbnails.get('p1'), isNull);
      expect(await db.thumbnails.get('p2'), isNull);
      expect(await db.thumbnails.totalBytes(), 0);
    });

    test('operations run one at a time in call order (put then deletePrefix '
        'then put, not awaited in between)', () async {
      final db = await FileBlobDatabase.open(root());
      addTearDown(db.close);
      final a = db.chunks.put('o/000000', _bytes(2 * _mib));
      final b = db.chunks.deletePrefix('o/');
      final c = db.chunks.put('o/000001', _bytes(1));
      final d = db.chunks.keys('o/');
      await Future.wait([a, b, c]);
      expect(await d, ['o/000001']);
    });

    test('close waits for the operations already called', () async {
      final db = await FileBlobDatabase.open(root());
      final put = db.chunks.put('c/000000', _bytes(4 * _mib));
      await db.close();
      await put;
      expect(File('${root()}/blobs/c/000000').lengthSync(), 4 * _mib);
    });

    group('a root that cannot be used → FileSystemException', () {
      test('under a regular file', () async {
        File('${tmp.path}/file').writeAsBytesSync([1]);
        await expectLater(
          FileBlobDatabase.open('${tmp.path}/file/assets'),
          throwsA(isA<FileSystemException>()),
        );
      });

      test("'blobs' is a regular file", () async {
        Directory(root()).createSync();
        File('${root()}/blobs').writeAsBytesSync([1]);
        await expectLater(
          FileBlobDatabase.open(root()),
          throwsA(isA<FileSystemException>()),
        );
      });

      test('a read-only directory (where the system enforces it)', () async {
        final r = Directory('${tmp.path}/ro')..createSync();
        Directory('${r.path}/blobs').createSync();
        Directory('${r.path}/thumbs').createSync();
        final chmod = await Process.run('chmod', [
          '0555',
          r.path,
          '${r.path}/blobs',
          '${r.path}/thumbs',
        ]);
        expect(chmod.exitCode, 0);
        addTearDown(() => Process.runSync('chmod', ['-R', '0755', r.path]));
        if (_writable('${r.path}/blobs')) {
          markTestSkipped('this process writes into 0555 directories (root)');
          return;
        }
        await expectLater(
          FileBlobDatabase.open(r.path),
          throwsA(isA<FileSystemException>()),
        );
      });
    });
  });
}

/// The sorted names of the entries directly in [dir].
List<String> _names(String dir) => [
  for (final e in Directory(dir).listSync())
    e.path.substring(e.path.lastIndexOf('/') + 1),
]..sort();

/// Whether this process can make a file in [dir] despite its mode (root can).
bool _writable(String dir) {
  final f = File('$dir/.probe');
  try {
    f.writeAsBytesSync([1]);
    f.deleteSync();
    return true;
  } on FileSystemException {
    return false;
  }
}
