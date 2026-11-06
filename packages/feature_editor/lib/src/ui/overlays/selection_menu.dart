// lib/src/ui/overlays/selection_menu.dart — 04-editor 6.6.5 (selection menu);
// (v2) m5-7/04-editor 6.7.1 (items), 6.7.2 ('색 ●' → the recolor popup),
// 6.7.3 (cut · copy · delete · duplicate).
import 'dart:async';
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

import '../../commands/extension_runner.dart';
import '../../di/editor_extensions.dart';
import '../../scope/editor_scope.dart';
import '../../state/popup.dart';
import '../../text/text_edit_session.dart';
import '../../tools/selection.dart';
import '../../tools/selection_menu_model.dart';
import '../editor_strings.dart';
import 'selection_frame_painter.dart' show selectionRepaint;

/// A rounded bar 8 px above the selection frame (below it when there is no
/// room). (v2, 6.7.1) [잘라내기] [복사] [삭제] [색 ●] [확장 항목 ≤ 2] [⋯]; '⋯'
/// (더보기) opens 복제 · 90° 돌리기 · (단일 텍스트) 편집 · 넘친 확장 항목 · 선택
/// 해제. Hidden while the selection is dragged. A sibling of the page area's Listener (6.4.3), so its taps
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

  /// (v2, appendix C) An extension item (bar or '⋯'): `editor.ext.<id>`.
  static ValueKey<String> extensionKey(String id) => ValueKey('editor.ext.$id');

  /// (v2, 6.7.1) Extension items on the bar at most; the rest go to '⋯'.
  static const int maxBarItems = 2;

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
///
/// (v2, E2-07c — 6.7.4) The extension items (EditorExtensions.
/// selectionMenuItems, duplicate ids dropped): at most 2 on the bar (list
/// order), the rest in '⋯' before 선택 해제 — and fewer on the bar when it
/// would be wider than the page area. Each is shown when its isVisible
/// (called at every build with this build's EditorSelectionContext) says so;
/// an isVisible exception hides the item and is reported once per menu
/// opening and item. A press runs it through ExtensionRunner.run: onSelected
/// starts synchronously with the editor body's context and a context made
/// at the press, then the '⋯' menu closes and the bar hides until the item
/// has finished (or the selection changes).
class _SelectionBar extends ConsumerStatefulWidget {
  const _SelectionBar({required this.selection});

  final EditorSelection selection;

  @override
  ConsumerState<_SelectionBar> createState() => _SelectionBarState();
}

class _SelectionBarState extends ConsumerState<_SelectionBar> {
  final MenuController _more = MenuController();

  /// Hidden for a running extension item (6.7.4 — the menu closes after the
  /// item started).
  bool _hidden = false;

  /// Items whose isVisible threw during this menu opening (reported once).
  final Set<String> _visibleErrors = {};

  @override
  void didUpdateWidget(_SelectionBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final a = oldWidget.selection, b = widget.selection;
    if (a.pageId != b.pageId ||
        !const SetEquality<String>().equals(a.elementIds, b.elementIds)) {
      // Another selection: a new menu opening.
      _hidden = false;
      _visibleErrors.clear();
    }
  }

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

  /// 4.3.1: the context is made now (a value copy), onSelected starts
  /// synchronously inside this onPressed, then the menus close.
  void _runExtension(EditorSelectionMenuItem item) {
    final selection = ref.read(editorCommandsProvider).selectionContext();
    if (selection == null) return;
    final done = ref
        .read(editorExtensionRunnerProvider)
        .run<void>(
          item.id,
          (body) => item.onSelected(body, selection),
          close: _closeForExtension,
        );
    unawaited(
      done.whenComplete(() {
        if (mounted && _hidden) setState(() => _hidden = false);
      }),
    );
  }

  void _closeForExtension() {
    if (_more.isOpen) _more.close();
    if (mounted) setState(() => _hidden = true);
  }

