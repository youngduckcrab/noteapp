// searchMatchRange (05-library 6.14, 8 L17): the highlighted part of a search
// result title.
import 'package:feature_library/src/model/search_match.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the first occurrence, case-insensitive', () {
    expect(searchMatchRange('극한 정리', '정리'), (start: 3, end: 5));
    expect(searchMatchRange('Math Notes', 'math'), (start: 0, end: 4));
    expect(searchMatchRange('abcABC', 'C'), (start: 2, end: 3));
    expect(searchMatchRange('일기', '일기'), (start: 0, end: 2));
  });

  test('no visible match → null', () {
    expect(searchMatchRange('극한 정리', ''), isNull);
    expect(searchMatchRange('극한 정리', '요약'), isNull);
    // CORE collapses spaces and composes Hangul jamo; the title does not.
    expect(searchMatchRange('극한  정리', '극한 정리'), isNull);
    expect(searchMatchRange('\u1109\u116e\u1112\u1161\u11a8 정리', '수학'), isNull);
  });

  test('lower-casing that changes the length → null', () {
    // U+0130 lower-cases to 'i' on the VM but to 'i' + U+0307 (two code
    // units) in browsers: there the index would not point into the title.
    final sameLength = 'İ'.toLowerCase().length == 1;
    expect(
      searchMatchRange('İstanbul', 'stan'),
      sameLength ? (start: 1, end: 5) : isNull,
    );
  });
}
