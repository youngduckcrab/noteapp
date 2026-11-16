// lib/src/ui/toolbar/insert_menu.dart — m5-7/04-editor 6.13.1 [+], 6.13.2
// (EditorInsertContext), 6.12.1–6.12.2 (the image submenu), 4.3.1 (the slot
// callback rules) — E2-12.
//
// [+] (`add`) opens a MenuAnchor: the '이미지' submenu with the image slot's
// sources (6.12.1 table, ImageImportSource order) when the slot offers any,
// then EditorExtensions.insertMenuItems in list order (duplicate ids dropped
// and reported — 4.3.1). Nothing to offer → no button (the toolbar checks
// [InsertMenu.hasItems]); a read-only note → the button is disabled. A press
// starts the source's picker / the item's onSelected synchronously inside
// the press, then the menu closes (ExtensionRunner.run — the rows are
// TextButtons, whose onPressed runs in the tap; MenuItemButton would run it
// a frame later, after the menu closed). A running item is disabled.
// (E2-13) The rows are [insertMenuRows], also used by the folded toolbar's
// [⋯도구] (overflow_tools_menu.dart).
import 'dart:async';

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
import '../../tools/text_pen/text_pen_controller.dart';
import '../../tools/tool_controller.dart';
import '../../tools/tool_state.dart';
import '../editor_strings.dart';
import 'tool_glyph.dart';

/// Icon of an image source (6.12.1 table).
IconData imageSourceIcon(core.ImageImportSource source) => switch (source) {
  core.ImageImportSource.photos => AppIconKind.photos.material,
  core.ImageImportSource.camera => AppIconKind.camera.material,
  core.ImageImportSource.files => AppIconKind.files.material,
  core.ImageImportSource.clipboard => AppIconKind.paste.material,
};

class InsertMenu extends ConsumerStatefulWidget {
  const InsertMenu({super.key});

  static const buttonKey = ValueKey('editor.toolbar.insert');
  static const imageKey = ValueKey('editor.insert.image');
  static ValueKey<String> imageSourceKey(core.ImageImportSource source) =>
      ValueKey('editor.insert.image.${source.name}');
  static ValueKey<String> extensionKey(String id) => ValueKey('editor.ext.$id');

  /// (text pen, phase 1) '손글씨를 텍스트로' (EditorExtensions.textPen only).
  static const handwritingToTextKey = ValueKey(
    'editor.insert.handwritingToText',
  );

  /// (v2.15-ui) '수식 쓰기' (EditorExtensions.mathPen only).
  static const mathKey = ValueKey('editor.insert.math');

  /// (v2.15-ui) '녹음' (EditorExtensions.recordingPanel only): opens / closes
  /// the recording panel.
  static const recordingKey = ValueKey('editor.insert.recording');

  /// Whether [+] has anything to offer (else it is hidden — E-7).
  static bool hasItems(
    EditorImageImporter? importer,
    List<EditorInsertMenuItem> items, {
    bool textPen = false,
    bool mathPen = false,
    bool recording = false,
  }) =>
      textPen ||
      mathPen ||
      recording ||
      items.isNotEmpty ||
      ImageFlows.sourcesOf(importer).isNotEmpty;

  @override
  ConsumerState<InsertMenu> createState() => InsertMenuState();
}

class InsertMenuState extends ConsumerState<InsertMenu> {
  final MenuController _menu = MenuController();

  /// Whether the menu is open (tests: a slot callback starts before the
  /// menu closes — review S-6).
  @visibleForTesting
  bool get isOpen => _menu.isOpen;

  void _toggle() => _menu.isOpen ? _menu.close() : _menu.open();

  void _close() {
    if (_menu.isOpen) _menu.close();
  }

