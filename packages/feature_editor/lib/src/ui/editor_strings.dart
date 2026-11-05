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
  // Popups (04-editor 6.9.2). The panels' own strings are in their sections.
  // ---------------------------------------------------------------------------

  static const penSettings = '펜 설정';
  static const quickPen = '빠른 펜';
  static const eraserSettings = '지우개 설정';

  // ---------------------------------------------------------------------------
  // Pen settings (04-editor 6.9.3 #1–#3, #7) and the eraser panel.
  // ---------------------------------------------------------------------------

  /// "굵기 2.4 pt" (tap → number input 0.1–30).
  static String widthLabel(double width) => '굵기 ${width.toStringAsFixed(1)} pt';

  /// Semantics labels of [−] / [+] next to the width slider and of the slider.
  static const widthDecrease = '굵기 줄이기';
  static const widthIncrease = '굵기 늘리기';
  static const width = '굵기';

  /// Shown on the preview when width × zoom is cut at 48 px.
  static String previewZoom(int percent) => '확대 $percent%';

  /// "투명도 60%".
  static String opacityLabel(int percent) => '투명도 $percent%';
  static const opacity = '투명도';

  /// The folded '고급' part (EDITOR-S3).
  static const advanced = '고급';
  static String pressureSensitivityLabel(int percent) => '필압 감도 $percent%';
  static const pressureSensitivity = '필압 감도';
  static const pressureCurve = '필압 곡선';
  static const curveSoft = '부드럽게';
  static const curveLinear = '보통';
  static const curveFirm = '단단하게';

  /// The pen's curve matches none of the three (a synced custom value).
  static const customCurve = '사용자 지정 곡선';

  /// Sensitivity and curve are disabled (6.5.7).
  static const noPressureHint = '이 펜은 필압이 없어 속도로 흉내 내요';
  static String smoothingLabel(int percent) => '손떨림 보정 $percent%';
  static const smoothing = '손떨림 보정';

  /// Highlighter only.
  static const straightening = '직선 보정';
  static const straighteningOff = '끔';
  static const straighteningOnLift = '뗄 때 보정';
  static const straighteningAlways = '항상 직선';

  /// Eraser panel (6.9.3 end).
  static const eraserModeStroke = '획';
  static const eraserModePartial = '부분';
  static String eraserSizeLabel(double diameter) =>
      '크기 ${diameter == diameter.roundToDouble() ? diameter.toStringAsFixed(0) : diameter.toStringAsFixed(1)} pt';
  static const eraserSize = '지우개 크기';
  static const filterAll = '전체';
  static const filterHighlighterOnly = '형광펜만';
  static const filterExceptHighlighter = '형광펜 제외';
  static const returnToPreviousTool = '지운 뒤 이전 도구로 돌아가기';

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
  // Preset bar, save dialog and manager sheet (04-editor 6.10).
  // ---------------------------------------------------------------------------

  /// Group menu of the bar: no filter.
  static const presetAllGroups = '모든 그룹';

  /// Semantics label of the bar's group menu button.
  static const presetGroupFilter = '프리셋 그룹';

  /// Empty bar.
  static const presetEmpty = '자주 쓰는 펜을 저장해 보세요';

  /// Button of the empty bar (opens the save dialog).
  static const presetSaveCurrent = '현재 펜 저장';

  /// Semantics label of the bar's [+].
  static const presetAdd = '프리셋 추가';

  /// Semantics label of the bar's [⚙] and the manager sheet's title.
  static const presetManage = '프리셋 관리';

  /// Pen settings #8 and the save dialog's title.
  static const saveAsPreset = '프리셋으로 저장';

  /// Default name of a new preset: "{펜 이름} {굵기}pt".
  static String presetDefaultName(core.PenTool tool, double width) =>
      '${penTypeName(tool)} ${width.toStringAsFixed(1)}pt';

  static const presetName = '이름';

  /// Helper under the name field (trimmed 1–20 characters).
  static const presetNameRule = '1~20자';
  static const presetGroup = '그룹';
  static const presetNoGroup = '그룹 없음';
  static const presetNewGroup = '새 그룹';
  static const presetNewGroupName = '그룹 이름';
  static const presetPinned = '툴바에 고정';
  static const save = '저장';

  /// Manager row menu (⋯).
  static const presetRename = '이름 바꾸기';
  static const presetChangeGroup = '그룹 변경';
  static const presetUpdateStyle = '현재 펜으로 업데이트';
  static const presetDelete = '삭제';

  /// Delete confirmation title.
  static String presetDeleteTitle(String name) => "'$name' 프리셋을 삭제할까요?";

  /// Semantics label of a manager row's drag handle.
  static const presetReorder = '순서 바꾸기';

  /// Shown after '현재 펜으로 업데이트'.
  static const presetUpdated = '현재 펜으로 업데이트했어요';

  // ---------------------------------------------------------------------------
  // Settings sections (04-editor 4.9). INFRA draws the section titles.
  // ---------------------------------------------------------------------------

  /// Input section: input mode.
  static const inputMode = '입력 모드';
  static const inputModeAuto = '자동';
  static const inputModePenOnly = '펜 전용';
  static const inputModeFingerDrawing = '손가락 필기';
  static const inputModeAutoHint = '펜을 한 번 쓰면 그다음부터는 펜으로만 그리고 손가락으로는 화면을 움직여요';
  static const inputModePenOnlyHint = '펜으로만 그려요. 손가락으로는 화면을 움직이고 확대해요';
  static const inputModeFingerDrawingHint = '한 손가락으로 그리고 두 손가락으로 화면을 움직여요';

  /// Input section: palm rejection (6.5.4).
  static const palmRejection = '손바닥 무시';
  static String penCooldownLabel(int ms) => '펜을 뗀 뒤 터치 무시 $ms ms';
  static const penCooldown = '펜을 뗀 뒤 터치 무시 시간';
  static const hoverAsPen = '펜이 화면 가까이 있을 때 터치 무시';
  static const hoverAsPenHint = '펜 hover를 지원하는 기기에서만 동작해요';
  static String maxTouchRadiusLabel(int px) => '큰 접촉 무시 $px px 넘음';
  static const maxTouchRadius = '큰 접촉 무시 기준';
  static const maxTouchRadiusHint =
      '접촉 크기를 알려 주는 기기에서만 동작해요. 웹 브라우저에서는 적용되지 않아요';

  /// Input section: gestures (F-12 — on/off only, contract 7.8).
  static const gestures = '제스처';
  static const twoFingerTapUndo = '두 손가락 탭으로 되돌리기';
  static const threeFingerTapRedo = '세 손가락 탭으로 다시 실행';
  static const longPressMenu = '손가락 길게 누르기로 메뉴 열기';

  /// The gestures that cannot be changed (read-only table).
  static const fixedGestures = '바꿀 수 없는 제스처';
  static const fixedGestureTable = <(String, String)>[
    ('두 손가락으로 끌기', '화면 이동'),
    ('두 손가락 벌리기·오므리기', '확대·축소'),
    ('펜 전용 모드에서 한 손가락으로 끌기', '화면 이동'),
    ('펜 전용 모드에서 한 손가락 짧게 탭', '선택 해제·메뉴 닫기'),
    ('트랙패드 두 손가락 스크롤·핀치', '화면 이동·확대'),
  ];
  static const resetInput = '입력 설정 기본값으로';

  /// Pen section: pressure mode (6.5.7).
  static const pressureMode = '필압 사용';
  static const pressureModeAuto = '자동';
  static const pressureModeReal = '항상 사용';
  static const pressureModeSimulated = '사용 안 함';
  static const pressureDetecting = '감지 중';
  static const pressureSupported = '필압 있음';
  static const pressureUnsupported = '필압 없음 — 속도로 흉내 내요';

  /// "지금 펜: 감지 중".
  static String pressureState(String state) => '지금 펜: $state';

  /// Which pen type the advanced values below belong to.
  static const penTypeToEdit = '펜 종류';
  static const resetPenDefaults = '펜 종류별 기본값으로 초기화';
  static const resetPenDefaultsTitle = '모든 펜 종류의 굵기·색·필압 설정을 기본값으로 되돌릴까요?';
  static const reset = '초기화';

  /// Page section.
  static const pageFlipHint = '좌우 넘기기에서는 한 장씩 넘겨요';

  /// Developer section (6.12.4).
  static const devOverlayHint =
      '에디터의 더보기 › 개발자 표시, ⌘⇧D / Ctrl+Shift+D, 또는 주소 끝에 ?dev=1을 붙여도 켜져요';
  static const seedSyntheticNote = '합성 노트 만들기';
  static const seedSyntheticNoteHint = '50쪽 × 쪽마다 획 300개인 성능 확인용 노트';
  static const seedSyntheticNoteDone =
      "합성 노트를 만들었어요. 라이브러리에서 'perf-test'를 열어 보세요";

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
