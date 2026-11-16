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
    // (2nd round, m5-7/04-editor 6.14.1) the P1 names shown in the picker.
    core.PenTool.brush => '붓펜',
    core.PenTool.calligraphy => '캘리그래피',
    core.PenTool.dashed => '점선',
    core.PenTool.laser => '레이저',
    core.PenTool.tape => '암기 테이프',
    // (v2.11, C211-01) texture and decoration pens (names of the lock-screen app's pens)
    core.PenTool.crayon => '크레파스',
    core.PenTool.chalk => '분필',
    core.PenTool.watercolor => '수채',
    core.PenTool.spray => '스프레이',
    core.PenTool.neon => '네온',
    core.PenTool.jelly => '젤리',
    core.PenTool.rainbow => '무지개',
    core.PenTool.glitter => '반짝이',
  };

  /// (v2.11, C211-01) Group headers of the pen picker (PenTypeGroup names).
  static String penGroupName(String group) => switch (group) {
    'texture' => '질감',
    'decor' => '꾸미기',
    _ => '기본',
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

  /// Input section: gestures ((v2) one row per gesture with its action —
  /// m5-7/04-editor 6.4.4; the names are under 'Gestures (6.4.4)' below).
  static const gestures = '제스처';

  /// The gestures that cannot be changed (read-only grey table — (v2) the
  /// three fixed rows of m5-7/04-editor 6.4.4).
  static const fixedGestures = '바꿀 수 없는 제스처';
  static const fixedGestureTable = <(String, String)>[
    ('두 손가락으로 끌기', '화면 이동'),
    ('두 손가락 벌리기·오므리기', '확대·축소'),
    ('펜 전용 모드에서 한 손가락으로 끌기', '화면 이동'),
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

  /// More menu submenu (shown while the developer overlay is visible, 6.12.4).
  static const devMenu = '개발자 메뉴';

  /// "현재 페이지에 합성 획 1,000개".
  static String syntheticStrokes(int count) {
    final digits = '$count';
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return '현재 페이지에 합성 획 $buffer개';
  }

  static const resetDiagnostics = '진단 초기화';

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

  // ---------------------------------------------------------------------------
  // Page panel, page selection mode, add-page sheet (04-editor 6.11).
  // ---------------------------------------------------------------------------

  /// Toolbar [▤] (semantics label).
  static const pagePanel = '페이지 패널';

  /// Panel header: "페이지 12".
  static String pageCount(int count) => '페이지 $count';

  /// Header [선택] (semantics label) — the page selection mode.
  static const selectPages = '페이지 선택';

  /// Header [+] (semantics label).
  static const addPageEllipsis = '페이지 추가…';

  /// Item ⋯ (semantics label): "3쪽 메뉴".
  static String pageMenu(int number) => '$number쪽 메뉴';

  /// Item number / semantics: "3쪽".
  static String pageNumber(int number) => '$number쪽';

  static const addPageBefore = '앞에 페이지 추가';
  static const addPageAfter = '뒤에 페이지 추가';
  static const duplicatePage = '복제';
  static const deletePage = '삭제';

  /// Snack bar after deleting pages, with [undo].
  static const pagesDeleted = '페이지를 삭제했어요';

  /// Selection bar: "3쪽 선택됨".
  static String pagesSelected(int count) => '$count쪽 선택됨';
  static const selectAll = '모두 선택';
  static const done = '완료';

  /// Page indicator "3 / 12".
  static String pageIndicator(int current, int count) => '$current / $count';

  /// The document-end button.
  static const addPageAtEnd = '+ 페이지';

  /// Pull to add a page (04-editor 6.11.7): shown while a pull past the document end
  /// is short of the threshold / from the threshold on.
  static const pullToAddPage = '당겨서 페이지 추가';
  static const releaseToAddPage = '놓으면 페이지 추가';

  /// Add-page sheet.
  static const addPageTitle = '페이지 추가';
  static const placement = '위치';
  static const placementBefore = '현재 페이지 앞';
  static const placementAfter = '현재 페이지 뒤';
  static const placementEnd = '맨 끝';
  static const template = '속지';
  static const paperColor = '색';
  static const pageSize = '크기';
  static const orientation = '방향';
  static const portrait = '세로';
  static const landscape = '가로';
  static const otherSources = '다른 소스';
  static const add = '추가';
  static const widthPt = '가로 (pt)';
  static const heightPt = '세로 (pt)';

  /// Custom size outside PageSizeLimits.userMinSidePt..userMaxSidePt.
  static const customSizeOutOfRange = '100~3000pt 사이로 입력해 주세요';
  static const customSize = '사용자 지정';

  static const paperWhite = '흰색';
  static const paperIvory = '미색';
  static const paperGray = '회색';
  static const paperBlack = '검정';

  /// A paper colour that is not one of core.PaperColors.all.
  static const paperOther = '다른 색';

  static const templateBlank = '빈 페이지';
  static const templateLined = '줄';
  static const templateGrid = '모눈';
  static const templateDotted = '점';
  static const templateCornell = '코넬';
  static const templateMusic = '악보';
  static const templatePlanner = '플래너';
  // ===========================================================================
  // 2nd round (m5-7/04-editor 1.2 table, E2-00). Later tasks read these; the
  // section of the plan that uses a string is named in its comment. Menu and
  // row labels are noun phrases; sentences are 해요체.
  // ===========================================================================

  // ---- Toolbar v2 and insert menu (6.13.1, 6.12.1) --------------------------

  /// Tool buttons (6.13.1).
  static const shapeTool = '도형';
  static const textTool = '텍스트';

  /// [+] (semantics label) and its menu.
  static const insert = '삽입';

  /// [⋯도구]: the folded shape / text / insert / mic buttons (< 720 px).
  static const moreTools = '도구 더보기';

  // (math pen, phase 1 — docs/plans/m5-7/research/math-pen-phase1.md 2.3, 8)
  static const mathPenTool = '수식 펜';
  static const mathFix = '고치기';
  static const mathReopen = '손글씨로 열기';

  /// A reopened formula that could not be converted again stays
  /// handwriting (undo brings the formula back).
  static const mathKeptHandwriting = '수식으로 바꾸지 못해 손글씨로 남겼어요.';

  // (text pen, phase 1 — m5-7/04-editor 6.21)
  static const textPenTool = '텍스트 펜';

  /// The first switch to the text pen on a note screen.
  static const textPenFirstHint = '글씨를 쓰고 말풍선을 누르면 텍스트로 바뀌어요.';

  /// The insert menu's row: the text pen, or the conversion sheet on the
  /// selected handwriting.
  static const handwritingToText = '손글씨를 텍스트로';

  /// Insert menu submenu and the add-page sheet row (6.12.1, 6.12.3).
  static const image = '이미지';

  /// Image sources (6.12.1 table).
  static String imageSourceName(core.ImageImportSource source) =>
      switch (source) {
        core.ImageImportSource.photos => '사진 보관함',
        core.ImageImportSource.camera => '카메라로 찍기',
        core.ImageImportSource.files => '파일에서',
        core.ImageImportSource.clipboard => '붙여넣기',
      };

  /// Context menu (6.12.2, source clipboard).
  static const pasteImage = '이미지 붙여넣기';

  /// importer.pick threw (E-7, 6.21).
  static const imageInsertFailed = '이미지를 넣지 못했어요';

  /// Over PageObjectLimits (6.21): "이 페이지에는 더 넣을 수 없어요(최대 2,000개)".
  static String objectLimitReached(int max) =>
      '이 페이지에는 더 넣을 수 없어요(최대 ${_grouped(max)}개)';

  // ---- Selection menu v2 (6.7) -----------------------------------------------

  static const selectionCut = '잘라내기';
  static const selectionColor = '색';
  static const selectionMore = '더보기';
  static const selectionDuplicate = '복제';
  static const selectionRotate90 = '90° 돌리기';
  static const selectionStyle = '스타일';
  static const selectionVertexEdit = '꼭짓점 편집';
  static const selectionEditText = '편집';
  static const selectionFormat = '서식';
  static const selectionUnlockAspect = '비율 고정 풀기';
  static const selectionLockAspect = '비율 고정 잠그기';

  /// The recolor popup's '더 보기' panel: applies the colour picked there
  /// (6.7.2 — the swatches apply on tap).
  static const recolorApply = '적용';

  /// Rotation tag while dragging the rotation handle (6.6.6): "45°".
  static String rotationLabel(int degrees) => '$degrees°';

  // ---- Shape tool (6.9.1) ----------------------------------------------------

  static String shapeKindName(core.ShapeKind kind) => switch (kind) {
    core.ShapeKind.line => '직선',
    core.ShapeKind.arrow => '화살표',
    core.ShapeKind.rectangle => '사각형',
    core.ShapeKind.ellipse => '원/타원',
    core.ShapeKind.triangle => '삼각형',
    core.ShapeKind.polygon => '다각형',
    core.ShapeKind.star => '별',
  };

  static const shapeKind = '종류';
  static const shapeStrokeColor = '테두리 색';
  static const shapeWidth = '굵기';
  static const shapeLineDash = '선 종류';
  static const lineSolid = '실선';
  static const lineDashed = '파선';
  static const lineDotted = '점선';
  static const shapeFill = '채우기';
  static const shapeFillOpacity = '채우기 투명도';
  static const shapeArrowHeads = '화살촉';
  static const none = '없음';
  static const arrowHeadEnd = '끝';
  static const arrowHeadBoth = '양쪽';
  static const usePenColor = '펜 색 쓰기';
  static const polygonSides = '변 수';
  static const starPoints = '꼭짓점 수';

  /// '더 보기' of a colour row (6.9.1, 6.11.4).
  static const moreColors = '더 보기';

  // ---- Auto shape (6.10) -----------------------------------------------------

  static const shapeAssist = '자동 도형 보정';
  static const shapeAssistHint =
      '선을 긋고 잠시 멈추면 도형으로 바꿔요. 펜을 떼기 전에 움직이면 크기와 방향을 다듬을 수 있어요';

  // ---- Text box (6.11) -------------------------------------------------------

  static const fontSize = '글자 크기';
  static const fontSizeDown = '글자 작게';
  static const fontSizeUp = '글자 크게';
  static const textColor = '글자 색';
  static const bold = '굵게';
  static const alignLeft = '왼쪽 정렬';
  static const alignCenter = '가운데 정렬';
  static const alignRight = '오른쪽 정렬';
  static const textBackground = '배경';

  /// Read-only rejection at the end of a session (6.11.5, S-11).
  static const textCopiedToClipboard = '편집한 글을 클립보드에 복사해 두었어요';

  /// Draft banner (6.11.2, P-B).
  static const textDraftFound = '저장되지 않은 글이 있어요';
  static const textDraftRestore = '되살리기';
  static const textDraftDiscard = '버리기';

  /// Sheet input (6.11.6 A): the panel title and its [완료] (= [done]).
  static const textInputSheetTitle = '텍스트 입력';

  /// Over the text length limit (6.11.2).
  static String textTooLong(int max) => '글자는 ${_grouped(max)}자까지 쓸 수 있어요';

  // ---- New pens (6.14) -------------------------------------------------------

  /// Pen settings popup section (6.14.2).
  static const penAdvanced = '고급';
  static const nibAngle = '펜촉 각도';
  static const nibAspect = '펜촉 비율';
  static const followBarrelRoll = '펜슬 돌리기로 각도 조절';
  static const dashSpacing = '간격';
  static const dashDense = '촘촘';
  static const dashNormal = '보통';
  static const dashLong = '긴 파선';
  static const laserFade = '사라지는 시간';
  static String laserFadeLabel(double seconds) =>
      '${seconds.toStringAsFixed(1)}초';
  static const tapeStyle = '모양';
  static const tapeSolid = '단색';
  static const tapeStriped = '줄무늬';

  /// More menu (6.14.4).
  static const tapesRevealAll = '테이프 모두 보이기';
  static const tapesHideAll = '테이프 모두 가리기';

  // ---- Recording (6.15) ------------------------------------------------------

  /// Mic button (semantics label) and the panel slot (6.15.4).
  static const recording = '녹음';
  static const recordingInOtherNote = '다른 노트에서 녹음 중이에요';
  static const recordingPanelFailed = '녹음 패널을 열지 못했어요';

  /// Settings > page '필기 재생' (6.15.3).
  static const playbackSection = '필기 재생';
  static const playbackPreRoll = '탭한 곳보다 앞에서 재생';
  static String playbackPreRollLabel(int ms) =>
      '${(ms / 1000).toStringAsFixed(1)}초 앞';
  static const playbackHighlight = '강조 방식';
  static const playbackDimUnwritten = '안 쓴 필기 흐리게';
  static const playbackHighlightRecent = '방금 쓴 필기만 강조';
  static const tapToSeek = '필기를 탭해 그 부분 재생';

  // ---- Eraser v2 (6.17) ------------------------------------------------------

  static const eraseShapes = '도형도 지우기';
  static const clearPageIncludeObjects = '도형·텍스트·이미지·수식도 지우기';

  // ---- Gestures (6.4.4) and Apple Pencil (6.5) ------------------------------

  static const gestureTwoFingerTap = '두 손가락 탭';
  static const gestureThreeFingerTap = '세 손가락 탭';
  static const gestureFingerLongPress = '손가락 길게 누르기';
  static const gesturePenButton = '펜 측면 버튼을 누른 채 쓰기(S펜 등)';
  static const gesturePenButtonHint = '안드로이드 S펜·일부 펜에서 동작해요';
  static const gestureInvertedStylus = '펜 뒤쪽 지우개';
  static const gestureInvertedStylusHint = '지우개 끝이 있는 펜에서 동작해요';
  static const gesturePencilDoubleTap = 'Apple Pencil 두 번 탭';
  static const gesturePencilSqueeze = 'Apple Pencil 스퀴즈';
  static const resetGestures = '기본값으로';

  /// Action names (6.4.4 — noun phrases, not 해요체).
  static const actionNone = '없음';
  static const actionUndo = '되돌리기';
  static const actionRedo = '다시 실행';
  static const actionContextMenu = '메뉴 열기';
  static const actionEraserWhileHeld = '누르는 동안 지우개';
  static const actionLassoWhileHeld = '누르는 동안 올가미';
  static const actionToggleEraser = '지우개 켜고 끄기';
  static const actionPreviousTool = '이전 도구';
  static const actionToolPalette = '도구 팔레트';
  static const actionColorPalette = '색 팔레트';
  static const actionFollowSystem = 'iPad 설정 따르기';

  /// Pencil rows (6.5.1, CD2-24).
  static const pencilFollowsSystem = 'iPad 설정을 따르고 있어요';
  static const pencilNextLaunch = 'iPad 설정을 바꾸면 앱을 다시 열 때 반영돼요';

  // ---- Developer menu and overlay (6.20) ------------------------------------

  static const devTextBoxProbe = '텍스트 상자 시험';
  static const devTextInputMode = '텍스트 입력 방식';
  static const devCollectShapeSamples = '도형 표본 모으기';
  static const devCopyShapeSample = '도형 표본 복사';
  static const devExpectedShape = '기대 종류';
  static const devNotAShape = '도형 아님(글씨)';
  static const devShapeSampleCopied = '도형 표본을 복사했어요';
  static const devNoShapeSamples = '모은 표본이 없어요';

  // ---- (v2.13-search) In-note search '노트에서 찾기' (m5-7/04-editor 17) --

  static const noteSearch = '노트에서 찾기';
  static const noteSearchHint = '필기·텍스트·수식·PDF에서 찾기';
  static const noteSearchClose = '찾기 닫기';
  static const noteSearchEmptyQuery = '이 노트의 손글씨, 텍스트 상자, 수식, PDF 글자를 찾아요';
  static const noteSearchNoResults = '찾는 내용이 없어요';
  static const noteSearchFailed = '검색하지 못했어요';
  static String noteSearchCount(int pages) => '$pages쪽에서 찾았어요';
  static String noteSearchPage(int pageNumber) => '$pageNumber쪽';
  static String noteSearchSource(core.SearchSource source) => switch (source) {
    core.SearchSource.ink => '손글씨',
    core.SearchSource.text => '텍스트',
    core.SearchSource.math => '수식',
    core.SearchSource.pdf => 'PDF',
  };

  // The handwriting hint — the same sentences as the library search's hint
  // (feature_library LibraryStrings.ink*, 05-library 6.19a).
  static const inkAutoIndexOff = "손글씨도 검색하려면 '검색용 자동 인식'을 켜 주세요";
  static const inkTurnOn = '켜기';
  static const inkModelMissing = '손글씨를 검색하려면 인식 모델(약 20MB)을 받아야 해요';
  static const inkModelDownloading = '손글씨 인식 모델을 받는 중이에요';
  static const inkWaitingForWifi = '손글씨 인식 모델을 받는 중이에요 (Wi-Fi에서만 받아요)';
  static const inkModelFailed = '손글씨 인식 모델을 받지 못했어요';
  static const inkDownloadNow = '지금 받기';
  static const inkCellularConfirm = '셀룰러 데이터로 받아요(약 20MB). 한 번 더 누르면 받아요.';
  static String inkIndexing(int pages) =>
      pages > 0 ? '이 노트의 손글씨를 읽는 중이에요 ($pages쪽 남음)' : '이 노트의 손글씨를 읽는 중이에요';
  static const inkUnsupported = '이 기기에서는 손글씨 검색을 쓸 수 없어요';

  /// 1 234 567 → "1,234,567" (no intl — contract 7.4.5).
  static String _grouped(int n) {
    final digits = n.abs().toString();
    final out = StringBuffer(n < 0 ? '-' : '');
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
      out.write(digits[i]);
    }
    return out.toString();
  }
}
