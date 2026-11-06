// Shared body (m5-7/02-core 6.10.6): the FTS5 candidate model of the fake index
// (ftsCandidateMatches over SearchText.indexTerms) answers like SQLite FTS5 MATCH on the real
// search_fts table (unicode61, remove_diacritics 0, contentless) — fixed-seed units (Hangul
// words, Han / kana, Latin words with and without accents, digits, CJK + Latin mixes) and
// queries (random words and slices of stored words), the result sets compared per query. Runs
// on the VM (test/search/fts_candidate_equivalence_test.dart) and in Chrome on the wasm build
// (test/web/search_fts_browser_test.dart). Web-safe.
import 'dart:math';

import 'package:note_core/note_core.dart';
import 'package:note_core/src/search/search_match.dart';
import 'package:test/test.dart';

const List<String> _syllables = [
  '회', '의', '록', '을', '정', '리', '했', '다', '방', '식', '계', '약', '서', //
  '확', '률', '통', '단', '어', '암', '기', '모', '델', '수', '학', '과', '제',
];
const List<String> _cjkOther = ['漢', '字', '学', 'の', 'か', 'ア', 'イ'];
const List<String> _latin = [
  'meeting', 'meet', 'notes', 'note', 'laplace', 'lap', 'eeting', 'cafe', //
  'café', 'x2', '2x', 'abc', 'ab', 'a', 'aim', 'naïve', 'über', 'σίγμα', '42',
];

String _word(Random r) {
  switch (r.nextInt(6)) {
    case 0 || 1 || 2:
      return [
        for (var i = 0, n = 1 + r.nextInt(5); i < n; i++)
          _syllables[r.nextInt(_syllables.length)],
      ].join();
    case 3:
      return [
        for (var i = 0, n = 1 + r.nextInt(3); i < n; i++)
          _cjkOther[r.nextInt(_cjkOther.length)],
      ].join();
    case 4:
      return _latin[r.nextInt(_latin.length)];
    default:
      // A CJK + Latin mix inside one word (6.10.2 known limit).
      return '${_latin[r.nextInt(_latin.length)]}'
          '${_syllables[r.nextInt(_syllables.length)]}'
          '${_syllables[r.nextInt(_syllables.length)]}';
  }
}

String _text(Random r) {
  final sep = [' ', ' ', ', ', '-', '. ', '\n'];
  final b = StringBuffer();
  for (var i = 0, n = 1 + r.nextInt(8); i < n; i++) {
    if (i > 0) b.write(sep[r.nextInt(sep.length)]);
    b.write(_word(r));
  }
  return b.toString();
}

/// One slice of a stored word (a substring query).
String _slice(Random r, String word) {
  final cps = word.runes.toList();
  final start = r.nextInt(cps.length);
  final end = start + 1 + r.nextInt(cps.length - start);
  return String.fromCharCodes(cps.sublist(start, end));
}

/// [insert] stores rows (rowid, g = index terms) in a real FTS5 table; [match] runs
/// `MATCH ?` there and returns the rowids.
void defineFtsEquivalenceCases({
  required Future<void> Function(List<(int, String)> rows) insert,
  required Future<Set<int>> Function(String matchQuery) match,
  int units = 2000,
  int queries = 500,
}) {
  test(
    'ftsCandidateMatches = FTS5 MATCH: $units units, $queries queries (seed 33)',
    () async {
      final r = Random(33);
      final texts = [for (var i = 0; i < units; i++) _text(r)];
      final terms = [
        for (final t in texts) SearchText.indexTerms(SearchText.normalize(t)),
      ];
      await insert([for (var i = 0; i < units; i++) (i + 1, terms[i])]);
      final words = [for (final t in texts) ...t.split(RegExp(r'[\s,.\-]+'))]
          .where((w) => w.isNotEmpty)
          .toList();
      var compared = 0, nonEmpty = 0;
      for (var i = 0; i < queries; i++) {
        final q = switch (i % 3) {
          0 => _word(r),
          1 => _slice(r, words[r.nextInt(words.length)]),
          _ =>
            '${_slice(r, words[r.nextInt(words.length)])} '
                '${_slice(r, words[r.nextInt(words.length)])}',
        };
        final m = SearchText.matchQuery(SearchText.normalize(q));
        if (m == null) continue; // the LIKE path (one-character runs only)
        final expected = {
          for (var u = 0; u < units; u++)
            if (ftsCandidateMatches(terms[u], m)) u + 1,
        };
        expect(await match(m), expected, reason: 'query "$q" → $m');
        compared++;
        if (expected.isNotEmpty) nonEmpty++;
      }
      // The table is not degenerate: most queries ran on FTS and many found rows.
      expect(compared, greaterThan(queries ~/ 2));
      expect(nonEmpty, greaterThan(compared ~/ 3));
    },
  );
}
