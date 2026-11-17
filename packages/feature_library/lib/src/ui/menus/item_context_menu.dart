// lib/src/ui/menus/item_context_menu.dart — 05-library 6.8 / 6.5: the item
// menus.
//
//   note (⋯)            이름 변경 · 표지 변경 · ☆ 즐겨찾기 / ★ 해제 · 복사 ·
//                       이동… · PDF로 내보내기 (only with the export slot,
//                       4.3) · 휴지통으로 이동
//   MD 문서 (⋯, v2.17-md) 이름 변경 · ☆ · 복사 · 이동… · .md로 내보내기 (only
//                       with its slot) · 휴지통으로 이동 (no cover, no PDF)
//   folder (⋯)          이름 변경 · 꾸미기 · 복사 · 이동… · 휴지통으로 이동
//   sidebar tree row    이름 변경 · 꾸미기 · 새 하위 폴더 · 이동… · 휴지통으로 이동
//
// ItemMenuButton is the 44 × 44 ⋯ of a tile / list row. SidebarRowMenu opens
// the same kind of menu from a tree row: a long press released without
// moving (the row's LibraryDraggable.onLongPressReleased — a long press
// starts a drag, 6.5) or a secondary (right) click, at the press point.
import 'package:flutter/gestures.dart' show TapGestureRecognizer;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' show Folder, Note;
import 'package:ui_kit/ui_kit.dart';

import '../../integration/markdown_flows.dart';
import '../../integration/markdown_slots.dart';
import '../../integration/pdf_flows.dart';
import '../../integration/pdf_slots.dart';
import '../../l10n/library_strings.dart';
import '../../model/item_key.dart';
import '../dialogs/create_flows.dart';
import '../layout/library_metrics.dart';
import 'item_action_flows.dart';

/// The menu entries of [note] or [folder] (exactly one). Every action runs
/// with [context] — the widget that owns the menu, still mounted after the
/// menu closes. [exportPdf] = libraryPdfExportActionProvider; null hides
/// 'PDF로 내보내기' (4.3).
List<Widget> itemMenuEntries(
  BuildContext context, {
  Note? note,
  Folder? folder,
  bool sidebar = false,
  LibraryPdfExportAction? exportPdf,
  LibraryMarkdownExportAction? exportMarkdown,
}) {
  assert((note == null) != (folder == null), 'exactly one item');
  if (note != null) {
    final key = noteKey(note.id);
    // (v2.17-md, C217M-11) an MD 문서: no cover, no PDF export; '.md로 내보내기'.
    final markdown = note.isMarkdown;
    return [
      MenuItemButton(
        leadingIcon: AppIcon(AppIconKind.rename),
        onPressed: () =>
            runRenameFlow(context, item: key, currentName: note.title),
        child: const Text(LibraryStrings.rename),
      ),
      if (!markdown)
        MenuItemButton(
          leadingIcon: AppIcon(AppIconKind.cover),
          onPressed: () => runCoverFlow(context, note),
          child: const Text(LibraryStrings.changeCover),
        ),
      MenuItemButton(
        leadingIcon: AppIcon(
          note.isFavorite ? AppIconKind.favoriteOn : AppIconKind.favorite,
        ),
        onPressed: () => runFavoriteFlow(
          context,
          ids: [note.id],
          favorite: !note.isFavorite,
        ),
        child: Text(
          note.isFavorite
              ? LibraryStrings.favoriteRemove
              : LibraryStrings.favoriteAdd,
        ),
      ),
      MenuItemButton(
        leadingIcon: AppIcon(AppIconKind.duplicate),
        onPressed: () =>
            runCopyHereFlow(context, item: key, parentId: note.folderId),
        child: const Text(LibraryStrings.copy),
      ),
      MenuItemButton(
        leadingIcon: AppIcon(AppIconKind.move),
        onPressed: () =>
            runMoveFlow(context, items: [key], parents: {key: note.folderId}),
        child: const Text(LibraryStrings.moveTo),
      ),
      if (markdown && exportMarkdown != null)
        ValueListenableBuilder<bool>(
          valueListenable: libraryMarkdownExportRunning(context),
          builder: (_, running, _) => MenuItemButton(
            key: const Key('library.menu.exportMarkdown'),
            leadingIcon: AppIcon(AppIconKind.exportMarkdown),
            onPressed: running
                ? null
                : () => runLibraryMarkdownExport(
                    context,
                    action: exportMarkdown,
                    noteId: note.id,
                  ),
            child: const Text(LibraryStrings.exportMarkdown),
          ),
        ),
      if (!markdown && exportPdf != null)
        ValueListenableBuilder<bool>(
          valueListenable: libraryPdfExportRunning(context),
          builder: (_, running, _) => MenuItemButton(
            leadingIcon: const Icon(Icons.picture_as_pdf_outlined),
            onPressed: running
                ? null
                : () => runLibraryPdfExport(
                    context,
                    action: exportPdf,
                    noteIds: [note.id],
                  ),
            child: const Text(LibraryStrings.exportPdfOne),
          ),
        ),
      MenuItemButton(
        leadingIcon: AppIcon(AppIconKind.trash),
        onPressed: () =>
            runTrashFlow(context, items: [key], singleName: note.title),
        child: const Text(LibraryStrings.moveToTrash),
      ),
    ];
  }
  final f = folder!;
  final key = folderKey(f.id);
  return [
    MenuItemButton(
      leadingIcon: AppIcon(AppIconKind.rename),
      onPressed: () => runRenameFlow(context, item: key, currentName: f.name),
      child: const Text(LibraryStrings.rename),
    ),
    MenuItemButton(
      leadingIcon: AppIcon(AppIconKind.style),
      onPressed: () => runFolderAppearanceFlow(context, f),
      child: const Text(LibraryStrings.customize),
    ),
    if (sidebar)
      MenuItemButton(
        leadingIcon: AppIcon(AppIconKind.newFolder),
        onPressed: () => runNewFolderFlow(context, parentId: f.id),
        child: const Text(LibraryStrings.newSubfolder),
      )
    else
      MenuItemButton(
        leadingIcon: AppIcon(AppIconKind.duplicate),
        onPressed: () =>
            runCopyHereFlow(context, item: key, parentId: f.parentId),
        child: const Text(LibraryStrings.copy),
      ),
    MenuItemButton(
      leadingIcon: AppIcon(AppIconKind.move),
      onPressed: () =>
          runMoveFlow(context, items: [key], parents: {key: f.parentId}),
      child: const Text(LibraryStrings.moveTo),
    ),
    MenuItemButton(
      leadingIcon: AppIcon(AppIconKind.trash),
      onPressed: () => runTrashFlow(context, items: [key], singleName: f.name),
      child: const Text(LibraryStrings.moveToTrash),
    ),
  ];
}

