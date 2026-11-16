// lib/src/ui/chrome/floating_layer.dart — 04-editor 19: the floating buttons
// over the page area — the restore pill while the top menu is hidden, the pen
// palette while it is detached.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui_kit/ui_kit.dart';

import '../../state/note_search.dart';
import '../../state/settings/editor_device_state.dart';
import '../editor_strings.dart';
import '../toolbar/editor_toolbar.dart';
import '../toolbar/undo_redo_buttons.dart';
import 'editor_chrome.dart';
import 'editor_layout.dart';
import 'pen_palette.dart';

/// Stack over [child] (the PageViewport): only the floating buttons take
/// pointers, everything else reaches the page. Positions are stored as
/// fractions of the room they move in (EditorDeviceState), so a rotation or
/// resize keeps them inside this box (inside the SafeArea).
///
/// (v2.16-ui — 04-editor 24.2) In 미니멀 also the floating toolbar pill
/// (EditorShellScope.floatingBar), [barTop] under the top edge, centred,
/// at most the area's width less [barSideMargin] on each side; the palette
/// stays below its strip ([barZoneHeight]) as it does below the restore
/// pill's.
class EditorFloatingLayer extends ConsumerWidget {
  const EditorFloatingLayer({super.key, required this.child});

  final Widget child;

  static const barKey = ValueKey('editor.floatingBar');

  /// The pill's gap to the top edge and to the sides of the page area.
  static const double barTop = 8;
  static const double barSideMargin = 12;

  /// The strip the floating pill covers (its gap, its height, a gap under
  /// it): ViewportController.topInset in 미니멀.
  static double barZoneHeight(BuildContext context) =>
      barTop + EditorToolbar.heightOf(context) + 8;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hidden = ref.watch(
      editorDeviceStateProvider.select((s) => s.toolbarHidden),
    );
    final detached = ref.watch(
      editorDeviceStateProvider.select((s) => s.paletteDetached),
    );
    final bar = EditorShellScope.floatingBarOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final area = constraints.biggest;
        return Stack(
          fit: StackFit.expand,
          children: [
            child,
            if (detached)
              PenPalette(
                area: area,
                // The palette never covers the restore pill (nor the
                // floating bar).
                topInset: hidden
                    ? MenuRestorePill.zoneHeight
                    : bar != null
                    ? barZoneHeight(context)
                    : 0,
              ),
            if (bar != null)
              Positioned(
                key: barKey,
                top: barTop,
                left: barSideMargin,
                right: barSideMargin,
                child: bar,
              ),
            if (hidden) MenuRestorePill(area: area),
          ],
        );
      },
    );
  }
}

/// [↶] [↷] │ [🔍] │ [⌄ 메뉴 보이기] ((v2.14-ui, UI stage 1) undo and redo
/// side by side, the way back to the menu last) at the top edge while the
/// menu is hidden,
/// semi-transparent, 48 dp targets. It covers that strip of the page (a
/// stroke starting on it reaches the pill, not the page — drag the pill
/// aside to write there). Tap the middle → the menu comes back; drag it sideways
/// → it moves along the top edge (remembered — restorePillX). Undo / redo
/// and '노트에서 찾기' (04-editor 19.1 — the toolbar [🔍] and [⋯] are hidden
/// too) stay reachable without the toolbar.
class MenuRestorePill extends ConsumerStatefulWidget {
  const MenuRestorePill({super.key, required this.area});

  /// The page area the pill sits in.
  final Size area;

  static const pillKey = ValueKey('editor.restorePill');
  static const showKey = ValueKey('editor.restorePill.show');

  /// (19.1) [🔍] '노트에서 찾기' (toggles, like the toolbar button).
  static const searchKey = ValueKey('editor.restorePill.search');

  /// 48 dp touch targets: it is the only way back to the menu and the only
  /// undo / redo while the menu is hidden.
  static const double height = 48;

  /// (v2.14-ui) The │ between the groups.
  static const double dividerWidth = 9;
  static const double width =
      48 + 48 + dividerWidth + 48 + dividerWidth + 56 + 8;

