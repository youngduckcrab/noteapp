// lib/src/l10n/library_strings.dart — 05-library 6.18 (contract 7.4.5: Korean
// 해요체 UI strings live in one constants file per area; no intl).
import 'package:note_core/note_core.dart'
    show PageTemplateKind, PaperColors, SearchSource;

import 'korean_josa.dart';

/// Every Korean UI string of the library screen. Widgets never contain Korean
/// literals; tests find widgets through these constants.
///
/// The main table of 05-library 6.18 (task L1). Strings used by only one
/// screen part are added with the task that builds it (L8-L18).
abstract final class LibraryStrings {
  // Sections
  static const String home = '홈';
  static const String recent = '최근';
  static const String favorites = '즐겨찾기';
  static const String trash = '휴지통';
  static const String folders = '폴더';
  static const String settings = '설정';

  // Paths ('홈 › … › A › B' — location labels, 6.14)
  static const String pathSeparator = ' › ';
  static const String ellipsis = '…';

  /// (v2) Between a content group's note title and its location (6.1.3).
  static const String metaSeparator = ' · ';

  /// Sidebar header (app name row).
  static const String appTitle = '노트';

  // Sidebar tree (6.5): tooltips of the ▸ / ▾ button.
  static const String expandFolder = '펼치기';
  static const String collapseFolder = '접기';

  // Top bar
  static const String openMenu = '메뉴 열기';
  static const String hideSidebar = '사이드바 숨기기';
  static const String showSidebar = '사이드바 보기';

  /// Title of the search section: `'"<query>" 검색 결과'`.
  static String searchResultsTitle(String query) => '"$query" 검색 결과';

  /// (v2, 6.21) '제목 검색' → '노트 검색' (the search finds note content too).
  static const String searchHint = '노트 검색';

  // Search (6.14)
  /// Compact top bar: the search icon's tooltip (opens the search field).
  static const String search = '검색';

  /// Compact search bar: ← back to the normal top bar.
  static const String closeSearch = '검색 닫기';

  /// Tooltip of the clear button inside the search field.
  static const String clearSearch = '검색어 지우기';

  /// Result group headers: '폴더 (3)', '노트 (12)'.
  static String searchFolderGroup(int n) => '폴더 ($n)';
  static String searchNoteGroup(int n) => '노트 ($n)';

  /// Below results cut at the search limit.
  static const String searchTruncated = '결과가 많아요. 검색어를 더 입력해 보세요.';

  // (v2) Content hits — '노트 내용' (6.1.3, 6.21)
  /// Group header: '노트 내용 (7)' (n = hit pages).
  static String searchContentGroup(int n) => '노트 내용 ($n)';

  /// Row under a note's first 3 hits.
  static String contentMore(int n) => '이 노트에서 $n개 더 보기';

  /// Below the content group when CORE cut the hits (pagesTruncated).
  static const String contentTruncated = '내용 결과가 많아요. 검색어를 더 입력해 보세요.';

  /// Source badges (SearchSource ink / pdf / text / math).
  static const String sourceInk = '손글씨';
  static const String sourcePdf = 'PDF';
  static const String sourceText = '텍스트';
  static const String sourceMath = '수식';

  /// (v2.17-md, C217M-08) the body of an MD 문서.
  static const String sourceMarkdown = '문서';
  static String sourceLabel(SearchSource source) => switch (source) {
    SearchSource.ink => sourceInk,
    SearchSource.pdf => sourcePdf,
    SearchSource.text => sourceText,
    SearchSource.math => sourceMath,
    SearchSource.markdown => sourceMarkdown,
  };

  /// A hit's page: '3쪽'; [pageUnknown] while loading or not found.
  static String pageLabel(int n) => '$n쪽';
  static const String pageUnknown = '페이지';

  /// Semantics of a content hit row: `'<title>, <page>, <source>, <snippet>'`.
  static String contentHitSemantics(
    String title,
    String page,
    String source,
    String snippet,
  ) => '$title, $page, $source, $snippet';

