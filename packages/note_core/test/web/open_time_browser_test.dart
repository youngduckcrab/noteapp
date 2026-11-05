// CORE T16 — first-open time of the real web store (6.18, 7.3; INFRA boot time limit):
// openNoteStore (worker + wasm load, schema, kv, presets, persist() ≤ 1 s) and the
// first library query, on an empty database and on one with 10,000 strokes. Record
// only (9.1 performance table: Chrome rows have no budget); run with
//   flutter test --platform chrome --run-skipped -t perf test/web/open_time_browser_test.dart
// The measured times are printed (the record of this test).
// ignore_for_file: avoid_print
@TestOn('browser')
@Tags(['perf'])
library;

import 'package:note_core/dev_tools.dart';
import 'package:note_core/note_core.dart';
import 'package:test/test.dart';

import 'web_store_support.dart';

/// openNoteStore + the first watchListing value, in milliseconds.
Future<(NoteStore, int)> _timedOpen(NoteStoreConfig config) async {
  final sw = Stopwatch()..start();
  final store = await openNoteStore(config);
  await store.library.watchListing(const LibraryQuery()).first;
  sw.stop();
  return (store, sw.elapsedMilliseconds);
}

void main() {
  test('openNoteStore: empty database, then 10,000 strokes (record)', () async {
    final config = freshWebConfig('open_time', requestPersistentStorage: true);
    dropAfterTest(config);

    final (empty, emptyMs) = await _timedOpen(config);
    final info = empty.storageInfo;
    final seed = Stopwatch()..start();
    final noteId = await seedSyntheticNote(
      empty,
      pages: 50,
      strokesPerPage: 200,
      pointsPerStroke: 100,
    );
    await empty.flush();
    seed.stop();
    await empty.close();

    final reopenMs = <int>[];
    for (var i = 0; i < 3; i++) {
      final (store, ms) = await _timedOpen(config);
      reopenMs.add(ms);
      if (i == 2) {
        final session = await store.openSession(noteId);
        final page = Stopwatch()..start();
        final content = await session.openPage(session.pages.first.id);
        page.stop();
        expect(content.strokes, hasLength(200));
        print(
          '[perf] web openPage (200 strokes): ${page.elapsedMilliseconds} ms',
        );
        await session.close();
      }
      await store.close();
    }
    print('[perf] web storage: $info');
    print('[perf] web openNoteStore empty DB: $emptyMs ms');
    print(
      '[perf] web seed 10,000 strokes (50 x 200, 100 points): '
      '${seed.elapsedMilliseconds} ms',
    );
    print('[perf] web openNoteStore with 10,000 strokes: $reopenMs ms');
  }, timeout: const Timeout(Duration(minutes: 15)));
}