  @override
  Widget build(BuildContext context) {
    final readOnly = ref.watch(editorReadOnlyProvider);
    final sources = ImageFlows.sourcesOf(
      ref.watch(editorImageImporterProvider),
    );
    final runner = ref.watch(editorExtensionRunnerProvider);
    final items = runner.withoutDuplicates(
      ref.watch(editorExtensionsProvider.select((e) => e.insertMenuItems)),
      (item) => item.id,
    );
    final textPen = ref.watch(
      editorExtensionsProvider.select((e) => e.textPen != null),
    );
    final mathPen = ref.watch(
      editorExtensionsProvider.select((e) => e.mathPen != null),
    );
    final recording = ref.watch(
      editorExtensionsProvider.select((e) => e.recordingPanel != null),
    );
    if (items.isEmpty &&
        sources.isEmpty &&
        !textPen &&
        !mathPen &&
        !recording) {
      return const SizedBox.shrink();
    }
    final active = ref.watch(editorToolProvider.select((s) => s.activeTool));
    final inserting =
        (mathPen && active == EditorTool.math) ||
        (textPen && active == EditorTool.textPen);
    return ValueListenableBuilder<Set<String>>(
      valueListenable: runner.runningIds,
      builder: (context, running, _) => MenuAnchor(
        controller: _menu,
        menuChildren: insertMenuRows(
          ref,
          sources: sources,
          items: items,
          running: running,
          close: _close,
          textPen: textPen,
          mathPen: mathPen,
          recording: recording,
        ),
        // (UI stage 2) the line icon with its name under it
        // (StyleTokens.toolLabels).
        // 48×48 like the ToolButtons beside it (contract 7.4.8 also where
        // the tap target shrink-wraps — desktop, web); the 미니멀 name on
        // hover anywhere on it (ToolHover).
        child: ToolHover(
          child: IconButton(
            key: InsertMenu.buttonKey,
            // (v2.15-ui) selected while 수식 펜 / 텍스트 펜 (now here) is the
            // tool.
            isSelected: inserting,
            onPressed: readOnly ? null : _toggle,
            style: IconButton.styleFrom(
              minimumSize: const Size(48, 48),
              padding: EdgeInsets.zero,
            ),
            icon: ToolGlyph(
              AppIconKind.insert,
              caption: EditorStrings.insert,
              semanticLabel: EditorStrings.insert,
              selected: inserting,
            ),
          ),
        ),
      ),
    );
  }
}

