// lib/src/ui/overlays/selection_menu.dart — 04-editor 6.6.5 (selection menu);
// (v2) m5-7/04-editor 6.7.1 (items), 6.7.2 ('색 ●' → the recolor popup),
// 6.7.3 (cut · copy · delete · duplicate).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

import '../../scope/editor_scope.dart';
import '../../state/popup.dart';
import '../../text/text_edit_session.dart';
import '../../tools/selection.dart';
import '../../tools/selection_menu_model.dart';
import '../editor_strings.dart';
import 'selection_frame_painter.dart' show selectionRepaint;

/// A rounded bar 8 px above the selection frame (below it when there is no
/// room). (v2, 6.7.1) [잘라내기] [복사] [삭제] [색 ●] [⋯]; '⋯' (더보기) opens
/// 복제 · 90° 돌리기 · (단일 텍스트) 편집 · 선택 해제. Hidden while the selection
/// is dragged. A sibling of the page area's Listener (6.4.3), so its taps
/// never reach the input router; the '⋯' menu sits in the overlay.
///
/// - Read-only note: 잘라내기 · 삭제 · 색 · 복제 · 돌리기 · 편집 disabled; 복사 and
///   선택 해제 stay.
/// - '색' hidden when nothing can be recolored (images and / or unknown
///   objects only — INK leaves them out); '90° 돌리기' hidden for unknown
///   objects only (SelectionMenuModel).
class SelectionMenu extends ConsumerWidget {
  const SelectionMenu({super.key});

  static const cutKey = ValueKey('editor.selectionMenu.cut');
  static const copyKey = ValueKey('editor.selectionMenu.copy');
  static const deleteKey = ValueKey('editor.selectionMenu.delete');
  static const colorKey = ValueKey('editor.selectionMenu.color');
  static const moreKey = ValueKey('editor.selectionMenu.more');
  static const duplicateKey = ValueKey('editor.selectionMenu.duplicate');
  static const rotate90Key = ValueKey('editor.selectionMenu.rotate90');
  static const styleKey = ValueKey('editor.selectionMenu.style');
  static const verticesKey = ValueKey('editor.selectionMenu.vertices');
  static const editTextKey = ValueKey('editor.selectionMenu.editText');
  static const formatKey = ValueKey('editor.selectionMenu.format');
  static const clearKey = ValueKey('editor.selectionMenu.clear');

  /// The colour dot inside '색'.
  static const colorDotKey = ValueKey('editor.selectionMenu.color.dot');

  /// Distance between the frame and the bar (px).
  static const double gap = 8;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selection = ref.watch(editorSelectionProvider);
    if (selection == null || selection.isDragging) {
      return const SizedBox.shrink();
    }
    final viewport = ref.watch(editorViewportProvider);
    final pages = ref.watch(editorMountedPagesProvider);
    return ListenableBuilder(
      listenable: selectionRepaint(viewport, pages, selection),
      builder: (context, child) {
        // (v2) clear of the whole frame, the rotate handle included (6.6.4).
        final rect = selectionFrameOnScreen(viewport, pages, selection)?.extent;
        if (rect == null) return const SizedBox.shrink();
        return CustomSingleChildLayout(
          delegate: _AboveOrBelow(rect),
          child: child,
        );
      },
      child: _SelectionBar(selection: selection),
    );
  }
}

/// The bar's items for [selection]; the model follows the page's CORE
/// content (PageMount.contentChanges — a recolor changes the dot of '색').
class _SelectionBar extends ConsumerStatefulWidget {
  const _SelectionBar({required this.selection});

  final EditorSelection selection;

  @override
  ConsumerState<_SelectionBar> createState() => _SelectionBarState();
}

class _SelectionBarState extends ConsumerState<_SelectionBar> {
  final MenuController _more = MenuController();

  void _toggleMore() {
    if (_more.isOpen) {
      _more.close();
    } else {
      _more.open();
    }
  }

  /// Runs [action] (synchronously, inside the item's onPressed), then closes
  /// the '⋯' menu.
  void _fromMore(VoidCallback action) {
    action();
    if (mounted && _more.isOpen) _more.close();
  }

  void _openRecolor(BuildContext buttonContext) {
    final box = buttonContext.findRenderObject();
    Offset? at;
    if (box is RenderBox && box.attached && box.hasSize) {
      // The popup's top-left 6 px under the button's left edge (the popup
      // host places it 12 px right of / below the point it gets).
      at =
          box.localToGlobal(box.size.bottomLeft(Offset.zero)) +
          const Offset(-12, -6);
    }
    if (_more.isOpen) _more.close();
    ref
        .read(editorPopupProvider.notifier)
        .open(RecolorPopup(globalPosition: at));
  }

