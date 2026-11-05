// lib/src/ui/editor_strings.dart — 04-editor 3 / 6.17, contract 7.4.5.
//
// User-facing strings of the editor: Korean 해요체, no intl (contract 7.4.5).
// Developer-only details and logs stay in English. Every user-visible sentence
// of feature_editor lives in this one table; later tasks add the strings of
// their screens (toolbar, pen settings, page panel, developer overlay) here.
import 'package:note_core/note_core.dart' as core;

abstract final class EditorStrings {
  // ---------------------------------------------------------------------------
  // Storage warning banner (04-editor 6.17.3) — contract 7.4.5 v1.1 FIXED
  // sentences (C11-24). LIBRARY shows the same two sentences on its screen;
  // unit/editor_strings_test.dart compares them with the contract text. Change
  // them only through the contract 7.4.12 procedure.
  // ---------------------------------------------------------------------------

  /// `StorageWarning.writeFailing` (contract 7.4.5 v1.1).
  static const storageWriteFailing = '저장에 계속 실패하고 있어요. 브라우저 저장 공간을 확인해 주세요.';

  /// `StorageWarning.notDurable` (contract 7.4.5 v1.1).
  static const storageNotDurable = '이 브라우저에서는 노트가 임시로만 저장돼요. 테스트 용도로만 사용하세요.';

  /// Snack bar for a new `PersistenceStatus.lastErrorAt` (6.17.3, at most
  /// once every 5 s).
  static const storageErrorSnack = '저장 중 문제가 생겼어요';

  // ---------------------------------------------------------------------------
  // Toolbar (04-editor 6.9.1). No tooltips; these are semantics labels.
  // ---------------------------------------------------------------------------

  /// Semantics label of the toolbar back button ([←], 04-editor 6.9.1).
  static const back = '뒤로';

  /// Semantics label of the more menu button ([⋯], 04-editor 6.9.1).
  static const more = '더보기';

  /// More menu item, shown only when EditorScreen.onOpenSettings != null.
  static const settings = '설정';

  /// Semantics label of [↶] (04-editor 6.8, 6.9.1).
  static const undo = '되돌리기';

  /// Semantics label of [↷].
  static const redo = '다시 실행';

  /// Tool buttons (6.9.1).
  static const pen = '펜';
  static const eraser = '지우개';
  static const lasso = '올가미';

  /// [✋] on (InputMode.fingerDrawing) / off (InputMode.penOnly).
  static const fingerDrawingOn = '손가락 필기 켜짐';
  static const fingerDrawingOff = '손가락 필기 꺼짐';

  /// Semantics hint of the zoom chip (tap = fit width).
  static const zoomToFit = '너비 맞춤';

  /// Pen type names (6.9.3 #1; P1 types for stored styles).
  static String penTypeName(core.PenTool tool) => switch (tool) {
    core.PenTool.ballpoint => '볼펜',
    core.PenTool.fountain => '만년필',
    core.PenTool.highlighter => '형광펜',
    core.PenTool.pencil => '연필',
    core.PenTool.marker => '마커',
    core.PenTool.brush => '붓',
    core.PenTool.calligraphy => '캘리그래피',
    core.PenTool.dashed => '점선 펜',
    core.PenTool.laser => '레이저 펜',
    core.PenTool.tape => '테이프',
  };

  /// Sync icon semantics (6.9.1 — same words as LIBRARY 6.16).
  static const syncDone = '동기화됨';
  static const syncInProgress = '동기화 중';
  static const syncOffline = '오프라인';
  static const syncError = '동기화 오류';

  // ---------------------------------------------------------------------------
  // More menu (04-editor 6.9.1) and note info (6.17.4).
  // ---------------------------------------------------------------------------

  static const pageFlip = '페이지 넘김';
  static const pageFlipVertical = '세로 스크롤';
  static const pageFlipHorizontal = '좌우 넘기기';
  static const devOverlay = '개발자 표시';
  static const noteInfo = '노트 정보';
  static const noteInfoTitle = '제목';
  static const noteInfoPages = '페이지 수';
  static const noteInfoCreated = '만든 날짜';
  static const noteInfoUpdated = '고친 날짜';
  static const close = '닫기';

  // ---------------------------------------------------------------------------
  // Popups (04-editor 6.9.2). The panels' own strings come with E-14..E-16.
  // ---------------------------------------------------------------------------

  static const penSettings = '펜 설정';
  static const quickPen = '빠른 펜';
  static const eraserSettings = '지우개 설정';

  // ---------------------------------------------------------------------------
  // Colour (04-editor 6.9.3 #4–#6, 6.9.5) and the stroke eyedropper (6.6.8).
  // ---------------------------------------------------------------------------

