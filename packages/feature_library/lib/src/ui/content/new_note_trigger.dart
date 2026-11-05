// lib/src/ui/content/new_note_trigger.dart — what every '새 노트' control
// does (the grid's '새 노트' tile, the empty state button). Until the new
// note dialog (L12) it creates '제목 없는 노트' with the new note defaults in
// [folderId] and opens it (the foundation behaviour); L12 opens the dialog
// here instead, so the controls themselves do not change.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' show FolderId;

import '../../l10n/library_strings.dart';
import '../../model/new_note_spec.dart';
import '../../state/library_actions.dart';
import '../../state/providers.dart';
import '../feedback/library_snack_bar.dart';
import '../library_scope.dart';

class NewNoteTrigger extends ConsumerStatefulWidget {
  const NewNoteTrigger({
    super.key,
    required this.folderId,
    required this.builder,
  });

  /// Where the note goes (null = 홈).
  final FolderId? folderId;

  /// [onPressed] is null while a creation is in flight (no double taps).
  final Widget Function(BuildContext context, VoidCallback? onPressed) builder;

  @override
  ConsumerState<NewNoteTrigger> createState() => _NewNoteTriggerState();
}

class _NewNoteTriggerState extends ConsumerState<NewNoteTrigger> {
  /// CORE write Futures stay pending while a failed commit is retried
  /// (contract 7.2.9 v1.2), so the control stays disabled meanwhile.
  bool _creating = false;

  /// The result is handled even when this widget is gone by then (the empty
  /// state disappears as soon as the new note shows up): the scope callbacks
  /// check the screen itself, the snack bar uses the messenger looked up now.
  Future<void> _create() async {
    if (_creating) return;
    setState(() => _creating = true);
    final scope = LibraryScope.read(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final outcome = await ref
        .read(libraryActionsProvider)
        .createNote(
          NewNoteSpec(
            title: LibraryStrings.defaultNoteTitle,
            options: ref.read(newNoteDefaultsProvider),
          ),
          folderId: widget.folderId,
        );
    if (mounted) setState(() => _creating = false);
    switch (outcome) {
      case ActionSuccess(:final value):
        scope.openNote(value.id);
      case ActionFailure(:final kind):
        if (messenger != null) {
          showLibrarySnackBarOn(
            messenger,
            message: libraryFailureMessage(kind),
            sizeClass: scope.sizeClass,
          );
        }
    }
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, _creating ? null : _create);
}
