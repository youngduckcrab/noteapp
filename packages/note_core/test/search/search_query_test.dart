// Runs, index terms, FTS query text and the match judgement (m5-7/02-core 6.10.2): the 9.2
// table, FTS grammar injection, the FTS candidate model as a superset of the judgement, the
// ranking order. Web-safe.
import 'dart:math';

import 'package:note_core/note_core.dart';
import 'package:note_core/src/search/search_match.dart';
import 'package:note_core/src/search/search_ranking.dart';
import 'package:note_core/src/search/search_runs.dart';
import 'package:test/test.dart';

const Map<int, String> _docs = {
  1: '오늘 회의록을 정리했다 meeting notes',
  2: '라플라스 방정식 Laplace equation',
  3: '확률과 통계',
  4: '정식 계약서',
  5: '영어 단어 암기',
};

/// The documents the real index would return: FTS candidates (or the LIKE path) judged by
/// searchMatches.
Set<int> _search(String query) {
  final q = SearchText.normalize(query);
  final match = SearchText.matchQuery(q);
  return {
    for (final MapEntry(key: id, value: body) in _docs.entries)
      if (match == null
          ? likeCandidateMatches(SearchText.normalize(body), q)
          : ftsCandidateMatches(
              SearchText.indexTerms(SearchText.normalize(body)),
              match,
            ))
        if (searchMatches(SearchText.normalize(body), q)) id,
  };
}

/// searchMatches as 6.10.2 states it: every query run against the runs of the whole unit
/// (the first implementation — the occurrence-based one must decide the same).
bool _referenceMatches(String unitNorm, String queryNorm) {
  final query = searchRunsOf(queryNorm);
  if (query.isEmpty) return false;
  final unitRuns = searchRunsOf(unitNorm);
  for (final q in query) {
    if (q.codePoints == 1) {
      if (!unitNorm.contains(q.text)) return false;
      continue;
    }
    final ok = q.isCjk
        ? unitRuns.any((r) => r.isCjk && r.text.contains(q.text))
        : unitRuns.any(
            (r) =>
                (!r.isCjk && r.text.startsWith(q.text)) ||
                (q.codePoints == 2 && r.isCjk && r.text.contains(q.text)),
          );
    if (!ok) return false;
  }
  return true;
}

