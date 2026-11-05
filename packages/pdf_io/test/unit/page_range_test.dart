// PdfPageRange (06-pdf 4.6, 8 T1).
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_io/pdf_io.dart';

void main() {
  test("'1-3, 5' → [0, 1, 2, 4]", () {
    final range = PdfPageRange.parse('1-3, 5', pageCount: 10);
    expect(range.resolve(10), [0, 1, 2, 4]);
    expect(range.isAll, isFalse);
    expect(range.format(), '1-3, 5');
  });

  test("'8-' runs to the last page", () {
    final range = PdfPageRange.parse('8-', pageCount: 10);
    expect(range.resolve(10), [7, 8, 9]);
    expect(range.format(), '8-');
    // The open end follows the page count given to resolve.
    expect(range.resolve(12), [7, 8, 9, 10, 11]);
  });

  test("'0', '3-1', 'x' and pages past the end are FormatExceptions", () {
    for (final input in ['0', '3-1', 'x', '11', '2-11', '1-x', '-3', '1--2']) {
      expect(
        () => PdfPageRange.parse(input, pageCount: 10),
        throwsFormatException,
        reason: input,
      );
    }
    for (final input in ['', '  ', ', ,']) {
      expect(
        () => PdfPageRange.parse(input, pageCount: 10),
        throwsFormatException,
        reason: 'empty "$input"',
      );
    }
  });

  test('messages are Korean', () {
    try {
      PdfPageRange.parse('3-1', pageCount: 10);
      fail('no exception');
    } on FormatException catch (e) {
      expect(e.message, contains('시작 쪽이 끝 쪽보다 커요'));
    }
    try {
      PdfPageRange.parse('12', pageCount: 10);
      fail('no exception');
    } on FormatException catch (e) {
      expect(e.message, contains('1–10쪽'));
    }
  });

  test('duplicates removed, ascending order, parts merged', () {
    final range = PdfPageRange.parse('5, 1-3, 2, 3-4, 5', pageCount: 10);
    expect(range.resolve(10), [0, 1, 2, 3, 4]);
    expect(range.format(), '1-5');
    expect(PdfPageRange.parse('9, 2', pageCount: 10).resolve(10), [1, 8]);
    expect(PdfPageRange.parse('7, 6-', pageCount: 10).format(), '6-');
  });

  test('spaces, en dash and tilde are accepted', () {
    final range = PdfPageRange.parse(' 1 – 2 ,4~5,', pageCount: 10);
    expect(range.resolve(10), [0, 1, 3, 4]);
    expect(range.format(), '1-2, 4-5');
  });

  test('all', () {
    const all = PdfPageRange.all();
    expect(all.isAll, isTrue);
    expect(all.resolve(3), [0, 1, 2]);
    expect(all.resolve(0), isEmpty);
    expect(all.format(), '1-');
    expect(PdfPageRange.parse('1-', pageCount: 3).isAll, isTrue);
    expect(PdfPageRange.parse('1-', pageCount: 3), all);
    expect(PdfPageRange.parse('1-3', pageCount: 3).isAll, isFalse);
  });

  test('equality follows the canonical text', () {
    expect(
      PdfPageRange.parse('5, 1-2, 3', pageCount: 9),
      PdfPageRange.parse('1-3, 5', pageCount: 9),
    );
    expect(
      PdfPageRange.parse('5, 1-2, 3', pageCount: 9).hashCode,
      PdfPageRange.parse('1-3, 5', pageCount: 9).hashCode,
    );
    expect(
      PdfPageRange.parse('1-3', pageCount: 9),
      isNot(PdfPageRange.parse('1-4', pageCount: 9)),
    );
  });
}
