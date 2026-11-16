// lib/src/ui/toolbar/overflow_tools_menu.dart — m5-7/04-editor 6.13.1
// (E2-13): the folded toolbar's [⋯도구] (key `editor.toolbar.overflowTools`,
// appendix C). Below EditorToolbar.foldWidth the [도형] [텍스트] [+] [🎤]
// buttons fold into this one menu:
//
//   도형 · 텍스트   — like their toolbar buttons: an inactive tool → select it,
//                    the active one → its tool popup (at this button);
//   이미지 ▸ · insert items — the [+] rows (insertMenuRows — started inside
//                    the press, then the menu closes; disabled on a
//                    read-only note);
//   녹음            — opens / closes the bottom panel (EditorExtensions.
//                    recordingPanel only).
//
// The button shows the active tool's icon (shape / text) on primaryContainer
// while one of the folded tools is active, and the mic's dot (red: this note
// records; grey: another note) while folded.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:ui_kit/ui_kit.dart';

import '../../commands/extension_runner.dart';
import '../../di/editor_extensions.dart';
import '../../di/editor_image_importer.dart';
import '../../objects/image_flows.dart';
import '../../scope/editor_scope.dart';
import '../../state/panel.dart';
import '../../state/popup.dart';
import '../../tools/tool_controller.dart';
import '../../tools/tool_state.dart';
import '../editor_strings.dart';
import 'insert_menu.dart';
import 'mic_button.dart';
import 'tool_button.dart';

class OverflowToolsMenu extends ConsumerStatefulWidget {
  const OverflowToolsMenu({
    super.key = buttonKey,
    required this.hasInsert,
    required this.hasPanel,
  });

  /// Appendix C.
  static const buttonKey = ValueKey('editor.toolbar.overflowTools');

  /// Rows (the same keys as the toolbar buttons they replace — only one of
  /// the two is built at a time).
  static const shapeKey = ValueKey('editor.toolbar.shape');
  static const textKey = ValueKey('editor.toolbar.text');

  /// (math pen, phase 1) the 수식 펜 row (EditorExtensions.mathPen only).
  static const mathKey = ValueKey('editor.toolbar.math');

  /// (text pen, phase 1) the 텍스트 펜 row (EditorExtensions.textPen only).
  static const textPenKey = ValueKey('editor.toolbar.textPen');

  /// Whether the [+] rows are offered (InsertMenu.hasItems).
  final bool hasInsert;

  /// Whether the 녹음 row is offered (EditorExtensions.recordingPanel).
  final bool hasPanel;

  @override
  ConsumerState<OverflowToolsMenu> createState() => OverflowToolsMenuState();
}

class OverflowToolsMenuState extends ConsumerState<OverflowToolsMenu> {
  final MenuController _menu = MenuController();

  /// Whether the menu is open (tests).
  @visibleForTesting
  bool get isOpen => _menu.isOpen;

  void _toggle() => _menu.isOpen ? _menu.close() : _menu.open();

  void _close() {
    if (_menu.isOpen) _menu.close();
  }

  /// Bottom-left of this button (global) — where a tool popup opens.
  Offset? _below() {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    return box.localToGlobal(box.size.bottomLeft(Offset.zero));
  }

  void _tool(EditorTool tool, EditorPopup Function(Offset? at) popup) {
    final active = ref.read(editorToolProvider).activeTool;
    if (active == tool) {
      ref.read(editorPopupProvider.notifier).open(popup(_below()));
    } else {
      ref.read(editorCommandsProvider).selectTool(tool);
    }
    _close();
  }

