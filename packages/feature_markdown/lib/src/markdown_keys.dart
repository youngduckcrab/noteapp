// Widget keys of the MD 문서 screen (08-markdown 13). Fixed in the foundation; the screen
// (Track B) and the app's tests (Track A) both use them.
import 'package:flutter/foundation.dart';

/// Keys of [MarkdownScreen]'s widgets. `<i>` keys count in document order from 0.
abstract final class MarkdownKeys {
  // --- chrome ---------------------------------------------------------------------
  static const ValueKey<String> screen = ValueKey('md.screen');
  static const ValueKey<String> back = ValueKey('md.back');
  static const ValueKey<String> title = ValueKey('md.title');

  /// The single 보기 ↔ 편집 button.
  static const ValueKey<String> mode = ValueKey('md.mode');

  /// 나란히 (side-by-side editor + preview, wide landscape only).
  static const ValueKey<String> split = ValueKey('md.split');
  static const ValueKey<String> undo = ValueKey('md.undo');
  static const ValueKey<String> redo = ValueKey('md.redo');
  static const ValueKey<String> saveState = ValueKey('md.saveState');
  static const ValueKey<String> more = ValueKey('md.more');
  static const ValueKey<String> menuExport = ValueKey('md.menu.export');
  static const ValueKey<String> menuRename = ValueKey('md.menu.rename');
  static const ValueKey<String> menuInfo = ValueKey('md.menu.info');

  // --- bodies ---------------------------------------------------------------------
  /// The rendered view's scrollable.
  static const ValueKey<String> view = ValueKey('md.view');

  /// The source editor's TextField.
  static const ValueKey<String> editor = ValueKey('md.editor');

  /// The symbol row above the keyboard while editing (# - [ ] * ` $ | > indent outdent).
  static const ValueKey<String> accessory = ValueKey('md.accessory');

  /// The search landing highlight (08-markdown 8.8).
  static const ValueKey<String> highlight = ValueKey('md.highlight');

  /// '이 문서는 MD 문서가 아니에요' with [노트로 열기].
  static const ValueKey<String> notMarkdown = ValueKey('md.notMarkdown');
  static const ValueKey<String> openAsNote = ValueKey('md.notMarkdown.open');

  // --- banners ----------------------------------------------------------------------
  static const ValueKey<String> bannerTrashed = ValueKey('md.banner.trashed');
  static const ValueKey<String> bannerNewerApp = ValueKey('md.banner.newerApp');

  /// '내용을 받는 중이에요' (the body has not arrived — editing blocked).
  static const ValueKey<String> bannerReceiving = ValueKey(
    'md.banner.receiving',
  );

  /// Save refused: over `MarkdownLimits`.
  static const ValueKey<String> bannerTooLarge = ValueKey('md.banner.tooLarge');

  /// Opened view-only because the text is over the editor's own limit.
  static const ValueKey<String> bannerTooLargeToEdit = ValueKey(
    'md.banner.tooLargeToEdit',
  );
  static const ValueKey<String> bannerSaveFailed = ValueKey(
    'md.banner.saveFailed',
  );
  static const ValueKey<String> bannerRetry = ValueKey('md.banner.retry');

  /// '다른 기기에서 바뀐 글을 사본으로 남겼어요' (saveText savedWithConflictCopy).
  static const ValueKey<String> bannerConflictCopy = ValueKey(
    'md.banner.conflictCopy',
  );

  // --- leave dialog (a failed save never loses the text) -------------------------
  static const ValueKey<String> leaveDialog = ValueKey('md.leave');
  static const ValueKey<String> leaveStay = ValueKey('md.leave.stay');
  static const ValueKey<String> leaveCopy = ValueKey('md.leave.copy');
  static const ValueKey<String> leaveDiscard = ValueKey('md.leave.discard');

  // --- link sheet -----------------------------------------------------------------
  static const ValueKey<String> linkSheet = ValueKey('md.linkSheet');
  static const ValueKey<String> linkSheetCopy = ValueKey('md.linkSheet.copy');
  static const ValueKey<String> linkSheetOpen = ValueKey('md.linkSheet.open');
  static const ValueKey<String> linkSheetCancel = ValueKey(
    'md.linkSheet.cancel',
  );

  /// The task-toggle undo snack bar ('할 일을 바꿨어요 [되돌리기]').
  static const ValueKey<String> taskUndo = ValueKey('md.taskUndo');

  // --- added by the screen (Track B) --------------------------------------------
  /// The folded YAML front matter box.
  static const ValueKey<String> frontMatter = ValueKey('md.frontMatter');

  /// 나란히 mode's preview pane.
  static const ValueKey<String> splitPreview = ValueKey('md.split.preview');

  /// '저장하지 못한 글이 있어요' (text kept on this device after a failed save on pause).
  static const ValueKey<String> bannerUnsaved = ValueKey('md.banner.unsaved');
  static const ValueKey<String> bannerUnsavedRestore = ValueKey(
    'md.banner.unsaved.restore',
  );
  static const ValueKey<String> bannerUnsavedDiscard = ValueKey(
    'md.banner.unsaved.discard',
  );

  /// Closes the conflict-copy banner.
  static const ValueKey<String> bannerDismiss = ValueKey('md.banner.dismiss');

  /// The rename dialog's field and its confirm button.
  static const ValueKey<String> renameField = ValueKey('md.rename.field');
  static const ValueKey<String> renameOk = ValueKey('md.rename.ok');

  /// The accessory row's buttons: `md.accessory.<symbol name>`.
  static ValueKey<String> accessoryButton(String name) =>
      ValueKey('md.accessory.$name');

  /// The fade at the 'start' / 'end' of the symbol row while more of it is hidden there.
  static ValueKey<String> accessoryFade(String side) =>
      ValueKey('md.accessory.fade.$side');

  /// [사본 열기] on the conflict-copy banner (shown when the app gives onOpenMarkdown).
  static const ValueKey<String> bannerOpenCopy = ValueKey(
    'md.banner.conflictCopy.open',
  );

  /// The table's [더 보기] (a long table shows its rows in parts).
  static ValueKey<String> tableMore(int i) => ValueKey('md.table.$i.more');

  // --- per element ----------------------------------------------------------------
  static ValueKey<String> block(int i) => ValueKey('md.block.$i');
  static ValueKey<String> task(int i) => ValueKey('md.task.$i');
  static ValueKey<String> link(int i) => ValueKey('md.link.$i');
  static ValueKey<String> code(int i) => ValueKey('md.code.$i');
  static ValueKey<String> codeCopy(int i) => ValueKey('md.code.$i.copy');
  static ValueKey<String> table(int i) => ValueKey('md.table.$i');
  static ValueKey<String> math(int i) => ValueKey('md.math.$i');
  static ValueKey<String> image(int i) => ValueKey('md.image.$i');
}