  /// (19.1) Without [🔍]: the width in a page area narrower than [width]
  /// (the search panel open on a narrow screen — Slide Over 320 px leaves
  /// the pages about 176 px). The panel's own close and back still close
  /// the search there.
  static const double compactWidth = width - 48 - dividerWidth;

  /// The pill's width in a page area [areaWidth] wide.
  static double widthFor(double areaWidth) =>
      areaWidth >= width ? width : compactWidth;

  /// Semi-transparent so the top of the page shows through.
  static const double opacity = 0.7;
  static const double top = 6;

  /// The strip the pill can be in (the palette stays below it).
  static const double zoneHeight = top + height + 6;

  @override
  ConsumerState<MenuRestorePill> createState() => _MenuRestorePillState();
}

class _MenuRestorePillState extends ConsumerState<MenuRestorePill> {
  /// The fraction while a drag runs (stored when it ends).
  double? _dragX;

  double get _width => MenuRestorePill.widthFor(widget.area.width);

  double get _room => (widget.area.width - _width).clamp(0.0, double.infinity);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final stored = ref.watch(
      editorDeviceStateProvider.select((s) => s.restorePillX),
    );
    final x = _dragX ?? stored;
    return Positioned(
      key: MenuRestorePill.pillKey,
      left: x * _room,
      top: MenuRestorePill.top,
      width: _width,
      height: MenuRestorePill.height,
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        child: Material(
          color: scheme.surfaceContainerHigh.withValues(
            alpha: MenuRestorePill.opacity,
          ),
          elevation: 2,
          shape: const StadiumBorder(),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const UndoRedoButtons(compact: true, part: UndoRedoPart.undo),
                const UndoRedoButtons(compact: true, part: UndoRedoPart.redo),
                const _PillDivider(),
                if (_width == MenuRestorePill.width) ...const [
                  _PillSearchButton(),
                  _PillDivider(),
                ],
                Expanded(
                  child: Semantics(
                    container: true,
                    button: true,
                    label: EditorStrings.showMenu,
                    child: GestureDetector(
                      key: MenuRestorePill.showKey,
                      behavior: HitTestBehavior.opaque,
                      onTap: () => EditorChrome.showMenu(ref),
                      onHorizontalDragStart: (_) => setState(() => _dragX = x),
                      onHorizontalDragUpdate: (d) {
                        if (_room <= 0) return;
                        setState(
                          () => _dragX = ((_dragX ?? x) + d.delta.dx / _room)
                              .clamp(0.0, 1.0),
                        );
                      },
                      onHorizontalDragEnd: (_) => _endDrag(),
                      onHorizontalDragCancel: _endDrag,
                      child: Icon(
                        Icons.expand_more,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _endDrag() {
    final x = _dragX;
    if (x == null) return;
    ref.read(editorDeviceStateProvider.notifier).setRestorePillX(x);
    setState(() => _dragX = null);
  }
}

/// (v2.14-ui) The pill's │.
class _PillDivider extends StatelessWidget {
  const _PillDivider();

  @override
  Widget build(BuildContext context) => Center(
    child: SizedBox(
      height: 24,
      child: VerticalDivider(
        width: MenuRestorePill.dividerWidth,
        color: Theme.of(context).colorScheme.outlineVariant,
      ),
    ),
  );
}

/// (19.1) The pill's [🔍]: the in-note search stays reachable while the
/// menu is hidden (selected while the panel is open).
class _PillSearchButton extends ConsumerWidget {
  const _PillSearchButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final open = ref.watch(editorNoteSearchProvider.select((s) => s.isOpen));
    return IconButton(
      key: MenuRestorePill.searchKey,
      isSelected: open,
      iconSize: 20, // like the pill's [↶] [↷]
      onPressed: ref.read(editorNoteSearchProvider.notifier).toggle,
      icon: const AppIcon(
        AppIconKind.search,
        size: 20,
        semanticLabel: EditorStrings.noteSearch,
      ),
    );
  }
}
