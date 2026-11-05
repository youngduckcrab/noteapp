// lib/src/ui/pen/pen_type_selector.dart — 04-editor 6.9.3 #1.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

import '../../tools/tool_controller.dart';
import '../editor_strings.dart';
import '../toolbar/editor_toolbar.dart' show penTypeIcon;

/// The P0 pen types (core.PenTool.isP0) as icon + name. [selected] is drawn
/// on primaryContainer; a tap calls [onSelected] (default: selectPenType —
/// that type's last style, pen active).
class PenTypeSelector extends ConsumerWidget {
  const PenTypeSelector({super.key, this.selected, this.onSelected});

  /// null = the current pen type.
  final core.PenTool? selected;
  final ValueChanged<core.PenTool>? onSelected;

  static ValueKey<String> keyOf(core.PenTool tool) =>
      ValueKey('editor.pen.type.${tool.name}');

  static List<core.PenTool> get types =>
      core.PenTool.values.where((t) => t.isP0).toList(growable: false);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current =
        selected ?? ref.watch(editorToolProvider.select((s) => s.penType));
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      children: [
        for (final tool in types)
          Expanded(
            child: Semantics(
              button: true,
              selected: tool == current,
              label: EditorStrings.penTypeName(tool),
              excludeSemantics: true,
              child: Material(
                color: tool == current
                    ? scheme.primaryContainer
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  key: keyOf(tool),
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => onSelected != null
                      ? onSelected!(tool)
                      : ref
                            .read(editorToolProvider.notifier)
                            .selectPenType(tool),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 56),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          penTypeIcon(tool),
                          size: 22,
                          color: tool == current
                              ? scheme.onPrimaryContainer
                              : scheme.onSurfaceVariant,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          EditorStrings.penTypeName(tool),
                          style: theme.textTheme.labelSmall,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
