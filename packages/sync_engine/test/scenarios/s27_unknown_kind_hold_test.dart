// S27 (07-sync 6.7.1, 6.3 — S-13): records of kinds an app does not know are held, not
// dropped. (a) A chunk [stroke, bookmark]: the stroke applies, the bookmark is held, one
// needsAppUpdate, the cursor moves on, the overlap re-receive adds nothing. (b) An old app
// (no handwriting) applies the stroke of a mixed chunk and holds the result; the app update
// (restart with every kind) re-applies it; a second restart right after (original chunk in
// the overlap) changes nothing; the bookmark stays held. (c) A small total cap that a chunk
// crosses in its middle: that chunk is not stored at all but marked; the update rewinds,
// re-applies the stored chunk and receives both again → every result. (d) The old app's
// compaction leaves the chunks with held kinds; a new device D gets the result. (e) The
// re-applied result is K1-held (writer 48 h ahead) while its original chunk is compacted
// away; once due it applies from sync.heldRecords (sync.held never used). (f) A corrupt
// held part → every kind rewound after the update → the result arrives.
import 'dart:convert';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';
import 'package:sync_engine/src/codec/chunk_codec.dart';
import 'package:sync_engine/src/codec/chunk_id.dart';
import 'package:sync_engine/src/engine/engine_controller.dart';
import 'package:sync_engine/src/engine/held_records.dart';
import 'package:sync_engine/src/engine/meta_keys.dart';
import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';

import '../support/local_writes.dart';
import '../support/raw_records.dart';
import 'support/scenario_checks.dart';
import 'support/sync_scenario.dart';

const String _uid = 'user-1';
const String _writer = 'c5c5c5c5c5c5c5c5';

final Set<EntityKind> noHandwriting = EntityKind.values.toSet()
  ..remove(EntityKind.handwriting);

SyncIssue? issueOf(TestDevice d, SyncIssueCode code) {
  for (final i in d.engine.status.issues) {
    if (i.code == code) return i;
  }
  return null;
}

/// A delta chunk of encoded [records] by [_writer] in [scope].
ChunkWrite rawChunk(
  List<Uint8List> records, {
  required String scope,
  required Hlc maxHlc,
}) {
  final payload = ChunkCodec.assemble(records);
  return ChunkWrite(
    id: chunkIdOf(_writer, payload),
    scope: scope,
    authorNodeId: _writer,
    recordCount: records.length,
    format: ChunkCodec.formatVersion,
    kind: ChunkKind.delta,
    maxHlc: maxHlc.toString(),
    payload: payload,
  );
}

/// A bookmark record (a kind no app knows) on [pageId] of [noteId], versioned at [hlc].
Uint8List bookmarkOf(String id, String noteId, String pageId, Hlc hlc) =>
    rawUpsertRecord(
      'bookmark',
      {'id': id, 'noteId': noteId, 'pageId': pageId, 'label': '중요'},
      {'b': hlc.toString()},
    );

/// Commits a chunk with one bookmark in [noteId]'s scope; returns its id.
String commitBookmark(SyncTestHarness h, String noteId, String pageId) {
  final hlc = Hlc(h.serverClock.now().millisecondsSinceEpoch, 0, _writer);
  final chunk = rawChunk(
    [bookmarkOf('bm-1', noteId, pageId, hlc)],
    scope: noteId,
    maxHlc: hlc,
  );
  h.server.commitRaw(_uid, [chunk]);
  return chunk.id;
}

/// Chunks of [scope] on the server, oldest first.
List<RemoteChunk> scopeChunks(SyncTestHarness h, String scope) => [
  for (final s in h.server.chunksOf(_uid))
    if (s.chunk.scope == scope) s.chunk,
];

List<String> linesOf(SyncDoc? doc) => [
  for (final line in doc!.json['lines']! as List)
    (line as Map)['text']! as String,
];