  /// Meta line of a recent note: `'<location> · <last opened>'`.
  static String recentNoteMeta(String location, String opened) =>
      '$location · $opened';

  /// Meta line of a favorite note: `'<location> · 수정 <modified>'`.
  static String favoriteNoteMeta(String location, String modified) =>
      '$location · ${modifiedOn(modified)}';

  /// `'수정 <date>'`.
  static String modifiedOn(String date) => '수정 $date';

  static const String newMenu = '새로 만들기';
  static const String newNote = '새 노트';
  static const String newFolder = '새 폴더';
  static const String importPdf = 'PDF 가져오기';

  // (v2.17-md, C217M-11) MD 문서
  static const String newMarkdown = '새 MD 문서';
  static const String importMarkdown = 'MD 가져오기';
  static const String defaultMarkdownTitle = '새 MD 문서';
  static const String exportMarkdown = '.md로 내보내기';
  static const String markdownBadge = 'MD';
  static const String markdownKind = '문서';

  /// The meta of an MD 문서 list row: `'<modified> · 문서 · 2.1 KB'`.
  static String markdownListMeta(String modified, int? bytes) => bytes == null
      ? '$modified · $markdownKind'
      : '$modified · $markdownKind · ${markdownSize(bytes)}';

  /// '820 B', '2.1 KB', '1.3 MB'.
  static String markdownSize(int bytes) {
    if (bytes < 1000) return '$bytes B';
    if (bytes < 1000000) return '${(bytes / 1000).toStringAsFixed(1)} KB';
    return '${(bytes / 1000000).toStringAsFixed(1)} MB';
  }

  /// After a bulk PDF export that left MD 문서 out.
  static String markdownLeftOutOfPdf(int n) => 'MD 문서 $n개는 빼고 내보냈어요';

  /// Every selected note is an MD 문서: nothing to export as PDF.
  static const String pdfExportNeedsInkNote =
      'PDF로 내보낼 노트가 없어요 (MD 문서는 .md로 내보내 주세요)';

  // Sort
  static const String sortName = '이름';
  static const String sortCreated = '만든 날짜';
  static const String sortUpdated = '수정한 날짜';
  static const String sortCustom = '사용자 지정';

  // Listing (6.7 / 6.8)
  /// Sort menu button tooltip.
  static const String sort = '정렬';

  /// Tooltip of the disabled sort button outside folder sections.
  static const String sortFixed = '이 보기는 정렬 순서가 정해져 있어요';

  /// View toggle tooltips: the icon shows the mode it switches TO.
  static const String viewAsList = '목록으로 보기';
  static const String viewAsGrid = '격자로 보기';

  /// Compact top bar overflow menu (정렬 · 보기 · 선택).
  static const String moreActions = '더 보기';

  /// Breadcrumb '…' (hidden path menu).
  static const String hiddenPath = '숨은 경로';

  /// Note meta line: '3페이지'.
  static String pageCount(int n) => '$n페이지';

  /// List row meta: `'<date> · <n>페이지'`.
  static String noteListMeta(String date, int pages) =>
      '$date · ${pageCount(pages)}';

  /// Tile semantics (6.8).
  static String noteSemantics(String title, String date) =>
      '노트, $title, 수정 $date';
  static String folderSemantics(String name) => '폴더, $name';

  /// Badge / meta / snack bar for a note made by a newer app version.
  static const String requiresNewerApp = '새 버전 앱에서 열 수 있어요';

  /// (v2.14-ui) The cover label of such a note (was an 'upgrade' arrow).
  static const String requiresNewerAppBadge = '새 버전 필요';

  // Empty states (6.7)
  static const String emptyHome = '노트가 없어요';
  static const String emptyFolder = '이 폴더는 비어 있어요';
  static const String emptyRecent = '최근에 연 노트가 없어요';
  static const String emptyFavorites =
      '즐겨찾기한 노트가 없어요. 노트 메뉴에서 ☆ 즐겨찾기를 눌러 추가하세요.';
  static String emptySearch(String query) => '"$query"에 대한 결과가 없어요';

