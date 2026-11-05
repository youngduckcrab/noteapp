// lib/src/ui/color/user_palette_grid.dart — 04-editor 6.9.3 #6 (내 팔레트).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../state/color_palette.dart';
import '../../tools/tool_controller.dart';
import '../editor_strings.dart';
import 'color_swatch.dart';

/// The user's palette in 44 px cells (7 to a 308 px row). With [editable] the
/// last cell is [+] (adds the current colour; disabled at
/// ColorPaletteState.maxPalette) and a long press on a colour offers '삭제'.
/// [limit] shows only the first colours (the quick popup shows 16).
class UserPaletteGrid extends ConsumerWidget {
  const UserPaletteGrid({super.key, this.limit, this.editable = true});

  final int? limit;
  final bool editable;

  static ValueKey<String> swatchKey(int index) =>
      ValueKey('editor.color.palette.$index');
  static const addKey = ValueKey('editor.color.palette.add');
  static const deleteKey = ValueKey('editor.color.palette.delete');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = ref.watch(
      editorColorPaletteProvider.select((s) => s.palette),
    );
    final current = ref.watch(
      editorToolProvider.select((s) => s.currentPen.colorArgb),
    );
    final shown = limit == null || palette.length <= limit!
        ? palette
        : palette.sublist(0, limit);
    final full = palette.length >= ColorPaletteState.maxPalette;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(EditorStrings.userPalette, style: theme.textTheme.labelLarge),
        Wrap(
          children: [
            for (var i = 0; i < shown.length; i++)
              Builder(
                builder: (cellContext) => ColorSwatchButton(
                  key: swatchKey(i),
                  argb: shown[i],
                  diameter: 30,
                  selected: shown[i] == current,
                  onTap: () =>
                      ref.read(editorToolProvider.notifier).setColor(shown[i]),
                  onLongPress: editable
                      ? () => _offerDelete(cellContext, ref, i)
                      : null,
                ),
              ),
            if (editable)
              Semantics(
                // No tooltip (6.9.1): a semantics label only.
                label: EditorStrings.addToPalette,
                child: IconButton(
                  key: addKey,
                  icon: const Icon(Icons.add),
                  onPressed: full
                      ? null
                      : () => ref
                            .read(editorColorPaletteProvider.notifier)
                            .addToPalette(
                              ref.read(editorToolProvider).currentPen.colorArgb,
                            ),
                  constraints: const BoxConstraints.tightFor(
                    width: ColorSwatchButton.cellSize,
                    height: ColorSwatchButton.cellSize,
                  ),
                  padding: EdgeInsets.zero,
                  iconSize: 22,
                ),
              ),
          ],
        ),
      ],
    );
  }

  /// Long press → a one-item menu '삭제' at the colour.
  Future<void> _offerDelete(
    BuildContext context,
    WidgetRef ref,
    int index,
  ) async {
    final box = context.findRenderObject() as RenderBox?;
    final overlay =
        Navigator.of(context).overlay?.context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;
    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
    final position = RelativeRect.fromRect(
      topLeft & box.size,
      Offset.zero & overlay.size,
    );
    final notifier = ref.read(editorColorPaletteProvider.notifier);
    final picked = await showMenu<bool>(
      context: context,
      position: position,
      items: const [
        PopupMenuItem<bool>(
          key: deleteKey,
          value: true,
          child: Text(EditorStrings.paletteDelete),
        ),
      ],
    );
    if (picked ?? false) notifier.removeFromPalette(index);
  }
}
