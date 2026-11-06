// CORE T33b — m5-7/02-core 6.19 PF-3 · PF-4 · PF-5 (contract 7.7.2 V10, budget of v2.5
// C25-01): a 5,000-page synthetic index (one pdf unit of 80 words per PDF page, no glyph boxes —
// 조사 03 9.2 shape; Hangul words from 400 syllables, 20 % Latin; 50 notes × 100 pages show the
// pages) on the in-memory store. PF-5: building it with replaceUnits (record only). PF-3: 2- and
// 3-syllable, word-middle, Latin prefix and AND queries. PF-4: one-syllable LIKE queries.
//
// The budget (contract v2.5 C25-01 — change request CP-18, plan 12.1, approved) depends on the
// query's candidates (FTS5 MATCH / LIKE rows before the 2,000 cap — 7.2.5), which the test counts
// with its own SQL for every query and uses to pick the budget:
// - fewer than [kFewCandidates] candidates: median ≤ 5 ms (PF-3), ≤ 15 ms (PF-4, 1-syllable LIKE);
// - any other query (the search reads up to the 2,000-candidate cap): median ≤ 50 ms.
// The cost grows with the candidates read (each one's liveness, and its normalized text judged
// and scored in Dart — 6.10.4 steps 1–2, the same judgement as the fake — CP-14) and with the
// pages returned (up to 100), so the frequent words of this corpus (1,000 to 5,000 candidates)
// take 20 to 46 ms. The set has queries on both sides of the threshold for PF-3 and PF-4 (the
// absent syllable is the PF-4 query under it: every syllable of the corpus has ≥ 576 candidates);
// the test checks that. It is the PF-3 / PF-4 completion judgement (plan 10장 #1), at load < 4
// (plan 9.1). (Until v2.5 a second test held every query to the v2.4 text — median ≤ 5 ms, 1-
// syllable LIKE ≤ 15 ms whatever the candidates — and failed on the frequent words; the threshold
// was 300 candidates, 600 for LIKE, until review 1.4.)
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

/// V10 (contract v2.5 C25-01): a query with fewer candidates than this is held to
/// [kFewBudget] …
const int kFewCandidates = 100;

/// … the budget of such a query per PF row (6.19 PF-3 · PF-4) …
const Map<String, Duration> kFewBudget = {
  'PF-3': Duration(milliseconds: 5),
  'PF-4': Duration(milliseconds: 15),
};

/// … and every other query (up to the 2,000-candidate cap) is held to this.
const Duration kOtherBudget = Duration(milliseconds: 50);

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

  test('PF-3/4 (V10, contract v2.5 C25-01): under $kFewCandidates '
      'candidates ≤ 5 ms (1-syllable LIKE ≤ 15 ms), '
      'others ≤ ${kOtherBudget.inMilliseconds} ms (median)', () {
    expect(measured, hasLength(15));
    // Both budgets of each PF row are exercised: the counted candidates put at least one
    // query on each side of the threshold.
    for (final id in kFewBudget.keys) {
      for (final few in [true, false]) {
        expect(
          measured.where(
            (q) => q.id == id && (q.candidates < kFewCandidates) == few,
          ),
          isNotEmpty,
          reason:
              '$id has no query with ${few ? 'fewer than' : 'at least'} '
              '$kFewCandidates candidates',
        );
      }
    }
    expect(
      [
        for (final q in measured)
          if (q.median >= budgetOf(q)) describe(q),
      ],
      isEmpty,
      reason:
          'over the V10 budget (contract v2.5 C25-01, plan 6.19 PF-3/PF-4 — '
          'judged at load < 4, plan 9.1)',
    );
  });
}

/// The V10 budget of [q] (contract v2.5 C25-01): chosen by its counted candidates.
Duration budgetOf(QueryTime q) =>
    q.candidates < kFewCandidates ? kFewBudget[q.id]! : kOtherBudget;

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
      // Not a syllable of the corpus (kSyllables steps by 27): no candidates, the
      // whole LIKE scan of the 5,000 units — the PF-4 query under the threshold.
      '1 syllable LIKE (absent)': String.fromCharCode(0xAC01),
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
      final band = q.candidates < kFewCandidates
          ? '< $kFewCandidates candidates'
          : '≥ $kFewCandidates candidates';
      print(
        '[perf] ${describe(q)} — V10 v2.5 '
        '${budgetOf(q).inMilliseconds} ms ($band): '
        '${q.median < budgetOf(q) ? 'ok' : 'OVER'}',
      );
      out.add(q);
    }
  }
  return out;
}
