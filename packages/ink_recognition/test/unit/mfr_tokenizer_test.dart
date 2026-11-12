// The on-device math engine's detokenizer (ondevice/mfr_tokenizer.dart)
// against the reference: ids produced by the int8 model in the PC
// evaluation and `tokenizers.Tokenizer.decode(ids, skip_special_tokens=True)`
// (test/fixtures/mfr/mfr_decode_cases.json), with the committed
// tokenizer.json (hosting/models/…).
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_recognition/src/ondevice/mfr_tokenizer.dart';

import '../support/math_model_fakes.dart';

void main() {
  late MfrTokenizer tokenizer;
  late Map<String, Object?> fixtures;

  setUpAll(() {
    tokenizer = MfrTokenizer.fromJson(
      File('${committedModelDir()}/tokenizer.json').readAsStringSync(),
    );
    fixtures = jsonDecode(
      File('${mfrFixtures()}/mfr_decode_cases.json').readAsStringSync(),
    ) as Map<String, Object?>;
  });

  test('the vocabulary has the model\'s 1868 ids', () {
    expect(tokenizer.vocabSize, 1868);
  });

  test('model outputs decode like the reference', () {
    final cases = (fixtures['cases']! as List).cast<Map<String, Object?>>();
    expect(cases, hasLength(greaterThanOrEqualTo(10)));
    for (final c in cases) {
      final ids = (c['ids']! as List).cast<int>();
      expect(ids.first, 1, reason: 'starts with <s>');
      expect(tokenizer.decode(ids), c['text'], reason: '${c['source']}');
    }
  });

  test('byte-level details: partial UTF-8, multi-byte tokens, Ġ spaces, '
      'special ids skipped', () {
    final extra = (fixtures['extra']! as List).cast<Map<String, Object?>>();
    for (final c in extra) {
      final ids = (c['ids']! as List).cast<int>();
      expect(tokenizer.decode(ids), c['text'], reason: '$ids');
    }
  });

  test('out-of-range ids are skipped; empty input → empty text', () {
    expect(tokenizer.decode([1, -1, 99999, 2]), '');
    expect(tokenizer.decode(const []), '');
  });

  test('a file of another layout is a FormatException', () {
    expect(() => MfrTokenizer.fromJson('[]'), throwsFormatException);
    expect(
      () => MfrTokenizer.fromJson('{"model": {"type": "BPE"}}'),
      throwsFormatException,
    );
    expect(() => MfrTokenizer.fromJson('not json'), throwsFormatException);
  });

  test('a minimal vocabulary: specials from added_tokens', () {
    final t = MfrTokenizer.fromJson(
      jsonEncode({
        'added_tokens': [
          {'id': 0, 'content': '<x>', 'special': true},
        ],
        'model': {
          'vocab': {'<x>': 0, 'a': 1, 'Ġb': 2},
        },
      }),
    );
    expect(t.decode([0, 1, 2, 0]), 'a b');
  });
}
