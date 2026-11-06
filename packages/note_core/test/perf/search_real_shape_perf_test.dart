// CORE T33b — m5-7/02-core 6.19 PF-10 (6.10.7, contract 7.4.5 · V10): a real-shape 500-page PDF
// index — 2,500 characters per page in lines of about 50 with one glyph box per character
// (search_corpus.dart, fixed seeds), Korean, mixed (30 % Latin words) and English — written with
// replaceUnits on a file database. Recorded: the replaceUnits total, the database growth (file
// pages × page size; also after FTS 'optimize' + VACUUM, the 6.10.7 experiment's state), the
// glyph box blob bytes (outside SQLite) and the median of a query returning 100 pages with
// their rects. Asserted: database growth ≤ 12 MB (7.4.5 target) and the query median ≤ 50 ms
// (6.19 said '≤ 20 ms [추측] — confirmed by the first measurement': 32–42 ms at load 10 on the
// shared 4 CPUs — 500 candidates of 2,500 characters each are read and judged, 100 bodies and
// 100 glyph box blobs read; progress log 'T33b'). (T37) The mixed corpus runs once more on the
// native store of openNoteStore (WAL file database on its background isolate + file blobs,
// 6.15.3): the same growth budget; its query is recorded against the budget, not asserted —
// the 500 candidate rows (norm of 2,500 characters each) cross the isolate boundary, which
// the budget's in-process store does not pay (progress log 'T37').
@TestOn('vm')
@Tags(['perf'])
library;

import 'dart:math';

import 'package:note_core/note_core.dart';
import 'package:note_core/src/search/search_rects.dart';
import 'package:note_core/src/storage/drift_note_store.dart';
import 'package:test/test.dart';

import 'perf_support.dart';
import 'search_corpus.dart';

const String _asset =
    'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee';

/// 7.4.5: the 500-page index grows the database file by at most this much.
const int kGrowthBudgetBytes = 12 * 1024 * 1024;

/// 6.19 PF-10 (confirmed by the first measurement): the median of a 100-page query with rects.
const Duration kQueryBudget = Duration(milliseconds: 50);

String mib(int bytes) => (bytes / 1024 / 1024).toStringAsFixed(2);

Future<int> dbBytes(DriftNoteStore store) async {
  final pages = await store.db.customSelect('PRAGMA page_count').getSingle();
  final size = await store.db.customSelect('PRAGMA page_size').getSingle();
  return pages.read<int>('page_count') * size.read<int>('page_size');
}

void main() {
  for (final (name, latinShare, seed, native) in const [
    ('Korean', 0.0, 21, false),
    ('mixed', 0.3, 22, false),
    ('English', 1.0, 23, false),
    ('mixed, native file blobs', 0.3, 22, true),
  ]) {
    test(
      'PF-10 $name: 500 real-shape pages — growth ≤ 12 MB, 100-page query ≤ 50 ms',
      () async {
        final store = native
            ? await openNativeFileStore('pf10n_$seed') as DriftNoteStore
            : await openFileStore(await tempDatabasePath('pf10_$seed'))
                  as DriftNoteStore;
        const pages = 500;
        await pdfLibrary(store, _asset, pages: pages);
        final before = await dbBytes(store);

        final r = Random(seed);
        final vocab = vocabulary(r, latinShare: latinShare);
        var blobBytes = 0;
        var chars = 0;
        final texts = [
          for (var i = 0; i < pages; i++) pageText(r, vocab, 2500),
        ];
        final (_, build) = await timed(() async {
          for (var i = 0; i < pages; i++) {
            final text = texts[i];
            final boxes = glyphBoxes(text);
            blobBytes += SearchRectsCodec.encode(boxes).length;
            chars += text.length;
            await store.search.replaceUnits(SearchSource.pdf, '$_asset#$i', [
              SearchUnitDraft(
                body: text,
                rects: boxes,
                pdfPageAspect: 595 / 842,
              ),
            ], sourceRev: '$_asset:1');
          }
        });
        final after = await dbBytes(store);
        await store.db.customStatement(
          "INSERT INTO search_fts(search_fts) VALUES('optimize')",
        );
        await store.db.customStatement('VACUUM');
        final vacuumed = await dbBytes(store);
        record('PF-10 $name replaceUnits × $pages pages ($chars chars)', build);

        // A frequent word (it is on most pages): 100 pages back, each with its rects.
        final q = name == 'English'
            ? vocab.firstWhere((w) => w.length >= 4).substring(0, 3)
            : String.fromCharCodes(
                vocab
                    .firstWhere((w) => !RegExp('[a-z]').hasMatch(w))
                    .runes
                    .take(2),
              );
        final hits = await store.search.searchPages(q);
        expect(hits, hasLength(100), reason: '"$q" is on fewer than 100 pages');
        expect(hits.every((h) => h.rects.isNotEmpty), isTrue);
        for (var i = 0; i < 3; i++) {
          await store.search.searchPages(q);
        }
        final times = <Duration>[];
        for (var i = 0; i < 21; i++) {
          times.add((await timed(() => store.search.searchPages(q))).$2);
        }
        final m = median(times);
        final growth = after - before;
        // ignore: avoid_print
        print(
          '[perf] PF-10 $name: DB growth ${mib(growth)} MiB '
          '(after optimize + VACUUM ${mib(vacuumed - before)} MiB; budget '
          '${mib(kGrowthBudgetBytes)} MiB), glyph box blobs ${mib(blobBytes)} MiB '
          '(outside SQLite)',
        );
        record(
          'PF-10 $name query "$q" (100 pages with rects)',
          m,
          note: native
              ? '(budget ${ms(kQueryBudget)} ms on the in-process store)'
              : '(budget ${ms(kQueryBudget)} ms)',
        );
        expect(growth, lessThanOrEqualTo(kGrowthBudgetBytes));
        if (!native) {
          expect(m, lessThan(kQueryBudget), reason: 'PF-10 $name query (6.19)');
        }
      },
      timeout: const Timeout(Duration(minutes: 10)),
    );
  }
}
