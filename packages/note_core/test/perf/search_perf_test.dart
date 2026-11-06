// CORE T33b — m5-7/02-core 6.19 PF-3 · PF-4 · PF-5 (contract 7.7.2 V10): a 5,000-page synthetic
// index (one pdf unit of 80 words per PDF page, no glyph boxes — 조사 03 9.2 shape; Hangul words
// from 400 syllables, 20 % Latin; 50 notes × 100 pages show the pages) on the in-memory store.
// PF-5: building it with replaceUnits (record only). PF-3: 2- and 3-syllable, word-middle,
// Latin prefix and AND queries, median ≤ 5 ms. PF-4: one-syllable LIKE queries, median ≤ 15 ms.
// Each query is measured with its candidate count (FTS5 MATCH / LIKE rows before the 2,000 cap).
//
// Two tests judge the same measurements (taken once, in setUpAll):
// - 'V10 as written' holds every query of the set to its budget — the contract text holds
//   until a change is approved (7.4.9). This design does not meet it for frequent words: the
//   time grows with the candidates read (each one's liveness, and its normalized text judged
//   and scored in Dart — 6.10.4 steps 1–2, the same judgement as the fake — CP-14): 20 to 46 ms
//   with 1,000 to 5,000 candidates (load 5 to 9). So this test fails until 총괄 rules on change
//   request CP-18 (plan 12.1; progress log '[총괄] V10'). It is the PF-3 / PF-4 completion
//   judgement (plan 10장 #1), at load < 4 (plan 9.1).
// - 'CP-18 as proposed' holds the queries with fewer candidates than [kHeldBelow] to the same
//   budgets and every other query to [kProposedOtherBudget] — the budget the change request
//   proposes, kept as a regression guard meanwhile. It is not the V10 judgement.
// ignore_for_file: avoid_print
@TestOn('vm')
@Tags(['perf'])
@Timeout(Duration(minutes: 10))
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

/// The V10 budgets as written (6.19 PF-3 · PF-4).
const Map<String, Duration> kBudget = {
  'PF-3': Duration(milliseconds: 5),
  'PF-4': Duration(milliseconds: 15),
};

/// CP-18 (pending): queries with fewer candidates than these keep [kBudget] …
const Map<String, int> kHeldBelow = {'PF-3': 300, 'PF-4': 600};

/// … and every other query (up to the 2,000-candidate cap) is held to this.
const Duration kProposedOtherBudget = Duration(milliseconds: 50);

const String _asset =
    'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd';

/// One query of the set: its median time and FTS5 / LIKE candidate count.
typedef QueryTime = ({
  String id,
  String name,
  String query,
  int candidates,
  int pages,
  Duration median,
});

void main() {
  late List<QueryTime> measured;

  setUpAll(() async {
    final store =
        await openTestNoteStore(seedDefaultPenPresets: false) as DriftNoteStore;
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
    measured = await measureQueries(store, vocab);
  });

  test('PF-3/4 (V10 as written): every query ≤ 5 ms, '
      '1-syllable LIKE ≤ 15 ms (median)', () {
    expect(measured, hasLength(14));
    expect(
      [
        for (final q in measured)
          if (q.median >= kBudget[q.id]!) describe(q),
      ],
      isEmpty,
      reason:
          'over the V10 budget (6.19 PF-3/PF-4, contract 7.7.2) — change '
          'request CP-18 (plan 12.1, progress log "[총괄] V10") is waiting',
    );
  });

  test('PF-3/4 (CP-18 as proposed, pending): under ${kHeldBelow['PF-3']} '
      'candidates ≤ 5 ms (LIKE: under ${kHeldBelow['PF-4']}, ≤ 15 ms), '
      'others ≤ ${kProposedOtherBudget.inMilliseconds} ms', () {
    expect(measured, hasLength(14));
    expect(
      [
        for (final q in measured)
          if (q.median >= proposedBudget(q)) describe(q),
      ],
      isEmpty,
      reason: 'over the CP-18 proposed budget (regression guard)',
    );
  });
}

/// The budget change request CP-18 proposes for [q].
Duration proposedBudget(QueryTime q) =>
    q.candidates < kHeldBelow[q.id]! ? kBudget[q.id]! : kProposedOtherBudget;

String describe(QueryTime q) =>
    '${q.id} ${q.name} "${q.query}": ${ms(q.median)} ms '
    '(${q.candidates} candidates, ${q.pages} pages)';

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

/// Measures and prints the PF-3 / PF-4 query set on [store] (built from [vocab]).
Future<List<QueryTime>> measureQueries(
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
  final sets = {
    'PF-3': {
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
    },
    'PF-4': {
      '1 syllable LIKE (frequent)': kSyllables.first,
      '1 syllable LIKE': kSyllables[200],
      '1 syllable LIKE (rarest)': kSyllables.last,
    },
  };
  final out = <QueryTime>[];
  for (final MapEntry(key: id, value: set) in sets.entries) {
    for (final MapEntry(key: name, value: query) in set.entries) {
      final q = (
        id: id,
        name: name,
        query: query,
        candidates: await candidatesOf(store, query),
        pages: (await store.search.searchPages(query)).length,
        median: await medianSearch(store, query),
      );
      final v10 = q.median < kBudget[id]! ? 'ok' : 'OVER';
      final proposed = q.median < proposedBudget(q) ? 'ok' : 'OVER';
      print(
        '[perf] ${describe(q)} — V10 ${kBudget[id]!.inMilliseconds} ms: $v10'
        ' · CP-18 ${proposedBudget(q).inMilliseconds} ms: $proposed',
      );
      out.add(q);
    }
  }
  return out;
}
