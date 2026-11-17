// (v2.17-md, m5-7/08-markdown 4.4 and 9) MarkdownLimits, MarkdownConflictCopy and
// MarkdownPreviewText — the pure helpers of the foundation.
import 'dart:convert';
import 'dart:math';

import 'package:note_core/note_core.dart';
import 'package:test/test.dart';

void main() {
  group('MarkdownLimits', () {
    test(
      'utf8BytesOf == utf8.encode length (ASCII, 한글, emoji, lone surrogates)',
      () {
        final samples = [
          '',
          'abc',
          '한글 문서',
          '﻿# 제목\r\n',
          'emoji 😀 and 𝔸',
          'lone \uD800 high',
          'lone \uDC00 low',
          'end \uD83D',
        ];
        final random = Random(7);
        for (var i = 0; i < 200; i++) {
          samples.add(
            String.fromCharCodes([
              for (var j = 0; j < 20; j++) random.nextInt(0x10000),
            ]),
          );
        }
        for (final s in samples) {
          expect(
            MarkdownLimits.utf8BytesOf(s),
            utf8.encode(s).length,
            reason: s,
          );
        }
      },
    );

    test('encodedBytesOf counts JSON escapes (control characters cost 6)', () {
      expect(MarkdownLimits.encodedBytesOf('ab'), 4);
      expect(MarkdownLimits.encodedBytesOf('\n'), 4);
      expect(MarkdownLimits.encodedBytesOf('\x1b'), 8);
      expect(MarkdownLimits.encodedBytesOf('"\\'), 6);
      expect(MarkdownLimits.encodedBytesOf('가'), 5);
    });

    test(
      'check: raw byte limit and encoded limit, exception carries sizes',
      () {
        MarkdownLimits.check('a' * MarkdownLimits.maxTextBytes);
        expect(
          () => MarkdownLimits.check('a' * (MarkdownLimits.maxTextBytes + 1)),
          throwsA(
            isA<MarkdownTooLargeException>().having(
              (e) => e.bytes,
              'bytes',
              MarkdownLimits.maxTextBytes + 1,
            ),
          ),
        );
        // 200,000 ESC characters: 200 KB raw, 1.2 MB as a JSON string.
        final escapes = '\x1b' * 200000;
        expect(
          () => MarkdownLimits.check(escapes),
          throwsA(
            isA<MarkdownTooLargeException>()
                .having((e) => e.bytes, 'bytes', 200000)
                .having((e) => e.encodedBytes, 'encodedBytes', 1200002),
          ),
        );
        // Korean text at the raw limit stays under the encoded limit.
        MarkdownLimits.check('가' * (MarkdownLimits.maxTextBytes ~/ 3));
      },
    );
  });

  group('MarkdownConflictCopy', () {
    test('title format and 200-character cut', () {
      final at = DateTime(2026, 3, 4, 5, 6);
      expect(
        MarkdownConflictCopy.titleFor(' 회의록 ', at),
        '회의록 (충돌 사본 2026-03-04 05:06)',
      );
      final long = MarkdownConflictCopy.titleFor('가' * 300, at);
      expect(long.length, 200);
      expect(long, endsWith(' (충돌 사본 2026-03-04 05:06)'));
      // Never cut inside a surrogate pair.
      final emoji = MarkdownConflictCopy.titleFor('😀' * 150, at);
      expect(emoji.length, lessThanOrEqualTo(200));
      expect(() => utf8.encode(emoji), returnsNormally);
      expect(emoji.runes.every((r) => r < 0xD800 || r > 0xDFFF), isTrue);
    });
  });

  group('MarkdownPreviewText', () {
    test('block markers, inline marks, links, images and HTML removed', () {
      const text =
          '﻿# 제목 하나\r\n'
          '\r\n'
          '> 인용 **굵게** 와 *기울임* ~~취소~~\r\n'
          '- [x] 할 일 `코드`\r\n'
          '1. 번호 [링크](https://example.com) ![그림](a.png)\r\n'
          '| 칸1 | 칸2 |\r\n'
          '|---|:-:|\r\n'
          '---\r\n'
          '```dart\r\n'
          'var snake_case = 1;\r\n'
          '```\r\n'
          '<br>끝 <b>태그</b>\r\n';
      expect(
        MarkdownPreviewText.of(text),
        '제목 하나\n'
        '인용 굵게 와 기울임 취소\n'
        '할 일 코드\n'
        '번호 링크 그림\n'
        '칸1 칸2\n'
        'var snake_case = 1;\n'
        '끝 태그',
      );
    });

    test(
      'front matter skipped; maxChars cut, never inside a surrogate pair',
      () {
        expect(
          MarkdownPreviewText.of('---\ntitle: x\ntags: [a]\n---\n본문'),
          '본문',
        );
        expect(MarkdownPreviewText.of('a' * 1000).length, 400);
        expect(MarkdownPreviewText.of('abcdef', maxChars: 3), 'abc');
        expect(MarkdownPreviewText.of('a😀', maxChars: 2), 'a');
        expect(MarkdownPreviewText.of('x', maxChars: 0), '');
        expect(MarkdownPreviewText.of(''), '');
      },
    );

    test('math dollars, footnote marks and \$\$ lines removed (cards read as text)', () {
      expect(
        MarkdownPreviewText.of(
          r'수식 $E = mc^2$ 도 있어요.[^1]'
          '\n\$\$\n\\int_0^1 x\\,dx\n\$\$\n[^1]: 각주예요.',
        ),
        '수식 E = mc^2 도 있어요.\n\\int_0^1 x\\,dx\n각주예요.',
      );
      // Prices are not math.
      expect(MarkdownPreviewText.of(r'$5 and $6'), r'$5 and $6');
      expect(MarkdownPreviewText.of(r'가격 $5$9'), r'가격 $5$9');
    });
  });
}
