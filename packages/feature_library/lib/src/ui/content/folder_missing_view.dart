// lib/src/ui/content/folder_missing_view.dart — 05-library 6.4: the route
// folder is not in the active tree (after the tree loaded). Trashed (also by
// another device, Y-2) → [휴지통 보기] [홈으로]; gone → [홈으로].
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/library_strings.dart';
import '../../model/content.dart';
import '../../state/providers.dart';
import '../library_scope.dart';

class FolderMissingView extends ConsumerWidget {
  const FolderMissingView({super.key, required this.state})
    : assert(state != FolderLookupState.active);

  /// trashed or missing.
  final FolderLookupState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final trashed = state == FolderLookupState.trashed;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                trashed ? Icons.delete_outline : Icons.folder_off_outlined,
                size: 64,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 16),
              Text(
                trashed
                    ? LibraryStrings.folderInTrash
                    : LibraryStrings.folderNotFound,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                runSpacing: 12,
                children: [
                  if (trashed)
                    OutlinedButton(
                      onPressed: () {
                        final scope = LibraryScope.read(context);
                        ref
                            .read(
                              librarySectionProvider(scope.routeFolderId)
                                  .notifier,
                            )
                            .showTrash();
                      },
                      child: const Text(LibraryStrings.showTrash),
                    ),
                  FilledButton(
                    onPressed: () =>
                        LibraryScope.read(context).openFolder(null),
                    child: const Text(LibraryStrings.goHome),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
