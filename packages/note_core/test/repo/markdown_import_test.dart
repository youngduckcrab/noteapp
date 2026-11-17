// (v2.17-md, C217M-16, m5-7/08-markdown 10.2, MD-T06) MarkdownImport.decode: UTF-8 only, the
// bytes kept exactly (BOM, CRLF, Korean, emoji, 4-byte characters), NUL → notText, CP949 →
// notUtf8, over the limits → tooLarge, and the title rules.
import 'dart:convert';
import 'dart:typed_data';

import 'package:note_core/note_core.dart';
import 'package:test/test.dart';

Uint8List _b(List<int> bytes) => Uint8List.fromList(bytes);

void main() {
  group('byte round trip: utf8.encode(decode(b).text) == b', () {
    final cases = <String, List<int>>{
      'BOM + CRLF + Korean + emoji': [
        0xEF, 0xBB, 0xBF, //
        ...utf8.encode('# 회의 메모\r\n\r\n- [ ] 발표 🙂\r\n'),
      ],
      'two BOMs': [0xEF, 0xBB, 0xBF, 0xEF, 0xBB, 0xBF, ...utf8.encode('a')],
      'a BOM in the middle': utf8.encode('a\uFEFFb'),
      '4-byte characters': utf8.encode('𝄞 𠀀 😀'),
      'mixed line ends': utf8.encode('a\r\nb\nc\rd'),
      'empty file': const [],
      'only a BOM': const [0xEF, 0xBB, 0xBF],
      'tabs and control characters (not NUL)': utf8.encode('\t\u0007\u001b[0m'),
    };
    for (final MapEntry(key: name, value: bytes) in cases.entries) {
      test(name, () {
        final r = MarkdownImport.decode(_b(bytes), fileName: 'a.md');
        expect(r.isOk, isTrue, reason: '$r');
        expect(utf8.encode(r.text!), bytes);
      });
    }
  });

  test('NUL → notText; CP949 → notUtf8; lone surrogate bytes → notUtf8', () {
    expect(
      MarkdownImport.decode(_b([0x61, 0x00, 0x62]), fileName: 'a.md').failure,
      MarkdownDecodeFailure.notText,
    );
    // '한글' in CP949 / EUC-KR.
    expect(
      MarkdownImport.decode(
        _b([0xC7, 0xD1, 0xB1, 0xDB]),
        fileName: 'a.md',
      ).failure,
      MarkdownDecodeFailure.notUtf8,
    );
    expect(
      MarkdownImport.decode(_b([0xED, 0xA0, 0x80]), fileName: 'a.md').failure,
      MarkdownDecodeFailure.notUtf8,
    );
  });

  test('over the limits → tooLarge (text bytes, and the encoded record)', () {
    expect(
      MarkdownImport.decode(
        _b(List.filled(MarkdownLimits.maxTextBytes + 1, 0x61)),
        fileName: 'a.md',
      ).failure,
      MarkdownDecodeFailure.tooLarge,
    );
    expect(
      MarkdownImport.decode(
        _b(List.filled(MarkdownLimits.maxTextBytes, 0x61)),
        fileName: 'a.md',
      ).isOk,
      isTrue,
    );
    // ESC is 1 byte in the file, 6 in a sync record.
    expect(
      MarkdownImport.decode(
        _b(List.filled(200000, 0x1B)),
        fileName: 'a.md',
      ).failure,
      MarkdownDecodeFailure.tooLarge,
    );
  });

  group('title', () {
    String title(String fileName, [String text = '']) =>
        MarkdownImport.decode(_b(utf8.encode(text)), fileName: fileName).title!;

    test('the file name without its extension, trimmed', () {
      expect(title('  회의록 .md'), '회의록');
      expect(title('강의.markdown'), '강의');
      expect(title('plan.v2.MD'), 'plan.v2');
      expect(title('readme.txt', '# 프로젝트 소개\n'), '프로젝트 소개');
      expect(title('/storage/emulated/0/Download/강의.md'), '강의');
      expect(title(r'C:\docs\보고서.md'), '보고서');
      expect(title('.md'), '.md');
    });

    test('decomposed Hangul (macOS names) is composed (NFC)', () {
      // '한글' as conjoining jamo.
      const nfd = '\u1112\u1161\u11AB\u1100\u1173\u11AF';
      expect(title('$nfd.md'), '한글');
      expect(MarkdownImport.composeHangul('\uAC00\u11A8'), '각');
    });

    test('a generic name takes the front matter title, then the first h1', () {
      expect(
        title('README.md', '---\ntitle: "정리 노트"\ntags: [a]\n---\n# 다른 제목\n'),
        '정리 노트',
      );
      expect(title('README.md', '```\n# 코드 안\n```\n# **진짜** 제목 #\n'), '진짜 제목');
      expect(title('index.md', '본문만'), 'index');
      expect(title('제목 없음.txt', ''), '제목 없음');
      expect(title('', ''), MarkdownImport.fallbackTitle);
      expect(title('   .md', ''), MarkdownImport.fallbackTitle);
    });

    test('at most 200 characters, never inside a surrogate pair', () {
      final long = '${'가' * 199}😀😀';
      final t = title('$long.md');
      expect(t.length, lessThanOrEqualTo(200));
      expect(t, '가' * 199);
    });
  });
}
