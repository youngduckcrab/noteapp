// CORE T33b — m5-7/02-core 6.19 PF-10w (6.10.7, contract 7.4.5 · V10): the real web store
// (drift WasmDatabase in the worker — the IndexedDB file system reads the whole database into
// memory when it opens) reopened before and after a real-shape 500-page PDF index (Korean —
// the largest of PF-10's three, search_corpus.dart, the same seed): the reopen time may grow by
// at most 300 ms (7.4.5 target). openNoteStore + the first library listing, median of 5 each.
// The measured times and the load are printed (the record of this test — a failure is kept
// with its load, 1차 9.1). Run with
//   flutter test --platform chrome --run-skipped -t perf test/web/search_reopen_time_browser_test.dart
// ignore_for_file: avoid_print
@TestOn('browser')
@Tags(['perf'])
library;

import 'dart:math';

import 'package:note_core/note_core.dart';
import 'package:test/test.dart';

import '../perf/search_corpus.dart';
import 'web_store_support.dart';

const String _asset =
    'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee';

/// 7.4.5: the 500-page index adds at most this much to the reopen time.
const int kReopenBudgetMs = 300;

/// openNoteStore + the first watchListing value, in milliseconds.
Future<(NoteStore, int)> _timedOpen(NoteStoreConfig config) async {
  final sw = Stopwatch()..start();
  final store = await openNoteStore(config);
  await store.library.watchListing(const LibraryQuery()).first;
  sw.stop();
  return (store, sw.elapsedMilliseconds);
}

/// The median of five reopen times of [config].
Future<int> _medianReopen(NoteStoreConfig config) async {
  final times = <int>[];
  for (var i = 0; i < 5; i++) {
    final (store, ms) = await _timedOpen(config);
    times.add(ms);
    await store.close();
  }
  print('[perf] web reopen times: $times ms');
  return (times..sort())[2];
}

void main() {
  test('PF-10w: reopen time grows by ≤ 300 ms with a 500-page real-shape index', () async {
    final config = freshWebConfig('pf10w', seedDefaultPenPresets: false);
    dropAfterTest(config);
    const pages = 500;

    final (first, _) = await _timedOpen(config);
    await pdfLibrary(first, _asset, pages: pages);
    await first.flush();
    await first.close();
    final without = await _medianReopen(config);

    final (store, _) = await _timedOpen(config);
    final r = Random(21);
    final vocab = vocabulary(r, latinShare: 0);
    final index = Stopwatch()..start();
    for (var i = 0; i < pages; i++) {
      final text = pageText(r, vocab, 2500);
      await store.search.replaceUnits(SearchSource.pdf, '$_asset#$i', [
        SearchUnitDraft(
          body: text,
          rects: glyphBoxes(text),
          pdfPageAspect: 595 / 842,
        ),
      ], sourceRev: '$_asset:1');
    }
    await store.flush();
    index.stop();
    final q = String.fromCharCodes(
      vocab.firstWhere((w) => !RegExp('[a-z]').hasMatch(w)).runes.take(2),
    );
    final query = Stopwatch()..start();
    final hits = await store.search.searchPages(q);
    query.stop();
    expect(hits, hasLength(100));
    await store.close();
    final withIndex = await _medianReopen(config);

    print('[perf] web PF-10w index 500 pages: ${index.elapsedMilliseconds} ms');
    print(
      '[perf] web PF-10w first query "$q" (100 pages): '
      '${query.elapsedMilliseconds} ms (record only)',
    );
    print(
      '[perf] web PF-10w reopen without index $without ms, with index '
      '$withIndex ms (+${withIndex - without} ms; budget +$kReopenBudgetMs ms)',
    );
    expect(withIndex - without, lessThanOrEqualTo(kReopenBudgetMs));
  }, timeout: const Timeout(Duration(minutes: 20)));
}
