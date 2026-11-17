// B-8 / MD-T16 (08-markdown 4.6): BOM and CRLF are stripped for the editor and restored on
// save, so an untouched document round-trips byte for byte and an edited one keeps them.
import 'dart:convert';

import 'package:feature_markdown/src/edit/line_endings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const bom = '﻿';

  test('round trip: LF, CRLF, BOM + CRLF, Korean and emoji', () {
    for (final raw in [
      '',
      '# 제목\n본문 😀\n',
      '# 제목\r\n본문 😀\r\n',
      '$bom# 제목\r\n\r\n- [ ] 할 일\r\n',
      '${bom}no newline',
      '끝에 줄바꿈 없음\r\n마지막',
    ]) {
      final codec = LineEndingCodec.of(raw);
      final decoded = codec.decode(raw);
      expect(decoded, isNot(contains('\r\n')));
      expect(decoded.startsWith(bom), isFalse);
      expect(codec.encode(decoded), raw, reason: jsonEncode(raw));
      expect(utf8.encode(codec.encode(decoded)), utf8.encode(raw));
    }
  });

  test('an edit keeps BOM and CRLF', () {
    const raw = '$bom첫 줄\r\n둘째 줄\r\n';
    final codec = LineEndingCodec.of(raw);
    expect(codec, const LineEndingCodec(bom: true, crlf: true));
    final edited = '${codec.decode(raw)}셋째 줄\n';
    expect(codec.encode(edited), '$bom첫 줄\r\n둘째 줄\r\n셋째 줄\r\n');
  });

  test(
    'mixed endings: decode keeps lone LF, encode unifies to the majority',
    () {
      const raw = 'a\r\nb\r\nc\nd';
      final codec = LineEndingCodec.of(raw);
      expect(codec.crlf, isTrue);
      expect(codec.decode(raw), 'a\nb\nc\nd');
      expect(codec.encode(codec.decode(raw)), 'a\r\nb\r\nc\r\nd');
      expect(LineEndingCodec.of('a\nb\nc\r\nd').crlf, isFalse);
    },
  );

  test('pasted CRLF in the editor does not double the CR', () {
    const codec = LineEndingCodec(bom: false, crlf: true);
    expect(codec.encode('a\r\nb'), 'a\r\nb');
    expect(
      const LineEndingCodec(bom: false, crlf: false).encode('a\r\nb'),
      'a\nb',
    );
  });
}