  // (handwriting search, 6.19a) why handwriting is not found yet — one line
  // under the search results or in the empty state.
  static const String inkAutoIndexOff = "손글씨도 검색하려면 '검색용 자동 인식'을 켜 주세요";
  static const String inkTurnOn = '켜기';
  static const String inkModelMissing = '손글씨를 검색하려면 인식 모델(약 20MB)을 받아야 해요';
  static const String inkModelDownloading = '손글씨 인식 모델을 받는 중이에요';
  // No connectivity check: a Wi-Fi-only download that runs long reads the
  // same on Wi-Fi as off it, so the line does not claim there is no Wi-Fi.
  static const String inkWaitingForWifi = '손글씨 인식 모델을 받는 중이에요 (Wi-Fi에서만 받아요)';
  static const String inkModelFailed = '손글씨 인식 모델을 받지 못했어요';
  static const String inkDownloadNow = '지금 받기';

  /// After the first [지금 받기] when it would use cellular data.
  static const String inkCellularConfirm =
      '셀룰러 데이터로 받아요(약 20MB). 한 번 더 누르면 받아요.';
  static String inkIndexing(int pages) =>
      pages > 0 ? '손글씨를 읽는 중이에요 ($pages쪽 남음)' : '손글씨를 읽는 중이에요';
  static const String inkUnsupported = '이 기기에서는 손글씨 검색을 쓸 수 없어요';

  /// Listing stream error (6.7 / 6.19).
  static const String listLoadFailed = '목록을 불러오지 못했어요';

  // Folder missing view (6.4)
  static const String folderInTrash = '이 폴더는 휴지통에 있어요';
  static const String folderNotFound = '폴더를 찾을 수 없어요. 다른 기기에서 영구 삭제됐을 수 있어요.';
  static const String showTrash = '휴지통 보기';
  static const String goHome = '홈으로';

  // Selection
  static const String select = '선택';
  static const String done = '완료';
  static const String selectAll = '모두 선택';
  static const String deselectAll = '모두 해제';
  static String selectedCount(int n) => '$n개 선택됨';

  /// Selection bar '이동' (the item menu says '이동…').
  static const String move = '이동';

  // Item actions
  static const String rename = '이름 변경';
  static const String customize = '꾸미기';
  static const String changeCover = '표지 변경';
  static const String favoriteAdd = '즐겨찾기';
  static const String favoriteRemove = '즐겨찾기 해제';
  static const String copy = '복사';
  static const String moveTo = '이동…';
  static const String moveToTrash = '휴지통으로 이동';

  /// Tooltip / semantics of an item's ⋯ button: '수학 메뉴'.
  static String itemMenu(String name) => '$name 메뉴';

  /// Sidebar tree row menu (6.5): a new folder inside that folder.
  static const String newSubfolder = '새 하위 폴더';

  // Item action dialogs and results (6.11)
  static const String moveDestination = '이동할 위치';
  static const String copyDestination = '복사할 위치';
  static const String moveHere = '여기로 이동';
  static const String copyHere = '여기에 복사';
  static const String preview = '미리보기';

  /// Rename field counter (shown from 180 characters): '185/200'.
  static String characterCount(int n, int max) => '$n/$max';

  /// Copy of one item from its menu (same folder, ' 사본').
  static const String copied = '복사했어요';

  /// Copy of n items (selection bar).
  static String copiedCount(int n) => '항목 $n개를 복사했어요';

  /// Move of one item: "'수학'으로 옮겼어요" (target name, 홈 for the top
  /// level).
  static String movedTo(String target) => '${quotedWithDirection(target)} 옮겼어요';

