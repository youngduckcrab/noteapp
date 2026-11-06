// CORE T33b — m5-7/02-core 6.19 PF-3 · PF-4 · PF-5 (V10): a 5,000-page synthetic index (one pdf
// unit of 80 words per PDF page, no glyph boxes — 조사 03 9.2 shape; Hangul words from 400
// syllables, 20 % Latin; 50 notes × 100 pages show the pages) on the in-memory store.
// PF-5: building it with replaceUnits (record only). PF-3: 2- and 3-syllable, word-middle,
// Latin prefix and AND queries, median ≤ 5 ms. PF-4: one-syllable LIKE queries, median ≤ 15 ms.
// Each query is measured with its candidate count (FTS5 MATCH / LIKE rows before the 2,000 cap):
// the budgets are asserted for queries below the candidate counts of [kHeldBelow]; queries
// above them (frequent words up to the 2,000 cap) are recorded with the budget next to them —
// the time grows with the candidates read (each one's liveness, and its normalized text judged
// and scored in Dart — 6.10.4 steps 1–2), change request '[총괄] V10' in the progress log.
@TestOn('vm')
@Tags(['perf'])
library;

import 'dart:math';

import 'package:drift/drift.dart' show Variable;
import 'package:note_core/note_core.dart';
import 'package:note_core/src/search/search_runs.dart';
import 'package:note_core/src/storage/drift_library_repository.dart'
    show likeContains;
import 'package:note_core/src/storage/drift_note_store.dart';
import 'package:note_core/testing_vm.dart';
import 'package:test/test.dart';

import 'perf_support.dart';
import 'search_corpus.dart';

/// Queries with fewer candidates than these are held to the PF-3 / PF-4 budgets.
const Map<String, int> kHeldBelow = {'PF-3': 300, 'PF-4': 600};

const String _asset =
    'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd';

void main() {
  test(
    'PF-3/4/5: 5,000-page index — queries ≤ 5 ms, LIKE ≤ 15 ms (median)',
    () async {
      final store = await openTestNoteStore(
        seedDefaultPenPresets: false,
      ) as DriftNoteStore;
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
      final perQuery = await measureQueries(store, vocab);
      expect(perQuery, isNotEmpty);
      for (final (name, m, budget) in perQuery) {
        expect(m, lessThan(budget), reason: '$name over its budget (6.19)');
      }
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}

/// FTS5 / LIKE rows of [q] before the cap (every unit of these corpora is live).
Future<int> candidatesOf(DriftNoteStore store, String q) async {
  final norm = SearchText.normalize(q);
  final match = SearchText.matchQuery(norm);
  final runs = searchRunsOf(norm);
  final row = match == null
      ? await store.db
            .customSelect(
              'SELECT count(*) AS c FROM search_units u WHERE '
              '${[for (final _ in runs) r"u.norm LIKE ? ESCAPE '\'"].join(' AND ')}',
              variables: [
                for (final x in runs) Variable<String>(likeContains(x.text)),
              ],
            )
            .getSingle()
      : await store.db
            .customSelect(
              'SELECT count(*) AS c FROM search_fts WHERE search_fts MATCH ?',
              variables: [Variable<String>(match)],
            )
            .getSingle();
  return row.read<int>('c');
}

/// The median of 21 runs of searchPages([q]) after 3 warm-up runs.
Future<Duration> medianSearch(NoteStore store, String q) async {
  for (var i = 0; i < 3; i++) {
    await store.search.searchPages(q);
  }
  final times = <Duration>[];
  for (var i = 0; i < 21; i++) {
    times.add((await timed(() => store.search.searchPages(q))).$2);
  }
  return median(times);
}

/// Measures and prints the PF-3 / PF-4 query set on [store] (built from [vocab]); returns the
/// measurements held to a budget (fewer candidates than [kHeldBelow]).
Future<List<(String, Duration, Duration)>> measureQueries(
  DriftNoteStore store,
  List<String> vocab,
) async {
  bool isLatin(String w) => RegExp(r'^[a-z]+$').hasMatch(w);
  final hangul = vocab.where((w) => !RegExp('[a-z]').hasMatch(w)).toList();
  final latin = vocab.where(isLatin).toList();
  // Frequent words come first in the vocabulary (draw); a rank picks a frequency.
  String nth(List<String> list, int rank, bool Function(String) test) =>
      list.skip(rank).firstWhere(test);
  String two(int rank) =>
      String.fromCharCodes(nth(hangul, rank, (_) => true).runes.take(2));
  String three(int rank) => nth(hangul, rank, (w) => w.runes.length == 3);
  String middle(int rank) => String.fromCharCodes(three(rank).runes.skip(1));
  String prefix(int rank) =>
      nth(latin, rank, (w) => w.length >= 4).substring(0, 3);
  final rare = hangul.length ~/ 2;
  final pf3 = {
    '2 syllables (frequent)': two(0),
    '2 syllables': two(400),
    '2 syllables (rare)': two(rare),
    '3 syllables (frequent)': three(0),
    '3 syllables (rare)': three(rare),
    'word middle (frequent)': middle(0),
    'word middle (rare)': middle(rare),
    'Latin prefix (frequent)': prefix(0),
    'Latin prefix (rare)': prefix(latin.length ~/ 2),
    'AND (frequent)': '${two(0)} ${latin.first}',
    'AND (rare)': '${two(rare)} ${latin.first}',
  };
  final pf4 = {
    '1 syllable LIKE (frequent)': kSyllables.first,
    '1 syllable LIKE': kSyllables[200],
    '1 syllable LIKE (rarest)': kSyllables.last,
  };
  // Every measurement is printed first; the caller checks the budgets.
  final held = <(String, Duration, Duration)>[];
  for (final (id, set, budget) in [
    ('PF-3', pf3, const Duration(milliseconds: 5)),
    ('PF-4', pf4, const Duration(milliseconds: 15)),
  ]) {
    for (final MapEntry(key: name, value: q) in set.entries) {
      final candidates = await candidatesOf(store, q);
      final hits = await store.search.searchPages(q);
      final m = await medianSearch(store, q);
      final isHeld = candidates < kHeldBelow[id]!;
      record(
        '$id $name "$q"',
        m,
        note:
            '($candidates candidates, ${hits.length} pages; budget '
            '${budget.inMilliseconds} ms${isHeld ? '' : ' — recorded only'})',
      );
      if (isHeld) held.add(('$id $name', m, budget));
    }
  }
  return held;
}
