// lib/src/ui/overlays/end_of_document_hint.dart — (v2.14-ui, UI stage 1 —
// m5-7/04-editor 'UI 정리 1단계') the faint hint after the last page. It
// replaced the document-end '+ 페이지' button (04-editor 6.4.3, 6.11.4; with
// its '+ + 페이지' double plus): a page is added by pulling past the end
// (6.11.7), the page panel [+] or a page's ⋯.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../scope/editor_scope.dart';
import '../../viewport/page_layout.dart';
import '../../viewport/viewport_constants.dart';
import '../../viewport/viewport_controller.dart';
import '../editor_strings.dart';

/// '↓ 아래로 당겨서 새 페이지' ('→ 옆으로 당겨서 새 페이지' in the horizontal
/// layout) centred in the trailing padding after the last page
/// (ViewportConstants.trailingPadding), moving with the camera; only built
/// while that spot is on screen, so only at the last page. Never takes input
/// (IgnorePointer — not a button), faint (onSurfaceVariant at
/// [opacity]); it fades in when it comes into view and out while a pull runs
/// (PullToAddPageIndicator then says what happens) — no fade with reduce
/// motion (MediaQuery.disableAnimations). Hidden on a read-only note (no pull
/// there).
class EndOfDocumentHint extends ConsumerWidget {
  const EndOfDocumentHint({super.key});

  static const hintKey = ValueKey('editor.endOfDocumentHint');

  /// Distance (pt) from the last page's end to the hint's centre.
  static const double offsetPt = ViewportConstants.trailingPadding / 2;

  /// The text box (logical px) around the centre: one line in the vertical
  /// layout, a narrow wrapped block beside the last page in the horizontal.
  static const Size size = Size(280, 32);
  static const Size sizeHorizontal = Size(100, 72);

  /// How faint it is.
  static const double opacity = 0.6;

  static const Duration fade = Duration(milliseconds: 250);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(editorReadOnlyProvider)) return const SizedBox.shrink();
    final viewport = ref.watch(editorViewportProvider);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final duration = reduceMotion ? Duration.zero : fade;
    final style = Theme.of(context).textTheme.bodyMedium
        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
    return IgnorePointer(
      child: ListenableBuilder(
        listenable: Listenable.merge([viewport, viewport.pullPhase]),
        builder: (context, _) {
          final centre = centreOf(viewport);
          if (centre == null) return const SizedBox.shrink();
          final vertical = viewport.axis == LayoutAxis.vertical;
          final box = vertical ? size : sizeHorizontal;
          final rect = Rect.fromCenter(
            center: centre,
            width: box.width,
            height: box.height,
          );
          final screen = Offset.zero & viewport.viewportSize;
          if (!screen.overlaps(rect)) return const SizedBox.shrink();
          final pulling = viewport.pullPhase.value != PullToAddPhase.idle;
          return Stack(
            children: [
              Positioned.fromRect(
                rect: rect,
                child: TweenAnimationBuilder<double>(
                  // Fades in when it is first built (the end came into view).
                  tween: Tween(begin: 0, end: 1),
                  duration: duration,
                  builder: (context, t, child) =>
                      Opacity(opacity: t * opacity, child: child),
                  child: AnimatedOpacity(
                    opacity: pulling ? 0 : 1,
                    duration: duration,
                    child: Center(
                      child: Text(
                        vertical
                            ? EditorStrings.pullForNewPageVertical
                            : EditorStrings.pullForNewPageHorizontal,
                        key: hintKey,
                        textAlign: TextAlign.center,
                        maxLines: vertical ? 1 : 3,
                        overflow: TextOverflow.ellipsis,
                        style: style,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Screen centre of the hint, or null without a camera.
  static Offset? centreOf(ViewportController viewport) {
    final layout = viewport.layout;
    if (viewport.viewportSize.isEmpty || layout.length == 0) return null;
    if (viewport.pages.length != layout.length) return null;
    final last = layout.rectOf(layout.length - 1);
    final doc = viewport.axis == LayoutAxis.vertical
        ? Offset(last.center.dx, last.bottom + offsetPt)
        : Offset(last.right + offsetPt, last.center.dy);
    return viewport.camera.docToScreen(doc);
  }
}
