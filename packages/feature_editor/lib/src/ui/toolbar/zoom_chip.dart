// lib/src/ui/toolbar/zoom_chip.dart — 04-editor 6.9.1 ([100%]).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../scope/editor_scope.dart';
import '../editor_strings.dart';

/// The current zoom (camera.scale / fitScale, rounded %); tap → fit width.
/// Listens to the viewport directly (no provider state on the camera path —
/// 6.13.1 #1). (v2.14-ui, UI stage 1) Nothing — no space either — while the
/// label would be '100%' (fit width): it shows only when it is useful (tap →
/// back to fit).
class ZoomChip extends ConsumerWidget {
  const ZoomChip({super.key});

  static const chipKey = ValueKey('editor.toolbar.zoom');

  /// '100%' for zoom 1.
  static String labelFor(double zoom) => '${(zoom * 100).round()}%';

  /// (v2.14-ui) The chip is hidden at this zoom (it reads '100%').
  static bool isFit(double zoom) => (zoom * 100).round() == 100;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewport = ref.watch(editorViewportProvider);
    final commands = ref.watch(editorCommandsProvider);
    return ListenableBuilder(
      listenable: viewport,
      builder: (context, _) {
        final label = labelFor(viewport.zoom);
        if (isFit(viewport.zoom)) return const SizedBox.shrink();
        return Semantics(
          hint: EditorStrings.zoomToFit,
          child: TextButton(
            key: chipKey,
            style: TextButton.styleFrom(minimumSize: const Size(64, 48)),
            onPressed: commands.zoomToFit,
            child: Text(label),
          ),
        );
      },
    );
  }
}
