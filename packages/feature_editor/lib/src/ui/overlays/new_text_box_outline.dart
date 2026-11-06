// lib/src/ui/overlays/new_text_box_outline.dart — m5-7/04-editor 6.11.1
// (E2-10): the empty box outline while the text tool drags a new box. Drawn
// by EDITOR itself — not an object, so not an INK preview (no INK change —
// 00-review 2.3 INK X-5).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../scope/editor_scope.dart';

/// A thin primary-coloured rectangle on the dragged box
/// (InteractionHost.newTextBoxOutline — page pt → screen with the camera).
/// Display only (IgnorePointer).
class NewTextBoxOutline extends ConsumerWidget {
  const NewTextBoxOutline({super.key});

  static const outlineKey = ValueKey('editor.newTextBoxOutline');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final host = ref.watch(editorInteractionHostProvider);
    final viewport = ref.watch(editorViewportProvider);
    final color = Theme.of(context).colorScheme.primary;
    return IgnorePointer(
      child: ListenableBuilder(
        listenable: Listenable.merge([host.newTextBoxOutline, viewport]),
        builder: (context, _) {
          final outline = host.newTextBoxOutline.value;
          if (outline == null ||
              outline.pageIndex >= viewport.pages.length ||
              viewport.pages[outline.pageIndex].id != outline.pageId) {
            return const SizedBox.shrink();
          }
          final r = outline.rectPt;
          final topLeft = viewport.pageToScreen(outline.pageIndex, r.topLeft);
          final bottomRight = viewport.pageToScreen(
            outline.pageIndex,
            r.bottomRight,
          );
          final rect = Rect.fromPoints(topLeft, bottomRight);
          return Stack(
            children: [
              Positioned.fromRect(
                rect: rect,
                child: DecoratedBox(
                  key: outlineKey,
                  decoration: BoxDecoration(
                    border: Border.all(color: color, width: 1.5),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
