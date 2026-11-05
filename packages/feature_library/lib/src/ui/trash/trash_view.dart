// lib/src/ui/trash/trash_view.dart — 05-library 6.13: the trash section's
// content. The notice line ('30일 뒤 자동으로 영구 삭제' + [휴지통 비우기] while
// there are entries) above the rows of trashItemsProvider (newest first),
// the empty state, the delayed spinner, or the load error with [다시 시도].
// Entries that left the trash leave the selection (6.7).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' show TrashItem, trashItemsProvider;

import '../../common/report_error.dart';
import '../../l10n/library_strings.dart';
import '../../model/item_key.dart';
import '../../model/section.dart';
import '../../state/providers.dart';
import '../content/empty_state.dart';
import '../layout/library_metrics.dart';
import '../library_scope.dart';
import '../menus/item_action_flows.dart';
import 'trash_row.dart';

class TrashView extends ConsumerWidget {
  const TrashView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final routeFolderId = LibraryScope.of(context).routeFolderId;
    ref.listen(trashItemsProvider, (_, next) {
      final items = next.value;
      if (items == null) return;
      ref.read(librarySelectionProvider(routeFolderId).notifier).retainVisible({
        for (final t in items) keyOfRef(t.ref),
      });
    });
    final async = ref.watch(trashItemsProvider);
    if (async.hasError) {
      reportLibraryErrorOnce(
        ProviderScope.containerOf(context, listen: false),
        async.error!,
        async.stackTrace,
        'library trash: trashItemsProvider',
      );
      return ListLoadError(onRetry: () => ref.invalidate(trashItemsProvider));
    }
    final items = async.value;
    if (items == null) return const DelayedSpinner();
    if (items.isEmpty) return const EmptyState(section: TrashSection());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TrashNotice(count: items.length),
        const Divider(height: 1),
        Expanded(child: _TrashList(items: items)),
      ],
    );
  }
}

/// `[ⓘ] 휴지통의 항목은 30일 뒤 자동으로 영구 삭제돼요. … [휴지통 비우기]`.
class _TrashNotice extends StatelessWidget {
  const _TrashNotice({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: [
            Icon(Icons.info_outline, size: 20, color: muted),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                LibraryStrings.trashNotice,
                style: theme.textTheme.bodyMedium?.copyWith(color: muted),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () => runEmptyTrashFlow(context, count: count),
              child: const Text(LibraryStrings.emptyTrash),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrashList extends StatelessWidget {
  const _TrashList({required this.items});

  final List<TrashItem> items;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemExtent: LibraryMetrics.trashRowHeight,
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return TrashRow(
          key: ValueKey<LibraryItemKey>(keyOfRef(item.ref)),
          item: item,
        );
      },
    );
  }
}
