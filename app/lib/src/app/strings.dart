/// Korean UI text of the app shell (해요체, contract 7.4.5).
///
/// Foundation step B8 holds only the strings of the placeholder shell; I7
/// adds the full table (splash, startup errors, settings, storage, about,
/// backup, update banner — docs/plans/01-infra.md 4.5.6).
abstract final class AppStrings {
  static const String appName = '필기노트';

  /// RuntimeInfo.rendererLabel off the web.
  static const String rendererNative = '네이티브';

  static const String back = '뒤로';
  static const String settings = '설정';
  static const String settingsPlaceholder = '설정 화면은 준비 중이에요.';

  /// Shown when openNoteStore fails at start (B8 has no startup error screen
  /// yet; I5 replaces this with StartupErrorScreen).
  static const String storeOpenFailed = '노트 저장소를 열지 못했어요.';
  static const String storeOpenFailedDetail =
      '시작 화면은 아직 준비 중이에요. 저장 기능이 연결되면 이 화면 대신 라이브러리가 열려요.';
}
