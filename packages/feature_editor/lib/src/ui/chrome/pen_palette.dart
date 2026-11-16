// lib/src/ui/chrome/pen_palette.dart — 04-editor 19: the detached preset row
// as a floating palette. (v2.15-ui — 22.5) The preset row is the toolbar's
// pen tray now: the palette is that tray, floating.
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui_kit/ui_kit.dart';

import '../../state/popup.dart';
import '../../state/preset_bar.dart';
import '../../state/settings/editor_device_state.dart';
import '../../tools/tool_controller.dart';
import '../../tools/tool_state.dart';
import '../editor_strings.dart';
import '../pen/pen_art_view.dart';
import '../pen/pen_tray.dart';
import 'editor_chrome.dart';

/// A round 48 dp button showing the current pen (its drawing in its ink
/// colour on the tray's well; an accent ring while the pen tool is active)
/// that can be
/// dragged anywhere in the page area (finger, stylus or mouse — a move past
/// the touch slop is a drag, otherwise a tap). Its place is stored as
/// fractions of the room (EditorDeviceState.palettePosition) and clamped
/// [margin] inside the area and below [topInset] (the inset clamps, it does
/// not scale the fractions — so a button low on the screen stays put when
/// the menu hides or shows).
///
/// Tap → the palette opens beside it, toward the side with more room: the
/// pen tray (PenTray — the same pens, eraser, taps and long presses as in
/// the toolbar; as many pens as the room takes, up to 8) and '메뉴에 다시
/// 붙이기' (a labelled button — 6.9.1 keeps tooltips off). Switching pens
/// closes the palette. A pointer down anywhere else (TapRegion outside — the
/// page still gets it, so a pen stroke draws) or system back closes it (open
/// / closed is editorPaletteExpandedProvider); while a popup opened from it
/// (the picker, the quick pen, the eraser's) shows, it stays open and closes
/// with that popup. Read-only note: the tray is
/// disabled (like in the toolbar).
class PenPalette extends ConsumerStatefulWidget {
  const PenPalette({super.key, required this.area, this.topInset = 0});

  /// The page area the palette moves in.
  final Size area;

  /// Room kept free at the top (the restore pill's strip).
  final double topInset;

  static const double size = 48;
  static const double margin = 8;

  static const buttonKey = ValueKey('editor.palette.button');
  static const panelKey = ValueKey('editor.palette.panel');
  static const dockKey = ValueKey('editor.palette.dock');

  /// The button's top-left in the area for the stored [fractions], kept
  /// below [topInset].
  static Offset buttonOffset(Size area, double topInset, Offset fractions) {
    final room = roomOf(area);
    return clampOffset(
      area,
      topInset,
      Offset(
        margin + fractions.dx.clamp(0.0, 1.0) * room.width,
        margin + fractions.dy.clamp(0.0, 1.0) * room.height,
      ),
    );
  }

  /// [at] (a top-left) moved [margin] inside the area and below [topInset].
  static Offset clampOffset(Size area, double topInset, Offset at) {
    final room = roomOf(area);
    final minY = topInset + margin;
    final maxY = math.max(minY, margin + room.height);
    return Offset(
      at.dx.clamp(margin, margin + room.width),
      at.dy.clamp(minY, maxY),
    );
  }

  /// The fractions of the room for the top-left [at].
  static Offset fractionsOf(Size area, Offset at) {
    final room = roomOf(area);
    return Offset(
      room.width <= 0 ? 0 : ((at.dx - margin) / room.width).clamp(0.0, 1.0),
      room.height <= 0 ? 0 : ((at.dy - margin) / room.height).clamp(0.0, 1.0),
    );
  }

  /// The room the button's top-left can move in (never negative).
  static Size roomOf(Size area) => Size(
    math.max(0, area.width - size - 2 * margin),
    math.max(0, area.height - size - 2 * margin),
  );

  @override
  ConsumerState<PenPalette> createState() => _PenPaletteState();
}

class _PenPaletteState extends ConsumerState<PenPalette> {
  final Object _group = Object();

  /// The fractions while a drag runs (stored when it ends).
  Offset? _drag;

  EditorPaletteExpandedNotifier get _expanded =>
      ref.read(editorPaletteExpandedProvider.notifier);

  void _collapse() => _expanded.set(false);

  /// (v2.15-ui review) A pointer down outside the palette: it stays open
  /// while a popup it opened is showing (the pointer is on that popup or
  /// its barrier — collapsing would unmount the tray the popup hangs
  /// from); it closes with that popup instead.
  void _outside(PointerDownEvent _) {
    if (ref.read(editorPopupProvider) != null) return;
    _collapse();
  }

  void _dragBy(Offset delta, Offset from) {
    final area = widget.area;
    final at = PenPalette.buttonOffset(area, widget.topInset, _drag ?? from);
    final moved = PenPalette.clampOffset(area, widget.topInset, at + delta);
    setState(() => _drag = PenPalette.fractionsOf(area, moved));
  }

  void _endDrag() {
    final f = _drag;
    if (f == null) return;
    ref.read(editorDeviceStateProvider.notifier).setPalettePosition(f);
    setState(() => _drag = null);
  }

