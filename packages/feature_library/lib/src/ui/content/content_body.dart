// lib/src/ui/content/content_body.dart — 05-library 6.1 / 6.4: the content
// area by section. Task L8 is the branch itself; the bodies come with their
// tasks: folder listing + folder missing view (L10), trash (L16), recent /
// favorites / search (L17). Until L10 the folder body is the foundation
// placeholder: a '새 노트' button that creates an untitled note in the folder
// and opens it.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' show FolderId;

import '../../l10n/library_strings.dart';
import '../../model/new_note_spec.dart';
import '../../model/section.dart';
import '../../state/library_actions.dart';
import '../../state/providers.dart';
import '../feedback/library_snack_bar.dart';
import '../library_scope.dart';

class ContentBody extends StatelessWidget {
  const ContentBody({super.key, required this.section});

  final LibrarySection section;

  @override
  Widget build(BuildContext context) => switch (section) {
    FolderSection(:final folderId) => _InterimFolderBody(
      key: ValueKey<FolderId?>(folderId),
      folderId: folderId,
    ),
    RecentSection() ||
    FavoritesSection() ||
    SearchSection() ||
    TrashSection() => const SizedBox.expand(),
  };
}

/// Placeholder folder body until the listing (L10).
class _InterimFolderBody extends ConsumerStatefulWidget {
  const _InterimFolderBody({super.key, required this.folderId});

  final FolderId? folderId;

  @override
  ConsumerState<_InterimFolderBody> createState() => _InterimFolderBodyState();
}

class _InterimFolderBodyState extends ConsumerState<_InterimFolderBody> {
  /// A createNote call is in flight: the button is disabled (no double taps).
  /// CORE write Futures stay pending while a failed commit is retried
  /// (contract 7.2.9 v1.2), so the button stays disabled meanwhile.
  bool _creating = false;

  Future<void> _createNote() async {
    if (_creating) return;
    setState(() => _creating = true);
    final scope = LibraryScope.read(context);
    final outcome = await ref
        .read(libraryActionsProvider)
        .createNote(
          NewNoteSpec(
            title: LibraryStrings.defaultNoteTitle,
            options: ref.read(newNoteDefaultsProvider),
          ),
          folderId: widget.folderId,
        );
    if (!mounted) return;
    setState(() => _creating = false);
    switch (outcome) {
      case ActionSuccess(:final value):
        scope.openNote(value.id);
      case ActionFailure(:final kind):
        showLibrarySnackBar(
          context,
          message: libraryFailureMessage(kind),
          sizeClass: scope.sizeClass,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FilledButton.icon(
        icon: const Icon(Icons.note_add_outlined),
        label: const Text(LibraryStrings.newNote),
        onPressed: _creating ? null : _createNote,
      ),
    );
  }
}
