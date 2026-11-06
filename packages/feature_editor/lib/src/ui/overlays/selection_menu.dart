// lib/src/ui/overlays/selection_menu.dart — 04-editor 6.6.5 (selection menu).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../scope/editor_scope.dart';
import '../../tools/selection.dart';
import '../editor_strings.dart';
import 'selection_frame_painter.dart' show selectionRepaint;

/// A rounded bar 8 px above the selection frame (below it when there is no
/// room): [복사] [삭제] [선택 해제]. Hidden while the selection is dragged.
/// A sibling of the page area's Listener (6.4.3), so its taps never reach the
/// input router. 삭제 is disabled on a read-only note.
class SelectionMenu extends ConsumerWidget {
  const SelectionMenu({super.key});

  static const copyKey = ValueKey('editor.selectionMenu.copy');
  static const deleteKey = ValueKey('editor.selectionMenu.delete');
  static const clearKey = ValueKey('editor.selectionMenu.clear');

  /// Distance between the frame and the bar (px).
  static const double gap = 8;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selection = ref.watch(editorSelectionProvider);
    if (selection == null || selection.isDragging) {
      return const SizedBox.shrink();
    }
    final viewport = ref.watch(editorViewportProvider);
    final pages = ref.watch(editorMountedPagesProvider);
    final readOnly = ref.watch(editorReadOnlyProvider);
    final commands = ref.watch(editorCommandsProvider);
    final scheme = Theme.of(context).colorScheme;
    final bar = Material(
      color: scheme.surfaceContainerHigh,
      elevation: 3,
      shape: const StadiumBorder(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              key: copyKey,
              onPressed: commands.copySelection,
              child: const Text(EditorStrings.selectionCopy),
            ),
            TextButton(
              key: deleteKey,
              onPressed: readOnly ? null : commands.deleteSelection,
              child: const Text(EditorStrings.selectionDelete),
            ),
            TextButton(
              key: clearKey,
              onPressed: commands.clearSelection,
              child: const Text(EditorStrings.selectionClear),
            ),
          ],
        ),
      ),
    );
    return ListenableBuilder(
      listenable: selectionRepaint(viewport, pages, selection),
      builder: (context, child) {
        // (v2) clear of the whole frame, the rotate handle included (6.6.4).
        final rect = selectionFrameOnScreen(viewport, pages, selection)?.extent;
        if (rect == null) return const SizedBox.shrink();
        return CustomSingleChildLayout(
          delegate: _AboveOrBelow(rect),
          child: child,
        );
      },
      child: bar,
    );
  }
}

/// Centres the bar over [frame], [SelectionMenu.gap] above it, or below it
/// when it does not fit above; kept inside the page area.
class _AboveOrBelow extends SingleChildLayoutDelegate {
  const _AboveOrBelow(this.frame);

  final Rect frame;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    var top = frame.top - SelectionMenu.gap - childSize.height;
    if (top < 0) top = frame.bottom + SelectionMenu.gap;
    final maxTop = size.height - childSize.height;
    final maxLeft = size.width - childSize.width;
    final left = frame.center.dx - childSize.width / 2;
    return Offset(
      maxLeft <= 0 ? 0 : left.clamp(0.0, maxLeft).toDouble(),
      maxTop <= 0 ? 0 : top.clamp(0.0, maxTop).toDouble(),
    );
  }

  @override
  bool shouldRelayout(_AboveOrBelow oldDelegate) => oldDelegate.frame != frame;
}
