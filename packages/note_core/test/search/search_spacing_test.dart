// (ink spacing) The compact text, the ink FTS terms, the ink judgement and the snippet range
// of search_spacing.dart (m5-7/02-core 6.10.2 'ink 띄어쓰기').
import 'package:note_core/note_core.dart' show SearchSource, SearchText;
import 'package:note_core/src/search/search_match.dart';
import 'package:note_core/src/search/search_ranking.dart';
import 'package:note_core/src/search/search_runs.dart';
import 'package:note_core/src/search/search_spacing.dart';
import 'package:test/test.dart';

void main() {
  test('cjkCompact drops only the spaces between two CJK characters', () {
    expect(cjkCompact('회의 록'), '회의록');
    expect(cjkCompact('회의 록 정리'), '회의록정리');
    expect(cjkCompact('회의 meeting 록'), '회의 meeting 록');
    expect(cjkCompact('a b'), 'a b');
    expect(cjkCompact('회의록'), '회의록');
    expect(cjkCompact(''), '');
  });

  test('unitIndexTerms adds the compact terms for ink only', () {
    expect(unitIndexTerms(SearchSource.text, '회의 록'), '회의 록');
    expect(unitIndexTerms(SearchSource.ink, '회의 록'), '회의 록 회의 의록');
    expect(unitIndexTerms(SearchSource.ink, '회의록'), '회의 의록');
    expect(
      unitIndexTerms(SearchSource.ink, 'meeting notes'),
      SearchText.indexTerms('meeting notes'),
    );
  });

  test('the compact terms are FTS candidates of the unspaced query', () {
    final match = SearchText.matchQuery('회의록')!;
    expect(
      ftsCandidateMatches(unitIndexTerms(SearchSource.ink, '회의 록'), match),
      isTrue,
    );
    expect(
      ftsCandidateMatches(unitIndexTerms(SearchSource.text, '회의 록'), match),
      isFalse,
    );
  });

  test('matchScore: ink is judged again on the compact texts', () {
    List<SearchRun> runs(String q) => searchRunsOf(q);
    final inkRuns = inkCompactRuns('회의록');
    expect(matchScore(SearchSource.ink, '회의 록', runs('회의록')), isNull);
    expect(
      matchScore(SearchSource.ink, '회의 록', runs('회의록'), inkRuns: inkRuns),
      isNotNull,
    );
    expect(
      matchScore(SearchSource.text, '회의 록', runs('회의록'), inkRuns: inkRuns),
      isNull,
    );
    // A space in the query against an unspaced unit.
    expect(
      matchScore(
        SearchSource.ink,
        '회의록음',
        runs('회의 록음'),
        inkRuns: inkCompactRuns('회의 록음'),
      ),
      isNotNull,
    );
    // A plain match keeps its plain score.
    expect(
      matchScore(SearchSource.ink, '회의록', runs('회의록'), inkRuns: inkRuns),
      matchScore(SearchSource.ink, '회의록', runs('회의록')),
    );
    expect(
      matchScore(SearchSource.ink, '전혀 다름', runs('회의록'), inkRuns: inkRuns),
      isNull,
    );
  });

  test('the snippet range of an ink match across a space', () {
    final s = snippetOf('오늘 회의  록!', '회의록', inkSpacing: true);
    final (a, b) = s.range;
    expect(s.snippet.substring(a, b), '회의  록');
    expect(inkSpacingBodyRange('abc', 'abc', '회의록'), isNull);
  });

  group('review fixes', () {
    List<SearchRun> runs(String q) => searchRunsOf(q);
    double? ink(String unit, String q) =>
        matchScore(SearchSource.ink, unit, runs(q), inkRuns: inkCompactRuns(q));

    test('a two-syllable query does not join two neighbouring words', () {
      expect(inkCompactRuns('사과'), isNull);
      expect(ink('이사 과장', '사과'), isNull);
      expect(ink('회의 록', '의록'), isNull);
      // Three syllables still cross the engine's space.
      expect(ink('회의 록', '회의록'), isNotNull);
    });

    test('a compact-only match ranks below a plain one', () {
      final plain = ink('회의록', '회의록')!;
      final spaced = ink('회의 록', '회의록')!;
      expect(spaced, lessThan(plain));
      expect(plain - spaced, closeTo(kInkSpacingPenalty, 1e-9));
    });

    test('Hangul next to a digit, and supplementary Han, are joined', () {
      expect(cjkCompact('회의 3분기'), '회의3분기');
      expect(cjkCompact('3 월 10 시'), '3월10시');
      expect(cjkCompact('2024 3'), '2024 3');
      expect(cjkCompact('a 3'), 'a 3');
      expect(cjkCompact('\u{20000} \u{20001}'), '\u{20000}\u{20001}');
      expect(ink('회의 3분기', '회의3분기'), isNotNull);
      expect(ink('3 월', '3월'), isNotNull);
      expect(
        ink('\u{20000} \u{20001}\u{20002}', '\u{20000}\u{20001}\u{20002}'),
        isNotNull,
      );
      final match = SearchText.matchQuery('3월')!;
      expect(
        ftsCandidateMatches(unitIndexTerms(SearchSource.ink, '3 월'), match),
        isTrue,
      );
    });

    test('the snippet highlights the whole phrase across the spaces', () {
      final s = snippetOf('주간 회의 록', '주간 회의록', inkSpacing: true);
      final (a, b) = s.range;
      expect(s.snippet.substring(a, b), '주간 회의 록');
      // Text units keep the first-run range.
      final t = snippetOf('주간 회의 록', '주간 회의록');
      expect(t.snippet.substring(t.range.$1, t.range.$2), '주간');
    });
  });
}