  /// SegmentedButton[휠 | 사각].
  static const colorWheel = '휠';
  static const colorSquare = '사각';

  /// Semantics labels of the hue and value sliders.
  static const colorHue = '색상';
  static const colorValue = '밝기';

  /// Labels of the HEX and R / G / B fields.
  static const colorHex = 'HEX';
  static const colorRed = 'R';
  static const colorGreen = 'G';
  static const colorBlue = 'B';

  static const recentColors = '최근 색';

  /// Shown instead of the recent colours before the first committed stroke.
  static const noRecentColors = '획을 그리면 그 색이 여기에 모여요';

  static const userPalette = '내 팔레트';

  /// Semantics label of the palette's [+] (adds the current colour).
  static const addToPalette = '팔레트에 추가';

  /// Long-press menu item of a palette colour.
  static const paletteDelete = '삭제';

  /// [스포이드] in the pen settings panel.
  static const eyedropper = '스포이드';

  /// Banner over the canvas while the eyedropper waits for a tap (6.6.8).
  static const eyedropperBanner = '획을 탭하면 그 색을 가져와요';

  /// The eyedropper took a stroke's colour.
  static const eyedropperPicked = '색을 가져왔어요';

  /// The eyedropper found no stroke under the tap.
  static const eyedropperMissed = '여기엔 획이 없어요';

  // ---------------------------------------------------------------------------
  // Screen states (04-editor 6.17.1) and leaving (6.17.4).
  // ---------------------------------------------------------------------------

  static const openingNote = '노트를 여는 중…';
  static const noteNotFound = '노트를 찾을 수 없어요';
  static const openFailed = '노트를 열지 못했어요';
  static const retry = '다시 시도';
  static const goBack = '돌아가기';

  /// A note with zero pages (guard against a CORE rule violation, 6.17.1).
  static const noPages = '페이지가 없어요';

  /// Button under [noPages]; hidden when the note is read only.
  static const addPage = '페이지 추가';

  /// Shown when leaving waits on `flush()` for more than 300 ms (6.17.4).
  static const saving = '저장하는 중…';

  // ---------------------------------------------------------------------------
  // Read only (04-editor 6.17.2, N-4) and rejected commands (5.1.3).
  // ---------------------------------------------------------------------------

  /// Read-only banner for a note in the trash.
  static const readOnlyTrashed = '휴지통에 있는 노트라 읽기만 할 수 있어요';

  /// Read-only banner for a note made by a newer app (`requiresNewerApp`).
  static const readOnlyNewerApp =
      '새 버전 앱에서 만든 노트라 읽기만 할 수 있어요. 앱을 새로고침해 최신 버전을 받아 주세요.';

  /// Toast when CORE refuses an edit with ReadOnlyNoteException (5.1.3).
  static const readOnlyToast = '읽기 전용 노트라 바꿀 수 없어요';

  /// Snack bar for any other rejected command (5.1.3, ArgumentError etc.).
  static const commandFailed = '실행하지 못했어요';

  // ---------------------------------------------------------------------------
  // Eraser (04-editor 6.6.4 #5): clearing the current page.
  // ---------------------------------------------------------------------------

  /// Eraser popup button and more menu item.
  static const clearPage = '현재 페이지 지우기';

  /// Confirmation title, eraser filter `all`.
  static const clearPageTitle = '이 페이지의 필기를 모두 지울까요?';

  /// Confirmation title, eraser filter `highlighterOnly`.
  static const clearPageTitleHighlighterOnly = '이 페이지의 형광펜만 모두 지울까요?';

  /// Confirmation title, eraser filter `exceptHighlighter`.
  static const clearPageTitleExceptHighlighter = '이 페이지의 필기를 형광펜을 빼고 모두 지울까요?';

  /// Confirmation body.
  static const clearPageBody = '되돌리기로 복구할 수 있어요';

  /// Confirmation button.
  static const clearPageConfirm = '지우기';

  /// Cancel button of the editor's dialogs.
  static const cancel = '취소';

  // ---------------------------------------------------------------------------
  // Selection menu and context menu (04-editor 6.6.2, 6.6.5, 6.6.7).
  // ---------------------------------------------------------------------------

  static const selectionCopy = '복사';
  static const selectionDelete = '삭제';
  static const selectionClear = '선택 해제';

  /// Context menu (long press / secondary click), when the clipboard has strokes.
  static const paste = '붙여넣기';

  /// Context menu: switch to the lasso tool.
  static const lassoTool = '올가미 도구';
}
