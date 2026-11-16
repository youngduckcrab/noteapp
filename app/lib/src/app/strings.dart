/// Korean UI text of the app shell (해요체, contract 7.4.5).
///
/// Each shell step added its own strings (bootstrap, routing, update banner,
/// settings / storage / about / backup — docs/plans/01-infra.md 4.5.6,
/// 4.5.8). The storage banner sentences of 계약 7.4.5 are not here: LIBRARY
/// and EDITOR show them.
abstract final class AppStrings {
  static const String appName = '필기노트';

  /// RuntimeInfo.rendererLabel off the web.
  static const String rendererNative = '네이티브';

  /// Release-mode replacement of the red error box (appErrorWidgetBuilder).
  static const String errorWidgetMessage = '이 부분을 표시하지 못했어요';

  static const String back = '뒤로';
  static const String close = '닫기';
  static const String settings = '설정';

  /// NotFoundScreen (unknown location, 6.6).
  static const String notFoundTitle = '페이지를 찾을 수 없어요';
  static const String notFoundDetail = '주소가 바뀌었거나 없는 페이지예요.';
  static const String goHome = '홈으로 가기';

  /// Splash (SplashView).
  static String splashSlow(int seconds) => '시간이 걸리고 있어요… ($seconds초)';

  /// Startup error screen (StartupErrorScreen, 6.7).
  static const String startupFailedTitle = '앱을 시작하지 못했어요';
  static const String startupStorageUnavailable =
      '이 브라우저에서는 저장소를 쓸 수 없어요. 개인정보 보호(비공개) 탭이라면 일반 탭이나 홈 화면 앱으로 열어 주세요.';
  static const String startupMigrationFailed =
      '저장된 데이터를 새 형식으로 바꾸지 못했어요. 진단 정보를 복사해 보내 주세요.';
  static const String startupCorrupted =
      '저장된 데이터가 손상되어 열 수 없어요. 진단 정보를 복사해 보내 주세요.';
  static const String startupNewerSchema =
      '더 새로운 버전에서 저장한 데이터예요. 앱을 새로고침해 최신 버전을 받아 주세요.';
  static const String startupStoreUnknown = '저장소를 여는 중 문제가 생겼어요. 다시 시도해 주세요.';
  static String startupTimedOut(String moduleLabel) =>
      '시작이 너무 오래 걸려요($moduleLabel). 다시 시도해 주세요.';
  static const String startupGeneric = '앱을 시작하지 못했어요. 다시 시도해 주세요.';
  static const String startupDetails = '자세히 보기';
  static String startupDetailModule(String moduleId) => '모듈: $moduleId';
  static const String retry = '다시 시도';
  static const String copyDiagnostics = '진단 정보 복사';
  static const String diagnosticsCopied = '진단 정보를 복사했어요.';
  static const String reload = '새로고침';
  static const String resetLocalData = '이 기기 데이터 지우고 다시 시작';
  static const String resetConfirmFirst =
      '이 기기에 저장된 노트·폴더·펜 설정이 모두 지워져요. 되돌릴 수 없어요.';
  static const String resetConfirmSecond = '정말 지울까요?';
  static const String cancel = '취소';
  static const String proceed = '계속';
  static const String erase = '지우기';
  static const String resetFailed = '데이터를 지우지 못했어요.';

  /// New-version banner (UpdateBanner, 6.11 step 5).
  static String updateAvailable(int buildNumber, String shortSha) =>
      '새 버전이 나왔어요 (#$buildNumber · $shortSha). 새로고침하면 적용돼요.';
  static const String later = '나중에';

  /// Settings sections (4.5.8 table): titles and the group header.
  static const String sectionStorage = '저장 공간';
  static const String sectionInput = '입력';
  static const String sectionPen = '펜';
  static const String sectionPageFlip = '페이지 넘김';
  static const String sectionNewNote = '새 노트 기본값';
  static const String sectionDeveloper = '개발자 표시';
  static const String sectionFeatures = '기능 켜고 끄기';
  static const String sectionV1Copy = '이전 판 DB 사본';
  static const String sectionAbout = '앱 정보';
  static const String groupGeneral = '일반';

