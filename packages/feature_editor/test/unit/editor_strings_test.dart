// E-00: the two storage-warning sentences equal the contract 7.4.5 v1.1 fixed
// sentences. E2-00 (m5-7/04-editor 1.2, 6.12.1, 6.14.1, 6.21): the 2nd-round
// strings the plan spells out word for word.
// sentences (C11-24, 04-editor 6.17.3 ①). The expected values are literals in
// this file on purpose: they are copied from 00-overview 7.4.5, not from lib/.
import 'dart:io';

import 'package:feature_editor/src/ui/editor_strings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart' as core;

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
  group('2nd round (E2-00)', () {
    test('the ten pen names of the picker (6.14.1)', () {
      expect(
        {for (final t in core.PenTool.values) t: EditorStrings.penTypeName(t)},
        {
          core.PenTool.ballpoint: '볼펜',
          core.PenTool.fountain: '만년필',
          core.PenTool.highlighter: '형광펜',
          core.PenTool.pencil: '연필',
          core.PenTool.marker: '마커',
          core.PenTool.brush: '붓펜',
          core.PenTool.calligraphy: '캘리그래피',
          core.PenTool.dashed: '점선',
          core.PenTool.laser: '레이저',
          core.PenTool.tape: '암기 테이프',
          // (C211-01) texture and decoration pens
          core.PenTool.crayon: '크레파스',
          core.PenTool.chalk: '분필',
          core.PenTool.watercolor: '수채',
          core.PenTool.spray: '스프레이',
          core.PenTool.neon: '네온',
          core.PenTool.jelly: '젤리',
          core.PenTool.rainbow: '무지개',
          core.PenTool.glitter: '반짝이',
        },
      );
    });

    test('image sources (6.12.1)', () {
      expect(
        [
          for (final s in core.ImageImportSource.values)
            EditorStrings.imageSourceName(s),
        ],
        ['사진 보관함', '카메라로 찍기', '파일에서', '붙여넣기'],
      );
    });

    test('the object limit sentence groups the number (6.21)', () {
      expect(
        EditorStrings.objectLimitReached(
          core.PageObjectLimits.maxObjectsPerPage,
        ),
        '이 페이지에는 더 넣을 수 없어요(최대 2,000개)',
      );
      expect(
        EditorStrings.objectLimitReached(999),
        '이 페이지에는 더 넣을 수 없어요(최대 999개)',
      );
      expect(
        EditorStrings.textTooLong(core.PageObjectLimits.maxTextLength),
        '글자는 10,000자까지 쓸 수 있어요',
      );
    });

    test('error and notice sentences (6.21)', () {
      expect(EditorStrings.imageInsertFailed, '이미지를 넣지 못했어요');
      expect(EditorStrings.recordingPanelFailed, '녹음 패널을 열지 못했어요');
      expect(EditorStrings.recordingInOtherNote, '다른 노트에서 녹음 중이에요');
      expect(EditorStrings.textCopiedToClipboard, '편집한 글을 클립보드에 복사해 두었어요');
      expect(EditorStrings.commandFailed, '실행하지 못했어요');
    });

    test('every shape kind has a name (6.9.1)', () {
      expect(
        [for (final k in core.ShapeKind.values) EditorStrings.shapeKindName(k)],
        ['직선', '화살표', '사각형', '원/타원', '삼각형', '다각형', '별'],
      );
    });
  });
}
