// lib/src/ui/editor_strings.dart — 04-editor 3 / 6.17, contract 7.4.5.
//
// User-facing strings of the editor: Korean 해요체, no intl (contract 7.4.5).
// Developer-only details and logs stay in English. Every user-visible sentence
// of feature_editor lives in this one table; later tasks add the strings of
// their screens (toolbar, pen settings, page panel, developer overlay) here.
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
}
