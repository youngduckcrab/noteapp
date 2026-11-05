// lib/src/library_screen.dart — contract 00-overview 7.2.18, 05-library 4.2.
//
// Foundation step B6 (contract 7.6): the final constructor with a placeholder
// body — a '새 노트' button that creates a note through CORE and opens it with
// onOpenNote. The real screen (sidebar, listing, dialogs, …) comes with tasks
// L8-L18 of 05-library 8.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' show libraryRepositoryProvider;

import 'l10n/library_strings.dart';

/// The library (home) screen. The app shell routes `/` (folderId null) and
/// `/folders/:folderId` to it; the screen knows no router and only calls the
/// callbacks below. The only provider the app shell must override is CORE's
/// noteStoreProvider (contract 7.3.3).
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({
    super.key,
    this.folderId,
    required this.onOpenFolder,
    required this.onOpenNote,
    required this.onOpenSettings,
  });

  /// The folder shown in the content area; null is the top level ('홈').
  final String? folderId; // null = 홈; unknown id → 'folder missing' view

  /// Navigates to a folder (null = home).
  final ValueChanged<String?> onOpenFolder; // null = 홈

  /// Opens a note in the editor. The library never calls markOpened: CORE's
  /// openSession records '최근' (contract 7.2.8 N-6).
  // also right after creating / importing a note
  final ValueChanged<String> onOpenNote;

  /// Opens the settings screen (sidebar settings button, sync status).
  final VoidCallback onOpenSettings;

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  /// A createNote call is in flight: the button is disabled (no double taps).
  /// CORE write Futures stay pending while a failed commit is retried, so the
  /// button simply stays disabled meanwhile (contract 7.2.9 v1.2).
  bool _creating = false;

  Future<void> _createNote() async {
    if (_creating) return;
    setState(() => _creating = true);
    try {
      final note = await ref
          .read(libraryRepositoryProvider)
          .createNote(title: LibraryStrings.defaultNoteTitle);
      if (!mounted) return;
      widget.onOpenNote(note.id);
    } on Object catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'feature_library',
          context: ErrorDescription('while creating a new note'),
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text(LibraryStrings.errorGeneric)),
      );
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.folderId == null
              ? LibraryStrings.home
              : LibraryStrings.folders,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: LibraryStrings.settings,
            onPressed: widget.onOpenSettings,
          ),
        ],
      ),
      body: Center(
        child: FilledButton.icon(
          icon: const Icon(Icons.note_add_outlined),
          label: const Text(LibraryStrings.newNote),
          onPressed: _creating ? null : _createNote,
        ),
      ),
    );
  }
}
