// lib/src/ui/overlays/page_indicator.dart — 04-editor 6.4.3 ("3 / 12").
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui_kit/ui_kit.dart';

import '../../scope/editor_scope.dart';
import '../../state/settings/editor_device_state.dart';
import '../editor_strings.dart';
import '../toolbar/editor_toolbar.dart' show EditorToolbar;

/// "current / count" at the bottom right of the page area; never takes
/// input (IgnorePointer). (UI stage 2, 04-editor 22) Only where the toolbar
/// does not show the count itself: while the top menu is hidden, and on a
/// window narrower than [EditorToolbar.pageCountMinWidth] (phones, split
/// screen — the page button is the icon alone there).
class PageIndicator extends ConsumerWidget {
  const PageIndicator({super.key});

  static const indicatorKey = ValueKey('editor.pageIndicator');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hidden = ref.watch(
      editorDeviceStateProvider.select((s) => s.toolbarHidden),
    );
    // The toolbar spans the window (EditorChrome).
    final narrow =
        MediaQuery.sizeOf(context).width < EditorToolbar.pageCountMinWidth;
    if (!hidden && !narrow) return const SizedBox.shrink();
    final index = ref.watch(editorCurrentPageIndexProvider);
    final count = ref.watch(editorPageCountProvider);
    if (count == 0) return const SizedBox.shrink();
    // (v2.14-ui) over the paper: a fixed dark-on-paper badge.
    final tokens = StyleTokens.of(context);
    return IgnorePointer(
      child: Align(
        alignment: Alignment.bottomRight,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: DecoratedBox(
            decoration: ShapeDecoration(
              color: tokens.paperBadge.withValues(alpha: 0.7),
              shape: const StadiumBorder(),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              child: Text(
                EditorStrings.pageIndicator(
                  index.clamp(0, count - 1) + 1,
                  count,
                ),
                key: indicatorKey,
                style: Theme.of(context).textTheme.labelMedium
                    ?.copyWith(color: tokens.onPaperBadge),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
