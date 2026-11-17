// (v2.17-md, C217M-08, m5-7/08-markdown 6) The search units of an MD 문서 body.
import 'package:note_core/src/search/markdown_index_text.dart';
import 'package:test/test.dart';

void main() {
  List<String> units(String text) => MarkdownIndexText.units(text);

  test('blocks at blank lines, markers and marks removed', () {
    expect(
      units(
        '\uFEFF# 제목 #\r\n\r\n문단 **굵게** 와 [링크](https://example.com)\r\n'
        '둘째 줄\r\n\r\n- [x] 할 일\n  - 중첩 `코드`\n\n> 인용 ![그림](a.png)\n\n---\n',
      ),
      ['제목', '문단 굵게 와 링크\n둘째 줄', '할 일\n중첩 코드', '인용 그림'],
    );
  });

  test(
    'fenced code and \$\$ math stay one block, blank lines inside included',
    () {
      expect(
        units(
          '```dart\nvoid main() {\n\n  print(1);\n}\n```\n\n\$\$\na^2\n\nb\n\$\$\n\n\$\$ x+1 \$\$',
        ),
        ['void main() {\n\n  print(1);\n}', 'a^2\n\nb', 'x+1'],
      );
      // An unclosed fence runs to the end.
      expect(units('~~~\n코드'), ['코드']);
    },
  );

  test('front matter is its own unit; tables lose the separator row', () {
    expect(
      units('---\ntitle: 메모\n---\n| 이름 | 값 |\n|:---|---:|\n| 사과 | 1 |\n'),
      ['title: 메모', '이름 값\n사과 1'],
    );
  });

  test('a block over 1,000 characters is split, nothing cut off', () {
    final words = [for (var i = 0; i < 400; i++) '단어$i'];
    final text = words.join(' ');
    final us = units(text);
    expect(us.length, greaterThan(1));
    for (final u in us) {
      expect(u.length, lessThanOrEqualTo(MarkdownIndexText.maxUnitChars));
    }
    expect(us.join(' ').split(' '), words);
    // No break point at all: hard split, surrogate pairs kept whole.
    final emoji = '😀' * 700;
    final parts = units(emoji);
    expect(parts.join(), emoji);
    for (final p in parts) {
      expect(p.length, lessThanOrEqualTo(1000));
    }
  });

  test('empty and whitespace-only text has no unit', () {
    expect(units(''), isEmpty);
    expect(units('\n\n   \n'), isEmpty);
    expect(units('---\n'), isEmpty);
  });
}