void main() {
  group('runs', () {
    test('letters, digits and private use; CJK flag; code point length', () {
      final runs = searchRunsOf('오늘 회의록을, meeting-notes 😀 x² 漢字 カタカナ aim모델');
      expect(runs.map((r) => r.text), [
        '오늘',
        '회의록을',
        'meeting',
        'notes',
        'x²',
        '漢字',
        'カタカナ',
        'aim모델',
      ]);
      expect(runs.map((r) => r.isCjk), [
        true,
        true,
        false,
        false,
        false,
        true,
        true,
        true,
      ]);
      expect(runs[1].start, 3);
      expect(searchRunsOf('𝐀𝐁').single.codePoints, 2);
    });
  });

  group('indexTerms', () {
    test('CJK runs → code point bigrams; others as they are', () {
      expect(SearchText.indexTerms('회의록을'), '회의 의록 록을');
      expect(SearchText.indexTerms('오늘 회의록을 meeting'), '오늘 회의 의록 록을 meeting');
      expect(SearchText.indexTerms('가 a'), '가 a');
      expect(SearchText.indexTerms('aim모델'), 'ai im m모 모델');
      expect(SearchText.indexTerms('!!!'), '');
    });
  });

  group('matchQuery', () {
    test('phrases for CJK, prefixes otherwise, only runs of two or more', () {
      expect(SearchText.matchQuery('방정식'), '"방정 정식"');
      expect(SearchText.matchQuery('회의'), '"회의"');
      expect(SearchText.matchQuery('meet'), '"meet"*');
      expect(SearchText.matchQuery('확률 통계'), '"확률" AND "통계"');
      expect(SearchText.matchQuery('정 meet'), '"meet"*');
      expect(SearchText.matchQuery('정'), isNull);
      expect(SearchText.matchQuery('a b'), isNull);
      expect(SearchText.matchQuery(''), isNull);
    });

    test('FTS grammar cannot be injected', () {
      final q = SearchText.matchQuery(
        SearchText.normalize('NEAR(ab cd) "x" OR yy* -zz ^ww col:vv'),
      );
      expect(
        q,
        '"near"* AND "ab"* AND "cd"* AND "or"* AND "yy"* AND "zz"* AND "ww"* AND "col"* AND "vv"*',
      );
      // Every item is a quoted string with no bare operator.
      for (final item in q!.split(' AND ')) {
        expect(item, matches(RegExp(r'^"[^"]+"\*?$')));
      }
    });
  });

  group('searchMatches — the 6.10.2 table', () {
    test('queries and the documents they find', () {
      final table = <String, Set<int>>{
        '회의': {1},
        '회의록': {1},
        '의록': {1},
        '정식': {2, 4},
        '정': {1, 2, 4},
        '록': {1},
        'meet': {1},
        'LAPLACE': {2},
        '확률 통계': {3},
        '단어 암기': {5},
        '방정 정식': {2},
        'eeting': {},
        '방정식': {2},
        '없는말': {},
        '!!!': {},
        '': {},
      };
      for (final MapEntry(key: q, value: expected) in table.entries) {
        expect(_search(q), expected, reason: q);
      }
    });

    test('a phrase across a run boundary is filtered by the judgement', () {
      const unit = '방정 정식';
      final norm = SearchText.normalize(unit);
      final q = SearchText.normalize('방정식');
      expect(
        ftsCandidateMatches(
          SearchText.indexTerms(norm),
          SearchText.matchQuery(q),
        ),
        isTrue,
      );
      expect(searchMatches(norm, q), isFalse);
    });

    test(
      'two-letter Latin queries also match an equal bigram of a CJK run',
      () {
        expect(searchMatches('aim모델', 'ai'), isTrue);
        expect(
          searchMatches('aim모델', 'aim'),
          isFalse,
        ); // the known limit (6.10.2)
        expect(searchMatches('aim 모델', 'aim'), isTrue);
      },
    );

    test(
      'the occurrence-based decision = the run-split definition (seed 7)',
      () {
        // Letters, digits, Hangul, Han (also outside the BMP), kana, private use, a combining
        // mark, an emoji and separators.
        const pieces = [
          'a', 'b', 'ab', 'aa', 'é', '1', '2', '회', '의', '록', '회의', '漢', //
          '𠀀', 'の', '\uE000', '\u0301', '😀', ' ', '-', '.', 'x',
        ];
        final r = Random(7);
        String text(int n) =>
            [for (var i = 0; i < n; i++) pieces[r.nextInt(pieces.length)]]
                .join();
        var matched = 0;
        for (var i = 0; i < 4000; i++) {
          final unit = SearchText.normalize(text(1 + r.nextInt(16)));
          final query = SearchText.normalize(text(1 + r.nextInt(4)));
          final expected = _referenceMatches(unit, query);
          expect(
            searchMatches(unit, query),
            expected,
            reason: '$unit / $query',
          );
          if (expected) matched++;
        }
        expect(matched, greaterThan(200));
      },
    );

    test('matchScore (one pass) = searchMatches ? unitScore : null; runCharBefore = the regex', () {
      const pieces = [
        'a', 'b', 'ab', 'aa', 'é', '1', '회', '의', '회의', '漢', '𠀀', 'の', //
        '\uE000', '\u0301', '😀', ' ', '-', '.', 'x', 'aim모델',
      ];
      final r = Random(11);
      String text(int n) =>
          [for (var i = 0; i < n; i++) pieces[r.nextInt(pieces.length)]].join();
      final runChar = RegExp(r'^[\p{L}\p{N}\p{Co}]$', unicode: true);
      var scored = 0;
      for (var i = 0; i < 4000; i++) {
        final unit = SearchText.normalize(text(1 + r.nextInt(20)));
        final query = SearchText.normalize(text(1 + r.nextInt(4)));
        final source = SearchSource.values[r.nextInt(4)];
        final expected = searchMatches(unit, query)
            ? unitScore(source, unit, query)
            : null;
        expect(
          matchScore(source, unit, searchRunsOf(query)),
          expected,
          reason: '$unit / $query',
        );
        if (expected != null) scored++;
        for (var k = 0; k <= unit.length; k++) {
          final before = k == 0
              ? false
              : runChar.hasMatch(
                  String.fromCharCode(
                    unit.runes.elementAt(unit.substring(0, k).runes.length - 1),
                  ),
                );
          // Only at code point boundaries (the callers' indexes).
          if (k > 0 &&
              k < unit.length &&
              unit.codeUnitAt(k) >= 0xDC00 &&
              unit.codeUnitAt(k) <= 0xDFFF) {
            continue;
          }
          expect(runCharBefore(unit, k), before, reason: '$unit @ $k');
        }
      }
      expect(scored, greaterThan(200));
    });

    test('the FTS candidate model is a superset of the judgement', () {
      const units = [
        '오늘 회의록을 정리했다 meeting notes',
        '방정 정식',
        'aim모델 aim',
        '회의 회의',
        'ab b회의',
        'meeting',
        '가나다라',
      ];
      const queries = [
        '회의',
        'meet',
        'ai',
        '방정식',
        'ab회',
        '나다',
        'aim',
        '회의록',
        'notes meet',
      ];
      for (final u in units) {
        final norm = SearchText.normalize(u);
        for (final q in queries) {
          final mq = SearchText.matchQuery(q);
          if (searchMatches(norm, q) && mq != null) {
            expect(
              ftsCandidateMatches(SearchText.indexTerms(norm), mq),
              isTrue,
              reason: '$u / $q',
            );
          }
        }
      }
    });
  });

  group('ranking', () {
    test('source weights and the order rule', () {
      expect(
        [for (final s in SearchSource.values) sourceWeight(s)],
        [0.9, 0.8, 1.0, 0.95, 1.0],
      );
      final hits = [
        (score: 1.0, noteUpdatedAt: 5, pageId: 'b'),
        (score: 1.2, noteUpdatedAt: 1, pageId: 'c'),
        (score: 1.0, noteUpdatedAt: 9, pageId: 'd'),
        (score: 1.0, noteUpdatedAt: 5, pageId: 'a'),
      ]..sort(comparePageHits);
      expect(hits.map((h) => h.pageId), ['c', 'd', 'a', 'b']);
    });

    test('a match at a run start scores higher; position and count matter', () {
      expect(
        unitScore(SearchSource.text, 'meeting', 'meet'),
        greaterThan(unitScore(SearchSource.text, 'xmeeting', 'meet')),
      );
      expect(
        unitScore(SearchSource.text, 'ab ab ab', 'ab'),
        greaterThan(unitScore(SearchSource.text, 'ab', 'ab')),
      );
      expect(pageScore(1.0, 1), 1.0);
      expect(pageScore(1.0, 100), pageScore(1.0, 11));
    });

    test(
      'snippet: ≤ 80 chars from 30 before the match, line breaks as spaces',
      () {
        final body = '${'가' * 50}\n회의록 정리\t끝${'나' * 60}';
        final s = snippetOf(body, SearchText.normalize('회의'));
        expect(s.snippet.length, 80);
        expect(s.snippet.contains('\n'), isFalse);
        expect(s.snippet.contains('\t'), isFalse);
        final (start, end) = s.range;
        expect(s.snippet.substring(start, end), '회의');
        expect(start, 30);
        expect(s.bodyRange, (51, 53));
        // A match near the start: the snippet starts at 0.
        final early = snippetOf('MEETING notes', 'meet');
        expect(early.snippet, 'MEETING notes');
        expect(early.range, (0, 4));
      },
    );
  });
}