  /// The visible extension items for [selection] (6.7.4 — none without a
  /// context: no loaded page).
  List<EditorSelectionMenuItem> _visibleItems(
    List<EditorSelectionMenuItem> items,
    EditorSelectionContext? selection,
  ) {
    if (selection == null) return const [];
    return [
      for (final item in items)
        if (ExtensionRunner.visible(
          item,
          selection,
          onError: (error, stack) {
            if (_visibleErrors.add(item.id)) {
              ExtensionRunner.reportVisibleError(item.id, error, stack);
            }
          },
        ))
          item,
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (_hidden) return const SizedBox.shrink();
    final selection = widget.selection;
    final readOnly = ref.watch(editorReadOnlyProvider);
    final commands = ref.watch(editorCommandsProvider);
    final session = ref.watch(editorSessionValueProvider);
    final pages = ref.watch(editorMountedPagesProvider);
    final runner = ref.watch(editorExtensionRunnerProvider);
    final slotItems = runner.withoutDuplicates(
      ref.watch(editorExtensionsProvider).selectionMenuItems,
      (item) => item.id,
    );
    final mount = pages[selection.pageId];
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ListenableBuilder(
      listenable: Listenable.merge([pages, ?mount?.contentChanges]),
      builder: (context, _) => LayoutBuilder(
        builder: (context, constraints) {
          final model = SelectionMenuModel.of(
            session.pageIfLoaded(selection.pageId),
            selection.elementIds,
          );
          final single = model.single;
          final extensions = _visibleItems(
            slotItems,
            slotItems.isEmpty ? null : commands.selectionContext(),
          );
          final onBar = _BarWidth.fit(
            context,
            maxWidth: constraints.maxWidth,
            builtIn: [
              EditorStrings.selectionCut,
              EditorStrings.selectionCopy,
              EditorStrings.selectionDelete,
              if (model.canRecolor) EditorStrings.selectionColor,
            ],
            colourDot: model.canRecolor,
            extensions: [
              for (final item in extensions.take(SelectionMenu.maxBarItems))
                item.label,
            ],
          );
          final barItems = extensions.take(onBar).toList();
          final overflow = extensions.skip(onBar).toList();
          final row = Row(
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
                        const SizedBox(width: _BarWidth.dotGap),
                        Container(
                          key: SelectionMenu.colorDotKey,
                          width: _BarWidth.dot,
                          height: _BarWidth.dot,
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
              // Extension items stay enabled on a read-only note (6.7.1 —
              // a refused execute is the item's to explain).
              for (final item in barItems)
                TextButton.icon(
                  key: SelectionMenu.extensionKey(item.id),
                  onPressed: () => _runExtension(item),
                  icon: Icon(item.icon),
                  label: Text(item.label),
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
                  for (final item in overflow)
                    _MoreItem(
                      key: SelectionMenu.extensionKey(item.id),
                      icon: item.icon,
                      label: item.label,
                      onPressed: () => _runExtension(item),
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
          );
          return Material(
            color: scheme.surfaceContainerHigh,
            elevation: 3,
            shape: const StadiumBorder(),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: _BarWidth.padding,
              ),
              // The width estimate's safety net: never an overflow.
              child: FittedBox(fit: BoxFit.scaleDown, child: row),
            ),
          );
        },
      ),
    );
  }
}

/// Width estimate of the bar (6.7.1 — extension items move to '⋯' first
/// when the bar would be wider than the page area). Material 3 button
/// metrics: a TextButton is its label (labelLarge) + 2 × 12 px, at least
/// 64 px; with an icon + 18 px icon, 8 px gap, 12 + 16 px padding; the
/// IconButton 48 px.
abstract final class _BarWidth {
  static const double padding = 6;
  static const double dot = 14;
  static const double dotGap = 6;
  static const double _iconButton = 48;

  static double _label(BuildContext context, String text) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: Theme.of(context).textTheme.labelLarge),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  static double _textButton(double label) => math.max(64, label + 24);

  /// How many of [extensions] (labels, at most SelectionMenu.maxBarItems)
  /// fit on the bar within [maxWidth].
  static int fit(
    BuildContext context, {
    required double maxWidth,
    required List<String> builtIn,
    required bool colourDot,
    required List<String> extensions,
  }) {
    if (extensions.isEmpty || !maxWidth.isFinite) return extensions.length;
    var width = 2 * padding + _iconButton;
    for (final label in builtIn) {
      width += _textButton(_label(context, label));
    }
    if (colourDot) width += dot + dotGap;
    var count = 0;
    for (final label in extensions) {
      width += math.max(64, _label(context, label) + 18 + 8 + 12 + 16);
      if (width > maxWidth) break;
      count++;
    }
    return count;
  }
}

/// One row of the '⋯' menu: at least 44 px high (contract 7.4.8). Its
/// [onPressed] runs synchronously in the tap (MenuItemButton would delay it
/// to the next frame, after the menu closed), so an extension item starts
/// inside the user activation (4.3.1).
class _MoreItem extends StatelessWidget {
  const _MoreItem({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final style = TextButton.styleFrom(
      alignment: AlignmentDirectional.centerStart,
      minimumSize: const Size(160, 44),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      shape: const RoundedRectangleBorder(),
    );
    final icon = this.icon;
    return icon == null
        ? TextButton(onPressed: onPressed, style: style, child: Text(label))
        : TextButton.icon(
            onPressed: onPressed,
            style: style,
            icon: Icon(icon),
            label: Text(label),
          );
  }
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
