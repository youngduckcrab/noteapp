// m5-7/02-core T25b — V7 in Chrome (6.12.3, contract 7.7.2 V7): the V7 fixture (a v1 database
// written by the 1st-round CORE code; the rollback-journal copy noteapp_v1_web.sqlite) becomes
// the initial bytes of a new web database in the drift web worker (the test hook of
// connect_browser.dart — WasmDatabase.open initializeDatabase), the PDF bytes are put in the
// blob IndexedDB under their 1st-round key, and the store opens it the way openNoteStore does
// (same executor, DriftNoteStore.open). Checks ①②③⑤ are the VM ones
// (test/shared/v7_fixture_checks.dart); ④′ here: the web copy is the canonical dump in the blob
// store (db/v1-backup/…, meta last) whose sha256 is fullDumpSha256. The fixture files come
// from tool/prepare_web_test.dart (test/web/fixtures_v1/, fetched relative to the test page).
// Prints the upgrade time (PF-8 Chrome — recorded), the same upgrade without the copy step, and
// the reopen times with the copy and after deleting it (6.12.4 'web cost').
// ignore_for_file: avoid_print
@TestOn('browser')
library;

import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show Variable, driftRuntimeOptions;
import 'package:idb_shim/idb_browser.dart';
import 'package:note_core/dev_tools.dart';
import 'package:note_core/note_core.dart';
import 'package:note_core/src/assets/idb_blob_store.dart';
import 'package:note_core/src/storage/connect/connect_browser.dart';
import 'package:note_core/src/storage/db/canonical_dump.dart';
import 'package:note_core/src/storage/db/note_database.dart';
import 'package:note_core/src/storage/drift_note_store.dart';
import 'package:note_core/src/storage/v1_copy/v1_copy.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

import '../shared/v7_fixture_checks.dart';
import 'web_store_support.dart';

/// A V7 fixture file copied next to the tests by tool/prepare_web_test.dart.
Future<Uint8List> _fixture(String name) async {
  final url = 'fixtures_v1/$name';
  final web.Response response;
  try {
    response = await web.window.fetch(url.toJS).toDart;
  } on Object catch (e) {
    fail('$url could not be fetched ($e)');
  }
  if (!response.ok) {
    fail(
      '$url: HTTP ${response.status}. Run `dart run tool/prepare_web_test.dart` in '
      'packages/note_core first (ws test --platform chrome runs it).',
    );
  }
  return (await response.arrayBuffer().toDart).toDart.asUint8List();
}

