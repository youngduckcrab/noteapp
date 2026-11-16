// lib/src/ui/content/empty_state.dart — 05-library 6.7: what the content
// area shows without items — the empty state of each section, the delayed
// loading spinner and the load error.
import 'dart:async' show Timer;

import 'package:material_ui/material_ui.dart';
import 'package:ui_kit/ui_kit.dart';

import '../../l10n/library_strings.dart';
import '../../model/section.dart';
import '../dialogs/create_flows.dart';
import 'ink_search_hint.dart';
import 'new_note_trigger.dart';

/// Icon 64 + text (+ buttons) in the middle.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.section});

  final LibrarySection section;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final section = this.section;
    final (icon, text) = switch (section) {
      FolderSection(folderId: null) => (
        AppIconKind.note.material,
        LibraryStrings.emptyHome,
      ),
      FolderSection() => (
        AppIconKind.folder.material,
        LibraryStrings.emptyFolder,
      ),
      RecentSection() => (
        AppIconKind.recent.material,
        LibraryStrings.emptyRecent,
      ),
      FavoritesSection() => (
        AppIconKind.favorite.material,
        LibraryStrings.emptyFavorites,
      ),
      SearchSection(:final query) => (
        Icons.search_off,
        LibraryStrings.emptySearch(query),
      ),
      TrashSection() => (
        AppIconKind.trash.material,
        LibraryStrings.emptyTrashView,
      ),
    };
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 64, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(height: 16),
              Text(
                text,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              // (handwriting search, 6.19a) why handwriting may be missing.
              if (section is SearchSection) ...[
                const SizedBox(height: 16),
                const InkSearchHint(),
              ],
              if (section is FolderSection) ...[
                const SizedBox(height: 24),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    NewNoteTrigger(
                      folderId: section.folderId,
                      builder: (context, onPressed) => FilledButton.icon(
                        icon: Icon(AppIconKind.newNote.material),
                        label: const Text(LibraryStrings.newNote),
                        onPressed: onPressed,
                      ),
                    ),
                    OutlinedButton.icon(
                      icon: Icon(AppIconKind.newFolder.material),
                      label: const Text(LibraryStrings.newFolder),
                      onPressed: () =>
                          runNewFolderFlow(context, parentId: section.folderId),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A CircularProgressIndicator in the middle, only after 300 ms (no flicker
/// for short loads).
class DelayedSpinner extends StatefulWidget {
  const DelayedSpinner({super.key});

  static const Duration delay = Duration(milliseconds: 300);

  @override
  State<DelayedSpinner> createState() => _DelayedSpinnerState();
}

class _DelayedSpinnerState extends State<DelayedSpinner> {
  Timer? _timer;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(DelayedSpinner.delay, () {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _visible
      ? const Center(child: CircularProgressIndicator())
      : const SizedBox.expand();
}

/// '목록을 불러오지 못했어요' + [다시 시도] (6.7 / 6.19).
class ListLoadError extends StatelessWidget {
  const ListLoadError({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              AppIconKind.error.material,
              size: 64,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              LibraryStrings.listLoadFailed,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: onRetry,
              child: const Text(LibraryStrings.retry),
            ),
          ],
        ),
      ),
    );
  }
}
