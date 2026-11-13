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

import '../../commands/extension_runner.dart';
import '../../di/editor_extensions.dart';
import '../../di/editor_image_importer.dart';
import '../../objects/image_flows.dart';
import '../../scope/editor_scope.dart';
import '../../tools/text_pen/text_pen_controller.dart';
import '../../tools/tool_state.dart';
import '../editor_strings.dart';

/// Icon of an image source (6.12.1 table).
IconData imageSourceIcon(core.ImageImportSource source) => switch (source) {
  core.ImageImportSource.photos => Icons.photo_library,
  core.ImageImportSource.camera => Icons.photo_camera,
  core.ImageImportSource.files => Icons.folder_open,
  core.ImageImportSource.clipboard => Icons.content_paste,
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

  /// Whether [+] has anything to offer (else it is hidden — E-7).
  static bool hasItems(
    EditorImageImporter? importer,
    List<EditorInsertMenuItem> items, {
    bool textPen = false,
  }) =>
      textPen || items.isNotEmpty || ImageFlows.sourcesOf(importer).isNotEmpty;

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
    if (items.isEmpty && sources.isEmpty && !textPen) {
      return const SizedBox.shrink();
    }
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
        ),
        child: IconButton(
          key: InsertMenu.buttonKey,
          onPressed: readOnly ? null : _toggle,
          icon: const Icon(Icons.add, semanticLabel: EditorStrings.insert),
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
        leadingIcon: const Icon(Icons.image),
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
        icon: Icons.edit_note,
        label: EditorStrings.handwritingToText,
        onPressed: enabled ? handwritingToText : null,
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
    required this.icon,
    required this.label,
    required this.onPressed,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TextButton.icon(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        alignment: AlignmentDirectional.centerStart,
        minimumSize: const Size(180, 44),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        shape: const RoundedRectangleBorder(),
        backgroundColor: selected ? scheme.primaryContainer : null,
        foregroundColor: selected ? scheme.onPrimaryContainer : null,
      ),
      icon: Icon(icon),
      label: Text(label),
    );
  }
}
