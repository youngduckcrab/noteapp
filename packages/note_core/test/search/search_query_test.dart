// Runs, index terms, FTS query text and the match judgement (m5-7/02-core 6.10.2): the 9.2
// table, FTS grammar injection, the FTS candidate model as a superset of the judgement, the
// ranking order. Web-safe.
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
        [0.9, 0.8, 1.0, 0.95],
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