  @override
  Widget build(BuildContext context) {
    final stored = ref.watch(
      editorDeviceStateProvider.select((s) => s.palettePosition),
    );
    final expanded = ref.watch(editorPaletteExpandedProvider);
    ref.listen(editorPopupProvider, (before, now) {
      if (before != null &&
          now == null &&
          ref.read(editorPaletteExpandedProvider)) {
        _collapse();
      }
    });
    final fractions = _drag ?? stored;
    final at = PenPalette.buttonOffset(widget.area, widget.topInset, fractions);
    final button = Rect.fromLTWH(
      at.dx,
      at.dy,
      PenPalette.size,
      PenPalette.size,
    );
    return Positioned.fill(
      child: Stack(
        children: [
          Positioned.fromRect(
            rect: button,
            child: TapRegion(
              groupId: _group,
              onTapOutside: _outside,
              child: GestureDetector(
                key: PenPalette.buttonKey,
                behavior: HitTestBehavior.opaque,
                onTap: () => _expanded.set(!expanded),
                onPanStart: (_) => setState(() => _drag = fractions),
                onPanUpdate: (d) => _dragBy(d.delta, fractions),
                onPanEnd: (_) => _endDrag(),
                onPanCancel: _endDrag,
                child: _PaletteButton(expanded: expanded),
              ),
            ),
          ),
          if (expanded)
            Positioned.fill(
              child: CustomSingleChildLayout(
                delegate: _PanelLayout(
                  button: button,
                  topInset: widget.topInset,
                ),
                child: TapRegion(
                  groupId: _group,
                  onTapOutside: _outside,
                  child: _PalettePanel(
                    maxWidth: widget.area.width - 2 * PenPalette.margin,
                    maxHeight: math.max(
                      PenPalette.size,
                      widget.area.height -
                          widget.topInset -
                          2 * PenPalette.margin,
                    ),
                    onDone: _collapse,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The panel beside the button, toward the side with more room; its top at
/// the button's top, moved up / sideways to stay [PenPalette.margin] inside
/// the area (and below the top inset).
class _PanelLayout extends SingleChildLayoutDelegate {
  const _PanelLayout({required this.button, required this.topInset});

  final Rect button;
  final double topInset;

  static const double gap = 8;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size child) {
    const m = PenPalette.margin;
    final toRight = button.center.dx <= size.width / 2;
    final wantX = toRight
        ? button.right + gap
        : button.left - gap - child.width;
    final maxX = size.width - child.width - m;
    final x = maxX <= m ? m : wantX.clamp(m, maxX);
    final minY = topInset + m;
    final maxY = size.height - child.height - m;
    final y = maxY <= minY ? minY : button.top.clamp(minY, maxY);
    return Offset(x.toDouble(), y.toDouble());
  }

  @override
  bool shouldRelayout(_PanelLayout old) =>
      old.button != button || old.topInset != topInset;
}

class _PaletteButton extends ConsumerWidget {
  const _PaletteButton({required this.expanded});

  final bool expanded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = StyleTokens.of(context);
    final look = PenTrayStyle.of(tokens);
    final tools = ref.watch(editorToolProvider);
    final pen = tools.currentPen;
    final penActive = tools.activeTool == EditorTool.pen;
    return Semantics(
      container: true,
      button: true,
      expanded: expanded,
      label: EditorStrings.paletteButton(penLabelOf(pen), expanded: expanded),
      child: Material(
        color: look.hasWell ? look.wellBottom : tokens.popover,
        elevation: expanded ? 6 : 3,
        shape: CircleBorder(
          side: penActive
              ? BorderSide(color: tokens.accent, width: 2)
              : BorderSide(
                  color: look.hasWell ? look.wellBorder : tokens.hairline,
                ),
        ),
        clipBehavior: Clip.antiAlias,
        child: ExcludeSemantics(
          child: look.hasWell
              ? Stack(
                  children: [
                    Positioned(
                      left: (PenPalette.size - 20) / 2,
                      top: 6,
                      child: PenArt.of(
                        pen,
                        width: 20,
                        height: 62,
                        rimLight: look.rimLight,
                      ),
                    ),
                  ],
                )
              : Center(
                  child: InkStroke(
                    style: swatchStyleOf(pen, max: 3.2),
                    size: const Size(28, 16),
                  ),
                ),
        ),
      ),
    );
  }
}

class _PalettePanel extends ConsumerWidget {
  const _PalettePanel({
    required this.maxWidth,
    required this.maxHeight,
    required this.onDone,
  });

  /// (19.1) The room across: the page area narrowed by the search panel can
  /// be narrower than the whole tray.
  final double maxWidth;
  final double maxHeight;
  final VoidCallback onDone;

  /// The panel's padding on each side.
  static const double padding = 8;

  /// (v2.15-ui) The tray's pens that fit [maxWidth] (1–8). [shownFor] is
  /// the slots a capacity takes (one more for '지금 펜' — trayPensOf).
  static int pensIn(double maxWidth, {int Function(int capacity)? shownFor}) {
    var pens = kTrayMaxPens;
    while (pens > 1 &&
        PenTray.widthFor(shownFor?.call(pens) ?? pens) + 2 * padding >
            maxWidth) {
      pens--;
    }
    return pens;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = StyleTokens.of(context);
    final presets = ref.watch(editorTrayPresetsProvider).value ?? const [];
    final current = ref.watch(editorToolProvider.select((s) => s.currentPen));
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: EditorStrings.palette,
      child: Material(
        key: PenPalette.panelKey,
        elevation: 6,
        color: tokens.popover,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(padding, 12, padding, 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                PenTray(
                  capacity: pensIn(
                    maxWidth,
                    shownFor: (c) =>
                        trayPensOf(presets, current, c).pens.length,
                  ),
                  onPicked: onDone,
                ),
                const SizedBox(height: 4),
                // Labelled (no tooltips — 6.9.1): putting the tray back
                // has to read as such from the palette itself.
                TextButton.icon(
                  key: PenPalette.dockKey,
                  onPressed: () {
                    onDone();
                    EditorChrome.dockPalette(ref);
                  },
                  icon: const Icon(Icons.vertical_align_top, size: 18),
                  label: const Text(
                    EditorStrings.dockPalette,
                    textAlign: TextAlign.center,
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