  /// Move of n items: "항목 3개를 '수학'으로 옮겼어요".
  static String movedCountTo(int n, String target) =>
      '항목 $n개를 ${quotedWithDirection(target)} 옮겼어요';

  /// Trash of one item: "'수학'을 휴지통으로 옮겼어요".
  static String trashedOne(String name) =>
      '${quotedWithObject(name)} 휴지통으로 옮겼어요';

  /// Trash of n items: '항목 3개를 휴지통으로 옮겼어요'.
  static String trashedCount(int n) => '항목 $n개를 휴지통으로 옮겼어요';

  // Trash view (6.13)

  static const String trashNotice = '휴지통의 항목은 30일 뒤 자동으로 영구 삭제돼요.';
  static const String emptyTrash = '휴지통 비우기';
  static const String emptyTrashView = '휴지통이 비어 있어요';
  static const String restore = '복원';
  static const String purge = '영구 삭제';
  static const String purgeTitle = '영구 삭제할까요?';
  static const String emptyTrashTitle = '휴지통을 비울까요?';

  /// "'수학'을 영구 삭제하면 되돌릴 수 없어요."
  static String purgeMessageOne(String name) =>
      '${quotedWithObject(name)} 영구 삭제하면 되돌릴 수 없어요.';

  /// '항목 3개를 영구 삭제하면 되돌릴 수 없어요.'
  static String purgeMessageCount(int n) => '항목 $n개를 영구 삭제하면 되돌릴 수 없어요.';

  /// '항목 3개를 영구 삭제해요. 되돌릴 수 없어요.'
  static String emptyTrashMessage(int n) => '항목 $n개를 영구 삭제해요. 되돌릴 수 없어요.';

  /// "'수학'을 복원했어요"
  static String restoredOne(String name) => '${quotedWithObject(name)} 복원했어요';

  /// '항목 3개를 복원했어요'
  static String restoredCount(int n) => '항목 $n개를 복원했어요';

  /// A trashed folder: '폴더 · 노트 3개, 폴더 1개 포함' (a 0 part left out; both
  /// 0 → '폴더').
  static String trashedFolderInfo({
    required int noteCount,
    required int folderCount,
  }) {
    final parts = [
      if (noteCount > 0) '노트 $noteCount개',
      if (folderCount > 0) '폴더 $folderCount개',
    ];
    return parts.isEmpty ? folders : '$folders · ${parts.join(', ')} 포함';
  }

  /// A trashed note: '노트 · 3페이지'.
  static String trashedNoteInfo(int pageCount) => '노트 · $pageCount페이지';

  /// '11월 4일 삭제' (date = formatLibraryDate).
  static String deletedOn(String date) => '$date 삭제';

  /// Screen reader label of a trash row.
  static String trashRowSemantics(String name, String info, String left) =>
      '$name, $info, $left';

  // Drag and drop (6.10)

  /// The drag card of several items: '항목 3개'.
  static String itemCount(int n) => '항목 $n개';

  /// One item dropped on the sidebar 휴지통 row (6.10.3).
  static const String droppedInTrash = '휴지통으로 옮겼어요';

  // PDF slots
  static const String exportPdfBulk = 'PDF 내보내기';
  static const String exportPdfOne = 'PDF로 내보내기';
  static const String exportNeedsNote = '노트를 선택하세요';

  /// '35.3~1058.3mm 사이로 입력하세요' for (35.3, 1058.3): one decimal each.
  static String customSizeRange(double minMm, double maxMm) =>
      '${minMm.toStringAsFixed(1)}~${maxMm.toStringAsFixed(1)}mm 사이로 입력하세요';

