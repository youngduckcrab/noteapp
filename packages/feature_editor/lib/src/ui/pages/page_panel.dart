// lib/src/ui/pages/page_panel.dart — 04-editor 6.11.1, 6.11.2.
import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:ui_kit/ui_kit.dart';

import '../../scope/editor_scope.dart';
import '../../state/page_panel.dart';
import '../../state/popup.dart';
import '../editor_strings.dart';
import 'page_panel_selection_bar.dart';
import 'page_panel_thumbnail.dart';

/// The page panel: a left overlay (width 176, from under the toolbar and the
/// preset bar to the bottom, elevation 2) over the page viewport, so the
/// viewport keeps its size and zoom. Toggled by the toolbar [▤].
///
/// Header "페이지 12" + [선택] (selection mode) + [+] (AddPagePopup). The
/// list is core.notePagesProvider(noteId) (note order; session.pages while
/// it loads), a ReorderableListView.builder: items keep ValueKey(page.id), a
/// long press (500 ms) starts a drag → EditorCommands.movePage(id, final
/// index) — off in the selection mode and on a read-only note.
///
/// Item: PagePanelThumbnail (width 120, height 120 × h / w, at most 200) +
/// number + ⋯ [앞에 페이지 추가, 뒤에 페이지 추가, 복제, 삭제] (삭제 is off
/// on a one-page note; all four on a read-only note). Tap → jumpToPage; in
/// the selection mode a tap toggles the page instead. The current page has
/// a 2 px primary border, and the list scrolls (200 ms) to keep it visible
/// when it changes (item heights are known from the page sizes).
class PagePanel extends ConsumerStatefulWidget {
  const PagePanel({super.key});

  static const double width = 176;
  static const double thumbnailWidth = 120;

  /// Item height around the thumbnail: 8 above, 4 + 36 (number row) + 4 below.
  static const double itemChrome = 52;

  static const Duration scrollDuration = Duration(milliseconds: 200);

  static const panelKey = ValueKey('editor.pagePanel');
  static const listKey = ValueKey('editor.pagePanel.list');
  static const selectModeKey = ValueKey('editor.pagePanel.selectMode');
  static const addKey = ValueKey('editor.pagePanel.add');
  static const countKey = ValueKey('editor.pagePanel.count');

  static ValueKey<String> itemKey(String pageId) =>
      ValueKey('editor.pagePanel.item.$pageId');
  static ValueKey<String> menuKey(String pageId) =>
      ValueKey('editor.pagePanel.menu.$pageId');
  static ValueKey<String> checkKey(String pageId) =>
      ValueKey('editor.pagePanel.check.$pageId');
  static ValueKey<String> menuItemKey(String pageId, PageMenuAction action) =>
      ValueKey('editor.pagePanel.menu.$pageId.${action.name}');

  /// Height of the list item of [page].
  static double itemHeightOf(core.Page page) =>
      PagePanelThumbnail.heightFor(page.size, thumbnailWidth) + itemChrome;

  @override
  ConsumerState<PagePanel> createState() => _PagePanelState();
}

/// The item ⋯ menu.
enum PageMenuAction { addBefore, addAfter, duplicate, delete }

class _PagePanelState extends ConsumerState<PagePanel> {
  final ScrollController _scroll = ScrollController();
  List<core.Page> _pages = const [];

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Scrolls the list so item [index] is fully visible.
  void _reveal(int index, {required bool animate}) {
    if (!_scroll.hasClients || index < 0 || index >= _pages.length) return;
    var top = 0.0;
    for (var i = 0; i < index; i++) {
      top += PagePanel.itemHeightOf(_pages[i]);
    }
    final height = PagePanel.itemHeightOf(_pages[index]);
    final position = _scroll.position;
    final viewport = position.viewportDimension;
    double? target;
    if (top < position.pixels) {
      target = top;
    } else if (top + height > position.pixels + viewport) {
      target = top + height - viewport;
    }
    if (target == null) return;
    target = target.clamp(position.minScrollExtent, position.maxScrollExtent);
    if (animate) {
      unawaited(
        _scroll.animateTo(
          target,
          duration: PagePanel.scrollDuration,
          curve: Curves.easeOut,
        ),
      );
    } else {
      _scroll.jumpTo(target);
    }
  }

