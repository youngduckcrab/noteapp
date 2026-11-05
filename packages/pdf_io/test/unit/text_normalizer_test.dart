// PdfTextNormalizer (06-pdf 4.8, 6.10.1; 8 T11): jamo composition, whitespace collapse,
// soft hyphen / zero-width removal, end-of-line hyphenation join, lower-casing and the
// source position table.
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_io/pdf_io.dart';

/// [(start, end)] of every normalized code unit.
List<(int, int)> _table(PdfNormalizedText n) => [
  for (var i = 0; i < n.text.length; i++) (n.sourceStart[i], n.sourceEnd[i]),
];

void main() {
  group('Hangul jamo (step 4)', () {
    test('\u1100 + \u1161 → 가', () {
      final n = PdfTextNormalizer.normalize('\u1100\u1161');
      expect(n.text, '가');
      expect(_table(n), [(0, 2)]);
    });

    test('\u1100 + \u1161 + \u11A8 → 각', () {
      final n = PdfTextNormalizer.normalize('\u1100\u1161\u11A8');
      expect(n.text, '각');
      expect(_table(n), [(0, 3)]);
    });

    test('가 + \u11A8 → 각 (LV syllable + T)', () {
      final n = PdfTextNormalizer.normalize('가\u11A8');
      expect(n.text, '각');
      expect(_table(n), [(0, 2)]);
    });

    test('NFD word next to precomposed text', () {
      // 강의 in conjoining jamo, 자료 precomposed.
      final n = PdfTextNormalizer.normalize(
        '\u1100\u1161\u11BC\u110B\u1174 자료',
      );
      expect(n.text, '강의 자료');
      expect(_table(n), [(0, 3), (3, 5), (5, 6), (6, 7), (7, 8)]);
    });
  });

  group('whitespace (step 3)', () {
    test('runs collapse to one space covering the run', () {
      final n = PdfTextNormalizer.normalize('a \t\r\n b');
      expect(n.text, 'a b');
      expect(_table(n), [(0, 1), (1, 6), (6, 7)]);
    });

    test('NBSP and ideographic space are whitespace', () {
      expect(PdfTextNormalizer.normalize('a\u00A0\u3000b').text, 'a b');
    });

    test('leading and trailing whitespace are kept as one space', () {
      final n = PdfTextNormalizer.normalize('  ab \n');
      expect(n.text, ' ab ');
      expect(_table(n), [(0, 2), (2, 3), (3, 4), (4, 6)]);
    });
  });

  group('dropped characters (step 2)', () {
    test('soft hyphen inside a word', () {
      final n = PdfTextNormalizer.normalize('hy\u00ADphen');
      expect(n.text, 'hyphen');
      // 'p' comes from source index 3 (after the soft hyphen).
      expect(n.sourceStart[2], 3);
      expect(n.sourceEnd[2], 4);
    });

    test('zero-width characters and BOM', () {
      expect(
        PdfTextNormalizer.normalize('\uFEFFa\u200Bb\u200Cc\u200Dd').text,
        'abcd',
      );
    });

    test('a zero-width character inside a whitespace run joins the run', () {
      final n = PdfTextNormalizer.normalize('a \u200B b');
      expect(n.text, 'a b');
      expect(_table(n), [(0, 1), (1, 4), (4, 5)]);
    });
  });

  group('end-of-line hyphenation (step 1)', () {
    test("'con-\\r\\ntinue' → 'continue'", () {
      final n = PdfTextNormalizer.normalize('con-\r\ntinue');
      expect(n.text, 'continue');
      // 't' maps to the source after the line break.
      expect(n.sourceStart[3], 6);
      expect(n.sourceEnd[3], 7);
      expect(n.sourceStart[2], 2);
    });

    test("'\\n' alone also joins", () {
      expect(PdfTextNormalizer.normalize('con-\ntinue').text, 'continue');
    });

    test('a hyphen not at a line end stays', () {
      expect(PdfTextNormalizer.normalize('well-known').text, 'well-known');
    });

    test('a hyphen after a space or before a space is not a word break', () {
      expect(PdfTextNormalizer.normalize('a -\r\nb').text, 'a - b');
      expect(PdfTextNormalizer.normalize('a-\r\n b').text, 'a- b');
    });

    test('Korean word broken over a line', () {
      expect(PdfTextNormalizer.normalize('강-\r\n의').text, '강의');
      expect(
        PdfTextNormalizer.normalize('\u1100\u1161\u11BC-\r\n\u110B\u1174').text,
        '강의',
      );
    });
  });

  group('case (step 5)', () {
    test('lower-cases ASCII and other scripts', () {
      expect(
        PdfTextNormalizer.normalize('ABC Ünïcode ΣΑ').text,
        'abc ünïcode σα',
      );
    });

    test('every unit of a lower-cased character maps to that character', () {
      // U+0130 lower-cases to 'i' + U+0307 in JavaScript, 'i' on the VM.
      final lower = '\u0130'.toLowerCase();
      final n = PdfTextNormalizer.normalize('x\u0130y');
      expect(n.text, 'x${lower}y');
      expect(_table(n), [
        (0, 1),
        for (final _ in lower.codeUnits) (1, 2),
        (2, 3),
      ]);
    });

    test('supplementary characters keep both halves', () {
      final n = PdfTextNormalizer.normalize('a😀b');
      expect(n.text, 'a😀b');
      expect(_table(n), [(0, 1), (1, 3), (1, 3), (3, 4)]);
    });
  });

  group('position table', () {
    test('identity for plain lower-case text', () {
      final n = PdfTextNormalizer.normalize('abc');
      expect(_table(n), [(0, 1), (1, 2), (2, 3)]);
    });

    test('everything at once', () {
      const raw = 'The Con-\r\ntinue  \u1100\u1161\u11A8\u00ADX';
      final n = PdfTextNormalizer.normalize(raw);
      expect(n.text, 'the continue 각x');
      expect(n.sourceStart.length, n.text.length);
      expect(n.sourceEnd.length, n.text.length);
      // Every range is inside the raw text and ordered.
      for (var i = 0; i < n.text.length; i++) {
        expect(n.sourceStart[i], lessThan(n.sourceEnd[i]));
        expect(n.sourceEnd[i], lessThanOrEqualTo(raw.length));
        if (i > 0) {
          expect(n.sourceStart[i], greaterThanOrEqualTo(n.sourceStart[i - 1]));
        }
      }
      final syllable = n.text.indexOf('각');
      expect(
        raw.substring(n.sourceStart[syllable], n.sourceEnd[syllable]),
        '\u1100\u1161\u11A8',
      );
    });

    test('empty text', () {
      final n = PdfTextNormalizer.normalize('');
      expect(n.text, '');
      expect(n.sourceStart, isEmpty);
    });
  });

  group('normalizeQuery (step 6)', () {
    test('same rules plus trimming', () {
      expect(
        PdfTextNormalizer.normalizeQuery('  강의\u00A0Notes \n'),
        '강의 notes',
      );
    });

    test('blank query → empty', () {
      expect(PdfTextNormalizer.normalizeQuery(' \t\u3000'), '');
    });

    test('a normalized query is found in normalized text', () {
      final text = PdfTextNormalizer.normalize('Lecture  NOTES: con-\r\ntinue');
      expect(text.text.indexOf(PdfTextNormalizer.normalizeQuery('notes:')), 8);
      expect(
        text.text.contains(PdfTextNormalizer.normalizeQuery('Continue')),
        isTrue,
      );
    });
  });
}
