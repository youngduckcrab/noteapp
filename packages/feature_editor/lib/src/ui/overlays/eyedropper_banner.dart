// lib/src/ui/overlays/eyedropper_banner.dart — 04-editor 6.6.8, 6.4.3.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../tools/tool_controller.dart';
import '../editor_strings.dart';

/// While the eyedropper waits for a tap: "획을 탭하면 그 색을 가져와요 [취소]"
/// at the top of the canvas (a sibling of the input Listener, so its button
/// never reaches the router; the rest of the canvas stays tappable).
class EyedropperBanner extends ConsumerWidget {
  const EyedropperBanner({super.key});

  static const bannerKey = ValueKey('editor.eyedropper.banner');
  static const cancelKey = ValueKey('editor.eyedropper.cancel');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(
      editorToolProvider.select((s) => s.eyedropperActive),
    );
    if (!active) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Material(
          key: bannerKey,
          color: scheme.inverseSurface,
          elevation: 2,
          shape: const StadiumBorder(),
          child: Padding(
            padding: const EdgeInsets.only(left: 16, right: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.colorize, size: 20, color: scheme.onInverseSurface),
                const SizedBox(width: 8),
                Text(
                  EditorStrings.eyedropperBanner,
                  style: text.bodyMedium?.copyWith(
                    color: scheme.onInverseSurface,
                  ),
                ),
                const SizedBox(width: 4),
                TextButton(
                  key: cancelKey,
                  style: TextButton.styleFrom(
                    foregroundColor: scheme.inversePrimary,
                    minimumSize: const Size(44, 44),
                  ),
                  onPressed: () => ref
                      .read(editorToolProvider.notifier)
                      .setEyedropper(false),
                  child: const Text(EditorStrings.cancel),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