/// The rows of [+] (6.13.1): the '이미지' submenu with [sources] (when any),
/// then [items] (duplicates already dropped) — shared by [InsertMenu] and the
/// folded toolbar's [⋯도구] (E2-13). A press starts the source's picker /
/// the item's onSelected synchronously inside the press (4.3.1), then
/// [close] closes the menu the rows are in. Rows whose id is [running] — or
/// all of them when not [enabled] — are disabled. (text pen, phase 1) With
/// [textPen] (EditorExtensions.textPen) the '손글씨를 텍스트로' row comes
/// first after the image rows: with handwriting selected it opens the
/// conversion sheet on it, otherwise it picks the 텍스트 펜.
List<Widget> insertMenuRows(
  WidgetRef ref, {
  required List<core.ImageImportSource> sources,
  required List<EditorInsertMenuItem> items,
  required Set<String> running,
  required VoidCallback close,
  bool enabled = true,
  bool textPen = false,
  bool mathPen = false,
  bool recording = false,
}) {
  void pickImage(core.ImageImportSource source) => unawaited(
    ref.read(editorImageFlowsProvider).insert(source, close: close),
  );

  // 4.3.1: the context is made now (6.13.2), onSelected starts
  // synchronously inside this onPressed, then the menu closes.
  void runExtension(EditorInsertMenuItem item) {
    final insert = ref.read(editorCommandsProvider).insertContext();
    if (insert == null) return;
    unawaited(
      ref
          .read(editorExtensionRunnerProvider)
          .run<void>(
            item.id,
            (body) => item.onSelected(body, insert),
            close: close,
          ),
    );
  }

  void handwritingToText() {
    close();
    final selection = ref.read(editorCommandsProvider).selectionContext();
    final ink = [
      ...?selection?.strokes.where(core.HandwritingText.isRecognitionInput),
    ];
    if (selection == null || ink.isEmpty) {
      ref.read(editorCommandsProvider).selectTool(EditorTool.textPen);
      return;
    }
    final converting = ref
        .read(editorTextPenProvider)
        .convertStrokes(selection.pageId, ink);
    unawaited(
      converting.then((ok) {
        if (ok) selection.clearSelection();
      }),
    );
  }

  return [
    if (sources.isNotEmpty)
      SubmenuButton(
        key: InsertMenu.imageKey,
        leadingIcon: const AppIcon(AppIconKind.image),
        menuChildren: [
          for (final source in sources)
            InsertMenuRow(
              key: InsertMenu.imageSourceKey(source),
              icon: imageSourceIcon(source),
              label: EditorStrings.imageSourceName(source),
              onPressed: !enabled || running.contains(ImageFlows.runId)
                  ? null
                  : () => pickImage(source),
            ),
        ],
        child: const Text(EditorStrings.image),
      ),
    if (textPen)
      InsertMenuRow(
        key: InsertMenu.handwritingToTextKey,
        kind: AppIconKind.textPen,
        label: EditorStrings.handwritingToText,
        onPressed: enabled ? handwritingToText : null,
      ),
    // (v2.15-ui) 수식 펜 left the toolbar: '수식 쓰기' picks it.
    if (mathPen)
      InsertMenuRow(
        key: InsertMenu.mathKey,
        kind: AppIconKind.math,
        label: EditorStrings.insertMath,
        selected: ref.read(editorToolProvider).activeTool == EditorTool.math,
        onPressed: enabled
            ? () {
                close();
                ref.read(editorCommandsProvider).selectTool(EditorTool.math);
              }
            : null,
      ),
    for (final item in items)
      InsertMenuRow(
        key: InsertMenu.extensionKey(item.id),
        icon: item.icon,
        label: item.label,
        onPressed: !enabled || running.contains(item.id)
            ? null
            : () => runExtension(item),
      ),
    // (v2.15-ui) [🎤] left the toolbar (it shows there only while recording
    // or with the panel open): '녹음' opens / closes the recording panel.
    if (recording)
      InsertMenuRow(
        key: InsertMenu.recordingKey,
        kind: AppIconKind.mic,
        label: EditorStrings.insertRecording,
        selected: ref.read(editorPanelProvider),
        onPressed: () {
          close();
          ref.read(editorPanelProvider.notifier).toggle();
        },
      ),
  ];
}

/// One row of the insert menu (and of the folded toolbar's [⋯도구]): at
/// least 44 px high (contract 7.4.8), its [onPressed] run synchronously in
/// the tap (4.3.1 — not a MenuItemButton, which runs it a frame later).
/// [selected] (the active tool of [⋯도구]) gets the primaryContainer
/// background.
class InsertMenuRow extends StatelessWidget {
  const InsertMenuRow({
    super.key,
    this.kind,
    this.icon,
    required this.label,
    required this.onPressed,
    this.selected = false,
  }) : assert(kind != null || icon != null, 'a kind or an icon');

  /// The meaning (ui_kit icon table): the same icon as the toolbar's.
  final AppIconKind? kind;

  /// A glyph not in the table (an extension's insert item).
  final IconData? icon;
  final String label;
  final VoidCallback? onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final tokens = StyleTokens.of(context);
    return TextButton.icon(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        alignment: AlignmentDirectional.centerStart,
        minimumSize: const Size(180, 44),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        shape: const RoundedRectangleBorder(),
        backgroundColor: selected ? tokens.accentSoft : null,
        foregroundColor: selected ? tokens.onAccentSoft : null,
      ),
      icon: kind != null ? AppIcon(kind!) : Icon(icon),
      label: Text(label),
    );
  }
}
