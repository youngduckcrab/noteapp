// lib/src/ui/overlays/page_indicator.dart — 04-editor 6.4.3 ("3 / 12").
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui_kit/ui_kit.dart';

import '../../scope/editor_scope.dart';
import '../editor_strings.dart';

/// "current / count" at the bottom right of the page area; never takes
/// input (IgnorePointer).
class PageIndicator extends ConsumerWidget {
  const PageIndicator({super.key});

  static const indicatorKey = ValueKey('editor.pageIndicator');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(editorCurrentPageIndexProvider);
    final viewport = ref.watch(editorViewportProvider);
    return ListenableBuilder(
      listenable: viewport,
      builder: (context, _) {
        final count = viewport.pages.length;
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
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
      },
    );
  }
}