  /// '화면' group (AppStyleSection ×2, AppBrightnessSection — 01-infra
  /// 14.3). (v2.14-ui split) the home screen and the note editor each have
  /// a style; brightness is one for both.
  static const String groupScreen = '화면';
  static const String sectionHomeStyle = '홈 화면 스타일';
  static const String sectionEditorStyle = '필기 화면 스타일';
  static const String homeStyleNote = '서재, 폴더, 휴지통, 검색, 설정 화면에 적용돼요.';
  static const String editorStyleNote = '노트를 열었을 때의 도구 막대, 펜, 메뉴에 적용돼요.';
  static const String sectionBrightness = '밝기';
  static const String styleCraft = '크래프트';
  static const String styleCraftHint = '따뜻한 종이 느낌, 부드러운 그림자';
  static const String styleCalm = '미니멀';
  static const String styleCalmHint = '군더더기 없이 차분하게, 강조색 하나';
  static const String styleStudio = '스튜디오';
  static const String styleStudioHint = '차가운 회색 작업대, 또렷한 대비';
  static const String brightnessSystem = '시스템 따라';
  static const String brightnessLight = '밝게';
  static const String brightnessDark = '어둡게';
  static const String styleLayoutNote =
      '지금은 색과 모양이 바뀌어요. 도구 막대 배치는 다음 업데이트에서 스타일에 맞게 바뀌어요.';
  static const String brightnessPaperNote =
      '어두운 화면에서도 노트 종이와 잉크 색은 그대로예요. 종이 바깥 화면만 어두워져요.';

  /// Common values.
  static const String yes = '예';
  static const String no = '아니요';
  static const String unknown = '알 수 없음';
  static const String none = '없음';

  /// StorageSection ('저장 공간').
  static const String storageBackend = '저장 방식';
  static const String storageDurability = '데이터 보존';
  static const String storageDurable = '이 기기에 저장돼요';
  static const String storageNotDurable = '임시 저장이에요. 새로고침하면 사라져요.';
  static const String storageMultiTab = '여러 탭';
  static const String storageMultiTabSafe = '여러 탭에서 열어도 안전해요';
  static const String storageMultiTabUnsafe = '여러 탭에서 함께 열면 안전하지 않아요';
  static const String storagePersist = '영구 보관';
  static const String storagePersistGranted = '허용됨';
  static const String storagePersistDenied =
      '허용되지 않음 — 공간이 부족하면 브라우저가 지울 수 있어요';
  static const String storageUsage = '사용량';
  static const String storageMissingFeatures = '부족한 브라우저 기능';
  static const String storagePending = '저장 대기';
  static String storagePendingOps(int count, {required bool writing}) =>
      '$count건${writing ? ' (저장하는 중)' : ''}';
  static const String storageLastCommit = '마지막 저장';
  static const String storageNoCommit = '아직 없음';
  static const String storageFailures = '연속 실패';
  static String storageFailureCount(int count) => '$count회';
  static const String storageWriteFailing =
      '저장에 계속 실패하고 있어요. 남은 저장 공간을 확인하고, 계속되면 진단 정보를 복사해 보내 주세요.';
  static const String storageLastError = '마지막 오류';
  static const String storageRefresh = '다시 확인';
  static const String storageRefreshFailed = '저장 공간 정보를 다시 읽지 못했어요.';

  /// 2차 6.18: per-type attachment bytes (AssetStorageUsage.bytesByType) and
  /// the search index row.
  static const String storageAssets = '첨부 파일';
  static String storageAssetUsage({
    required int count,
    required int total,
    required int audio,
    required int image,
    required int pdf,
  }) =>
      '$count개 · ${megabytes(total)} (녹음 ${megabytes(audio)} · '
      '이미지 ${megabytes(image)} · PDF ${megabytes(pdf)})';
  static const String storageAssetsUnread = '첨부 파일 정보를 읽지 못했어요';
  static const String storageSearchIndex = '검색 색인';
  static String storageSearchIndexStatus(
    int pendingOwners, {
    required bool rebuilding,
  }) => '대기 $pendingOwners개${rebuilding ? ' · 재구축 중' : ''}';
  static const String storageRebuildIndex = '다시 만들기';
  static const String storageRebuildConfirm =
      '검색 색인을 처음부터 다시 만들어요. 시간이 걸릴 수 있어요.';
  static const String storageRebuildFailed =
      '검색 색인을 다시 만들지 못했어요. 진단 정보를 복사해 보내 주세요.';

