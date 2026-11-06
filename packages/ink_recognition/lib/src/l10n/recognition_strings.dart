// lib/src/l10n/recognition_strings.dart — (internal) every Korean string of
// ink_recognition (m5-7/05-library 6.21, 6.11.4, 4.4.4, 4.4.9). One place so
// unit/strings_contract_test.dart can pin the contract sentence (7.4.2) and
// the action labels.
abstract final class RecognitionStrings {
  /// Contract m5-7/00-overview 7.4.2 — the web conversion sheet (fixed).
  static const String webUnsupported =
      '이 기기(웹)에서는 손글씨 인식을 쓸 수 없어요. 안드로이드 앱에서 쓸 수 있어요.';

  /// Native without an engine (desktops, before a model platform exists).
  static const String unsupported = '이 기기에서는 손글씨 인식을 쓸 수 없어요.';
  static const String noInk = '변환할 손글씨가 없어요.';
  static const String recognizing = '인식 중…';
  static String lineProgress(int i, int n) => '$i/$n줄';

  /// [language] = [languageName] of a tag.
  static String modelNeeded(String language) =>
      '$language 인식 모델을 받아야 해요(약 20MB).';
  static const String korean = '한국어';
  static const String english = '영어';
  static String languageName(String tag) => tag == 'en' ? english : korean;

  static const String cellularWarning =
      '셀룰러 데이터로 받을 수 있어요(약 20MB). 한 번 더 누르면 받아요.';
  static const String waitingForWifi = '와이파이에 연결되면 받아요.';
  static const String downloadOnCellular = '지금 셀룰러로 받기';
  static const String cellularConfirm = '셀룰러 데이터로 받아요(약 20MB). 한 번 더 누르면 받아요.';
  static const String copyFailed = '복사하지 못했어요.';
  static const String mathFixtureEntry = '수식 고정 자료 만들기';
  static const String mathFixtureCopy = '고정 자료 복사';
  static const String mathFixtureCopied =
      '고정 자료를 복사했어요. functions/tool/fixtures/math/에 붙여 넣으세요.';
  static const String recognizeFailed = '인식하지 못했어요. 다시 시도해 주세요.';
  static const String readOnly = '읽기 전용 노트라 바꿀 수 없어요.';
  static const String copied = '복사했어요.';
  static String tooManyLines(int n) => '나머지 $n줄은 선택을 나눠 변환해 주세요.';
  static const String manualOnly = '수식 인식 엔진이 연결되지 않아 LaTeX로 직접 입력해요.';

  /// Unexpected exception inside an action (6.22).
  static const String runFailed = '실행하지 못했어요.';

  // G-3 consent card.
  static const String consentTitle = '수식 인식에 외부 서비스를 써요';
  static const String consentBody =
      '고른 영역의 손글씨 획과 그 영역 이미지를 외부 수식 인식 서비스로 보내요. '
      '노트의 다른 내용은 보내지 않아요. 설정 › 인식에서 언제든 끌 수 있어요.';
  static const String consentAgree = '동의하고 쓰기';
  static const String typeInstead = '직접 입력';

  // Math engine answers (6.11.4).
  static const String mathUnauthenticated = '로그인한 뒤에 수식 인식을 쓸 수 있어요.';
  static const String mathPermissionDenied = '이 계정에서는 수식 인식을 쓸 수 없어요.';
  static const String mathInvalidArgument = '이 필기는 수식으로 보낼 수 없어요.';
  static const String mathQuotaExceeded = '오늘 쓸 수 있는 수식 인식 횟수를 다 썼어요.';
  static const String mathOffline = '수식 인식 서버에 연결할 수 없어요. 인터넷 연결을 확인해 주세요.';
  static const String mathFailed = '수식을 인식하지 못했어요. 다시 시도해 주세요.';

  // Sheet buttons and fields (6.12, 6.15).
  static const String cancel = '취소';
  static const String apply = '적용';
  static const String copyLatex = 'LaTeX 복사';
  static const String latexField = 'LaTeX';
  static const String mathPadTitle = '수식 입력';
  static const String insert = '넣기';

  // Action labels (4.4.4).
  static const String toText = '텍스트로 변환';
  static const String copyText = '텍스트 복사';
  static const String toMath = '수식으로 변환';
  static const String editMath = '수식 편집';
  static const String mathPad = '수식';

  /// The developer overlay without an indexer (4.4.9).
  static const String noIndexerLine = '손글씨 색인 없음 (이 기기에서 인식 불가)';

  // Settings section '인식' (6.18).
  static const String handwritingGroup = '손글씨 인식';
  static const String mathGroup = '수식 인식';
  static const String labGroup = '품질 실험';
  static const String languageTitle = '인식 언어';

  /// The language choices and the model rows: 한국어 · English (6.18 layout).
  static String languageLabel(String tag) => tag == 'en' ? 'English' : korean;
  static const String modelTitle = '인식 모델';
  static const String wifiOnlyTitle = 'Wi-Fi에서만 모델 받기';

  /// Under the Wi-Fi switch on iPad (the engine does not enforce it — 6.7.4).
  static const String wifiOnlyAskFirst = '받기 전에 셀룰러 데이터 사용을 한 번 더 물어봐요.';
  static const String autoIndexTitle = '검색용 자동 인식';
  static const String mathEngineTitle = '엔진';
  static const String mathEngineManual = '연결 안 됨 — LaTeX로 직접 입력해요';
  static const String mathEngineServer = '서버 엔진';
  static const String consentSwitch = '외부 서비스로 보내기 동의';

  // Indexer status line (6.19) — '상태: ' + the phase text (not for off).
  static const String statusPrefix = '상태: ';
  static const String indexerOff = '이 기기에서는 자동 인식을 쓸 수 없어요';
  static const String indexerDisabled = '꺼져 있어요';
  static const String indexerWaitingModel = '인식 모델을 기다리는 중이에요';
  static const String indexerWaitingWifi = ' · 와이파이 대기';
  static String indexerIdle(int indexed) => '대기 중 · 인식한 페이지 $indexed';
  static String indexerWaitingInput(int queued) =>
      '필기가 멈추길 기다리는 중 · 남은 페이지 $queued';
  static String indexerRecognizing(int queued) => '인식 중 · 남은 페이지 $queued';
  static const String indexerPaused = '앱이 뒤에 있어 멈췄어요';
}
