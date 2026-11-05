/// Korean UI text of the app shell (해요체, contract 7.4.5).
///
/// Each shell step adds its own strings; I7 completes the table (settings,
/// storage, about, backup, update banner — docs/plans/01-infra.md 4.5.6).
abstract final class AppStrings {
  static const String appName = '필기노트';

  /// RuntimeInfo.rendererLabel off the web.
  static const String rendererNative = '네이티브';

  /// Release-mode replacement of the red error box (appErrorWidgetBuilder).
  static const String errorWidgetMessage = '이 부분을 표시하지 못했어요';

  static const String back = '뒤로';
  static const String close = '닫기';
  static const String settings = '설정';
  static const String settingsPlaceholder = '설정 화면은 준비 중이에요.';

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
}
