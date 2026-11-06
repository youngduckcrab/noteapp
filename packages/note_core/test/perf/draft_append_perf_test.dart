// CORE T31 — PF-7 (m5-7/02-core 6.19): one recording draft append of 8 KiB (the chunk blob
// and the row commit) on a file database, median ≤ 10 ms on the VM. The Chrome figure (≤ 30 ms,
// recorded) is in test/web/recording_draft_browser_test.dart. (v2, m5-7 T35) Twice: the test
// file store (in-memory IndexedDB blobs) and the native store of openNoteStore (file blobs —
// the chunk is a flushed file and a rename, 6.15.3).
@TestOn('vm')
@Tags(['perf'])
library;

import 'dart:typed_data';

import 'package:note_core/note_core.dart';
import 'package:test/test.dart';

import 'perf_support.dart';

void main() {
  for (final (name, open) in <(String, Future<NoteStore> Function())>[
    (
      'test file store',
      () async => openFileStore(await tempDatabasePath('draft')),
    ),
    ('native file blobs', () => openNativeFileStore('draft')),
  ]) {
    test(
      'PF-7 ($name): draft append (8 KiB) → durable: median ≤ 10 ms',
      () async {
        final store = await open();
        final note = await store.library.createNote(title: 'draft');
        final draft = await store.recordingDrafts.begin(
          recordingId: 'rec-perf',
          noteId: note.id,
          mimeType: 'audio/webm',
          startedAt: 0,
        );
        final chunk = Uint8List.fromList(
          List.generate(8 * 1024, (i) => i % 251),
        );
        final times = <Duration>[];
        for (var i = 0; i < 110; i++) {
          final sw = Stopwatch()..start();
          await store.recordingDrafts.append(
            draft.draftId,
            chunk,
            activeMs: (i + 1) * 1000,
          );
          sw.stop();
          if (i < 10) continue; // warm-up
          times.add(sw.elapsed);
        }
        record(
          'PF-7 draft append 8 KiB, $name (median of 100)',
          median(times),
          budget: const Duration(milliseconds: 10),
        );
        expect(
          (await store.recordingDrafts.listDrafts()).single.chunkCount,
          110,
        );
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );
  }
}
