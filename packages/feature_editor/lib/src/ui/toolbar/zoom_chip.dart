// lib/src/ui/toolbar/zoom_chip.dart — 04-editor 6.9.1 ([100%]).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../scope/editor_scope.dart';
import '../editor_strings.dart';

/// The current zoom (camera.scale / fitScale, rounded %); tap → fit width.
/// Listens to the viewport directly (no provider state on the camera path —
/// 6.13.1 #1).
class ZoomChip extends ConsumerWidget {
  const ZoomChip({super.key});

  static const chipKey = ValueKey('editor.toolbar.zoom');

  /// '100%' for zoom 1.
  static String labelFor(double zoom) => '${(zoom * 100).round()}%';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewport = ref.watch(editorViewportProvider);
    final commands = ref.watch(editorCommandsProvider);
    return ListenableBuilder(
      listenable: viewport,
      builder: (context, _) => Semantics(
        hint: EditorStrings.zoomToFit,
        child: TextButton(
          key: chipKey,
          style: TextButton.styleFrom(minimumSize: const Size(64, 48)),
          onPressed: commands.zoomToFit,
          child: Text(labelFor(viewport.zoom)),
        ),
      ),
    );
  }
}
