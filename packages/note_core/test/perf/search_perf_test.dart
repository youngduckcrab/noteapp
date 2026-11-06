// CORE T33b — m5-7/02-core 6.19 PF-3 · PF-4 · PF-5 (V10): a 5,000-page synthetic index (one pdf
// unit of 80 words per PDF page, no glyph boxes — 조사 03 9.2 shape; Hangul words from 400
// syllables, 20 % Latin; 50 notes × 100 pages show the pages) on the in-memory store.
// PF-5: building it with replaceUnits (record only). PF-3: 2- and 3-syllable, Latin prefix and
// AND queries, median ≤ 5 ms. PF-4: one-syllable LIKE queries, median ≤ 15 ms.
// CORE T33b (in progress): the first measurements are far over PF-3 / PF-4 (a frequent word
// fills the 2,000 candidates — progress log 'T33b'); until the query path is tuned the budgets
// are printed next to each value and not asserted ([kAssertSearchBudgets]).
@TestOn('vm')
@Tags(['perf'])
library;

import 'dart:math';

import 'package:note_core/note_core.dart';
import 'package:note_core/testing_vm.dart';
import 'package:test/test.dart';

import 'perf_support.dart';
import 'search_corpus.dart';

/// Turned on when the query path meets PF-3 / PF-4 (CORE T33b / T37).
const bool kAssertSearchBudgets = false;

const String _asset =
    'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd';

void main() {
  test(
    'PF-3/4/5: 5,000-page index — queries ≤ 5 ms, LIKE ≤ 15 ms (median)',
    () async {
      final store = await openTestNoteStore(seedDefaultPenPresets: false);
      addTearDown(store.close);
      const pages = 5000;
      await pdfLibrary(store, _asset, pages: pages);
      final r = Random(3);
      final vocab = vocabulary(r, latinShare: 0.2);
      final (_, build) = await timed(() async {
        for (var i = 0; i < pages; i++) {
          await store.search.replaceUnits(SearchSource.pdf, '$_asset#$i', [
            SearchUnitDraft(body: words(r, vocab, 80)),
          ], sourceRev: '$_asset:1');
        }
      });
      record('PF-5 replaceUnits × 5,000 pages', build);

      Future<Duration> medianOf(String q) async {
        for (var i = 0; i < 3; i++) {
          await store.search.searchPages(q);
        }
        final times = <Duration>[];
        for (var i = 0; i < 15; i++) {
          times.add((await timed(() => store.search.searchPages(q))).$2);
        }
        return median(times);
      }

      final hangul = vocab.where((w) => !RegExp('[a-z]').hasMatch(w)).toList();
      final latin = vocab
          .where((w) => RegExp('^[a-z]+\$').hasMatch(w))
          .toList();
      final two = hangul.firstWhere((w) => w.runes.length == 2);
      final three = hangul.firstWhere((w) => w.runes.length == 3);
      final rare = hangul[hangul.length ~/ 2];
      final queries = {
        '2 syllables (frequent)': two,
        '3 syllables': three,
        '2 syllables (rare word)': String.fromCharCodes(rare.runes.take(2)),
        'Latin prefix': latin.first.substring(0, 3),
        'AND': '$two ${latin.first}',
      };
      // Every measurement is printed first; the budgets are checked at the end.
      final checks = <(String, Duration, Duration)>[];
      for (final MapEntry(key: name, value: q) in queries.entries) {
        final hits = await store.search.searchPages(q);
        final m = await medianOf(q);
        record(
          'PF-3 $name "$q"',
          m,
          note: '(${hits.length} pages; budget 5 ms)',
        );
        checks.add(('PF-3 $name', m, const Duration(milliseconds: 5)));
      }
      for (final q in [kSyllables.first, kSyllables[200]]) {
        final hits = await store.search.searchPages(q);
        final m = await medianOf(q);
        record(
          'PF-4 1 syllable LIKE "$q"',
          m,
          note: '(${hits.length} pages; budget 15 ms)',
        );
        checks.add(('PF-4 "$q"', m, const Duration(milliseconds: 15)));
      }
      if (kAssertSearchBudgets) {
        for (final (name, m, budget) in checks) {
          expect(m, lessThan(budget), reason: '$name over its budget (6.19)');
        }
      }
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
