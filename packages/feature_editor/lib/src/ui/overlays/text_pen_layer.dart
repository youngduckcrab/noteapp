// lib/src/ui/overlays/text_pen_layer.dart — (text pen, phase 1 —
// m5-7/04-editor 6.21) the bubble of the open text pen group.
//
// The math pen's frame (math_pen_layer.dart: PenBubbleLayout — above the
// group's keep-away zone, below / beside / a corner when there is no room —
// and PenBubbleTap — a palm does not convert), around recog's content
// (EditorTextPenSession.buildBubble — the recognized text, '인식 중…', the
// model card, [다시]). A tap converts the group into a text box (one undo
// step); a long press, or the content's '고치기', opens the conversion sheet.
// Hidden while the group is off screen and while a text box is edited.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../scope/editor_scope.dart';
import '../../text/text_edit_session.dart';
import '../../tools/text_pen/text_pen_controller.dart';
import '../../viewport/viewport_controller.dart';
import 'math_pen_layer.dart';

class TextPenLayer extends ConsumerWidget {
  const TextPenLayer({super.key});

  static const bubbleKey = ValueKey('editor.textPen.bubble');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(editorTextPenProvider);
    if (!controller.enabled) return const SizedBox.shrink();
    final viewport = ref.watch(editorViewportProvider);
    final editingText = ref.watch(
      editorTextEditProvider.select((s) => s != null),
    );
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final recognition = controller.recognition;
        return ListenableBuilder(
          listenable: Listenable.merge([viewport, ?recognition?.changes]),
          builder: (context, _) => Stack(
            children: [
              if (!editingText) ?_bubble(context, controller, viewport),
            ],
          ),
        );
      },
    );
  }

  Rect? _screenRect(ViewportController viewport, String pageId, Rect pt) {
    final index = viewport.pages.indexWhere((p) => p.id == pageId);
    if (index < 0) return null;
    return Rect.fromPoints(
      viewport.pageToScreen(index, pt.topLeft),
      viewport.pageToScreen(index, pt.bottomRight),
    );
  }

  Widget? _bubble(
    BuildContext context,
    TextPenController controller,
    ViewportController viewport,
  ) {
    final group = controller.group;
    final recognition = controller.recognition;
    final zone = controller.bubbleAnchorPt;
    if (group == null || recognition == null || zone == null) return null;
    final anchor = _screenRect(viewport, group.pageId, zone);
    final ink = _screenRect(viewport, group.pageId, group.boundsPt);
    if (anchor == null || ink == null) return null;
    void convert() => unawaited(controller.convertOpenGroup());
    void fix() => unawaited(controller.fixOpenGroup());
    final busy = controller.phase == TextPenPhase.converting;
    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Off screen (scrolled away): no bubble.
          if (!ink.inflate(1).overlaps(Offset.zero & constraints.biggest)) {
            return const SizedBox.shrink();
          }
          return CustomSingleChildLayout(
            delegate: PenBubbleLayout(anchor),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: MathPenLayer.maxWidth,
                minHeight: MathPenLayer.minHeight,
              ),
              child: Material(
                key: bubbleKey,
                elevation: 2,
                borderRadius: BorderRadius.circular(12),
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: PenBubbleTap(
                  onTap: busy ? null : convert,
                  onLongPress: busy ? null : fix,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    child: recognition.buildBubble(
                      context,
                      group,
                      convert,
                      fix,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
