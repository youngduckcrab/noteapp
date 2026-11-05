// lib/src/ui/overlays/context_menu.dart — 04-editor 6.6.2 (long press / secondary click).
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../scope/editor_scope.dart';
import '../../tools/interaction_host.dart';
import '../../tools/stroke_clipboard.dart';
import '../../tools/tool_state.dart';
import '../editor_strings.dart';

/// The context menu opened by a long press or a secondary click away from the
/// selection (InteractionHost.contextMenu): [붙여넣기] at that point when the
/// app clipboard has strokes, [올가미 도구]. Placed at the press point, kept
/// inside the page area. A sibling of the page area's Listener (6.4.3); a tap
/// elsewhere on the canvas closes it (tapGesture(1)).
class EditorContextMenu extends ConsumerWidget {
  const EditorContextMenu({super.key});

  static const pasteKey = ValueKey('editor.contextMenu.paste');
  static const lassoKey = ValueKey('editor.contextMenu.lasso');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final host = ref.watch(editorInteractionHostProvider);
    return ValueListenableBuilder<ContextMenuRequest?>(
      valueListenable: host.contextMenu,
      builder: (context, request, _) {
        if (request == null) return const SizedBox.shrink();
        return CustomSingleChildLayout(
          delegate: _AtPoint(request.position),
          child: _MenuItems(host: host, request: request),
        );
      },
    );
  }
}

class _MenuItems extends ConsumerWidget {
  const _MenuItems({required this.host, required this.request});

  final InteractionHost host;
  final ContextMenuRequest request;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final commands = ref.watch(editorCommandsProvider);
    final hasClipboard = ref.watch(editorClipboardProvider) != null;
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHigh,
      elevation: 3,
      borderRadius: BorderRadius.circular(12),
      child: IntrinsicWidth(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (hasClipboard)
              _Item(
                key: EditorContextMenu.pasteKey,
                label: EditorStrings.paste,
                onTap: () {
                  host.closeContextMenu();
                  unawaited(commands.paste(screenPoint: request.position));
                },
              ),
            _Item(
              key: EditorContextMenu.lassoKey,
              label: EditorStrings.lassoTool,
              onTap: () {
                host.closeContextMenu();
                commands.selectTool(EditorTool.lasso);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _Item extends StatelessWidget {
  const _Item({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48, minWidth: 140),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        widthFactor: 1,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(label),
        ),
      ),
    ),
  );
}

/// Top-left at [point], shifted to stay inside the page area.
class _AtPoint extends SingleChildLayoutDelegate {
  const _AtPoint(this.point);

  final Offset point;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final maxLeft = size.width - childSize.width;
    final maxTop = size.height - childSize.height;
    return Offset(
      maxLeft <= 0 ? 0 : point.dx.clamp(0.0, maxLeft).toDouble(),
      maxTop <= 0 ? 0 : point.dy.clamp(0.0, maxTop).toDouble(),
    );
  }

  @override
  bool shouldRelayout(_AtPoint oldDelegate) => oldDelegate.point != point;
}
