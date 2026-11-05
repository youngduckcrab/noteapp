// lib/src/ui/feedback/library_snack_bar.dart — 05-library 6.11 / 6.19.
import 'package:material_ui/material_ui.dart';

import '../../l10n/library_strings.dart';
import '../../state/library_actions.dart';
import '../layout/library_metrics.dart';
import '../layout/size_class.dart';

/// Snack bar text for a failed action (6.19): folderCycle → errorCycle,
/// notFound → errorNotFound, invalidName / unknown → errorGeneric.
String libraryFailureMessage(LibraryFailureKind kind) => switch (kind) {
  LibraryFailureKind.folderCycle => LibraryStrings.errorCycle,
  LibraryFailureKind.notFound => LibraryStrings.errorNotFound,
  LibraryFailureKind.invalidName ||
  LibraryFailureKind.unknown => LibraryStrings.errorGeneric,
};

/// Floating snack bar on the nearest ScaffoldMessenger (S-2); 480 wide in
/// the expanded class; replaces the current one at once. With [action]
/// (실행 취소 / 보기) it stays 6 s, otherwise 4 s.
void showLibrarySnackBar(
  BuildContext context, {
  required String message,
  required LibrarySizeClass sizeClass,
  SnackBarAction? action,
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  showLibrarySnackBarOn(
    messenger,
    message: message,
    sizeClass: sizeClass,
    action: action,
  );
}

/// [showLibrarySnackBar] on a messenger looked up before an await — for
/// results that arrive after the widget that started the action is gone
/// (the empty state's '새 노트' button is replaced by the grid as soon as the
/// new note appears; an unfavorited row leaves the favorites list).
void showLibrarySnackBarOn(
  ScaffoldMessengerState messenger, {
  required String message,
  required LibrarySizeClass sizeClass,
  SnackBarAction? action,
}) {
  if (!messenger.mounted) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        action: action,
        behavior: SnackBarBehavior.floating,
        width: sizeClass == LibrarySizeClass.expanded ? 480 : null,
        duration: action != null
            ? LibraryMetrics.undoSnackBarDuration
            : LibraryMetrics.errorSnackBarDuration,
      ),
    );
}
