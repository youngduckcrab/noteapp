// m5-7/04-editor 8.2 E2-22, 9.3, 10 #4: every row of the EDITOR action →
// CORE command table (test/helpers/mapping_table.dart — 5.1.2 '명령 매핑
// 전체' + the 1st-round rows) is covered: its covering test file exists,
// names the row's command label (the recorder's 'execute:<label>' /
// 'executeAsync:<label>' or the history's undoLabel) and asserts the undo
// step (history.undoDepth / undoLabel). Every covering test is the
// completion test of a P-A task (or a 1st-round test), so cutting P-B / P-C
// work never leaves a row uncovered (revision 3).
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/mapping_table.dart';

/// The covering file's text (the package root is the working directory of
/// `flutter test`).
String? _source(String coveredBy) {
  final file = File('test/$coveredBy');
  return file.existsSync() ? file.readAsStringSync() : null;
}

/// Whether [source] names [label] as a command label: a string literal
/// 'label' or a recorder call ':label' ('execute:label', …).
bool _namesLabel(String source, String label) =>
    source.contains("'$label'") ||
    source.contains('"$label"') ||
    source.contains(':$label');

void main() {
  test('the table has the 1st-round rows and the 2nd-round rows of 5.1.2', () {
    final firstRound = kEditorCommandMapping.where((r) => r.task == '1차');
    final secondRound = kEditorCommandMapping.where((r) => r.task != '1차');
    expect(firstRound, hasLength(10));
    expect(secondRound, hasLength(17));
    // The 2nd-round actions of 5.1.2, in plan order.
    expect(secondRound.map((r) => r.action).toList(), [
      '도형 도구로 끌어 그리기',
      '자동 도형 보정 확정',
      '텍스트 편집 세션 끝(새 상자, 내용 있음 / 기존 상자, 바뀜)',
      '텍스트 편집 세션 끝(기존 상자, 내용을 모두 지움)',
      '텍스트 편집 세션 끝(기존 상자, 그 사이 원격 삭제)',
      '단일 객체 변 핸들·텍스트 폭 핸들·꼭짓점 이동·도형 스타일 변경',
      '이동·모서리 핸들·회전 핸들·90° 돌리기',
      '색 변경',
      '잘라내기',
      '붙여넣기',
      '복제',
      '이미지 삽입',
      '이미지 페이지',
      '현재 페이지 전체 지우기(객체 포함)',
      '획 지우개가 도형에 닿음',
      '부분 지우개가 도형에 닿음',
      '확장 항목(recog 변환 등)',
    ]);
  });

  test('no row is covered by a P-B / P-C task', () {
    for (final row in kEditorCommandMapping) {
      expect(kNotPaTasks, isNot(contains(row.task)), reason: row.action);
    }
  });

  for (final row in kEditorCommandMapping) {
    test('${row.action} → ${row.coveredBy}', () {
      final source = _source(row.coveredBy);
      expect(source, isNotNull, reason: 'test/${row.coveredBy} is missing');
      // The undo step is asserted (one action = one step).
      expect(
        source!.contains('undoDepth') || source.contains('undoLabel'),
        isTrue,
        reason: '${row.coveredBy} asserts no undo step',
      );
      if (row.labels.isEmpty) {
        // The extension items: the context's execute(command) — any
        // command, one step (the covering test runs one and counts it).
        expect(source, contains('execute'));
        return;
      }
      expect(
        row.labels.any((label) => _namesLabel(source, label)),
        isTrue,
        reason: '${row.coveredBy} names none of ${row.labels}',
      );
    });
  }
}
