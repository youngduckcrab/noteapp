// lib/src/ui/pen/pen_type_selector.dart — 04-editor 6.9.3 #1; (v2,
// m5-7/04-editor 6.14.1 — E2-14) all the types in rows. (v2.15-ui, UI stage 3
// — 22.1) The pen drawings instead of the icons, the groups 필기 / 질감 /
// 꾸미기 / 발표·공부 도구.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:ui_kit/ui_kit.dart';

import '../../tools/tool_controller.dart';
import '../editor_strings.dart';
import 'pen_art_view.dart';

/// Pen type groups of the picker (v2.11, C211-01). (v2.15-ui) basic = 필기;
/// [tools] = 발표·공부 도구 (the laser and the tape: not for writing).
enum PenTypeGroup { basic, texture, decor, tools }

/// The pen types as their drawing + name in a grid, by group (settings ›
/// 펜, where a type is picked to edit its values; the pen picker shows the
/// same groups as cards). [selected] is drawn on the accent's soft fill; a
/// tap calls [onSelected] (default: selectPenType — that type's last style,
/// pen active).
class PenTypeSelector extends ConsumerWidget {
  const PenTypeSelector({super.key, this.selected, this.onSelected});

  /// null = the current pen type.
  final core.PenTool? selected;
  final ValueChanged<core.PenTool>? onSelected;

  static ValueKey<String> keyOf(core.PenTool tool) =>
      ValueKey('editor.pen.type.${tool.name}');

  static ValueKey<String> groupKeyOf(PenTypeGroup group) =>
      ValueKey('editor.pen.group.${group.name}');

  /// Cells per row.
  static const int columns = 5;

  /// (v2.15-ui) The writing pens in the picker's order.
  static const List<core.PenTool> writingPens = [
    core.PenTool.ballpoint,
    core.PenTool.fountain,
    core.PenTool.pencil,
    core.PenTool.marker,
    core.PenTool.highlighter,
    core.PenTool.brush,
    core.PenTool.calligraphy,
    core.PenTool.dashed,
  ];

  /// (v2.15-ui) 발표·공부 도구.
  static const List<core.PenTool> toolPens = [
    core.PenTool.laser,
    core.PenTool.tape,
  ];

  /// (v2.15-ui) The card groups of the picker (발표·공부 도구 is a chip row
  /// under them).
  static const Map<PenTypeGroup, List<core.PenTool>> cardGroups = {
    PenTypeGroup.basic: writingPens,
    PenTypeGroup.texture: [
      core.PenTool.crayon,
      core.PenTool.chalk,
      core.PenTool.watercolor,
      core.PenTool.spray,
    ],
    PenTypeGroup.decor: [
      core.PenTool.neon,
      core.PenTool.jelly,
      core.PenTool.rainbow,
      core.PenTool.glitter,
    ],
  };

  /// The rows of each group ([columns] at most a row).
  static Map<PenTypeGroup, List<List<core.PenTool>>> get groups => {
    for (final MapEntry(key: g, value: tools) in {
      ...cardGroups,
      PenTypeGroup.tools: toolPens,
    }.entries)
      g: [
        for (var i = 0; i < tools.length; i += columns)
          tools.sublist(i, (i + columns).clamp(0, tools.length)),
      ],
  };

  /// Every row, group by group.
  static List<List<core.PenTool>> get rows => [
    for (final g in groups.values) ...g,
  ];

  /// Every type, row by row.
  static List<core.PenTool> get types => [for (final r in rows) ...r];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current =
        selected ?? ref.watch(editorToolProvider.select((s) => s.penType));
    final styles = ref.watch(editorToolProvider.select((s) => s.penStyles));
    final theme = Theme.of(context);
    final tokens = StyleTokens.of(context);
    Widget cell(core.PenTool tool) => Expanded(
      child: Semantics(
        button: true,
        selected: tool == current,
        label: EditorStrings.penTypeName(tool),
        excludeSemantics: true,
        child: Material(
          color: tool == current ? tokens.accentSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            key: keyOf(tool),
            borderRadius: BorderRadius.circular(10),
            onTap: () => onSelected != null
                ? onSelected!(tool)
                : ref.read(editorToolProvider.notifier).selectPenType(tool),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 60),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // The drawing's top (nib and the start of the body).
                  SizedBox(
                    width: 16,
                    height: 34,
                    child: ClipRect(
                      child: OverflowBox(
                        alignment: Alignment.topCenter,
                        maxHeight: 72,
                        child: PenArt.of(styles[tool]!, width: 14, height: 72),
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    EditorStrings.penTypeName(tool),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: tool == current
                          ? tokens.onAccentSoft
                          : tokens.textSecondary,
                    ),
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

    Widget header(PenTypeGroup group) => Padding(
      key: groupKeyOf(group),
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 2),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          EditorStrings.penGroupName(group.name),
          style: theme.textTheme.labelSmall?.copyWith(
            color: tokens.textSecondary,
          ),
        ),
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final MapEntry(key: group, value: rows) in groups.entries) ...[
          header(group),
          for (final row in rows)
            Row(
              children: [
                for (final t in row) cell(t),
                for (var i = row.length; i < columns; i++)
                  const Expanded(child: SizedBox()),
              ],
            ),
        ],
      ],
    );
  }
}
