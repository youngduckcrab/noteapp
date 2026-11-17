// Korean strings of the MD 문서 screen (08-markdown 8, B-14).
abstract final class MdStrings {
  // --- top bar -----------------------------------------------------------------
  static const String back = '뒤로';
  static const String view = '보기';
  static const String edit = '편집';
  static const String toView = '보기로 바꾸기';
  static const String toEdit = '편집으로 바꾸기';
  static const String split = '나란히';
  static const String splitOff = '나란히 끄기';
  static const String splitTooltip = '편집과 미리보기를 나란히';
  static const String undo = '되돌리기';
  static const String redo = '다시 하기';
  static const String more = '더 보기';
  static const String saved = '저장됨';
  static const String saving = '저장 중…';
  static const String saveFailed = '저장하지 못했어요';
  static const String untitled = '제목 없음';
  static const String renameTooltip = '이름 바꾸기';

  // --- menu ----------------------------------------------------------------------
  static const String menuExport = '.md로 내보내기';
  static const String menuRename = '이름 바꾸기';
  static const String menuInfo = '정보';

  // --- dialogs -------------------------------------------------------------------
  static const String renameTitle = '이름 바꾸기';
  static const String renameHint = '문서 이름';
  static const String cancel = '취소';
  static const String ok = '확인';
  static const String close = '닫기';
  static const String renameFailed = '이름을 바꾸지 못했어요';
  static const String infoTitle = '문서 정보';
  static const String infoChars = '글자 수';
  static const String infoBytes = '크기';
  static const String infoModified = '고친 시각';
  static String bytes(int n) => n < 1024
      ? '$n바이트'
      : n < 1024 * 1024
      ? '${(n / 1024).toStringAsFixed(1)} KB ($n바이트)'
      : '${(n / 1024 / 1024).toStringAsFixed(2)} MB ($n바이트)';
  static String chars(int n) => '$n자';
  static const String exportFailed = '내보내지 못했어요';

  static const String leaveTitle = '저장하지 못한 글이 있어요';
  static const String leaveBody =
      '지금 나가면 고친 글이 사라질 수 있어요. 글을 복사해 두거나 조금 뒤에 다시 시도해 주세요.';
  static const String leaveStay = '머무르기';
  static const String leaveCopy = '복사하고 나가기';
  static const String leaveDiscard = '버리고 나가기';

  // --- banners -------------------------------------------------------------------
  static const String bannerTrashed = '휴지통에 있는 문서예요 — 보기만 돼요';
  static const String bannerNewerApp = '새 버전 앱에서 만든 문서예요 — 앱을 업데이트하면 고칠 수 있어요';
  static const String bannerReceiving = '내용을 받는 중이에요 — 다 받을 때까지 고칠 수 없어요';
  static const String bannerReceivingLong =
      '아직 내용을 받지 못했어요 — 다른 기기에서 이 문서를 한 번 열어 주세요';
  static const String bannerTooLargeToEdit =
      '이 문서는 너무 길어서 앱에서 고칠 수 없어요 — 보기만 돼요';
  static const String bannerTooLarge =
      '문서가 너무 커서 저장하지 못했어요 (최대 400 KB) — 글을 줄여 주세요';
  static const String bannerSaveFailed = '저장하지 못했어요 — 글은 그대로 있어요';
  static const String bannerConflictCopy = '다른 기기에서 바뀐 글을 사본으로 남겼어요';
  static const String bannerUnsaved = '저장하지 못한 글이 있어요';
  static const String openCopy = '사본 열기';
  static const String tableMore = '더 보기';
  static String tableRest(int n) => '$n행 더 있어요';
  static const String retry = '다시 시도';
  static const String restore = '되살리기';
  static const String discard = '버리기';
  static const String dismiss = '닫기';

  // --- body ----------------------------------------------------------------------
  static const String notMarkdown = '이 문서는 MD 문서가 아니에요';
  static const String openAsNote = '노트로 열기';
  static const String loadFailed = '문서를 열지 못했어요';
  static const String emptyDoc = '아직 내용이 없어요 — 편집에서 글을 써 보세요';
  static const String editorHint = '마크다운으로 글을 써 보세요';
  static const String frontMatter = '문서 정보 (머리말)';
  static const String footnotes = '각주';
  static const String copied = '복사했어요';
  static const String copy = '복사';
  static const String codeCopy = '코드 복사';
  static const String taskChanged = '할 일을 바꿨어요';
  static const String indent = '들여쓰기';
  static const String outdent = '내어쓰기';

  // --- images --------------------------------------------------------------------
  static const String image = '이미지';
  static const String imageNotLoaded = '이미지를 불러오지 않았어요';
  static const String imageRelative = '원본 파일의 이미지는 가져오지 않았어요';
  static const String imageUnsupported = '이 이미지는 보여 줄 수 없어요';

  // --- links ---------------------------------------------------------------------
  static const String linkTitle = '링크';
  static const String linkCopy = '주소 복사';
  static const String linkOpen = '외부 앱에서 열기';
  static const String linkOpenFailed = '링크를 열지 못했어요';
  static const String linkNoAnchor = '문서 안에서 그 제목을 찾지 못했어요';
  static const String linkCopyOnly = '이 주소는 앱에서 열 수 없어서 복사만 돼요';

  // --- semantics -----------------------------------------------------------------
  static String taskLabel(String text, bool checked) =>
      '할 일${text.isEmpty ? '' : ': $text'}, ${checked ? '끝남' : '안 끝남'}';
  static String linkLabel(String text) => '링크: $text';
  static String mathError(String message) => '수식 오류: $message';
}