/// The ⋯ (44 × 44, tooltip `'<name> 메뉴'`) of a grid tile or a list row.
class ItemMenuButton extends ConsumerWidget {
  const ItemMenuButton({super.key, this.note, this.folder})
    : assert((note == null) != (folder == null), 'exactly one item');

  final Note? note;
  final Folder? folder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exportPdf = note == null
        ? null
        : ref.watch(libraryPdfExportActionProvider);
    final exportMarkdown = note == null
        ? null
        : ref.watch(libraryMarkdownExportActionProvider);
    return MenuAnchor(
      menuChildren: itemMenuEntries(
        context,
        note: note,
        folder: folder,
        exportPdf: exportPdf,
        exportMarkdown: exportMarkdown,
      ),
      builder: (context, controller, _) => IconButton(
        icon: AppIcon(AppIconKind.more),
        tooltip: LibraryStrings.itemMenu(note?.title ?? folder!.name),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(
          width: LibraryMetrics.minTapTarget,
          height: LibraryMetrics.minTapTarget,
        ),
        style: const ButtonStyle(
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }
}

/// The menu of a sidebar tree row: opened by a secondary click, or by the
/// openMenu callback that [builder] gets (LibraryDraggable.onLongPressReleased
/// of the row), at the last press point.
class SidebarRowMenu extends StatefulWidget {
  const SidebarRowMenu({
    super.key,
    required this.folder,
    required this.builder,
  });

  final Folder folder;

  /// The row; [openMenu] opens the menu where the row was last pressed.
  final Widget Function(BuildContext context, VoidCallback openMenu) builder;

  @override
  State<SidebarRowMenu> createState() => _SidebarRowMenuState();
}

class _SidebarRowMenuState extends State<SidebarRowMenu> {
  final MenuController _controller = MenuController();

  /// Where the row was last pressed (local).
  Offset? _downLocal;

  void _openAt(Offset? local) => _controller.open(position: local);

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      controller: _controller,
      menuChildren: itemMenuEntries(
        context,
        folder: widget.folder,
        sidebar: true,
      ),
      child: Listener(
        onPointerDown: (event) => _downLocal = event.localPosition,
        child: RawGestureDetector(
          // The row keeps its own semantics node (label + tap); screen reader
          // users reach the same actions through the folder's ⋯ in the
          // listing.
          excludeFromSemantics: true,
          gestures: {
            TapGestureRecognizer:
                GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
                  () => TapGestureRecognizer(debugOwner: this),
                  (recognizer) =>
                      recognizer
                        ..onSecondaryTapUp = (details) =>
                            _openAt(details.localPosition),
                ),
          },
          child: widget.builder(context, () => _openAt(_downLocal)),
        ),
      ),
    );
  }
}
