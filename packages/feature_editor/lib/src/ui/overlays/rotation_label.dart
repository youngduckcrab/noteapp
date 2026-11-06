// lib/src/ui/overlays/rotation_label.dart — m5-7/04-editor 6.6.6 (the angle tag
// while the rotate handle is dragged) — E2-06.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../scope/editor_scope.dart';
import '../../tools/selection.dart';
import '../editor_strings.dart';
import 'selection_frame_painter.dart' show selectionRepaint;

/// A small tag ('30°') beside the rotate handle while it is dragged: the
/// absolute angle for an object whose frame rotates, the relative one for
/// several elements and a polyline shape (InteractionHost.rotationLabel).
/// Display only (IgnorePointer); outside the frame layer, so the selection
/// frame goldens never show its text (9.2).
class RotationLabel extends ConsumerWidget {
  const RotationLabel({super.key});

  static const labelKey = ValueKey('editor.selection.rotationLabel');

  /// The tag's top-left corner from the rotate handle's centre (px).
  static const Offset offset = Offset(16, -28);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final host = ref.watch(editorInteractionHostProvider);
    final selection = ref.watch(editorSelectionProvider);
    final viewport = ref.watch(editorViewportProvider);
    final pages = ref.watch(editorMountedPagesProvider);
    final scheme = Theme.of(context).colorScheme;
    return IgnorePointer(
      child: ListenableBuilder(
        listenable: Listenable.merge([
          host.rotationLabel,
          selectionRepaint(viewport, pages, selection),
        ]),
        builder: (context, _) {
          final label = host.rotationLabel.value;
          final frame = label == null
              ? null
              : selectionFrameOnScreen(viewport, pages, selection);
          if (label == null || frame == null) return const SizedBox.shrink();
          final at = frame.quad.rotateHandlePosition + offset;
          return Stack(
            children: [
              Positioned(
                left: at.dx,
                top: at.dy,
                child: DecoratedBox(
                  key: labelKey,
                  decoration: BoxDecoration(
                    color: scheme.inverseSurface,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    child: Text(
                      EditorStrings.rotationLabel(label.degrees),
                      style: Theme.of(context).textTheme.labelSmall
                          ?.copyWith(color: scheme.onInverseSurface),
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
}
