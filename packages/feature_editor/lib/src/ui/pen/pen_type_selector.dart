// lib/src/ui/pen/pen_type_selector.dart — 04-editor 6.9.3 #1; (v2,
// m5-7/04-editor 6.14.1 — E2-14) all ten types in two rows.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

import '../../tools/tool_controller.dart';
import '../editor_strings.dart';
import '../toolbar/editor_toolbar.dart' show penTypeIcon;

/// The pen types as icon + name in two rows (v2, 6.14.1): the P0 row
/// (볼펜 · 만년필 · 형광펜 · 연필 · 마커) and the extra row (붓펜 · 캘리그래피 ·
/// 점선 · 레이저 · 암기 테이프). [selected] is drawn on primaryContainer; a
/// tap calls [onSelected] (default: selectPenType — that type's last style,
/// pen active).
class PenTypeSelector extends ConsumerWidget {
  const PenTypeSelector({super.key, this.selected, this.onSelected});

  /// null = the current pen type.
  final core.PenTool? selected;
  final ValueChanged<core.PenTool>? onSelected;

  static ValueKey<String> keyOf(core.PenTool tool) =>
      ValueKey('editor.pen.type.${tool.name}');

  /// The two rows (6.14.1), in core.PenTool order.
  static List<List<core.PenTool>> get rows => [
    [
      for (final t in core.PenTool.values)
        if (t.isP0) t,
    ],
    [
      for (final t in core.PenTool.values)
        if (!t.isP0) t,
    ],
  ];

  /// Every type, row by row.
  static List<core.PenTool> get types => [for (final r in rows) ...r];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current =
        selected ?? ref.watch(editorToolProvider.select((s) => s.penType));
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    Widget cell(core.PenTool tool) => Expanded(
      child: Semantics(
        button: true,
        selected: tool == current,
        label: EditorStrings.penTypeName(tool),
        excludeSemantics: true,
        child: Material(
          color: tool == current ? scheme.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            key: keyOf(tool),
            borderRadius: BorderRadius.circular(10),
            onTap: () => onSelected != null
                ? onSelected!(tool)
                : ref.read(editorToolProvider.notifier).selectPenType(tool),
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
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final row in rows) Row(children: [for (final t in row) cell(t)]),
      ],
    );
  }
}
