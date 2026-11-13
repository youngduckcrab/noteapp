// lib/src/ui/overlays/math_pen_layer.dart — (math pen, phase 1 —
// docs/plans/m5-7/research/math-pen-phase1.md 6.1, 8): the preview bubble
// of the open math pen group and the menu of a tapped formula.
//
// A sibling of the page Listener (page_viewport.dart): a tap on the bubble or
// the menu never reaches the input router, so it is never a stroke. The
// editor owns the frame — the place (8 px above the group's bounds grown by
// one line height H, so the zone where an exponent or a fraction still joins
// stays free; below when there is no room; kept 8 px inside the page area),
// the shadow and
// the tap target; recog builds the content (EditorMathPenSession
// .buildBubble — the live result rendered with INK's MathPreview, '인식
// 중…', the no-engine notice).
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../scope/editor_scope.dart';
import '../../text/text_edit_session.dart';
import '../../tools/math_pen/math_pen_controller.dart';
import '../../viewport/viewport_controller.dart';
import '../editor_strings.dart';

class MathPenLayer extends ConsumerWidget {
  const MathPenLayer({super.key});

  static const bubbleKey = ValueKey('editor.mathPen.bubble');
  static const formulaMenuKey = ValueKey('editor.mathPen.formulaMenu');
  static const fixKey = ValueKey('editor.mathPen.fix');
  static const reopenKey = ValueKey('editor.mathPen.reopen');

  /// The bubble's gap to the group (logical px) and its widest size.
  static const double gap = 8;
  static const double maxWidth = 320;
  static const double minHeight = 44;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(editorMathPenProvider);
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
              ?_menu(context, controller, viewport),
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
    MathPenController controller,
    ViewportController viewport,
  ) {
    final group = controller.group;
    final recognition = controller.recognition;
    final zone = controller.bubbleAnchorPt;
    if (group == null || recognition == null || zone == null) return null;
    final anchor = _screenRect(viewport, group.pageId, zone);
    if (anchor == null) return null;
    void convert() => unawaited(controller.convertOpenGroup());
    return Positioned.fill(
      child: CustomSingleChildLayout(
        delegate: _AboveDelegate(anchor),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: maxWidth,
            minHeight: minHeight,
          ),
          child: Material(
            key: bubbleKey,
            elevation: 2,
            borderRadius: BorderRadius.circular(12),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: controller.phase == MathPenPhase.converting
                  ? null
                  : convert,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                child: recognition.buildBubble(context, group, convert),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget? _menu(
    BuildContext context,
    MathPenController controller,
    ViewportController viewport,
  ) {
    final math = controller.menuFormula;
    if (math == null) return null;
    final b = math.frame.bounds;
    final anchor = _screenRect(
      viewport,
      math.pageId,
      Rect.fromLTRB(b.left, b.top, b.right, b.bottom),
    );
    if (anchor == null) return null;
    final buttonStyle = TextButton.styleFrom(minimumSize: const Size(64, 44));
    return Positioned.fill(
      child: CustomSingleChildLayout(
        delegate: _AboveDelegate(anchor),
        child: Material(
          key: formulaMenuKey,
          elevation: 3,
          borderRadius: BorderRadius.circular(12),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  key: fixKey,
                  style: buttonStyle,
                  onPressed: () => unawaited(controller.fixFormula()),
                  child: const Text(EditorStrings.mathFix),
                ),
                if (math.ink.isNotEmpty)
                  TextButton(
                    key: reopenKey,
                    style: buttonStyle,
                    onPressed: () => controller.reopenFormula(math),
                    child: const Text(EditorStrings.mathReopen),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Puts the child [MathPenLayer.gap] above [anchor] (left-aligned to it),
/// below it when there is no room above, inside the area with an 8 px
/// margin.
final class _AboveDelegate extends SingleChildLayoutDelegate {
  const _AboveDelegate(this.anchor);

  final Rect anchor;

  static const double _margin = 8;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(
        Size(
          math.max(0, constraints.maxWidth - 2 * _margin),
          math.max(0, constraints.maxHeight - 2 * _margin),
        ),
      );

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final above = anchor.top - MathPenLayer.gap - childSize.height;
    final y = above >= _margin ? above : anchor.bottom + MathPenLayer.gap;
    final maxX = math.max(_margin, size.width - childSize.width - _margin);
    final maxY = math.max(_margin, size.height - childSize.height - _margin);
    return Offset(
      anchor.left.clamp(_margin, maxX).toDouble(),
      y.clamp(_margin, maxY).toDouble(),
    );
  }

  @override
  bool shouldRelayout(_AboveDelegate oldDelegate) =>
      oldDelegate.anchor != anchor;
}
