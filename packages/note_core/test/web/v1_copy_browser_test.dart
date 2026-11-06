// CORE T24 — the web v1 copy (m5-7/02-core 6.12.4, C22-02) on the real web store: a v1
// database in the drift web worker (drift's generated schema_v1 + synthetic rows) upgraded by
// openNoteStore → the canonical dump in the blob IndexedDB under db/v1-backup/, meta written
// last; joined chunks = the dump of the v1 database (sha256 in meta); a copy cut before its
// meta is replaced; dev_tools.dart read / delete. Prints the 'first day' times (6.12.4): copy
// (upgrade open), reopen with the copy, reopen after deleting it.
// The 'first day' times are printed for the progress log.
// ignore_for_file: avoid_print
@TestOn('browser')
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:idb_shim/idb_browser.dart';
import 'package:note_core/dev_tools.dart';
import 'package:note_core/note_core.dart';
import 'package:note_core/src/assets/idb_blob_store.dart';
import 'package:note_core/src/storage/connect/connect_browser.dart';
import 'package:note_core/src/storage/db/canonical_dump.dart';
import 'package:note_core/src/storage/drift_note_store.dart';
import 'package:note_core/src/storage/v1_copy/v1_copy.dart';
import 'package:test/test.dart';

import '../shared/v1_database.dart';
import 'web_store_support.dart';

/// Creates the synthetic v1 database under [config]'s name; returns its canonical dump.
/// [bulkStrokes]: that many more strokes of 257 point bytes (about the V7 fixture's size).
Future<Uint8List> _createV1(
  NoteStoreConfig config, {
  int bulkStrokes = 0,
}) async {
  final (executor, _) = await openNoteDatabaseExecutor(config);
  final bulk =
      'INSERT INTO strokes (id, page_id, note_id, tool, color_argb, width, opacity, '
      'pressure_sensitivity, pressure_curve, smoothing, style_extras_json, points, '
      'point_count, min_x, min_y, max_x, max_y, recording_id, recording_offset_ms, '
      'created_at, updated_at, deleted_at, version, field_versions) '
      "SELECT 'b' || x, 'p1', 'n1', 'ballpoint', 4279900698, 1.6, 1.0, 1.0, "
      "'0.25,0.25,0.75,0.75', 0.5, NULL, randomblob(257), 30, 0.0, 0.0, 1.0, 1.0, "
      "NULL, NULL, 1792972980000, 1792972980000, NULL, '$kV1Hlc', NULL FROM "
      '(WITH RECURSIVE c(x) AS (SELECT 1 UNION ALL SELECT x + 1 FROM c '
      'WHERE x < $bulkStrokes) SELECT x FROM c)';
  return createV1Database(
    executor,
    statements: [...syntheticV1Rows(), if (bulkStrokes > 0) bulk],
  );
}

Future<int> _ms(Future<void> Function() body) async {
  final sw = Stopwatch()..start();
  await body();
  return sw.elapsedMilliseconds;
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test('upgrade: the dump in the blob store, meta last; read; delete; reopen times', () async {
    final config = freshWebConfig('v1copy');
    dropAfterTest(config);
    final v1Dump = await _createV1(config, bulkStrokes: 2000);

    late DriftNoteStore store;
    final upgradeMs = await _ms(() async {
      store = await openWebStoreWithNode(config, kV1Node) as DriftNoteStore;
    });
    expect(store.db.schemaVersion, 2);
    final blobs = store.blobs.chunks;
    final keys = await blobs.keys(kV1CopyBlobPrefix);
    expect(keys, [v1CopyChunkKey(0), kV1CopyMetaKey]);
    final meta = jsonDecode(
      utf8.decode((await blobs.get(kV1CopyMetaKey))!),
    ) as Map<String, Object?>;
    expect(meta['bytes'], v1Dump.length);
    expect(meta['chunkCount'], 1);
    expect(meta['format'], kCanonicalDumpHeader);
    expect(meta['sha256'], sha256.convert(v1Dump).toString());
    final joined = (await readV1DatabaseCopy(store).toList()).expand((c) => c);
    expect(joined.toList(), v1Dump);
    final info = await v1DatabaseCopyInfo(store);
    expect(info!.fileName, 'noteapp-v1-backup.sql.txt');
    expect(info.bytes, v1Dump.length);
    expect(info.normalOpens, 1);
    expect(info.failure, isNull);
    await store.close();

    late NoteStore reopened;
    final withCopyMs = await _ms(() async {
      reopened = await openWebStoreWithNode(config, kV1Node);
    });
    expect((await v1DatabaseCopyInfo(reopened))!.normalOpens, 2);
    final deleteMs = await _ms(() => deleteV1DatabaseCopy(reopened));
    expect(await v1DatabaseCopyInfo(reopened), isNull);
    expect(
      await (reopened as DriftNoteStore).blobs.chunks.keys(kV1CopyBlobPrefix),
      isEmpty,
    );
    await reopened.close();
    final withoutCopyMs = await _ms(() async {
      reopened = await openWebStoreWithNode(config, kV1Node);
    });
    await reopened.close();
    // 6.12.4 'first day' check (progress log): 2,005 strokes of 257 point bytes, about the
    // V7 fixture's 2,000 (the fixture itself is T25b's).
    print(
      'v1 copy (web): dump ${v1Dump.length} B; upgrade open with the copy $upgradeMs ms; '
      'reopen with the copy $withCopyMs ms; delete $deleteMs ms; '
      'reopen without $withoutCopyMs ms',
    );
  });

  test('a copy cut before its meta is replaced by the upgrade', () async {
    final config = freshWebConfig('v1cut');
    dropAfterTest(config);
    final v1Dump = await _createV1(config);
    final blobDb = IdbBlobDatabase(
      idbFactoryBrowser,
      config.web.blobDatabaseName,
    );
    await blobDb.chunks.put(v1CopyChunkKey(0), Uint8List.fromList([1, 2, 3]));
    await blobDb.chunks.put(v1CopyChunkKey(5), Uint8List.fromList([4]));
    await blobDb.close();

    final store = await openWebStoreWithNode(config, kV1Node) as DriftNoteStore;
    addTearDown(store.close);
    expect(await store.blobs.chunks.keys(kV1CopyBlobPrefix), [
      v1CopyChunkKey(0),
      kV1CopyMetaKey,
    ]);
    final joined = (await readV1DatabaseCopy(store).toList()).expand((c) => c);
    expect(joined.toList(), v1Dump);
  });
}
