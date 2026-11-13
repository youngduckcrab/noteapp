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
}