void main() {
  syncScenario('S27 (a) [stroke, bookmark]: stroke applied, bookmark held, '
      'one needsAppUpdate, cursor on; the overlap re-receive adds nothing', (
    h,
  ) {
    final a = h.device('A');
    final note = a.createNote('S27a');
    final page = a.pageIdsOf(note).single;
    h.settle();
    final cursorBefore = a.store.meta[MetaKeys.cursor];
    final writer = FakeLocalStore(
      nodeId: _writer,
      clock: h.serverClock,
      ownerId: _uid,
    )..localWrite([strokeWrite('s-raw', page)]);
    final stroke = UpsertRecord.fromVersioned(
      writer.rows[const EntityRef(EntityKind.stroke, 's-raw')]!,
    );
    h.server.commitRaw(_uid, [
      rawChunk(
        [
          ChunkCodec.encodeRecord(stroke),
          bookmarkOf('bm-1', note, page, stroke.versions.max),
        ],
        scope: note,
        maxHlc: stroke.versions.max,
      ),
    ]);
    h.settle();
    expect(strokeOn(a, 's-raw'), isNotNull);
    expect(a.engine.debug.heldRecords, 1);
    expect(a.engine.debug.heldRecordsMarked, isFalse);
    expect(a.store.meta[MetaKeys.heldRecordParts.first], contains('bookmark'));
    final issue = issueOf(a, SyncIssueCode.needsAppUpdate)!;
    expect(issue.count, 1);
    expect(issue.message, contains('bookmark'));
    expect(a.store.meta[MetaKeys.cursor], isNot(cursorBefore));
    final cursor = a.store.meta[MetaKeys.cursor];

    // Reconnect (same session: the LRU skips the chunk), then an app restart (new
    // session): the catch-up overlap (cursor − 5 min) decodes the chunk again — the
    // stroke is kept, the bookmark is already held, nothing new is reported.
    a
      ..goOffline()
      ..goOnline();
    h.settle();
    expect(a.engine.debug.heldRecords, 1);
    expect(issueOf(a, SyncIssueCode.needsAppUpdate)!.count, 1);
    h.restart('A');
    h.settle();
    expect(a.engine.status.phase, SyncPhase.live);
    expect(a.engine.debug.recordsKept, greaterThan(0), reason: 'decoded again');
    expect(a.engine.debug.heldRecords, 1);
    expect(issueOf(a, SyncIssueCode.needsAppUpdate), isNull);
    expect(a.store.meta[MetaKeys.cursor], cursor);
    h.checkConverged([a]);
  });

  syncScenario('S27 (b) old app holds a handwriting result of a mixed chunk; '
      'the update re-applies it, a second restart changes nothing, the '
      'bookmark stays held', (h) {
    final a = h.device('A', knownKinds: noHandwriting);
    final b = h.device('B');
    final note = b.createNote('S27b');
    final page = b.pageIdsOf(note).single;
    h.settle();
    commitBookmark(h, note, page);
    h.settle();
    expect(a.engine.debug.heldRecords, 1);
    expect(b.engine.debug.heldRecords, 1, reason: 'no app knows bookmark');

    final stroke = b.addStroke(page);
    b.putHandwriting(page, ['극한']);
    final before = scopeChunks(h, note).length;
    h.settle();
    expect(scopeChunks(h, note), hasLength(before + 1), reason: 'one chunk');
    expect(strokeOn(a, stroke), isNotNull);
    expect(a.handwritingOf(page), isNull);
    expect(a.engine.debug.heldRecords, 2);
    h.checkConverged([a, b], kinds: noHandwriting);

    h.restart('A');
    h.settle();
    expect(a.handwritingOf(page)!.json, b.handwritingOf(page)!.json);
    expect(a.engine.debug.reappliedRecords, 1);
    expect(a.engine.debug.heldRecords, 1, reason: 'the bookmark');
    expect(a.store.meta[MetaKeys.heldRecordParts.first], contains('bookmark'));
    h.checkConverged([a, b]);

    // Right after the update: restart again; the original chunk is inside the overlap.
    h.restart('A');
    h.settle();
    expect(a.engine.debug.reappliedRecords, 0, reason: 'nothing left to apply');
    expect(a.engine.debug.heldRecords, 1);
    expect(a.handwritingOf(page)!.json, b.handwritingOf(page)!.json);
    h.checkConverged([a, b]);
  });

  syncScenario('S27 (c) a small cap crossed in the middle of chunk C2: C2 is '
      'only marked; the update rewinds and every result arrives', (h) {
    final a = h.device('A', knownKinds: noHandwriting, signedIn: false);
    final b = h.device('B');
    final note = b.createNote('S27c', pages: 4);
    final pages = b.pageIdsOf(note);
    for (final p in pages) {
      b.addStroke(p);
    }
    h.settle();
    b.putHandwriting(pages[0], ['C1 결과']);
    h.settle();
    final c1 = scopeChunks(h, note).last;
    h.elapse(const Duration(seconds: 1));
    for (final p in pages.skip(1)) {
      b.putHandwriting(p, ['C2 결과 $p']);
    }
    h.settle();
    final c2 = scopeChunks(h, note).last;
    expect(c2.recordCount, 3);

    // A cap that holds C1's record and not one more entry (07-sync 6.3.2: all or nothing
    // per chunk — C2's first record would still fit).
    final oldNames = {for (final k in noHandwriting) k.name};
    final probe = HeldRecords(knownKinds: oldNames)
      ..add(
        c1,
        ChunkCodec.decodeTolerant(
          c1.payload,
          isKnownKind: oldNames.contains,
        ).unknown,
      );
    final text = probe.encode();
    final one = text.values.fold(0, (n, v) => n + utf8.encode(v).length);
    final entry =
        text[MetaKeys.heldRecordParts.first]!.length -
        HeldRecords.emptyPartBytes;
    EngineController.of(a.engine).debugHeldRecordsLimits = (
      maxPartBytes: HeldRecords.defaultMaxPartBytes,
      maxTotalBytes: one + entry ~/ 2 + entry,
    );
    a.auth.setUser(const AuthUser(uid: _uid));
    h.settle();
    expect(a.engine.status.phase, SyncPhase.live);
    expect(a.engine.debug.heldRecords, 1, reason: 'C1 stored');
    expect(a.engine.debug.heldRecordsMarked, isTrue, reason: 'C2 marked');
    expect(a.store.meta[MetaKeys.heldRecordParts.first], contains(c1.id));
    expect(
      a.store.meta[MetaKeys.heldRecordParts.first],
      isNot(contains(c2.id)),
    );
    for (final p in pages) {
      expect(a.handwritingOf(p), isNull);
    }
    h.checkConverged([a, b], kinds: noHandwriting);

    h.restart('A');
    h.settle();
    expect(a.engine.debug.reappliedChunks, 1, reason: 'C1, out of the LRU');
    for (final p in pages) {
      expect(a.handwritingOf(p)!.json, b.handwritingOf(p)!.json, reason: p);
    }
    expect(a.engine.debug.heldRecords, 0);
    expect(a.engine.debug.heldRecordsMarked, isFalse);
    h.checkConverged([a, b]);
  });

  syncScenario('S27 (d) the old app compacts: chunks with held kinds stay; a '
      'new device gets the handwriting result', (h) {
    final a = h.device(
      'A',
      knownKinds: noHandwriting,
      config: const SyncConfig(
        compaction: CompactionConfig(
          minChunksPerScope: 4,
          startJitterMax: Duration.zero,
        ),
      ),
    );
    final b = h.device(
      'B',
      config: const SyncConfig(compaction: CompactionConfig(enabled: false)),
    );
    final note = b.createNote('S27d');
    final page = b.pageIdsOf(note).single;
    h.settle();
    for (var i = 0; i < 3; i++) {
      b.addStroke(page, seed: i);
      h.settle();
    }
    b.addStroke(page, seed: 9);
    b.putHandwriting(page, ['연속']);
    h.settle();
    final mixed = scopeChunks(h, note).last;
    final bookmark = commitBookmark(h, note, page);
    final before = scopeChunks(h, note);
    expect(before.length, greaterThanOrEqualTo(6));

    elapseUntil(
      h,
      () => scopeChunks(h, note).any((c) => c.kind == ChunkKind.snapshot),
      max: const Duration(minutes: 5),
    );
    h.settle();
    final after = scopeChunks(h, note);
    final snapshots = [
      for (final c in after)
        if (c.kind == ChunkKind.snapshot) c,
    ];
    expect(snapshots, isNotEmpty);
    expect(
      snapshots.every((c) => c.authorNodeId == a.store.sync.deviceNodeId),
      isTrue,
    );
    expect(
      {for (final c in after) c.id},
      containsAll([mixed.id, bookmark]),
      reason: 'chunks with records A does not know stay',
    );
    expect(after.length, lessThan(before.length));

    final d = h.device('D');
    h.settle();
    expect(linesOf(d.handwritingOf(page)), ['연속']);
    expect(d.engine.debug.heldRecords, 1, reason: 'the bookmark');
    h.checkConverged([b, d]);
    h.checkConverged([a, b, d], kinds: noHandwriting);
  });

  syncScenario('S27 (e) the re-applied result is K1-held while its original '
      'chunk is compacted away; it applies from sync.heldRecords once due', (
    h,
  ) {
    final a = h.device(
      'A',
      knownKinds: noHandwriting,
      config: const SyncConfig(compaction: CompactionConfig(enabled: false)),
    );
    // B accepts records up to 72 h ahead, so it applies the result at once and can
    // compact the scope while A still holds it.
    final b = h.device(
      'B',
      config: const SyncConfig(
        clockSkewLimit: Duration(hours: 72),
        compaction: CompactionConfig(
          minChunksPerScope: 3,
          startJitterMax: Duration.zero,
        ),
      ),
    );
    final note = b.createNote('S27e');
    final page = b.pageIdsOf(note).single;
    h.settle();
    // A writer whose clock is 48 h ahead sends the handwriting result of the page.
    final writer = FakeLocalStore(
      nodeId: _writer,
      clock: Clock(() => h.serverClock.now().add(const Duration(hours: 48))),
      ownerId: _uid,
    )..localWrite([handwritingWrite(page, note, text: '미래')]);
    final record = UpsertRecord.fromVersioned(
      writer.rows[EntityRef(
        EntityKind.handwriting,
        HandwritingText.idFor(page),
      )]!,
    );
    final c1 = rawChunk(
      [ChunkCodec.encodeRecord(record)],
      scope: note,
      maxHlc: record.versions.max,
    );
    h.server.commitRaw(_uid, [c1]);
    h.settle();
    expect(a.engine.debug.heldRecords, 1);
    expect(linesOf(b.handwritingOf(page)), ['미래']);
    // B's third chunk of the scope makes it due; B compacts it, C1 included.
    b.addStroke(page);
    h.settle();
    elapseUntil(
      h,
      () => !scopeChunks(h, note).any((c) => c.id == c1.id),
      max: const Duration(minutes: 5),
    );
    h.settle();
    expect(
      scopeChunks(h, note).where((c) => c.kind == ChunkKind.snapshot),
      isNotEmpty,
    );
    expect(a.engine.debug.heldRecords, 1, reason: 'the snapshot copy: a dup');
    // A later chunk, past the catch-up overlap: the attach after the update does not
    // receive the snapshot again (the held record is the only way in).
    h.elapse(const Duration(minutes: 10));
    a.createNote('later');
    h.settle();

    h.restart('A');
    h.settle();
    expect(a.engine.status.phase, SyncPhase.live);
    expect(a.engine.debug.reappliedChunks, 1);
    expect(a.engine.debug.reappliedRecords, 0, reason: 'K1');
    expect(a.engine.debug.heldRecords, 1, reason: 'kept with ra');
    expect(a.engine.debug.heldChunks, 0, reason: 'not in sync.held');
    expect(a.handwritingOf(page), isNull);

    h.elapse(const Duration(hours: 25));
    h.settle();
    expect(linesOf(a.handwritingOf(page)), ['미래']);
    expect(a.engine.debug.reappliedRecords, 1);
    expect(a.engine.debug.heldRecords, 0);
    expect(a.engine.debug.heldChunks, 0);
    h.checkConverged([a, b]);
  });

  syncScenario('S27 (f) a corrupt held part: the update rewinds every kind and '
      'the result arrives', (h) {
    final a = h.device('A', knownKinds: noHandwriting);
    final b = h.device('B');
    final note = b.createNote('S27f');
    final page = b.pageIdsOf(note).single;
    b.addStroke(page);
    b.putHandwriting(page, ['손상']);
    h.settle();
    expect(a.engine.debug.heldRecords, 1);
    // Later chunks: the handwriting is no longer inside the overlap of A's cursor.
    h.elapse(const Duration(minutes: 10));
    b.createNote('later');
    h.settle();
    h.run(
      a.store.sync.writeMeta({MetaKeys.heldRecordParts.first: '{"p":1,"r":['}),
    );

    h.restart('A');
    h.settle();
    expect(linesOf(a.handwritingOf(page)), ['손상']);
    expect(a.engine.debug.heldRecords, 0);
    expect(a.engine.debug.heldRecordsMarked, isFalse);
    expect(a.store.meta[MetaKeys.heldRecordParts.first] ?? '', isEmpty);
    h.checkConverged([a, b]);
  });
}
