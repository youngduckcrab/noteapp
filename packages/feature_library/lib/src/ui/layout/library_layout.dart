// lib/src/ui/layout/library_layout.dart — 05-library 6.1: the pinned sidebar
// (expanded class, while shown) next to the content pane.
import 'package:material_ui/material_ui.dart';

import 'library_metrics.dart';
import 'size_class.dart';

class LibraryLayout extends StatelessWidget {
  const LibraryLayout({
    super.key,
    required this.sizeClass,
    required this.sidebarVisible,
    required this.sidebar,
    required this.content,
  });

  final LibrarySizeClass sizeClass;

  /// library.sidebar.visible; used in the expanded class only.
  final bool sidebarVisible;
  final Widget sidebar;
  final Widget content;

  /// Whether [sidebar] is pinned in the body (else it lives in the drawer).
  static bool pinsSidebar(LibrarySizeClass sizeClass, bool sidebarVisible) =>
      sizeClass == LibrarySizeClass.expanded && sidebarVisible;

  @override
  Widget build(BuildContext context) {
    if (!pinsSidebar(sizeClass, sidebarVisible)) return content;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        sidebar,
        const VerticalDivider(width: LibraryMetrics.dividerWidth),
        Expanded(child: content),
      ],
    );
  }
}