Future<int> _ms(Future<void> Function() body) async {
  final sw = Stopwatch()..start();
  await body();
  return sw.elapsedMilliseconds;
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late V7Manifest m;
  late Uint8List dbBytes;
  late Uint8List pdfBytes;

  setUpAll(() async {
    m = V7Manifest.parse(utf8.decode(await _fixture('manifest.json')));
    dbBytes = await _fixture('noteapp_v1_web.sqlite');
    pdfBytes = await _fixture('pdf_asset.pdf');
  });

  /// A fresh web database whose first open starts from the fixture bytes, the PDF bytes
  /// already in its blob IndexedDB (1st-round key format).
  Future<NoteStoreConfig> freshFixture(String tag) async {
    final config = freshWebConfig(tag, clock: v7Clock());
    dropAfterTest(config);
    final blobs = IdbBlobDatabase(
      idbFactoryBrowser,
      config.web.blobDatabaseName,
    );
    for (final e in m.blobEntries) {
      await blobs.chunks.put(
        e.key,
        Uint8List.fromList(
          Uint8List.sublistView(pdfBytes, e.offset, e.offset + e.bytes),
        ),
      );
    }
    await blobs.close();
    return config;
  }

  /// The store of [config] as openNoteStore opens it (same executor and blob IndexedDB);
  /// [initial]: the fixture bytes for a database that does not exist yet.
  Future<DriftNoteStore> openStore(
    NoteStoreConfig config, {
    bool initial = false,
    bool withCopy = true,
  }) async {
    final (executor, info) = await openNoteDatabaseExecutor(
      config,
      // A copy each time: drift transfers the buffer to the worker (it is detached here).
      initialDatabaseBytes: initial ? () => Uint8List.fromList(dbBytes) : null,
    );
    return DriftNoteStore.open(
      executor: executor,
      storageInfo: info,
      config: config,
      blobFactory: blobIdbFactory(config),
      databaseFactory: withCopy ? null : (e, _) => NoteDatabase(e),
    );
  }

  test('the fixture files are the ones of the manifest', () {
    final files = m.json['files']! as Map<String, Object?>;
    expect(
      sha256.convert(dbBytes).toString(),
      (files['noteapp_v1_web.sqlite']! as Map<String, Object?>)['sha256'],
    );
    expect(sha256.convert(pdfBytes).toString(), m.pdfAssetId);
  });

  test('the web store upgrades the fixture: ①②③, ④′ the blob dump copy, ⑤, '
      'a reopened store is the same; reopen times with and without the copy', () async {
    final config = await freshFixture('v7');
    late DriftNoteStore store;
    final upgradeMs = await _ms(() async {
      store = await openStore(config, initial: true);
    });
    var closed = false;
    addTearDown(() async {
      if (!closed) await store.close();
    });

    // ①②③
    await expectV7Upgraded(store, m);

    // ④′ the copy: chunks then meta under db/v1-backup/, the joined chunks are the
    // canonical dump of the fixture.
    final blobs = store.blobs.chunks;
    final keys = await blobs.keys(kV1CopyBlobPrefix);
    expect(keys.last, kV1CopyMetaKey);
    final chunkKeys = keys.sublist(0, keys.length - 1);
    expect(chunkKeys, [
      for (var i = 0; i < chunkKeys.length; i++) v1CopyChunkKey(i),
    ]);
    final joined = BytesBuilder();
    for (final k in chunkKeys) {
      joined.add((await blobs.get(k))!);
    }
    final dump = joined.takeBytes();
    expect(dump.length, m.fullDumpBytes);
    expect(sha256.convert(dump).toString(), m.fullDumpSha256);
    final meta = jsonDecode(
      utf8.decode((await blobs.get(kV1CopyMetaKey))!),
    ) as Map<String, Object?>;
    expect(meta['sha256'], m.fullDumpSha256);
    expect(meta['bytes'], m.fullDumpBytes);
    expect(meta['chunkCount'], chunkKeys.length);
    expect(meta['format'], kCanonicalDumpHeader);
    final record = await v7CopyRecord(store);
    expect(record['method'], 'dump');
    expect(record['bytes'], m.fullDumpBytes);
    expect(record['normalOpens'], 1);
    final info = (await v1DatabaseCopyInfo(store))!;
    expect(info.fileName, 'noteapp-v1-backup.sql.txt');
    expect(info.bytes, m.fullDumpBytes);
    expect(info.failure, isNull);
    final read = (await readV1DatabaseCopy(store).toList()).expand((c) => c);
    expect(sha256.convert(read.toList()).toString(), m.fullDumpSha256);

    // Where the copy step's time goes (6.12.4 'web cost' — T24 left the split to here): the
    // dump queries and lines through the worker, the sha256, the blob put — each again on
    // the upgraded store (the v1 tables with their v1 columns are the same rows).
    late Uint8List again1;
    final dumpMs = await _ms(() async {
      again1 = await canonicalDump(
        (sql, args) async => [
          for (final r
              in await store.db
                  .customSelect(
                    sql,
                    variables: [for (final a in args) Variable<Object>(a)],
                  )
                  .get())
            r.data.values.first! as String,
        ],
        tables: m.v1Tables,
        columns: {for (final t in m.v1Tables) t: m.columnsOf(t)},
      );
    });
    expect(again1.length, greaterThan(0));
    final hashMs = await _ms(() async => sha256.convert(again1));
    final putMs = await _ms(
      () => store.blobs.chunks.put('probe/000000', again1),
    );
    await store.blobs.chunks.delete('probe/000000');

    // ⑤
    final made = await exerciseV7Store(store, m, pdfBytes);
    final state = await v7StateSha(store);
    await store.close();
    closed = true;

    late DriftNoteStore again;
    final withCopyMs = await _ms(() async {
      again = await openStore(config);
    });
    expect(await v7StateSha(again), state);
    await expectV7Made(again, made);
    expect((await v7CopyRecord(again))['normalOpens'], 2);
    expect(
      await again.blobs.chunks.get(kV1CopyMetaKey),
      utf8.encode(jsonEncode(meta)),
    );
    final deleteMs = await _ms(() => deleteV1DatabaseCopy(again));
    expect(await again.blobs.chunks.keys(kV1CopyBlobPrefix), isEmpty);
    await again.close();

    late DriftNoteStore last;
    final withoutCopyMs = await _ms(() async {
      last = await openStore(config);
    });
    expect(await v7StateSha(last), state);
    expect(await v1DatabaseCopyInfo(last), isNull);
    await last.close();

    // The same upgrade without the copy step (a second fresh database).
    final bareConfig = await freshFixture('v7bare');
    late DriftNoteStore bare;
    final bareMs = await _ms(() async {
      bare = await openStore(bareConfig, initial: true, withCopy: false);
    });
    expect(await v1DatabaseCopyInfo(bare), isNull);
    await bare.close();

    print(
      '[V7 web] backend ${store.storageInfo.backend.name}; fixture '
      '${dbBytes.length} B, dump ${dump.length} B in ${chunkKeys.length} chunk(s); '
      'PF-8 (Chrome, recorded): upgrade open with the copy $upgradeMs ms, without the '
      'copy step $bareMs ms; reopen with the copy $withCopyMs ms; delete the copy '
      '$deleteMs ms; reopen without it $withoutCopyMs ms; copy step parts again on the '
      'open store: dump queries + lines $dumpMs ms, sha256 $hashMs ms, blob put '
      '$putMs ms',
    );
  }, timeout: const Timeout(Duration(minutes: 4)));
}
