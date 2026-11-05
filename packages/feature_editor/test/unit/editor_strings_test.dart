// E-00: the two storage-warning sentences equal the contract 7.4.5 v1.1 fixed
// sentences (C11-24, 04-editor 6.17.3 ①). The expected values are literals in
// this file on purpose: they are copied from 00-overview 7.4.5, not from lib/.
import 'dart:io';

import 'package:feature_editor/src/ui/editor_strings.dart';
import 'package:flutter_test/flutter_test.dart';

/// Contract 7.4.5 v1.1: `writeFailing`.
const _contractWriteFailing = '저장에 계속 실패하고 있어요. 브라우저 저장 공간을 확인해 주세요.';

/// Contract 7.4.5 v1.1: `notDurable`.
const _contractNotDurable = '이 브라우저에서는 노트가 임시로만 저장돼요. 테스트 용도로만 사용하세요.';

void main() {
  test('storageWriteFailing is the contract 7.4.5 fixed sentence', () {
    expect(EditorStrings.storageWriteFailing, _contractWriteFailing);
  });

  test('storageNotDurable is the contract 7.4.5 fixed sentence', () {
    expect(EditorStrings.storageNotDurable, _contractNotDurable);
  });

  test('lib/ spells the fixed sentences only in editor_strings.dart', () {
    // The banner must read the constants; a second copy could drift.
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.path.endsWith('editor_strings.dart')) continue;
      final text = entity.readAsStringSync();
      if (text.contains('저장에 계속 실패하고') || text.contains('노트가 임시로만 저장돼요')) {
        offenders.add(entity.path);
      }
    }
    expect(offenders, isEmpty);
  });
}
