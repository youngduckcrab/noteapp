// lib/src/l10n/library_strings.dart — 05-library 6.18 (contract 7.4.5: Korean
// 해요체 UI strings live in one constants file per area; no intl).
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
  static const String searchHint = '제목 검색';
  static const String newMenu = '새로 만들기';
  static const String newNote = '새 노트';
  static const String newFolder = '새 폴더';
  static const String importPdf = 'PDF 가져오기';
  static const String comingSoon = '준비 중';

  // Sort
  static const String sortName = '이름';
  static const String sortCreated = '만든 날짜';
  static const String sortUpdated = '수정한 날짜';
  static const String sortCustom = '사용자 지정';

  // Selection
  static const String select = '선택';
  static const String done = '완료';
  static const String selectAll = '모두 선택';
  static const String deselectAll = '모두 해제';
  static String selectedCount(int n) => '$n개 선택됨';

  // Item actions
  static const String rename = '이름 변경';
  static const String customize = '꾸미기';
  static const String changeCover = '표지 변경';
  static const String favoriteAdd = '즐겨찾기';
  static const String favoriteRemove = '즐겨찾기 해제';
  static const String copy = '복사';
  static const String moveTo = '이동…';
  static const String moveToTrash = '휴지통으로 이동';

  // PDF slots
  static const String exportPdfBulk = 'PDF 내보내기';
  static const String exportPdfOne = 'PDF로 내보내기';
  static const String exportNeedsNote = '노트를 선택하세요';

  /// '35.3~1058.3mm 사이로 입력하세요' for (35.3, 1058.3): one decimal each.
  static String customSizeRange(double minMm, double maxMm) =>
      '${minMm.toStringAsFixed(1)}~${maxMm.toStringAsFixed(1)}mm 사이로 입력하세요';

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
