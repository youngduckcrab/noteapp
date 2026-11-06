// T16-v2 (integration stage 3 — 07-sync 6.7.2, 6.3): records of kinds an app does not know
// are held, not dropped, on real CORE. K1 a newer app's chunk [stroke, bookmark]: A applies
// the stroke, holds the bookmark, reports needsAppUpdate once; the cursor and the held-record
// keys are written in the stroke's applyRemote transaction — the values are there as soon as
// the stroke is, and the same after closing and opening the file again; after the restart
// the bookmark stays held and nothing new is reported. K2 an app before M7 (debugKnownKinds
// without handwriting) holds B's handwriting result of a mixed chunk (the stroke applies);
// the app update — the engine disposed, the same file opened again, every kind — re-applies
// it: A's result = B's, nothing held.
//
// CORE milestones (6.7.2 table): K1 runs now (strokes and the meta KV only); K2 needs T32
// (B's handwriting.put) and T28 (A's handwriting applyRemote).
@Tags(['integration'])
@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';
import 'package:sync_engine/src/codec/chunk_codec.dart';
import 'package:sync_engine/src/engine/meta_keys.dart';
import 'package:sync_engine/sync_engine.dart';

import '../support/local_writes.dart';
import '../support/raw_records.dart';
import 'support/core_sync_device.dart';

/// A bookmark record (a kind no app knows) on [pageId] of [noteId], versioned at [hlc].
Uint8List _bookmarkOf(String noteId, String pageId, Hlc hlc) => rawUpsertRecord(
  'bookmark',
  {'id': 'bm-1', 'noteId': noteId, 'pageId': pageId, 'label': '중요'},
  {'b': hlc.toString()},
);

void main() {
  coreScenario(
    'K1 [stroke, bookmark] from a newer app: the stroke applies, the '
    'bookmark is held, one needsAppUpdate; cursor and held keys commit with the '
    'stroke and survive reopening the file',
    (s) async {
      final a = await s.device('A');
      final note = (await a.store.library.createNote(title: 'K1')).id;
      final page = (await a.pageIdsOf(note)).single;
      await s.converge([a], [note]);
      final cursorBefore = await a.sync.readMeta(MetaKeys.cursor);

      const strokeRef = EntityRef(EntityKind.stroke, 's-newer-app');
      final writer = newerAppStore()
        ..localWrite([strokeWrite(strokeRef.id, page)]);
      final stroke = upsertOf(writer, strokeRef);
      s.server.commitRaw(kT16Uid, [
        newerAppChunk(
          [
            ChunkCodec.encodeRecord(stroke),
            _bookmarkOf(note, page, stroke.versions.max),
          ],
          scope: note,
          maxHlc: stroke.versions.max,
        ),
      ]);
      await s.until(
        'the stroke on A',
        () async => await a.read(strokeRef.kind, strokeRef.id) != null,
      );
      // One applyRemote transaction: the stroke, the cursor and the held-record keys.
      final cursor = await a.sync.readMeta(MetaKeys.cursor);
      final head = await a.sync.readMeta(MetaKeys.heldRecordParts.first);
      expect(cursor, isNotNull);
      expect(cursor, isNot(cursorBefore));
      expect(head, contains('bookmark'));
      await s.settle([a]);
      expect(a.engine.debug.heldRecords, 1);
      expect(a.engine.debug.heldRecordsMarked, isFalse);
      final issue = a.issue(SyncIssueCode.needsAppUpdate)!;
      expect(issue.count, 1);
      expect(issue.message, contains('bookmark'));
      expect((await a.store.content.loadPage(page)).strokes.map((s) => s.id), [
        strokeRef.id,
      ]);

      // The app restarts: the reopened file has the same cursor and held keys.
      final held = {
        for (final key in MetaKeys.heldRecordKeys)
          key: await a.sync.readMeta(key),
      };
      await a.restart(
        whileStopped: () async {
          expect(await a.sync.readMeta(MetaKeys.cursor), cursor);
          for (final MapEntry(:key, :value) in held.entries) {
            expect(await a.sync.readMeta(key), value, reason: key);
          }
        },
      );
      await s.settle([a]);
      expect(a.engine.debug.heldRecords, 1);
      expect(a.issue(SyncIssueCode.needsAppUpdate), isNull);
      expect(
        await a.sync.readMeta(MetaKeys.heldRecordParts.first),
        contains('bookmark'),
      );
      expect(await a.read(strokeRef.kind, strokeRef.id), isNotNull);
      await s.converge([a], [note]);
    },
  );

  coreScenario(
    'K2 an app before M7 holds B\'s handwriting result; after the app '
    'update (same file, every kind) A has B\'s result and holds nothing',
    (s) async {
      final a = await s.device('A', knownKinds: kKindsWithoutHandwriting);
      final b = await s.device('B');
      final note = (await b.store.library.createNote(title: 'K2')).id;
      final page = (await b.pageIdsOf(note)).single;
      await s.converge([a, b], [note]);

      final stroke = await b.core.addStroke(page, seed: 2);
      await b.core.putHandwriting(page, ['극한']);
      await s.until('A to hold the result', () async {
        if (!a.idle || !b.idle) return false;
        return a.engine.debug.heldRecords == 1;
      });
      expect(await a.read(EntityKind.stroke, stroke.id), isNotNull);
      expect(await a.store.handwriting.forPage(page), isNull);
      expect(a.issue(SyncIssueCode.needsAppUpdate), isNotNull);

      await a.restart();
      await s.until(
        'the result on A',
        () async => await a.store.handwriting.forPage(page) != null,
      );
      await s.converge([a, b], [note]);
      expect(
        (await a.store.handwriting.forPage(page))!.toJson(),
        (await b.store.handwriting.forPage(page))!.toJson(),
      );
      expect(a.engine.debug.reappliedRecords, 1);
      expect(a.engine.debug.heldRecords, 0);
      expect(a.issue(SyncIssueCode.needsAppUpdate), isNull);
    },
  );
}