  /// '0 MB', '<0.1 MB', '12.3 MB' (1024-based, one decimal).
  static String megabytes(int bytes) {
    if (bytes <= 0) return '0 MB';
    final mb = bytes / (1024 * 1024);
    if (mb < 0.05) return '<0.1 MB';
    return '${mb.toStringAsFixed(1)} MB';
  }

  /// AboutSection ('앱 정보').
  static const String aboutBuild = '빌드';

  /// (v2.14-ui) Developer mode (7 taps on the 빌드 row).
  static const String developerModeOn = '개발자 모드를 켰어요';
  static const String developerModeOff = '개발자 모드를 껐어요';

  /// (v2.14-ui review) The stored switch is off but the developer overlay
  /// (⌘⇧D) or `?dev=1` keeps developer mode on.
  static const String developerModeStillOn =
      '개발자 모드 설정을 껐어요. 개발자 표시나 주소의 ?dev=1 때문에 아직 켜져 있어요';

  /// (v2.14-ui review) Taps left on the 빌드 row.
  static String developerModeTapsLeft(int left) => '개발자 모드까지 $left번 남았어요';
  static const String aboutRenderer = '렌더러';
  static const String aboutStandalone = '홈 화면 앱';
  static const String aboutStartup = '시작 시간';
  static String aboutStartupTimes(int? pageMs, int bootstrapMs) => [
    if (pageMs != null) '페이지 열기→준비 ${groupDigits(pageMs)}ms',
    '부트스트랩 ${groupDigits(bootstrapMs)}ms',
  ].join(' · ');
  static const String aboutErrors = '오류';
  static String aboutErrorCount(int count) => '$count건';
  static const String aboutUpdate = '새 버전';

  /// The feature line (2차 6.18): '녹음 켬 · 인식 꺼짐(개발자 메뉴) · 수식 엔진
  /// 꺼짐(빌드)' — appFeatureStatusLine.
  static const String aboutFeatures = '기능';

  /// The Apple Pencil line (iOS, 2차 6.12.3 / 6.18): 'iOS 17.5 · 더블탭 · 호버';
  /// squeeze and roll only once this run has received one ('· 스퀴즈(받음)').
  static const String aboutPencil = 'Apple Pencil';
  static String aboutPencilOs(String os) => 'iOS $os';
  static const String aboutPencilUnread = '능력을 읽지 못했어요';
  static const String aboutPencilDoubleTap = '더블탭';
  static const String aboutPencilHover = '호버';
  static const String aboutPencilSqueezeSeen = '스퀴즈(받음)';
  static const String aboutPencilRollSeen = '롤(받음)';
  static const String checkForUpdate = '새 버전 확인';
  static const String updateDisabled = '이 빌드에서는 새 버전을 확인하지 않아요.';
  static const String updateUnknown = '아직 확인하지 않았어요.';
  static String updateUpToDate(String time) => '최신 버전이에요. ($time 확인)';
  static String updateFound(int buildNumber, String shortSha) =>
      '새 버전이 있어요 (#$buildNumber · $shortSha). 새로고침하면 적용돼요.';
  static const String licenses = '오픈소스 라이선스';

