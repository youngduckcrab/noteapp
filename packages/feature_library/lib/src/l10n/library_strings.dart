// lib/src/l10n/library_strings.dart — 05-library 6.18 (contract 7.4.5: Korean
// 해요체 UI strings live in one constants file per area; no intl).

/// Every Korean UI string of the library screen. Widgets never contain Korean
/// literals; tests find widgets through these constants.
///
/// Foundation step B6 holds only the strings of the placeholder screen. The
/// full table of 05-library 6.18 is added with task L1.
abstract final class LibraryStrings {
  static const String home = '홈';
  static const String folders = '폴더';
  static const String settings = '설정';
  static const String newNote = '새 노트';
  static const String defaultNoteTitle = '제목 없는 노트';
  static const String errorGeneric = '작업을 마치지 못했어요. 다시 시도해 주세요.';
}
