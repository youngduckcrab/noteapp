// lib/src/ui/pen/pen_tray.dart — (v2.15-ui, UI stage 5 — m5-7/04-editor 23.3)
// The pen tray in the middle of the toolbar: it replaces the pen and eraser
// buttons and the preset row under the toolbar.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart'
    show PointerDeviceKind, PointerEnterEvent;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:ui_kit/ui_kit.dart';

import '../../di/editor_extensions.dart';
import '../../scope/editor_scope.dart';
import '../../state/popup.dart';
import '../../state/preset_bar.dart';
import '../../tools/tool_controller.dart';
import '../../tools/tool_state.dart';
import '../editor_strings.dart';
import '../popup_host.dart';
import '../toolbar/editor_toolbar.dart' show EditorToolbar;
import 'pen_art_view.dart';

/// One pen of the tray: a pinned preset, or the current pen when it is none
/// of them ([presetId] null — '지금 펜').
@immutable
class TrayPen {
  const TrayPen({required this.style, this.presetId});

  final core.StrokeStyle style;
  final String? presetId;

  bool get isLoose => presetId == null;
}

/// The pens [PenTray] shows for [presets] (the pinned ones, CORE order) and
/// the [current] pen: the first [capacity] presets; when [current] equals
/// none of them it stands after them as '지금 펜' — one slot more, so no
/// pinned pen is pushed out while a tray pen is being edited (the pinned
/// pens never shift when it comes and goes; the toolbar plans for that
/// slot). Returns the pens and the index of the one that is [current].
({List<TrayPen> pens, int current}) trayPensOf(
  List<core.PenPreset> presets,
  core.StrokeStyle current,
  int capacity,
) {
  final cap = capacity.clamp(1, kTrayMaxPens);
  final shown = presets.take(cap).toList();
  final at = shown.indexWhere((p) => p.style == current);
  if (at < 0) {
    final pens = [
      for (final p in shown) TrayPen(style: p.style, presetId: p.id),
      TrayPen(style: current),
    ];
    return (pens: pens, current: pens.length - 1);
  }
  return (
    pens: [for (final p in shown) TrayPen(style: p.style, presetId: p.id)],
    current: at,
  );
}

/// The tray (04-editor 23.3): up to [capacity] pens standing in a recessed
/// well — pen drawings in the ink colour (크래프트, 스튜디오) or flat ink
/// stroke chips (미니멀; [PenTrayStyle]) — then the eraser at the right end.
/// The current pen (and the eraser while it is the tool) is lifted with a
/// shadow.
///
/// - Tap a pen → that pen (ToolController.applyStyle); tap the lifted pen →
///   the pen picker (PenSettingsPopup); tap '지금 펜' → the pen tool.
/// - Long press a pen → the quick pen next to it (QuickPenPopup with the
///   preset's id; a preset not in use is switched to first).
/// - Eraser: tap → the eraser; tap again / long press → the eraser popup.
/// - A hovering stylus or mouse shows "만년필 · 남색 2.2pt" under the pen.
/// - Read-only note: dimmed, nothing reacts (6.9.1).
///
/// The current pen's slot has [EditorToolbar.penKey], the eraser
/// [EditorToolbar.eraserKey]; the popups hang under the tray
/// (PopupAnchors.pen / penBox) and the eraser (PopupAnchors.eraser /
/// eraserBox). Those are GlobalKeys: only one tray is mounted at a time
/// (the toolbar's, or the floating palette's while it is detached).
///
/// (v2.15-ui review) Its height follows the style's toolbar
/// ([outerHeightOf]): in a 64 px 크래프트 bar the well is 56 px and about
/// 42 px of each drawing shows; a lifted pen rises ~11 px and stays inside
/// the bar.
///
/// (v2.16-ui — 04-editor 24) With [axis] vertical (스튜디오's left rail) the
/// slots stack top to bottom, the drawings lie pointing right (their backs
/// in the rail's left wall), the lifted pen slides out to the right, the
/// hover label and the popups open to the right of it.
class PenTray extends ConsumerWidget {
  const PenTray({
    super.key,
    required this.capacity,
    this.onPicked,
    this.axis = Axis.horizontal,
  });