  @override
  Widget build(BuildContext context) {
    final readOnly = ref.watch(editorReadOnlyProvider);
    final active = ref.watch(editorToolProvider.select((s) => s.activeTool));
    final noteId = ref.watch(editorNoteIdProvider);
    final panelOpen = ref.watch(editorPanelProvider);
    final indicator = widget.hasPanel
        ? micIndicatorOf(ref.watch(editorRecorderStatusProvider).value, noteId)
        : MicIndicator.none;
    final scheme = Theme.of(context).colorScheme;
    final runner = ref.watch(editorExtensionRunnerProvider);
    final sources = widget.hasInsert
        ? ImageFlows.sourcesOf(ref.watch(editorImageImporterProvider))
        : const <core.ImageImportSource>[];
    final items = widget.hasInsert
        ? runner.withoutDuplicates(
            ref.watch(
              editorExtensionsProvider.select((e) => e.insertMenuItems),
            ),
            (item) => item.id,
          )
        : const <EditorInsertMenuItem>[];
    final hasMathPen = ref.watch(
      editorExtensionsProvider.select((e) => e.mathPen != null),
    );
    final mathActive = hasMathPen && active == EditorTool.math;
    final hasTextPen = ref.watch(
      editorExtensionsProvider.select((e) => e.textPen != null),
    );
    final textPenActive = hasTextPen && active == EditorTool.textPen;
    final folded =
        active == EditorTool.shape ||
        active == EditorTool.text ||
        mathActive ||
        textPenActive;
    return ValueListenableBuilder<Set<String>>(
      valueListenable: runner.runningIds,
      builder: (context, running, _) => MenuAnchor(
        controller: _menu,
        menuChildren: [
          InsertMenuRow(
            key: OverflowToolsMenu.shapeKey,
            icon: AppIconKind.shape.material,
            label: EditorStrings.shapeTool,
            selected: active == EditorTool.shape,
            onPressed: readOnly
                ? null
                : () => _tool(
                    EditorTool.shape,
                    (at) => ShapeToolPopup(globalPosition: at),
                  ),
          ),
          InsertMenuRow(
            key: OverflowToolsMenu.textKey,
            icon: AppIconKind.text.material,
            label: EditorStrings.textTool,
            selected: active == EditorTool.text,
            onPressed: readOnly
                ? null
                : () => _tool(
                    EditorTool.text,
                    (at) => TextToolPopup(globalPosition: at),
                  ),
          ),
          if (hasMathPen)
            InsertMenuRow(
              key: OverflowToolsMenu.mathKey,
              icon: AppIconKind.math.material,
              label: EditorStrings.mathPenTool,
              selected: mathActive,
              onPressed: readOnly
                  ? null
                  : () {
                      ref
                          .read(editorCommandsProvider)
                          .selectTool(EditorTool.math);
                      _close();
                    },
            ),
          if (hasTextPen)
            InsertMenuRow(
              key: OverflowToolsMenu.textPenKey,
              icon: AppIconKind.textPen.material,
              label: EditorStrings.textPenTool,
              selected: textPenActive,
              onPressed: readOnly
                  ? null
                  : () {
                      ref
                          .read(editorCommandsProvider)
                          .selectTool(EditorTool.textPen);
                      _close();
                    },
            ),
          if (widget.hasInsert)
            ...insertMenuRows(
              ref,
              sources: sources,
              items: items,
              running: running,
              close: _close,
              enabled: !readOnly,
              // The 텍스트 펜 row is right above: no second row doing the
              // same ('텍스트로 변환' on the selection bar converts a
              // selection).
              textPen: false,
            ),
          if (widget.hasPanel)
            InsertMenuRow(
              key: MicButton.micKey,
              icon: indicator == MicIndicator.thisNote
                  ? AppIconKind.micOn.material
                  : AppIconKind.mic.material,
              label: EditorStrings.recording,
              selected: panelOpen,
              onPressed: () {
                ref.read(editorPanelProvider.notifier).toggle();
                _close();
              },
            ),
        ],
        child: ToolButton(
          glyph: switch (active) {
            EditorTool.shape => AppIconKind.shape,
            EditorTool.text => AppIconKind.text,
            EditorTool.math when mathActive => AppIconKind.math,
            EditorTool.textPen when textPenActive => AppIconKind.textPen,
            _ => AppIconKind.moreTools,
          },
          label: EditorStrings.moreTools,
          active: folded,
          dotColor: switch (indicator) {
            MicIndicator.none => null,
            MicIndicator.thisNote => MicButton.recordingDotColor,
            MicIndicator.otherNote => scheme.outline,
          },
          onTap: _toggle,
        ),
      ),
    );
  }
}
