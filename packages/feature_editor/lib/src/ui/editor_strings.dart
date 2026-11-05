// lib/src/ui/editor_strings.dart — 04-editor 3 / 6.17, contract 7.4.5.
//
// User-facing strings of the editor: Korean 해요체, no intl. Foundation step B5
// holds only the placeholder screen's strings; task E-00 adds the full table,
// including the two fixed storage-warning sentences of contract 7.4.5.
abstract final class EditorStrings {
  /// Semantics label of the toolbar back button ([←], 04-editor 6.9.1).
  static const back = '뒤로';

  /// Semantics label of the more menu button ([⋯], 04-editor 6.9.1).
  static const more = '더보기';

  /// More menu item, shown only when EditorScreen.onOpenSettings != null.
  static const settings = '설정';

  // Screen states (04-editor 6.17.1).
  static const openingNote = '노트를 여는 중…';
  static const noteNotFound = '노트를 찾을 수 없어요';
  static const openFailed = '노트를 열지 못했어요';
  static const retry = '다시 시도';
  static const goBack = '돌아가기';

  /// Body of the B5 placeholder screen (replaced by EditorBody in E-13).
  static const placeholderBody = '필기 화면을 준비하고 있어요';
}
