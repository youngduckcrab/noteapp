// lib/src/ui/chrome/pen_palette.dart — 04-editor 17: the detached preset row
// as a floating palette.
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

import '../../scope/editor_scope.dart';
import '../../state/popup.dart';
import '../../state/preset_bar.dart';
import '../../state/settings/editor_device_state.dart';
import '../../tools/tool_controller.dart';
import '../../tools/tool_state.dart';
import '../editor_strings.dart';
import '../presets/preset_chip.dart';
import '../toolbar/editor_toolbar.dart' show penTypeIcon;
import 'editor_chrome.dart';

/// A round 48 dp button showing the current pen (its colour with the pen
/// type's icon; a primary ring while the pen tool is active) that can be
/// dragged anywhere in the page area (finger, stylus or mouse — a move past
/// the touch slop is a drag, otherwise a tap). Its place is stored as
/// fractions of the room (EditorDeviceState.palettePosition) and clamped
/// [margin] inside the area and below [topInset] (the inset clamps, it does
/// not scale the fractions — so a button low on the screen stays put when
/// the menu hides or shows).
///
/// Tap → the palette opens beside it, toward the side with more room: the
/// same presets as the preset row (editorVisiblePresetsProvider — pinned,
/// group filter, CORE order) as PresetChips (the current one bordered), then
/// [+] save the current pen (SavePresetDialog), [⚙] the manager sheet and
/// '메뉴에 다시 붙이기' (a labelled button — 6.9.1 keeps tooltips off). A chip → ToolController.applyStyle (also switches to
/// the pen tool), the palette closes. A pointer down anywhere else (TapRegion
/// outside — the page still gets it, so a pen stroke draws) or system back
/// closes it (open / closed is editorPaletteExpandedProvider).
/// Read-only note: chips, [+] and [⚙] are disabled (like the row).
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
  static const addKey = ValueKey('editor.palette.add');
  static const manageKey = ValueKey('editor.palette.manage');
  static const dockKey = ValueKey('editor.palette.dock');
  static const emptyKey = ValueKey('editor.palette.empty');
  static ValueKey<String> chipKey(String id) =>
      ValueKey('editor.palette.chip.$id');

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
              onTapOutside: (_) => _collapse(),
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
                  onTapOutside: (_) => _collapse(),
                  child: _PalettePanel(
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
    final scheme = Theme.of(context).colorScheme;
    final tools = ref.watch(editorToolProvider);
    final pen = tools.currentPen;
    final color = Color(pen.colorArgb).withValues(alpha: pen.opacity);
    final shown = Color.alphaBlend(color, scheme.surface);
    final penActive = tools.activeTool == EditorTool.pen;
    return Semantics(
      container: true,
      button: true,
      expanded: expanded,
      label: EditorStrings.paletteButton(
        EditorStrings.penTypeName(tools.penType),
        expanded: expanded,
      ),
      child: Material(
        color: scheme.surfaceContainerHigh.withValues(alpha: 0.95),
        elevation: expanded ? 6 : 3,
        shape: CircleBorder(
          side: penActive
              ? BorderSide(color: scheme.primary, width: 2)
              : BorderSide(color: scheme.outlineVariant),
        ),
        child: Center(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              // A full outline ring: a dark pen on a dark theme's surface
              // still shows its edge.
              border: Border.all(color: scheme.outline),
            ),
            child: SizedBox.square(
              dimension: 30,
              child: Icon(
                penTypeIcon(tools.penType),
                size: 18,
                color: PresetChip.dotColorOn(shown, scheme),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PalettePanel extends ConsumerWidget {
  const _PalettePanel({required this.maxHeight, required this.onDone});

  final double maxHeight;
  final VoidCallback onDone;

  /// Columns of chips: 3 up to 6 presets, then 4.
  static int columnsFor(int count) => count <= 6 ? 3 : 4;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final readOnly = ref.watch(editorReadOnlyProvider);
    final tools = ref.watch(editorToolProvider);
    final pen = tools.activeTool == EditorTool.pen ? tools.currentPen : null;
    final controller = ref.read(editorToolProvider.notifier);
    final popups = ref.read(editorPopupProvider.notifier);
    final list = ref.watch(editorVisiblePresetsProvider).value;
    final presets = list ?? const <core.PenPreset>[];
    final columns = columnsFor(presets.length);
    final width = columns * PresetChip.width;

    void open(EditorPopup popup) {
      onDone();
      popups.open(popup);
    }

    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: EditorStrings.palette,
      child: Material(
        key: PenPalette.panelKey,
        elevation: 6,
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(8),
            child: SizedBox(
              width: width,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
                    child: Text(
                      EditorStrings.palette,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (list != null && presets.isEmpty)
                    Padding(
                      key: PenPalette.emptyKey,
                      padding: const EdgeInsets.all(4),
                      child: Text(
                        EditorStrings.presetEmpty,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  else
                    Wrap(
                      children: [
                        for (final p in presets)
                          PresetChip(
                            key: PenPalette.chipKey(p.id),
                            preset: p,
                            active: pen != null && p.style == pen,
                            onTap: readOnly
                                ? null
                                : () {
                                    controller.applyStyle(p.style);
                                    onDone();
                                  },
                          ),
                      ],
                    ),
                  const Divider(height: 9),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton(
                        key: PenPalette.addKey,
                        onPressed: readOnly
                            ? null
                            : () => open(const SavePresetPopup()),
                        icon: const Icon(
                          Icons.add,
                          semanticLabel: EditorStrings.presetAdd,
                        ),
                      ),
                      IconButton(
                        key: PenPalette.manageKey,
                        onPressed: readOnly
                            ? null
                            : () => open(const PresetManagerPopup()),
                        icon: const Icon(
                          Icons.tune,
                          semanticLabel: EditorStrings.presetManage,
                        ),
                      ),
                    ],
                  ),
                  // Labelled (no tooltips — 6.9.1): putting the row back
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
      ),
    );
  }
}