  /// Most pens shown (the toolbar gives 8, 5 or 3 by its width).
  final int capacity;

  /// (v2.16-ui) Horizontal in a top bar or the palette; vertical in the
  /// rail.
  final Axis axis;

  bool get _vertical => axis == Axis.vertical;

  /// Called after a tap switched pens (the floating palette closes).
  final VoidCallback? onPicked;

  static const trayKey = ValueKey('editor.tray');

  /// The '지금 펜' slot (the current pen is not pinned).
  static const looseKey = ValueKey('editor.tray.current');
  static ValueKey<String> slotKey(String presetId) =>
      ValueKey('editor.tray.pen.$presetId');

  /// The hover label.
  static const hoverLabelKey = ValueKey('editor.tray.hoverLabel');

  /// One slot (≥ 44 × 44 — contract 7.4.8).
  static const double slotWidth = 44;

  /// The least slot height (the flat 미니멀 tray's).
  static const double height = 44;
  static const double _padding = 4;
  static const double _divider = 13;

  /// The tray's outer height in [tokens]' style: the toolbar height less
  /// 4 px above and below for a well (크래프트 56, 스튜디오 52), 46 for the
  /// flat tray.
  static double outerHeightOf(StyleTokens tokens) =>
      PenTrayStyle.of(tokens).hasWell
      ? math.max(height + 2, tokens.toolbarHeight - 8)
      : height + 2;

  /// The slot height inside the tray's 1 px rim.
  static double slotHeightOf(StyleTokens tokens) => outerHeightOf(tokens) - 2;

  /// How much of a resting drawing shows above the well's bottom.
  /// (owner review) The lifted pen rises up to 16 px, its tip out of the
  /// well — a clear "this one is in my hand", not a nudge.
  static const double _shown = 40;
  static const double _lift = 16;

  /// The drawing's top in its slot, resting / lifted (≥ -1: a lifted pen
  /// stays 4 px inside a bar 4 px taller than the tray on each side).
  static double downTopOf(double slotHeight) =>
      math.max(4, slotHeight - _shown);
  static double upTopOf(double slotHeight) =>
      math.max(-1, downTopOf(slotHeight) - _lift);

  /// The tray's width with [pens] pens and the eraser.
  static double widthFor(int pens) =>
      2 * _padding + 2 + pens * slotWidth + _divider + slotWidth;

  /// (v2.16-ui) A vertical tray's slot: [railSlotWidth] × [height].
  static const double railSlotWidth = 74;

  /// (v2.16-ui) The vertical tray's outer width (the slot and the rim).
  static const double railWidth = railSlotWidth + 2;

  /// (v2.16-ui) The vertical tray's height with [pens] pens and the eraser.
  static double heightFor(int pens) =>
      2 * _padding + 2 + pens * height + _divider + height;

  /// (v2.16-ui review) The ink strip under a vertical slot's drawing.
  static const double railInkHeight = 12;

  /// (v2.16-ui) How much of a lying drawing shows right of the rail's wall,
  /// resting / lifted (the tip; the back stays in the wall).
  static const double _railShown = 48;
  static double railLeftOf({required bool lifted}) =>
      (lifted ? _railShown + _lift : _railShown) - artSize.height;

  /// The drawing's size.
  static const Size artSize = Size(26, 80);

  /// The key on each slot's drawing (tests measure where it stands).
  static const artKey = ValueKey('editor.tray.art');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tools = ref.watch(editorToolProvider);
    final readOnly = ref.watch(editorReadOnlyProvider);
    final presets = ref.watch(editorTrayPresetsProvider).value ?? const [];
    final anchors = PopupHost.maybeAnchorsOf(context);
    // An open popup of the tray places itself again after this build.
    anchors?.scheduleTrayMoved();
    final tokens = StyleTokens.of(context);
    final look = PenTrayStyle.of(tokens);
    // (v2.15-ui review) A stored 수식 펜 / 텍스트 펜 without its slot draws
    // with the pen (InteractionHost) — the tray shows the pen as current.
    final hasMathPen = ref.watch(
      editorExtensionsProvider.select((e) => e.mathPen != null),
    );
    final hasTextPen = ref.watch(
      editorExtensionsProvider.select((e) => e.textPen != null),
    );
    final penActive = penToolActive(
      tools.activeTool,
      hasMathPen: hasMathPen,
      hasTextPen: hasTextPen,
    );
    final eraserActive = tools.activeTool == EditorTool.eraser;
    final (:pens, :current) = trayPensOf(presets, tools.currentPen, capacity);

