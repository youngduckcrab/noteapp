// CORE T31 — the draft store on the REAL web store (m5-7/02-core 6.7, V16 CORE part): 120
// chunks → close → reopen under the same name → listDrafts / readAll the same; a row deleted
// (a row not yet durable when the tab closed) is rebuilt from the meta, also after a reopen;
// 30 minutes of chunks (1,800 × 8 KiB ≈ 14 MB) → readAll → AssetStore.put, time and
// performance.memory recorded (M-4 — one result buffer); PF-7 append median recorded
// (Chrome ≤ 30 ms is a record, not a budget). The printed lines are the record of the run.
// ignore_for_file: avoid_print
@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:note_core/note_core.dart';
import 'package:note_core/src/storage/db/note_database.dart';
import 'package:note_core/src/storage/drift_note_store.dart';
import 'package:note_core/testing_web.dart';
import 'package:test/test.dart';

var _serial = 0;
String _name(String tag) =>
    'core_t31_${tag}_${DateTime.now().microsecondsSinceEpoch}_${_serial++}';

Uint8List _chunk(int n, int seed) =>
    Uint8List.fromList(List.generate(n, (i) => (i + seed) % 251));

/// performance.memory.usedJSHeapSize in MB (Chrome only), or null.
String _heapMb() {
  final perf = globalContext['performance'] as JSObject?;
  final mem = perf?['memory'] as JSObject?;
  final used = (mem?['usedJSHeapSize'] as JSNumber?)?.toDartDouble;
  return used == null ? 'n/a' : (used / (1024 * 1024)).toStringAsFixed(1);
}

void main() {
  late String name;

  Future<DriftNoteStore> open() async =>
      await openWebTestNoteStore(name) as DriftNoteStore;

  setUp(() => name = _name('drafts'));
  tearDown(() => deleteWebTestNoteStore(name));

  test(
    '120 chunks → close → reopen: listDrafts and readAll the same',
    () async {
      final store = await open();
      final note = await store.library.createNote(title: 'drafts');
      final draft = await store.recordingDrafts.begin(
        recordingId: 'rec-web',
        noteId: note.id,
        mimeType: 'audio/webm',
        startedAt: 1000,
      );
      final writes = [
        for (var i = 0; i < 120; i++)
          store.recordingDrafts.append(
            draft.draftId,
            _chunk(64 + i, i),
            activeMs: (i + 1) * 1000,
          ),
      ];
      await Future.wait(writes);
      final listed = await store.recordingDrafts.listDrafts();
      final bytes = await store.recordingDrafts.readAll(draft.draftId);
      expect(listed.single.chunkCount, 120);
      expect(bytes, hasLength(listed.single.bytes));
      await store.close();

      final again = await open();
      expect(await again.recordingDrafts.listDrafts(), listed);
      expect(await again.recordingDrafts.readAll(draft.draftId), bytes);
      await again.close();
    },
  );

  test('a deleted row is rebuilt from the meta (updatedAt = startedAt), also '
      'after a reopen', () async {
    final store = await open();
    final note = await store.library.createNote(title: 'drafts');
    final draft = await store.recordingDrafts.begin(
      recordingId: 'rec-web',
      noteId: note.id,
      mimeType: 'audio/webm',
      startedAt: 777,
    );
    await store.recordingDrafts.append(
      draft.draftId,
      _chunk(300, 1),
      activeMs: 1000,
    );
    await (store.db.delete(
      store.db.recordingDrafts,
    )..where((t) => t.draftId.equals(draft.draftId))).go();
    final rebuilt = (await store.recordingDrafts.listDrafts()).single;
    expect((rebuilt.updatedAt, rebuilt.activeMs), (777, 0));
    expect((rebuilt.chunkCount, rebuilt.bytes), (1, 300));
    await store.close();
    final again = await open();
    expect(await again.recordingDrafts.listDrafts(), [rebuilt]);
    await again.close();
  });

  test('PF-7 (record): 100 appends of 8 KiB, median', () async {
    final store = await open();
    final note = await store.library.createNote(title: 'drafts');
    final draft = await store.recordingDrafts.begin(
      recordingId: 'rec-web',
      noteId: note.id,
      mimeType: 'audio/webm',
      startedAt: 0,
    );
    final chunk = _chunk(8 * 1024, 3);
    final times = <int>[];
    for (var i = 0; i < 110; i++) {
      final sw = Stopwatch()..start();
      await store.recordingDrafts.append(
        draft.draftId,
        chunk,
        activeMs: (i + 1) * 1000,
      );
      sw.stop();
      if (i >= 10) times.add(sw.elapsedMicroseconds);
    }
    times.sort();
    print(
      '[perf] PF-7 Chrome draft append 8 KiB median of 100: '
      '${(times[times.length ~/ 2] / 1000).toStringAsFixed(2)} ms '
      '(record; ≤ 30 ms)',
    );
    await store.close();
  });

  test('30 minutes of chunks → readAll → AssetStore.put (time and memory '
      'recorded)', () async {
    final store = await open();
    final note = await store.library.createNote(title: 'drafts');
    final draft = await store.recordingDrafts.begin(
      recordingId: 'rec-web',
      noteId: note.id,
      mimeType: 'audio/webm',
      startedAt: 0,
    );
    // 1,800 one-second chunks of 8 KiB (64 kbps), written as append's step ① writes them;
    // the row then says what the appends would have left.
    const count = 1800, size = 8 * 1024;
    final fill = Stopwatch()..start();
    for (var i = 0; i < count; i++) {
      await store.recordingDrafts.blobs.put(
        'rd/${draft.draftId}/${i.toString().padLeft(6, '0')}',
        _chunk(size, i),
      );
    }
    await store.queue.run(
      (tx) =>
          (store.db.update(
            store.db.recordingDrafts,
          )..where((t) => t.draftId.equals(draft.draftId))).write(
            RecordingDraftsCompanion(
              chunkCount: const Value(count),
              bytes: const Value(count * size),
            ),
          ),
    );
    fill.stop();
    final before = _heapMb();
    final read = Stopwatch()..start();
    final bytes = await store.recordingDrafts.readAll(draft.draftId);
    read.stop();
    final afterRead = _heapMb();
    expect(bytes, hasLength(count * size));
    expect(bytes.sublist(size, size + 3), _chunk(3, 1));
    final put = Stopwatch()..start();
    final asset = await store.assets.put(
      bytes,
      type: AssetType.audio,
      mimeType: 'audio/webm',
    );
    put.stop();
    expect(asset.size, count * size);
    print(
      '[perf] 30 min draft (1,800 × 8 KiB = ${count * size} B): fill '
      '${fill.elapsedMilliseconds} ms, readAll ${read.elapsedMilliseconds} ms, '
      'AssetStore.put ${put.elapsedMilliseconds} ms; usedJSHeapSize MB before '
      '$before, after readAll $afterRead, after put ${_heapMb()} (record)',
    );
    await store.close();
  }, timeout: const Timeout(Duration(minutes: 5)));
}
