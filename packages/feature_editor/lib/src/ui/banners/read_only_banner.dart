// lib/src/ui/banners/read_only_banner.dart — 04-editor 6.17.2 (N-4).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../scope/editor_scope.dart';
import '../editor_strings.dart';

/// Above the toolbar while the note is read only: a trashed note, or one made
/// by a newer app (note.requiresNewerApp). Height 0 otherwise.
class ReadOnlyBanner extends ConsumerWidget {
  const ReadOnlyBanner({super.key});

  static const bannerKey = ValueKey('editor.banner.readOnly');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(editorReadOnlyProvider)) return const SizedBox.shrink();
    final note = ref.watch(editorSessionValueProvider).note;
    final scheme = Theme.of(context).colorScheme;
    return BannerLine(
      key: bannerKey,
      icon: Icons.lock,
      text: note.requiresNewerApp
          ? EditorStrings.readOnlyNewerApp
          : EditorStrings.readOnlyTrashed,
      background: scheme.secondaryContainer,
      foreground: scheme.onSecondaryContainer,
    );
  }
}

/// Shared look of the editor's banners (read only, storage warning): one
/// line with an icon, no close button (6.17.2, 6.17.3).
class BannerLine extends StatelessWidget {
  const BannerLine({
    super.key,
    required this.icon,
    required this.text,
    required this.background,
    required this.foreground,
  });

  final IconData icon;
  final String text;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) => Material(
    color: background,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: foreground),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: foreground),
            ),
          ),
        ],
      ),
    ),
  );
}
