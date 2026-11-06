// m5-7/02-core T25b — V7 on the VM (6.12.3, contract 7.7.2 V7): the V7 fixture (a v1 database
// written by the 1st-round CORE code, test/fixtures/db_v1) copied to a temporary directory and
// opened by openNoteStore as the native app opens it — a file database plus file blobs (T35),
// the PDF bytes already in the 1st-round blob key format. Checks ①②③⑤ are shared with Chrome
// (test/shared/v7_fixture_checks.dart); ④ here: the copy '<path>-v1-backup' is a v1 SQLite
// file (user_version 1) whose canonical dump is fullDumpSha256, and the kv record says so.
// Reopening keeps everything (the copy too) and counts one more normal open.
@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:note_core/dev_tools.dart';
import 'package:note_core/note_core.dart';
import 'package:note_core/src/storage/db/canonical_dump.dart';
import 'package:note_core/src/storage/drift_note_store.dart';
import 'package:note_core/src/storage/v1_copy/v1_copy_file.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:test/test.dart';

import '../shared/v7_fixture_checks.dart';

const String _fixtureDir = 'test/fixtures/db_v1';

/// The canonical dump of the SQLite file [path] (opened read-only).
Future<Uint8List> _fileDump(String path) async {
  final db = sqlite.sqlite3.open(path, mode: sqlite.OpenMode.readOnly);
  try {
    return await canonicalDump(
      (sql, args) async => [
        for (final r in db.select(sql, args)) r.values.first! as String,
      ],
    );
  } finally {
    db.close();
  }
}

int _userVersion(String path) {
  final db = sqlite.sqlite3.open(path, mode: sqlite.OpenMode.readOnly);
  try {
    return db.userVersion;
  } finally {
    db.close();
  }
}

void main() {
  late Directory tmp;
  late V7Manifest m;
  late Uint8List pdfBytes;
  late NoteStoreConfig config;
  late String dbPath;

  setUpAll(() {
    m = V7Manifest.parse(File('$_fixtureDir/manifest.json').readAsStringSync());
    pdfBytes = File('$_fixtureDir/pdf_asset.pdf').readAsBytesSync();
  });

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('note_core_v7_');
    dbPath = '${tmp.path}/noteapp.db';
    File('$_fixtureDir/noteapp_v1.sqlite').copySync(dbPath);
    final blobRoot = '${tmp.path}/assets';
    // The PDF bytes in the 1st-round chunk keys (<assetId>/000000), as files (6.15.3).
    for (final e in m.blobEntries) {
      File('$blobRoot/blobs/${e.key}')
        ..createSync(recursive: true)
        ..writeAsBytesSync(
          Uint8List.sublistView(pdfBytes, e.offset, e.offset + e.bytes),
        );
    }
    config = NoteStoreConfig(
      nativeDatabasePath: dbPath,
      nativeAssetDirectoryPath: blobRoot,
      clock: v7Clock(),
    );
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('the fixture files are the ones of the manifest', () {
    expect(
      sha256.convert(File(dbPath).readAsBytesSync()).toString(),
      ((m.json['files']! as Map<String, Object?>)['noteapp_v1.sqlite']!
          as Map<String, Object?>)['sha256'],
    );
    expect(sha256.convert(pdfBytes).toString(), m.pdfAssetId);
  });

  test('openNoteStore (file database + file blobs) upgrades the fixture: '
      '①–⑤, and a reopened store is the same', () async {
    final store = await openNoteStore(config) as DriftNoteStore;
    var closed = false;
    addTearDown(() async {
      if (!closed) await store.close();
    });
    expect(store.storageInfo.backend, StorageBackend.nativeFile);

    // ①②③
    await expectV7Upgraded(store, m);

    // ④ the copy next to the database file: a v1 SQLite file of the fixture's dump.
    final copyPath = v1CopyPathOf(dbPath);
    expect(File(copyPath).existsSync(), isTrue);
    expect(File(v1CopyTempPathOf(dbPath)).existsSync(), isFalse);
    expect(_userVersion(copyPath), 1);
    final copyDump = await _fileDump(copyPath);
    expect(copyDump.length, m.fullDumpBytes);
    expect(sha256.convert(copyDump).toString(), m.fullDumpSha256);
    final record = await v7CopyRecord(store);
    expect(record['method'], 'vacuum');
    expect(record['bytes'], File(copyPath).lengthSync());
    expect(record['normalOpens'], 1);
    final info = (await v1DatabaseCopyInfo(store))!;
    expect(info.fileName, 'noteapp-v1-backup.sqlite');
    expect(info.bytes, File(copyPath).lengthSync());
    expect(info.failure, isNull);
    final read = BytesBuilder();
    await readV1DatabaseCopy(store).forEach(read.add);
    expect(read.takeBytes(), File(copyPath).readAsBytesSync());

    // ⑤
    final made = await exerciseV7Store(store, m, pdfBytes);
    final state = await v7StateSha(store);
    final copyFileSha = sha256
        .convert(File(copyPath).readAsBytesSync())
        .toString();
    await store.close();
    closed = true;

    final again = await openNoteStore(config) as DriftNoteStore;
    addTearDown(again.close);
    expect(await v7StateSha(again), state);
    await expectV7Made(again, made);
    expect(
      sha256.convert(File(copyPath).readAsBytesSync()).toString(),
      copyFileSha,
    );
    final after = await v7CopyRecord(again);
    expect(after['normalOpens'], 2);
    expect(after['createdAt'], record['createdAt']);
    expect(after['bytes'], record['bytes']);
  });

  test('the trashed note of the fixture stays in the trash (fixed clock: not '
      'yet 30 days)', () async {
    final store = await openNoteStore(config);
    addTearDown(store.close);
    final trashed = await store.trash.watchTrash().first;
    expect(trashed.map((t) => t.name), ['지난 메모']);
    // The auto purge of openNoteStore finds nothing due on this clock.
    expect(await store.trash.purgeExpired(), 0);
  });
}