    final slotHeight = _vertical ? height : slotHeightOf(tokens);
    final slots = <Widget>[
      for (var i = 0; i < pens.length; i++)
        _penSlot(
          context,
          ref,
          pens[i],
          i == current,
          penActive,
          look,
          slotHeight,
        ),
    ];
    Widget lying(Widget art) =>
        _vertical ? RotatedBox(quarterTurns: 1, child: art) : art;
    final eraser = CompositedTransformTarget(
      link: anchors?.eraser ?? LayerLink(),
      child: _TraySlot(
        boxKey: anchors?.eraserBox,
        slotHeight: slotHeight,
        key: EditorToolbar.eraserKey,
        axis: axis,
        lifted: eraserActive,
        look: look,
        label: EditorStrings.eraser,
        hint: null,
        hoverText: EditorStrings.eraser,
        onTap: () {
          if (eraserActive) {
            ref
                .read(editorPopupProvider.notifier)
                .open(const EraserSettingsPopup());
          } else {
            ref.read(editorCommandsProvider).selectTool(EditorTool.eraser);
            onPicked?.call();
          }
        },
        onLongPress: (_) => ref
            .read(editorPopupProvider.notifier)
            .open(const EraserSettingsPopup()),
        child: look.hasWell
            ? lying(
                EraserArt(
                  key: artKey,
                  width: artSize.width,
                  height: artSize.height,
                ),
              )
            : _FlatEraser(active: eraserActive, look: look),
      ),
    );

    // (v2.16-ui) A vertical well opens to the right: its recess shadow
    // runs down the right edge, the drawings' backs are clipped at the left.
    final wellBegin = _vertical ? Alignment.centerRight : Alignment.topCenter;
    final wellEnd = _vertical ? Alignment.centerLeft : Alignment.bottomCenter;
    final divider = Container(
      width: _vertical ? railSlotWidth - 14 : 1,
      height: _vertical ? 1 : slotHeight - 14,
      margin: _vertical
          ? const EdgeInsets.symmetric(vertical: 6)
          : const EdgeInsets.symmetric(horizontal: 6),
      color: look.divider,
    );
    final children = [...slots, divider, eraser];
    Widget tray = Container(
      key: trayKey,
      // The 1 px rim around the slots.
      height: _vertical ? null : slotHeight + 2,
      width: _vertical ? railWidth : null,
      padding: _vertical
          ? const EdgeInsets.symmetric(vertical: _padding)
          : const EdgeInsets.symmetric(horizontal: _padding),
      decoration: look.hasWell
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: LinearGradient(
                begin: wellBegin,
                end: wellEnd,
                colors: [look.wellTop, look.wellBottom],
              ),
              border: Border.all(color: look.wellBorder),
            )
          : null,
      foregroundDecoration: look.hasWell
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: LinearGradient(
                begin: wellBegin,
                end: wellEnd,
                colors: [
                  look.innerShadow,
                  look.innerShadow.withValues(alpha: 0),
                ],
                stops: const [0, .18],
              ),
            )
          : null,
      child: ClipRect(
        clipper: _vertical
            ? const _OpenRightClipper()
            : const _OpenTopClipper(),
        child: _vertical
            ? Column(mainAxisSize: MainAxisSize.min, children: children)
            : Row(mainAxisSize: MainAxisSize.min, children: children),
      ),
    );
    if (readOnly) {
      tray = IgnorePointer(
        child: ExcludeSemantics(child: Opacity(opacity: 0.38, child: tray)),
      );
    }
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: EditorStrings.penTray,
      child: _anchorBox(
        anchors?.penBox,
        CompositedTransformTarget(
          link: anchors?.pen ?? LayerLink(),
          child: tray,
        ),
        beside: _vertical,
      ),
    );
  }

  Widget _penSlot(
    BuildContext context,
    WidgetRef ref,
    TrayPen pen,
    bool isCurrent,
    bool penActive,
    PenTrayStyle look,
    double slotHeight,
  ) {
    final lifted = isCurrent && penActive;
    final controller = ref.read(editorToolProvider.notifier);
    final popups = ref.read(editorPopupProvider.notifier);
    final label = penLabelOf(pen.style);
    final slot = _TraySlot(
      key: pen.isLoose ? looseKey : slotKey(pen.presetId!),
      axis: axis,
      slotHeight: slotHeight,
      lifted: lifted,
      look: look,
      label: pen.isLoose ? '${EditorStrings.trayCurrentPen}, $label' : label,
      hint: lifted ? EditorStrings.trayActiveHint : EditorStrings.trayPenHint,
      hoverText: lifted ? '$label — ${EditorStrings.trayTapAgain}' : label,
      onTap: () {
        if (lifted) {
          popups.open(const PenSettingsPopup());
          return;
        }
        if (pen.isLoose) {
          ref.read(editorCommandsProvider).selectTool(EditorTool.pen);
        } else {
          controller.applyStyle(pen.style);
        }
        onPicked?.call();
      },
      onLongPress: (at) {
        if (!pen.isLoose && !isCurrent) controller.applyStyle(pen.style);
        popups.open(QuickPenPopup(globalPosition: at, presetId: pen.presetId));
      },
      inkStyle: _vertical && look.hasWell ? pen.style : null,
      child: look.hasWell
          ? (_vertical
                ? RotatedBox(
                    quarterTurns: 1,
                    child: PenArt.of(
                      pen.style,
                      key: artKey,
                      width: artSize.width,
                      height: artSize.height,
                      rimLight: look.rimLight,
                    ),
                  )
                : PenArt.of(
                    pen.style,
                    key: artKey,
                    width: artSize.width,
                    height: artSize.height,
                    rimLight: look.rimLight,
                  ))
          : _StrokeChip(style: pen.style, active: lifted, look: look),
    );
    return isCurrent
        ? KeyedSubtree(key: EditorToolbar.penKey, child: slot)
        : slot;
  }
}