  // New note / new folder dialogs and their pickers (6.12)
  static const String fieldTitle = '제목';
  static const String fieldName = '이름';
  static const String fieldLocation = '위치';
  static const String fieldPageSize = '페이지 크기';
  static const String fieldOrientation = '방향';
  static const String fieldTemplate = '속지';
  static const String fieldPaperColor = '속지 색';
  static const String fieldCover = '표지';
  static const String fieldColor = '색';
  static const String fieldIcon = '아이콘';
  static const String pageSizeA4 = 'A4';
  static const String pageSizeLetter = 'Letter';
  static const String pageSize16x9 = '16:9';
  static const String pageSizeCustom = '사용자 지정';
  static const String portrait = '세로';
  static const String landscape = '가로';
  static const String customWidth = '너비';
  static const String customHeight = '높이';
  static const String millimeters = 'mm';
  static const String coverFirstPage = '첫 페이지';
  static const String colorNone = '없음';

  /// Template picker cell names: null = blank page.
  static String templateName(PageTemplateKind? kind) => switch (kind) {
    null => '빈 페이지',
    PageTemplateKind.lined => '줄',
    PageTemplateKind.grid => '모눈',
    PageTemplateKind.dotted => '점',
    PageTemplateKind.cornell => '코넬',
    PageTemplateKind.music => '악보',
    PageTemplateKind.planner => '플래너',
  };

  /// Paper color names in PaperColors.all order; another value → ''.
  static String paperColorName(int argb) => switch (argb) {
    PaperColors.white => '흰색',
    PaperColors.ivory => '미색',
    PaperColors.gray => '회색',
    PaperColors.black => '검정',
    _ => '',
  };

  // Sync badge (6.16.1)
  static const String syncOff = '이 기기에 저장';
  static const String syncDone = '동기화됨';
  static const String syncInProgress = '동기화 중';
  static const String syncOffline = '오프라인';
  static const String syncError = '동기화 오류';

  /// '동기화 중' when n == 0, else '동기화 중 · n'.
  static String syncInProgressCount(int n) =>
      n > 0 ? '$syncInProgress · $n' : syncInProgress;
  static const String syncOffTooltip = '노트는 이 기기에만 저장돼요';
  static String syncDoneTooltip(String when) => '마지막 동기화 $when';
  static String syncPendingTooltip(int n) => '보내는 중인 변경 $n개';
  static const String syncOfflineTooltip = '연결되면 자동으로 동기화해요';
  static const String syncErrorTooltip = '동기화하지 못한 변경이 있어요. 설정에서 확인해 주세요.';

  // Storage warning banner — contract 7.4.5 v1.1 fixed sentences. Change only
  // through the contract procedure (7.4.12); unit/strings_contract_test.dart
  // compares them.
  static const String storageWriteFailing =
      '저장에 계속 실패하고 있어요. 브라우저 저장 공간을 확인해 주세요.';
  static const String storageNotDurable =
      '이 브라우저에서는 노트가 임시로만 저장돼요. 테스트 용도로만 사용하세요.';

  // Default names
  static const String defaultNoteTitle = '제목 없는 노트';
  static const String defaultFolderName = '새 폴더';

  /// Suffix for copies (CORE copyItems nameSuffix).
  static const String copySuffix = ' 사본';

  // Buttons
  static const String undo = '실행 취소';
  static const String show = '보기';
  static const String retry = '다시 시도';
  static const String cancel = '취소';
  static const String create = '만들기';
  static const String save = '저장';
  static const String close = '닫기';

  // Errors (6.19)
  static const String errorGeneric = '작업을 마치지 못했어요. 다시 시도해 주세요.';
  static const String errorCycle = '폴더를 자기 안이나 하위 폴더로 옮길 수 없어요.';
  static const String errorNotFound = '항목을 찾을 수 없어요. 다른 기기에서 삭제됐을 수 있어요.';
  static const String loadFailed = '불러오지 못했어요';

  // Sentences with particles (KoreanJosa)

  /// `'<name>'` + 을/를, e.g. "'수학'을".
  static String quotedWithObject(String name) =>
      "'$name'${KoreanJosa.object(name)}";

  /// `'<name>'` + (으)로, e.g. "'수학'으로".
  static String quotedWithDirection(String name) =>
      "'$name'${KoreanJosa.direction(name)}";
}
