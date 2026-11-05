// lib/src/ui/content/content_pane.dart — 05-library 6.1:
// Column[top bar (64) — the selection bar in selection mode (6.9), storage
// warning banner (L18), Expanded(ContentBody)]. While a drag runs the top
// bar stays (its breadcrumb takes drops, 6.6) even though the drag started
// selection mode; the selection bar comes when the drag ends.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../dnd/library_drag_scope.dart';
import '../../model/section.dart';
import '../../state/providers.dart';
import '../library_scope.dart';
import '../top_bar/library_top_bar.dart';
import '../top_bar/selection_bar.dart';
import 'content_body.dart';

class ContentPane extends ConsumerWidget {
  const ContentPane({super.key, required this.section});

  final LibrarySection section;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final routeFolderId = LibraryScope.of(context).routeFolderId;
    final selecting = ref.watch(
      librarySelectionProvider(routeFolderId).select((s) => s.active),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ValueListenableBuilder<bool>(
          valueListenable: LibraryDragScope.draggingOf(context),
          builder: (context, dragging, _) => selecting && !dragging
              ? SelectionBar(section: section)
              : LibraryTopBar(section: section),
        ),
        const Divider(height: 1),
        Expanded(child: ContentBody(section: section)),
      ],
    );
  }
}
