// lib/src/ui/chrome/floating_layer.dart — 04-editor 17: the floating buttons
// over the page area — the restore pill while the top menu is hidden, the pen
// palette while it is detached.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../state/settings/editor_device_state.dart';
import '../editor_strings.dart';
import '../toolbar/undo_redo_buttons.dart';
import 'editor_chrome.dart';
import 'pen_palette.dart';

/// Stack over [child] (the PageViewport): only the floating buttons take
/// pointers, everything else reaches the page. Positions are stored as
/// fractions of the room they move in (EditorDeviceState), so a rotation or
/// resize keeps them inside this box (inside the SafeArea).
class EditorFloatingLayer extends ConsumerWidget {
  const EditorFloatingLayer({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hidden = ref.watch(
      editorDeviceStateProvider.select((s) => s.toolbarHidden),
    );
    final detached = ref.watch(
      editorDeviceStateProvider.select((s) => s.paletteDetached),
    );
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
                // The palette never covers the restore pill.
                topInset: hidden ? MenuRestorePill.zoneHeight : 0,
              ),
            if (hidden) MenuRestorePill(area: area),
          ],
        );
      },
    );
  }
}

/// [↶] [⌄ 메뉴 보이기] [↷] at the top edge while the menu is hidden,
/// semi-transparent, 48 dp targets. It covers that strip of the page (a
/// stroke starting on it reaches the pill, not the page — drag the pill
/// aside to write there). Tap the middle → the menu comes back; drag it sideways
/// → it moves along the top edge (remembered — restorePillX). Undo / redo
/// stay reachable without the toolbar.
class MenuRestorePill extends ConsumerStatefulWidget {
  const MenuRestorePill({super.key, required this.area});

  /// The page area the pill sits in.
  final Size area;

  static const pillKey = ValueKey('editor.restorePill');
  static const showKey = ValueKey('editor.restorePill.show');

  /// 48 dp touch targets: it is the only way back to the menu and the only
  /// undo / redo while the menu is hidden.
  static const double height = 48;
  static const double width = 48 + 56 + 48 + 8;

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

  double get _room =>
      (widget.area.width - MenuRestorePill.width).clamp(0.0, double.infinity);

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
      width: MenuRestorePill.width,
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
                const UndoRedoButtons(compact: true, part: UndoRedoPart.redo),
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