  @override
  Widget build(BuildContext context) {
    final selection = widget.selection;
    final readOnly = ref.watch(editorReadOnlyProvider);
    final commands = ref.watch(editorCommandsProvider);
    final session = ref.watch(editorSessionValueProvider);
    final pages = ref.watch(editorMountedPagesProvider);
    final mount = pages[selection.pageId];
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: Listenable.merge([pages, ?mount?.contentChanges]),
      builder: (context, _) {
        final model = SelectionMenuModel.of(
          session.pageIfLoaded(selection.pageId),
          selection.elementIds,
        );
        final single = model.single;
        return Material(
          color: scheme.surfaceContainerHigh,
          elevation: 3,
          shape: const StadiumBorder(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  key: SelectionMenu.cutKey,
                  onPressed: readOnly ? null : commands.cutSelection,
                  child: const Text(EditorStrings.selectionCut),
                ),
                TextButton(
                  key: SelectionMenu.copyKey,
                  onPressed: commands.copySelection,
                  child: const Text(EditorStrings.selectionCopy),
                ),
                TextButton(
                  key: SelectionMenu.deleteKey,
                  onPressed: readOnly ? null : commands.deleteSelection,
                  child: const Text(EditorStrings.selectionDelete),
                ),
                if (model.canRecolor)
                  Builder(
                    builder: (buttonContext) => TextButton(
                      key: SelectionMenu.colorKey,
                      onPressed: readOnly
                          ? null
                          : () => _openRecolor(buttonContext),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(EditorStrings.selectionColor),
                          const SizedBox(width: 6),
                          Container(
                            key: SelectionMenu.colorDotKey,
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              color: Color(model.colorArgb ?? 0xFF000000),
                              shape: BoxShape.circle,
                              border: Border.all(color: scheme.outlineVariant),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                MenuAnchor(
                  controller: _more,
                  menuChildren: [
                    _MoreItem(
                      key: SelectionMenu.duplicateKey,
                      label: EditorStrings.selectionDuplicate,
                      onPressed: readOnly
                          ? null
                          : () => _fromMore(commands.duplicateSelection),
                    ),
                    if (model.canTransform)
                      _MoreItem(
                        key: SelectionMenu.rotate90Key,
                        label: EditorStrings.selectionRotate90,
                        onPressed: readOnly
                            ? null
                            : () => _fromMore(commands.rotateSelection90),
                      ),
                    if (single is core.TextBoxObject)
                      _MoreItem(
                        key: SelectionMenu.editTextKey,
                        label: EditorStrings.selectionEditText,
                        onPressed: readOnly
                            ? null
                            : () => _fromMore(() {
                                commands.clearSelection();
                                ref
                                    .read(editorTextEditProvider.notifier)
                                    .start(single, isNew: false);
                              }),
                      ),
                    _MoreItem(
                      key: SelectionMenu.clearKey,
                      label: EditorStrings.selectionClear,
                      onPressed: () => _fromMore(commands.clearSelection),
                    ),
                  ],
                  child: IconButton(
                    key: SelectionMenu.moreKey,
                    onPressed: _toggleMore,
                    icon: const Icon(
                      Icons.more_horiz,
                      semanticLabel: EditorStrings.selectionMore,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// One row of the '⋯' menu: at least 44 px high (contract 7.4.8). Its
/// [onPressed] runs synchronously in the tap (MenuItemButton would delay it
/// to the next frame, after the menu closed), so an extension item can open
/// a browser picker inside the user activation (4.3.1 — E2-07c).
class _MoreItem extends StatelessWidget {
  const _MoreItem({super.key, required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: onPressed,
    style: TextButton.styleFrom(
      alignment: AlignmentDirectional.centerStart,
      minimumSize: const Size(160, 44),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      shape: const RoundedRectangleBorder(),
    ),
    child: Text(label),
  );
}

/// Centres the bar over [frame], [SelectionMenu.gap] above it, or below it
/// when it does not fit above; kept inside the page area.
class _AboveOrBelow extends SingleChildLayoutDelegate {
  const _AboveOrBelow(this.frame);

  final Rect frame;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    var top = frame.top - SelectionMenu.gap - childSize.height;
    if (top < 0) top = frame.bottom + SelectionMenu.gap;
    final maxTop = size.height - childSize.height;
    final maxLeft = size.width - childSize.width;
    final left = frame.center.dx - childSize.width / 2;
    return Offset(
      maxLeft <= 0 ? 0 : left.clamp(0.0, maxLeft).toDouble(),
      maxTop <= 0 ? 0 : top.clamp(0.0, maxTop).toDouble(),
    );
  }

  @override
  bool shouldRelayout(_AboveOrBelow oldDelegate) => oldDelegate.frame != frame;
}