  void _revealLater(int index, {required bool animate}) {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) _reveal(index, animate: animate);
    });
  }

  @override
  Widget build(BuildContext context) {
    final panel = ref.watch(editorPagePanelProvider);
    ref.listen(editorPagePanelProvider.select((p) => p.isOpen), (_, open) {
      if (open) {
        _revealLater(ref.read(editorCurrentPageIndexProvider), animate: false);
      }
    });
    ref.listen(editorCurrentPageIndexProvider, (_, index) {
      if (ref.read(editorPagePanelProvider).isOpen) {
        _revealLater(index, animate: true);
      }
    });
    if (!panel.isOpen) return const SizedBox.shrink();

    final session = ref.watch(editorSessionValueProvider);
    final noteId = ref.watch(editorNoteIdProvider);
    final pages =
        ref.watch(core.notePagesProvider(noteId)).value ?? session.pages;
    _pages = pages;
    final current = ref.watch(editorCurrentPageIndexProvider);
    final readOnly = ref.watch(editorReadOnlyProvider);
    final commands = ref.watch(editorCommandsProvider);
    final theme = Theme.of(context);
    final notifier = ref.read(editorPagePanelProvider.notifier);
    final canDrag = !panel.isSelecting && !readOnly;
    final container = ProviderScope.containerOf(context, listen: false);

    return Align(
      alignment: Alignment.centerLeft,
      child: SizedBox(
        width: PagePanel.width,
        height: double.infinity,
        child: Material(
          key: PagePanel.panelKey,
          elevation: 2,
          color: StyleTokens.of(context).panel,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 48,
                child: Row(
                  children: [
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        EditorStrings.pageCount(pages.length),
                        key: PagePanel.countKey,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                    IconButton(
                      key: PagePanel.selectModeKey,
                      isSelected: panel.isSelecting,
                      onPressed: () =>
                          notifier.setSelecting(!panel.isSelecting),
                      icon: const Icon(
                        Icons.checklist,
                        semanticLabel: EditorStrings.selectPages,
                      ),
                    ),
                    IconButton(
                      key: PagePanel.addKey,
                      onPressed: readOnly
                          ? null
                          : () => ref
                                .read(editorPopupProvider.notifier)
                                .open(const AddPagePopup()),
                      icon: const Icon(
                        Icons.add,
                        semanticLabel: EditorStrings.addPageEllipsis,
                      ),
                    ),
                  ],
                ),
              ),
              if (panel.isSelecting) PagePanelSelectionBar(pages: pages),
              const Divider(height: 1),
              Expanded(
                child: ReorderableListView.builder(
                  key: PagePanel.listKey,
                  scrollController: _scroll,
                  buildDefaultDragHandles: false,
                  // The dragged item is built in the app's Overlay, outside
                  // the per-note ProviderScope: give it this note's container.
                  proxyDecorator: (child, index, animation) =>
                      UncontrolledProviderScope(
                        container: container,
                        child: Material(
                          elevation: 6,
                          color: theme.colorScheme.surfaceContainerHigh,
                          child: child,
                        ),
                      ),
                  itemCount: pages.length,
                  onReorderItem: (from, to) {
                    if (from < pages.length) {
                      commands.movePage(pages[from].id, to);
                    }
                  },
                  itemBuilder: (context, index) {
                    final page = pages[index];
                    final item = _PageItem(
                      key: PagePanel.itemKey(page.id),
                      page: page,
                      index: index,
                      pageCount: pages.length,
                      isCurrent: index == current,
                      isSelecting: panel.isSelecting,
                      isSelected: panel.selectedIds.contains(page.id),
                      readOnly: readOnly,
                    );
                    return KeyedSubtree(
                      key: ValueKey(page.id),
                      child: canDrag
                          ? ReorderableDelayedDragStartListener(
                              index: index,
                              child: item,
                            )
                          : item,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PageItem extends ConsumerWidget {
  const _PageItem({
    super.key,
    required this.page,
    required this.index,
    required this.pageCount,
    required this.isCurrent,
    required this.isSelecting,
    required this.isSelected,
    required this.readOnly,
  });

  final core.Page page;
  final int index;
  final int pageCount;
  final bool isCurrent;
  final bool isSelecting;
  final bool isSelected;
  final bool readOnly;

  void _tap(WidgetRef ref) {
    if (isSelecting) {
      ref.read(editorPagePanelProvider.notifier).toggleSelected(page.id);
      return;
    }
    final viewport = ref.read(editorViewportProvider);
    final i = viewport.pages.indexWhere((p) => p.id == page.id);
    if (i >= 0) unawaited(viewport.jumpToPage(i));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final number = index + 1;
    final thumbHeight = PagePanelThumbnail.heightFor(
      page.size,
      PagePanel.thumbnailWidth,
    );
    return Semantics(
      label: EditorStrings.pageNumber(number),
      selected: isSelecting ? isSelected : isCurrent,
      child: InkWell(
        onTap: () => _tap(ref),
        child: SizedBox(
          height: thumbHeight + PagePanel.itemChrome,
          child: Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Column(
              children: [
                SizedBox(
                  width: PagePanel.thumbnailWidth,
                  height: thumbHeight,
                  child: Stack(
                    children: [
                      DecoratedBox(
                        position: DecorationPosition.foreground,
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: isCurrent
                                ? scheme.primary
                                : scheme.outlineVariant,
                            width: isCurrent ? 2 : 1,
                          ),
                        ),
                        child: PagePanelThumbnail(
                          page: page,
                          width: PagePanel.thumbnailWidth,
                        ),
                      ),
                      if (isSelecting)
                        Positioned(
                          top: 4,
                          right: 4,
                          child: Icon(
                            isSelected
                                ? Icons.check_circle
                                : Icons.radio_button_unchecked,
                            key: PagePanel.checkKey(page.id),
                            color: isSelected
                                ? scheme.primary
                                : scheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  height: 36,
                  width: PagePanel.thumbnailWidth + 24,
                  child: Row(
                    children: [
                      const SizedBox(width: 44),
                      Expanded(
                        child: Text(
                          '$number',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                color: isCurrent ? scheme.primary : null,
                                fontWeight: isCurrent ? FontWeight.w600 : null,
                              ),
                        ),
                      ),
                      SizedBox(
                        width: 44,
                        child: isSelecting
                            ? null
                            : _PageMenu(
                                page: page,
                                number: number,
                                canDelete: pageCount > 1,
                                readOnly: readOnly,
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PageMenu extends ConsumerWidget {
  const _PageMenu({
    required this.page,
    required this.number,
    required this.canDelete,
    required this.readOnly,
  });

  final core.Page page;
  final int number;
  final bool canDelete;
  final bool readOnly;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final commands = ref.watch(editorCommandsProvider);
    final popups = ref.read(editorPopupProvider.notifier);
    VoidCallback? enabled(VoidCallback action) => readOnly ? null : action;
    MenuItemButton item(PageMenuAction a, String label, VoidCallback? run) =>
        MenuItemButton(
          key: PagePanel.menuItemKey(page.id, a),
          onPressed: run,
          child: Text(label),
        );
    return MenuAnchor(
      menuChildren: [
        item(
          PageMenuAction.addBefore,
          EditorStrings.addPageBefore,
          enabled(
            () => popups.open(
              AddPagePopup(
                initialPlacement: AddPagePlacement.before,
                anchorPageId: page.id,
              ),
            ),
          ),
        ),
        item(
          PageMenuAction.addAfter,
          EditorStrings.addPageAfter,
          enabled(() => popups.open(AddPagePopup(anchorPageId: page.id))),
        ),
        item(
          PageMenuAction.duplicate,
          EditorStrings.duplicatePage,
          enabled(() => unawaited(commands.duplicatePages([page.id]))),
        ),
        item(
          PageMenuAction.delete,
          EditorStrings.deletePage,
          canDelete ? enabled(() => commands.deletePages([page.id])) : null,
        ),
      ],
      builder: (context, controller, _) => IconButton(
        key: PagePanel.menuKey(page.id),
        padding: EdgeInsets.zero,
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
        icon: Icon(
          Icons.more_horiz,
          semanticLabel: EditorStrings.pageMenu(number),
        ),
      ),
    );
  }
}
