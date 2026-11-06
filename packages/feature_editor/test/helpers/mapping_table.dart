// test/helpers/mapping_table.dart — m5-7/04-editor 5.1.2 '명령 매핑 전체',
// 9.3, 8.2 E2-00.
//
// The EDITOR action → CORE command table (every row = one undo step), with
// the test file that covers each row. Every covering test is the completion
// test of a P-A task (revision 3: the auto-shape row is covered by E2-09,
// not by the P-B E2-15), so cutting P-B work never leaves a row uncovered.
// unit/mapping_coverage_test.dart (E2-22) checks that each covering file
// exists, names the row's command label and asserts the undo step.

/// One row of the table.
final class MappingRow {
  const MappingRow({
    required this.action,
    required this.command,
    required this.labels,
    required this.coveredBy,
    required this.task,
  });

  /// The user action (plan wording).
  final String action;

  /// The call, as the plan writes it.
  final String command;

  /// EditCommand.label of the command the row sends (alternatives: either
  /// one, e.g. a composite or its only non-empty part).
  final Set<String> labels;

  /// The covering test file, relative to test/.
  final String coveredBy;

  /// The P-A task whose completion test is [coveredBy] ('1차' = 1st round).
  final String task;
}

/// 1st-round rows (1st plan 5.1.3) and 2nd-round rows (m5-7 5.1.2), in plan
/// order.
const kEditorCommandMapping = <MappingRow>[
  // ---- 1st round (regression — 1st plan 5.1.3) ----------------------------
  MappingRow(
    action: '펜 획(펜을 뗌)',
    command: 'edit.toCommand() = AddStrokes(pageId:, strokes: edit.added)',
    labels: {'add-strokes'},
    coveredBy: 'widget/pen_stroke_test.dart',
    task: '1차',
  ),
  MappingRow(
    action: '지우개 제스처(획/부분)',
    command: 'edit.toCommand() = RemoveStrokes / SplitStrokes',
    labels: {'remove-strokes', 'split-strokes'},
    coveredBy: 'widget/erase_test.dart',
    task: '1차',
  ),
  MappingRow(
    action: '올가미 이동·크기',
    command: 'commitTransform()!.toCommand() = TransformElements(…)',
    labels: {'transform'},
    coveredBy: 'widget/lasso_test.dart',
    task: '1차',
  ),
  MappingRow(
    action: '선택 삭제',
    command: 'selection.delete().toCommand() = RemoveStrokes(…)',
    labels: {'remove-strokes', 'remove-elements'},
    coveredBy: 'widget/lasso_test.dart',
    task: '1차',
  ),
  MappingRow(
    action: '현재 페이지 전체 지우기',
    command: 'ClearPage(pageId:, filter:)',
    labels: {'clear-page'},
    coveredBy: 'widget/erase_test.dart',
    task: '1차',
  ),
  MappingRow(
    action: '페이지 추가(앞/뒤/끝)',
    command: 'InsertPages(drafts: [PageDraft(…)], position: …)',
    labels: {'insert-pages'},
    coveredBy: 'widget/add_page_sheet_test.dart',
    task: '1차',
  ),
  MappingRow(
    action: '페이지 복제(1장/선택)',
    command: 'DuplicatePages(pageIds:)',
    labels: {'duplicate-pages'},
    coveredBy: 'widget/page_panel_test.dart',
    task: '1차',
  ),
  MappingRow(
    action: '페이지 삭제(1장/선택)',
    command: 'DeletePages(pageIds:)',
    labels: {'delete-pages'},
    coveredBy: 'widget/page_panel_test.dart',
    task: '1차',
  ),
  MappingRow(
    action: '페이지 이동',
    command: 'MovePages(pageIds: [id], position: …)',
    labels: {'move-pages'},
    coveredBy: 'widget/page_panel_test.dart',
    task: '1차',
  ),
  MappingRow(
    action: '합성 획 N개(개발자 메뉴)',
    command: 'AddStrokes(pageId:, strokes: InkDevTools.syntheticStrokes(…))',
    labels: {'add-strokes'},
    coveredBy: 'widget/dev_menu_test.dart',
    task: '1차',
  ),
  // ---- 2nd round (m5-7/04-editor 5.1.2) -----------------------------------
  MappingRow(
    action: '도형 도구로 끌어 그리기',
    command: 'AddObjects(pageId: p, objects: [shape])',
    labels: {'add-objects'},
    coveredBy: 'widget/shape_tool_test.dart',
    task: 'E2-09',
  ),
  MappingRow(
    action: '자동 도형 보정 확정',
    command:
        'InkEdit(addShape).toCommand() = AddObjects(pageId: p, '
        'objects: addedObjects)',
    labels: {'add-objects'},
    coveredBy: 'widget/shape_tool_test.dart',
    task: 'E2-09',
  ),
  MappingRow(
    action: '텍스트 편집 세션 끝(새 상자, 내용 있음 / 기존 상자, 바뀜)',
    command:
        'AddObjects(…, objects: [draft]) / UpdateObjects(…, '
        'objects: [draft])',
    labels: {'add-objects', 'update-objects'},
    coveredBy: 'widget/text_box_test.dart',
    task: 'E2-10',
  ),
  MappingRow(
    action: '텍스트 편집 세션 끝(기존 상자, 내용을 모두 지움)',
    command: 'RemoveElements(pageId: p, elementIds: [boxId])',
    labels: {'remove-elements'},
    coveredBy: 'widget/text_box_test.dart',
    task: 'E2-10',
  ),
  MappingRow(
    action: '텍스트 편집 세션 끝(기존 상자, 그 사이 원격 삭제)',
    command: 'AddObjects(…, objects: [draft.copyTo(id: 새 id, …)])',
    labels: {'add-objects'},
    coveredBy: 'widget/text_box_test.dart',
    task: 'E2-10',
  ),
  MappingRow(
    action: '단일 객체 변 핸들·텍스트 폭 핸들·꼭짓점 이동·도형 스타일 변경',
    command: 'UpdateObjects(pageId: p, objects: [...])',
    labels: {'update-objects'},
    coveredBy: 'widget/object_handles_test.dart',
    task: 'E2-08',
  ),
  MappingRow(
    action: '이동·모서리 핸들·회전 핸들·90° 돌리기',
    command:
        'setPreviewTransform(m) → commitTransform() → '
        'TransformElements(…, scaleStrokeWidth: true)',
    labels: {'transform'},
    coveredBy: 'widget/rotate_test.dart',
    task: 'E2-06',
  ),
  MappingRow(
    action: '색 변경',
    command:
        'InkSelection.recolor(argb) → CompositeCommand([RestyleStrokes, '
        'UpdateObjects])',
    labels: {'composite', 'restyle', 'update-objects'},
    coveredBy: 'widget/recolor_test.dart',
    task: 'E2-07b',
  ),
  MappingRow(
    action: '잘라내기',
    command:
        '클립보드 복사 + InkSelection.delete() → RemoveStrokes / '
        'RemoveElements',
    labels: {'remove-strokes', 'remove-elements'},
    coveredBy: 'widget/selection_menu_test.dart',
    task: 'E2-07b',
  ),
  MappingRow(
    action: '붙여넣기',
    command: 'CompositeCommand([AddStrokes, AddObjects]) — 빈 쪽은 뺌',
    labels: {'composite', 'add-strokes', 'add-objects'},
    coveredBy: 'widget/paste_test.dart',
    task: 'E2-07a',
  ),
  MappingRow(
    action: '복제',
    command:
        'InkSelection.duplicate() → CompositeCommand([AddStrokes, '
        'AddObjects])',
    labels: {'composite', 'add-strokes', 'add-objects'},
    coveredBy: 'widget/selection_menu_test.dart',
    task: 'E2-07b',
  ),
  MappingRow(
    action: '이미지 삽입',
    command: 'AddObjects(pageId: p, objects: [image])',
    labels: {'add-objects'},
    coveredBy: 'widget/image_insert_test.dart',
    task: 'E2-12',
  ),
  MappingRow(
    action: '이미지 페이지',
    command:
        'InsertPages(drafts: [PageDraft(size:, background: '
        'ImageBackground(…))], position: …)',
    labels: {'insert-pages'},
    coveredBy: 'widget/add_page_sheet_test.dart',
    task: 'E2-12',
  ),
  MappingRow(
    action: '현재 페이지 전체 지우기(객체 포함)',
    command: 'ClearPage(pageId: p, filter: f, includeObjects: true)',
    labels: {'clear-page'},
    coveredBy: 'widget/erase_v2_test.dart',
    task: 'E2-19',
  ),
  MappingRow(
    action: '획 지우개가 도형에 닿음',
    command:
        'InkEdit(eraseStrokes, removedObjectIds: {도형}).toCommand() → '
        'RemoveElements(…)',
    labels: {'remove-elements'},
    coveredBy: 'widget/erase_v2_test.dart',
    task: 'E2-19',
  ),
  MappingRow(
    action: '부분 지우개가 도형에 닿음',
    command:
        'InkEdit(splitStrokes, removedObjectIds: {도형}).toCommand() → '
        'CompositeCommand([SplitStrokes 또는 RemoveStrokes, RemoveElements])',
    labels: {'composite', 'remove-elements'},
    coveredBy: 'widget/erase_v2_test.dart',
    task: 'E2-19',
  ),
  MappingRow(
    action: '확장 항목(recog 변환 등)',
    command: '자리 문맥의 execute(command) 한 번',
    labels: {},
    coveredBy: 'widget/selection_extensions_test.dart',
    task: 'E2-07c',
  ),
];

/// P-B / P-C task ids of m5-7/04-editor 8.2 — no row may be covered by them.
const kNotPaTasks = {'E2-10b', 'E2-11', 'E2-15', 'E2-18', 'E2-20'};