/// Lets the lifted pen's tip stand out above the tray; clips the bottom.
class _OpenTopClipper extends CustomClipper<Rect> {
  const _OpenTopClipper();

  @override
  Rect getClip(Size size) =>
      Rect.fromLTRB(-40, -40, size.width + 40, size.height);

  @override
  bool shouldReclip(covariant CustomClipper<Rect> oldClipper) => false;
}

/// (v2.16-ui) The vertical tray's: the lifted pen's tip stands out to the
/// right; the drawings' backs are clipped at the rail's wall.
class _OpenRightClipper extends CustomClipper<Rect> {
  const _OpenRightClipper();

  @override
  Rect getClip(Size size) =>
      Rect.fromLTRB(0, -40, size.width + 40, size.height + 40);

  @override
  bool shouldReclip(covariant CustomClipper<Rect> oldClipper) => false;
}

/// Whether the pen tool is the one drawing for [active]: the pen, or a
/// stored 수식 펜 / 텍스트 펜 whose slot is missing (it draws with the pen).
bool penToolActive(
  EditorTool active, {
  required bool hasMathPen,
  required bool hasTextPen,
}) =>
    active == EditorTool.pen ||
    (active == EditorTool.math && !hasMathPen) ||
    (active == EditorTool.textPen && !hasTextPen);

/// The calm look: the real stroke, flat on the bar (no plate — a dark ink in
/// a dark style gets a small paper-light plate, a pale ink on a light bar a
/// hairline edge); the active chip has a soft box and the underline.
class _StrokeChip extends StatelessWidget {
  const _StrokeChip({
    required this.style,
    required this.active,
    required this.look,
  });

  final core.StrokeStyle style;
  final bool active;
  final PenTrayStyle look;

  /// The chip is a sign, not the real stroke: a pale highlighter /
  /// watercolour shows at least this opaque.
  static const double _minOpacity = .75;