  /// FeatureSwitchSection ('기능 켜고 끄기' — docs/plans/m5-7/01-infra.md 6.6).
  static const String featureMedia = '녹음';
  static const String featureMediaHint = '녹음·녹음 패널. 이미지 넣기는 꺼지지 않아요';
  static const String featureRecognition = '인식';
  static const String featureRecognitionHint = '손글씨·수식 인식, 자동 도형 보정';
  static const String featureMathEngine = '수식 엔진';
  static const String featureMathEngineHint =
      '수식 인식 서버(인식이 켜져 있을 때). 수식 직접 입력은 꺼지지 않아요';
  static const String featureOffInBuild = '이 빌드에서 꺼져 있어요';
  static const String featureRestartToApply = '다시 시작하면 적용돼요';
  static const String featureRestart = '다시 시작';
  static const String featureRestartNative = '앱을 완전히 닫았다가 다시 열어 주세요';
  static const String featureSaveFailed = '설정을 저장하지 못했어요.';
  static const String featureFlushFailed =
      '저장이 아직 끝나지 않아 다시 시작하지 않았어요. 잠시 뒤 다시 눌러 주세요.';

  /// V1CopySection ('이전 판 DB 사본' — 2차 6.18, 4.6.7; contract 7.2.7).
  static const String v1CopyLoading = '확인하는 중…';
  static String v1CopyPresent({
    required String createdAt,
    required String size,
    required int normalOpens,
  }) => '사본 있음: $createdAt · $size · 정상 열기 $normalOpens번';
  static String v1CopyFailed(String reason) =>
      '사본을 만들지 못했어요($reason) — 이전 판 데이터는 새 판으로 옮겨졌어요';
  static const String v1CopyFailedQuota = '저장 공간 부족';
  static const String v1CopyFailedIo = '읽기·쓰기 오류';
  static const String v1CopyFailedOther = '알 수 없는 오류';
  static const String v1CopyNone = '사본 없음';
  static const String v1CopyPending = '이 판의 저장소에서는 아직 볼 수 없어요';
  static const String v1CopyInfoError = '사본 정보를 읽지 못했어요';
  static const String v1CopyExport = '내보내기';
  static const String v1CopyDelete = '지우기';
  static String v1CopyPreparing(String received, String total) =>
      '준비 중… $received / $total';
  static const String v1CopyReadFailed = '사본을 읽지 못했어요';
  static const String v1CopyDeleteConfirm = '이전 판 DB 사본을 지워요. 되돌릴 수 없어요.';
  static const String v1CopyDeleteFailed = '사본을 지우지 못했어요';

  /// Reload while recording (6.17 — the update banner and the feature
  /// switches).
  static const String reloadBlockedByRecording =
      '녹음 중에는 새로 고칠 수 없어요. 녹음을 멈춘 뒤 눌러 주세요.';

  /// Backup export (AboutSection, BackupReadySheet — 4.5.8).
  static const String backupExport = '백업 내보내기';
  static const String backupPreparing = '백업을 만드는 중…';
  static const String backupSlowWrites = '저장이 늦어지고 있어요. 저장 공간을 확인해 주세요.';
  static const String backupReadyTitle = '백업 파일이 준비됐어요';
  static const String backupShare = '공유 · 파일에 저장';
  static const String backupDownload = '내려받기';
  static const String backupDownloaded = '백업 파일을 내려받았어요. 파일 앱에 보관해 주세요.';
  static const String backupShared = '공유 시트로 보냈어요. 파일 앱에 저장됐는지 확인해 주세요.';
  static const String backupUnsupported =
      '이 기기에서는 이 방법으로 백업 파일을 저장할 수 없어요. 다른 방법을 눌러 주세요.';
  static const String backupFailed = '백업을 만들지 못했어요. 진단 정보를 복사해 보내 주세요.';

  /// `12,345` (thousands separators).
  static String groupDigits(int value) {
    final digits = '${value.abs()}';
    final out = StringBuffer(value < 0 ? '-' : '');
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
      out.write(digits[i]);
    }
    return out.toString();
  }

  /// `12.3MB` (1024-based, one decimal from KB up).
  static String bytes(int bytes) {
    const units = ['KB', 'MB', 'GB', 'TB'];
    if (bytes < 1024) return '${bytes}B';
    var value = bytes / 1024;
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    return '${value.toStringAsFixed(1)}${units[unit]}';
  }
}
