// lib/src/ui/overlays/math_pen_layer.dart — (math pen, phase 1 —
// docs/plans/m5-7/research/math-pen-phase1.md 6.1, 8): the preview bubble
// of the open math pen group and the menu of a tapped formula.
//
// A sibling of the page Listener (page_viewport.dart): a tap on the bubble or
// the menu never reaches the input router, so it is never a stroke. The
// editor owns the frame — the place ([mathPenBubbleOffset]: 8 px above the
// group's bounds grown by bubbleClearanceFactor × H, so the zone where an
// exponent, a fraction or the next stroke starts stays free; below when
// there is no room; beside the group, then the viewport corner away from it
// when zoomed in so far that neither fits; kept 8 px inside the area;
// hidden while the group is off screen), the shadow and the tap target (a
// finger the input router would take for a palm — the writing hand right
// after a stroke — does not convert: InputRouter.rejectsAsPalm); recog
// builds the content (EditorMathPenSession.buildBubble — the live result
// rendered with INK's MathPreview, '인식 중…', the no-engine notice).
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../input/input_router.dart';
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
    final ink = _screenRect(viewport, group.pageId, group.boundsPt);
    if (anchor == null || ink == null) return null;
    void convert() => unawaited(controller.convertOpenGroup());
    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Off screen (scrolled away): no bubble — a tap there would
          // convert a group the user cannot see.
          if (!ink.inflate(1).overlaps(Offset.zero & constraints.biggest)) {
            return const SizedBox.shrink();
          }
          return CustomSingleChildLayout(
            delegate: PenBubbleLayout(anchor),
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
                child: PenBubbleTap(
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
          );
        },
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
        delegate: PenBubbleLayout(anchor),
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

/// The bubble's tap (the math pen's and the text pen's): a finger down the
/// input router would reject as a palm (InputRouter.rejectsAsPalm — P1–P3,
/// P5) does not convert; nor does it long-press.
class PenBubbleTap extends ConsumerStatefulWidget {
  const PenBubbleTap({
    super.key,
    required this.onTap,
    required this.child,
    this.onLongPress,
  });

  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Widget child;

  @override
  ConsumerState<PenBubbleTap> createState() => PenBubbleTapState();
}

class PenBubbleTapState extends ConsumerState<PenBubbleTap> {
  bool _palm = false;

  void _down(PointerDownEvent e) {
    InputRouter? router;
    try {
      router = ref.read(editorInputRouterProvider);
    } on Object {
      router = null; // no viewport (a test of the layer alone)
    }
    _palm = router?.rejectsAsPalm(e) ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final onTap = widget.onTap;
    final onLongPress = widget.onLongPress;
    return Listener(
      onPointerDown: _down,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap == null
            ? null
            : () {
                if (_palm) return; // the writing hand
                onTap();
              },
        onLongPress: onLongPress == null
            ? null
            : () {
                if (_palm) return;
                onLongPress();
              },
        child: widget.child,
      ),
    );
  }
}

/// Where a child of [child] size goes in an [area] for a group whose keep-
/// away zone is [anchor] (all logical px, the area's coordinates):
/// [MathPenLayer.gap] above it, left-aligned; below when there is no room
/// above; right of it, then left of it (top-aligned) when neither fits —
/// zoomed in so far that the zone fills the height; else the corner of the
/// area farthest from the zone. Always [margin] inside the area.
@visibleForTesting
Offset mathPenBubbleOffset(
  Size area,
  Size child,
  Rect anchor, {
  double margin = 8,
}) {
  const gap = MathPenLayer.gap;
  final maxX = math.max(margin, area.width - child.width - margin);
  final maxY = math.max(margin, area.height - child.height - margin);
  double clampX(double x) => x.clamp(margin, maxX).toDouble();
  double clampY(double y) => y.clamp(margin, maxY).toDouble();
  final above = anchor.top - gap - child.height;
  if (above >= margin) return Offset(clampX(anchor.left), above);
  final below = anchor.bottom + gap;
  if (below + child.height <= area.height - margin) {
    return Offset(clampX(anchor.left), below);
  }
  final right = anchor.right + gap;
  if (right + child.width <= area.width - margin) {
    return Offset(right, clampY(anchor.top));
  }
  final left = anchor.left - gap - child.width;
  if (left >= margin) return Offset(left, clampY(anchor.top));
  final corners = [
    Offset(margin, margin),
    Offset(maxX, margin),
    Offset(margin, maxY),
    Offset(maxX, maxY),
  ];
  Offset best = corners.first;
  var bestScore = double.negativeInfinity;
  for (final c in corners) {
    final rect = c & child;
    final overlap = rect.intersect(anchor);
    final covered = overlap.width > 0 && overlap.height > 0
        ? overlap.width * overlap.height
        : 0.0;
    // Least overlap first, then the farthest from the zone's centre.
    final score = -covered * 1e6 + (rect.center - anchor.center).distance;
    if (score > bestScore) (best, bestScore) = (c, score);
  }
  return best;
}

/// Lays the bubble (or the formula menu; the text pen's bubble too) out by
/// [mathPenBubbleOffset].
final class PenBubbleLayout extends SingleChildLayoutDelegate {
  const PenBubbleLayout(this.anchor);

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
  Offset getPositionForChild(Size size, Size childSize) =>
      mathPenBubbleOffset(size, childSize, anchor, margin: _margin);

  @override
  bool shouldRelayout(PenBubbleLayout oldDelegate) =>
      oldDelegate.anchor != anchor;
}