  @override
  Widget build(BuildContext context) {
    final tokens = StyleTokens.of(context);
    final inkColor = penArtColorOf(style);
    var shown = swatchStyleOf(style, max: 3.2);
    if (shown.opacity < _minOpacity) {
      shown = shown.copyWith(opacity: _minOpacity);
    }
    const size = Size(32, 20);
    // The highlighter's stroke multiplies with what is under it: it needs
    // the paper-light plate on a dark bar, and no edge stroke under it.
    final multiplies = style.tool == core.PenTool.highlighter;
    final plate =
        look.needsPlate(inkColor) || (multiplies && look.chipPlate.a > 0);
    final stroke = InkStroke(
      style: shown,
      size: size,
      shape: ink.PenPreviewShape.sCurve,
    );
    return SizedBox(
      key: PenTray.artKey,
      width: 40,
      height: 36,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 40,
            height: 32,
            decoration: BoxDecoration(
              color: active ? look.chipActiveFill : look.chipFill,
              borderRadius: BorderRadius.circular(9),
            ),
            alignment: Alignment.center,
            // (v2.16-ui review) A dark ink's plate is a soft capsule just
            // behind the stroke, not a bright tile (five of them shouted on
            // the dark pill).
            child: plate
                ? DecoratedBox(
                    decoration: BoxDecoration(
                      color: look.chipPlate,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: SizedBox(
                      width: 36,
                      height: 22,
                      child: Center(child: stroke),
                    ),
                  )
                : !multiplies && look.needsEdge(inkColor)
                ? Stack(
                    alignment: Alignment.center,
                    children: [
                      // A hairline edge: the same stroke a little wider in
                      // the hairline colour, under it.
                      InkStroke(
                        style: shown.copyWith(
                          colorArgb: tokens.outline.toARGB32(),
                          opacity: .55,
                          width: shown.width + 1.4,
                        ),
                        size: size,
                        shape: ink.PenPreviewShape.sCurve,
                      ),
                      stroke,
                    ],
                  )
                : stroke,
          ),
          if (active)
            Positioned(
              bottom: 0,
              child: Container(
                width: 14,
                height: 3,
                decoration: BoxDecoration(
                  color: look.activeMark,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The calm eraser: a line glyph in the icon weight, the underline while
/// it is the tool.
class _FlatEraser extends StatelessWidget {
  const _FlatEraser({required this.active, required this.look});

  final bool active;
  final PenTrayStyle look;

  @override
  Widget build(BuildContext context) {
    final tokens = StyleTokens.of(context);
    return SizedBox(
      width: 40,
      height: 36,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 40,
            height: 32,
            decoration: BoxDecoration(
              color: active ? look.chipActiveFill : look.chipFill,
              borderRadius: BorderRadius.circular(9),
            ),
            alignment: Alignment.center,
            child: EraserGlyph(
              key: PenTray.artKey,
              color: active ? tokens.accent : tokens.textSecondary,
            ),
          ),
          if (active)
            Positioned(
              bottom: 0,
              child: Container(
                width: 14,
                height: 3,
                decoration: BoxDecoration(
                  color: look.activeMark,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One tray slot: [PenTray.slotWidth] × [PenTray.height], the drawing down in
/// the well or lifted with a shadow, tap / long press, the hover label.
class _TraySlot extends StatefulWidget {
  const _TraySlot({
    super.key,
    this.boxKey,
    this.axis = Axis.horizontal,
    required this.slotHeight,
    required this.lifted,
    required this.look,
    required this.label,
    required this.hint,
    required this.hoverText,
    required this.onTap,
    required this.onLongPress,
    required this.child,
    this.inkStyle,
  });

  /// (v2.16-ui review) A vertical slot's pen: its ink strip under the
  /// drawing (the real colour and width — what tells the pens apart).
  final core.StrokeStyle? inkStyle;

  /// A GlobalKey on the slot's box (the eraser popup is placed by it).
  final GlobalKey? boxKey;

  /// (v2.16-ui) The tray's axis: vertical slots are [PenTray.railSlotWidth]
  /// wide, their drawing lies pointing right.
  final Axis axis;
  final double slotHeight;
  final bool lifted;
  final PenTrayStyle look;
  final String label;
  final String? hint;
  final String hoverText;
  final VoidCallback onTap;

  /// Receives the point a popup opened from here should use (global).
  final void Function(Offset at) onLongPress;
  final Widget child;

  @override
  State<_TraySlot> createState() => _TraySlotState();
}

class _TraySlotState extends State<_TraySlot> {
  final OverlayPortalController _hover = OverlayPortalController();
  Timer? _hoverDelay;

  static const Duration _hoverWait = Duration(milliseconds: 350);

  @override
  void dispose() {
    _hoverDelay?.cancel();
    super.dispose();
  }

  void _enter(PointerEnterEvent e) {
    if (e.kind != PointerDeviceKind.stylus &&
        e.kind != PointerDeviceKind.invertedStylus &&
        e.kind != PointerDeviceKind.mouse) {
      return;
    }
    _hoverDelay?.cancel();
    _hoverDelay = Timer(_hoverWait, () {
      if (mounted && !_hover.isShowing) _hover.show();
    });
  }

  void _exit([Object? _]) {
    _hoverDelay?.cancel();
    if (_hover.isShowing) _hover.hide();
  }

  /// Under the slot, left-aligned (the quick pen / popups open there).
  /// (v2.16-ui) Right of a vertical slot, top-aligned.
  Offset _popupPoint() {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return Offset.zero;
    if (widget.axis == Axis.vertical) {
      return box.localToGlobal(box.size.topRight(Offset.zero)) +
          const Offset(0, -12);
    }
    // _AtPointLayout adds 12 px right and below: the popup's top is 12 px
    // under the slot, clear of the toolbar's edge.
    return box.localToGlobal(box.size.bottomLeft(Offset.zero)) +
        const Offset(-12, 0);
  }

  @override
  Widget build(BuildContext context) {
    final look = widget.look;
    final up = widget.lifted;
    final tokens = StyleTokens.of(context);
    final vertical = widget.axis == Axis.vertical;
    final art = look.hasWell && vertical
        ? Stack(
            clipBehavior: Clip.none,
            children: [
              // (v2.16-ui) A soft light behind the pen in the hand.
              Positioned.fill(
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 160),
                  opacity: up ? 1 : 0,
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(2, 3, 2, 3),
                    decoration: BoxDecoration(
                      color: tokens.accent.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              // The shadow under the lifted pen (it lies to the right).
              AnimatedOpacity(
                duration: const Duration(milliseconds: 160),
                opacity: up ? 1 : 0,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    margin: EdgeInsets.only(
                      left: PenTray.railSlotWidth - PenTray._railShown - 26,
                    ),
                    width: PenTray._railShown + 6,
                    height: 16,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: look.liftShadow,
                          blurRadius: 8,
                          offset: const Offset(5, 3),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // (review) The ink strip: the stroke this pen writes.
              if (widget.inkStyle case final ink?)
                Positioned(
                  left: 10,
                  right: 6,
                  bottom: 3,
                  height: PenTray.railInkHeight,
                  child: _RailInkStrip(style: ink),
                ),
              AnimatedPositioned(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOutCubic,
                top: widget.inkStyle != null
                    ? 1
                    : (widget.slotHeight - PenTray.artSize.width) / 2,
                left: PenTray.railLeftOf(lifted: up),
                child: widget.child,
              ),
              // The mark at the wall: this one is in the hand.
              Positioned(
                left: 0,
                top: (widget.slotHeight - 26) / 2,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 160),
                  opacity: up ? 1 : 0,
                  child: Container(
                    width: 3,
                    height: 26,
                    decoration: BoxDecoration(
                      color: look.activeMark,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ],
          )
        : look.hasWell
        ? Stack(
            clipBehavior: Clip.none,
            children: [
              // The shadow under the lifted pen.
              AnimatedOpacity(
                duration: const Duration(milliseconds: 160),
                opacity: up ? 1 : 0,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Container(
                    margin: EdgeInsets.only(
                      top: PenTray.upTopOf(widget.slotHeight) + 10,
                    ),
                    width: 18,
                    height: widget.slotHeight,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: look.liftShadow,
                          blurRadius: 8,
                          offset: const Offset(2, 5),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              AnimatedPositioned(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOutCubic,
                left: (PenTray.slotWidth - PenTray.artSize.width) / 2,
                top: up
                    ? PenTray.upTopOf(widget.slotHeight)
                    : PenTray.downTopOf(widget.slotHeight),
                child: widget.child,
              ),
            ],
          )
        : Center(child: widget.child);
    return Semantics(
      container: true,
      button: true,
      selected: up,
      label: widget.label,
      hint: widget.hint,
      excludeSemantics: true,
      onTap: widget.onTap,
      onLongPress: () => widget.onLongPress(_popupPoint()),
      child: MouseRegion(
        onEnter: _enter,
        onExit: _exit,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            _exit();
            widget.onTap();
          },
          onLongPress: () {
            _exit();
            widget.onLongPress(_popupPoint());
          },
          child: OverlayPortal(
            controller: _hover,
            overlayChildBuilder: (context) => Positioned.fill(
              child: IgnorePointer(
                child: CustomSingleChildLayout(
                  delegate: _HoverLabelLayout(
                    _slotRectIn(context),
                    beside: vertical,
                  ),
                  child: Container(
                    key: PenTray.hoverLabelKey,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: tokens.paperBadge,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: tokens.shadows(2),
                    ),
                    child: Text(
                      widget.hoverText,
                      style: Theme.of(context).textTheme.labelLarge
                          ?.copyWith(color: tokens.onPaperBadge),
                    ),
                  ),
                ),
              ),
            ),
            child: _anchorBox(
              widget.boxKey,
              SizedBox(
                width: vertical ? PenTray.railSlotWidth : PenTray.slotWidth,
                height: widget.slotHeight,
                child: art,
              ),
              beside: vertical,
            ),
          ),
        ),
      ),
    );
  }

  /// This slot's rect in the overlay that shows the hover label.
  Rect? _slotRectIn(BuildContext overlayContext) {
    final box = context.findRenderObject();
    final overlay = Overlay.maybeOf(overlayContext)?.context.findRenderObject();
    if (box is! RenderBox || !box.hasSize || overlay is! RenderBox) {
      return null;
    }
    final at = overlay.globalToLocal(box.localToGlobal(Offset.zero));
    return at & box.size;
  }
}

/// The hover label: centred [_gap] under the slot, moved sideways to stay
/// [_margin] inside the screen (a tray left of centre in portrait).
class _HoverLabelLayout extends SingleChildLayoutDelegate {
  const _HoverLabelLayout(this.slot, {this.beside = false});

  final Rect? slot;

  /// (v2.16-ui) Right of the slot, centred on it (a vertical tray).
  final bool beside;

  static const double _gap = 6;
  static const double _margin = 8;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size child) {
    final r = slot;
    if (r == null) return Offset.zero;
    if (beside) {
      final maxY = size.height - child.height - _margin;
      final y = maxY <= _margin
          ? _margin
          : (r.center.dy - child.height / 2).clamp(_margin, maxY);
      return Offset(r.right + _gap, y.toDouble());
    }
    final maxX = size.width - child.width - _margin;
    final x = maxX <= _margin
        ? _margin
        : (r.center.dx - child.width / 2).clamp(_margin, maxX);
    return Offset(x.toDouble(), r.bottom + _gap);
  }

  @override
  bool shouldRelayout(_HoverLabelLayout old) =>
      old.slot != slot || old.beside != beside;
}

/// (v2.16-ui review) [child] under [key] as a PopupAnchorBox (its popups open
/// [beside] it — a vertical tray), or [child] alone without a key.
Widget _anchorBox(GlobalKey? key, Widget child, {bool beside = false}) =>
    key == null
    ? child
    : PopupAnchorBox(key: key, beside: beside, child: child);

/// (v2.16-ui review) A vertical tray slot's ink strip: the pen's stroke (its
/// colour, its width up to 5 px) on a paper-light strip, as the 스튜디오
/// mockup shows under each pen.
class _RailInkStrip extends StatelessWidget {
  const _RailInkStrip({required this.style});

  final core.StrokeStyle style;

  @override
  Widget build(BuildContext context) {
    final tokens = StyleTokens.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.inkSwatch,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Center(
        child: InkStroke(
          style: style.copyWith(width: style.width.clamp(1.2, 5.0)),
          size: const Size(48, 8),
          shape: ink.PenPreviewShape.line,
        ),
      ),
    );
  }
}
