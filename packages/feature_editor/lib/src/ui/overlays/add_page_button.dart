// lib/src/ui/overlays/add_page_button.dart — 04-editor 6.4.3, 6.11.4
// (문서 끝 '+ 페이지').
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../scope/editor_scope.dart';
import '../../viewport/page_layout.dart';
import '../../viewport/viewport_constants.dart';
import '../../viewport/viewport_controller.dart';
import '../editor_strings.dart';

/// '+ 페이지' after the last page (in the trailing padding the layout keeps
/// for it — ViewportConstants.trailingPadding), moving with the camera; only
/// built while that spot is on screen. Tap → EditorCommands.addPageAtEndLikeLast
/// (same size and background as the last page; a PDF / image page gives a
/// blank page of its paper colour). Hidden on a read-only note. A sibling of
/// the input Listener, so its tap never reaches the router.
class AddPageButton extends ConsumerWidget {
  const AddPageButton({super.key});

  static const buttonKey = ValueKey('editor.addPageButton');

  /// Distance (pt) from the last page's end to the button's centre.
  static const double offsetPt = ViewportConstants.trailingPadding / 2;

  static const Size size = Size(120, 44);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(editorReadOnlyProvider)) return const SizedBox.shrink();
    final viewport = ref.watch(editorViewportProvider);
    final commands = ref.watch(editorCommandsProvider);
    return ListenableBuilder(
      listenable: viewport,
      builder: (context, _) {
        final centre = _centreOf(viewport);
        if (centre == null) return const SizedBox.shrink();
        final rect = Rect.fromCenter(
          center: centre,
          width: size.width,
          height: size.height,
        );
        final screen = Offset.zero & viewport.viewportSize;
        if (!screen.overlaps(rect)) return const SizedBox.shrink();
        return Stack(
          children: [
            Positioned.fromRect(
              rect: rect,
              child: FilledButton.tonalIcon(
                key: buttonKey,
                onPressed: () => unawaited(commands.addPageAtEndLikeLast()),
                icon: const Icon(Icons.add),
                label: const Text(EditorStrings.addPageAtEnd),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Screen centre of the button, or null without a camera.
  static Offset? _centreOf(ViewportController viewport) {
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
