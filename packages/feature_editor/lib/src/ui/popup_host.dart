// lib/src/ui/popup_host.dart — 04-editor 6.9.2 (PopupHost).
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui_kit/ui_kit.dart';

import '../di/editor_extensions.dart';
import '../state/popup.dart';
import '../state/settings/editor_device_state.dart';
import 'color/color_palette_popup.dart';
import 'color/recolor_panel.dart';
import 'editor_strings.dart';
import 'eraser/eraser_popup.dart';
import 'pages/add_page_sheet.dart';
import 'pen/pen_settings_popup.dart';
import 'pen/quick_pen_popup.dart';
import 'presets/preset_manager_sheet.dart';
import 'presets/save_preset_dialog.dart';
import 'shape/shape_style_controls.dart';
import 'text/text_style_controls.dart';

/// Toolbar anchors the popups follow (CompositedTransformTarget links).
class PopupAnchors {
  final LayerLink pen = LayerLink();

  /// (v2.15-ui) The pen tray (its popups are placed under its rect).
  final GlobalKey penBox = GlobalKey(debugLabel: 'editor.penTray');
  final LayerLink eraser = LayerLink();

  /// (v2.15-ui review) The tray's eraser slot (its popup is placed by its
  /// rect, kept inside the screen).
  final GlobalKey eraserBox = GlobalKey(debugLabel: 'editor.trayEraser');

  /// (v2, E2-13) the toolbar's shape and text buttons (6.13.1).
  final LayerLink shape = LayerLink();
  final LayerLink text = LayerLink();

  /// (v2.16-ui — 04-editor 24) The axis of the mounted pen tray (set by it
  /// while it builds): its popups open to the right of a vertical tray (스
  /// 튜디오's rail) instead of under it.
  Axis trayAxis = Axis.horizontal;

  /// (v2.16-ui) Whether the shape and text buttons stand in the rail (set
  /// by them while they build): their popups open to the right of them, by
  /// the rects of [shapeBox] / [textBox].
  bool toolsBeside = false;
  final GlobalKey shapeBox = GlobalKey(debugLabel: 'editor.railShape');
  final GlobalKey textBox = GlobalKey(debugLabel: 'editor.railText');

  /// (v2.15-ui review) Bumped after the pen tray was built again (another
  /// width, capacity, rotation, the palette moved): an open tray popup
  /// places itself again by the new rect.
  final ValueNotifier<int> trayMoved = ValueNotifier(0);
  bool _movePending = false;

  /// Called by the tray while it builds: bumps [trayMoved] after the frame
  /// (once per frame).
  void scheduleTrayMoved() {
    if (_movePending) return;
    _movePending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _movePending = false;
      trayMoved.value++;
    });
  }

  /// The tray rect an open tray popup was placed by. A new rect with the
  /// same right edge and top (a '지금 펜' slot came or went — the tray grew
  /// to the left) keeps it, so the open picker does not jump sideways while
  /// its colour or width changes; anything else (another width, a rotation,
  /// the palette moved) places it again. Cleared when the popup closes.
  Rect? _placedBy;

  Rect? _placeBy(Rect? now) {
    final was = _placedBy;
    if (was != null &&
        now != null &&
        (was.right - now.right).abs() < .5 &&
        (was.top - now.top).abs() < .5) {
      return was;
    }
    return _placedBy = now;
  }

  void dispose() => trayMoved.dispose();
}

/// Shows editorPopupProvider's popup with an OverlayPortal (its overlay child
/// stays a logical descendant here: provider scope, shortcuts, focus) next to
/// the toolbar button it belongs to (CompositedTransformFollower), above a
/// full-screen transparent barrier: a pointer down on the barrier closes the
/// popup and is consumed (nothing is drawn on the canvas).
///
/// E-13 shows the toolbar popups (pen settings, quick pen, eraser); the
/// context menus stay with InteractionHost (E-10). E-16: the preset save
/// dialog and manager sheet have no anchor — they sit in the middle of the
/// screen (above the keyboard) over a light scrim; so does the add-page
/// sheet (E-17).
class PopupHost extends ConsumerStatefulWidget {
  const PopupHost({super.key, required this.child});

  final Widget child;

  static const barrierKey = ValueKey('editor.popup.barrier');

  /// The anchors of the enclosing PopupHost.
  static PopupAnchors anchorsOf(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<_PopupAnchorsScope>();
    assert(scope != null, 'No PopupHost above this context');
    return scope!.anchors;
  }

  /// (v2.15-ui) The anchors of the enclosing PopupHost, null without one (a
  /// pen tray shown outside the editor, e.g. in a test).
  static PopupAnchors? maybeAnchorsOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_PopupAnchorsScope>()?.anchors;

  /// Runs an extension item picked inside a popup (the add-page sheet's
  /// '다른 소스' row, 4.5) with the PopupHost's own context, which stays
  /// mounted after the popup closes: awaited, never twice at the same time;
  /// an exception is reported and shows '실행하지 못했어요'.
  static Future<void> runMenuItem(
    BuildContext context,
    EditorMenuItem item,
    EditorMenuContext menu,
  ) {
    final scope = context.getInheritedWidgetOfExactType<_PopupAnchorsScope>();
    assert(scope != null, 'No PopupHost above this context');
    return scope!.host._runMenuItem(item, menu);
  }

  @override
  ConsumerState<PopupHost> createState() => _PopupHostState();
}

class _PopupHostState extends ConsumerState<PopupHost> {
  final PopupAnchors _anchors = PopupAnchors();
  final OverlayPortalController _portal = OverlayPortalController();
  final Set<String> _running = {};

  Future<void> _runMenuItem(EditorMenuItem item, EditorMenuContext menu) async {
    if (!_running.add(item.id)) return;
    try {
      await item.onSelected(context, menu);
    } on Object catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'feature_editor',
          context: ErrorDescription('while running menu item ${item.id}'),
        ),
      );
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)
          ?..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(content: Text(EditorStrings.commandFailed)),
          );
      }
    } finally {
      _running.remove(item.id);
    }
  }

  void _sync(EditorPopup? popup) {
    final show = _layoutOf(popup) != null;
    if (!show) _anchors._placedBy = null;
    if (show && !_portal.isShowing) _portal.show();
    if (!show && _portal.isShowing) _portal.hide();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _sync(ref.read(editorPopupProvider));
    });
  }

  @override
  void dispose() {
    _anchors.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(editorPopupProvider, (_, next) => _sync(next));
    return _PopupAnchorsScope(
      anchors: _anchors,
      host: this,
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: (context) => _PopupLayer(anchors: _anchors),
        child: widget.child,
      ),
    );
  }
}

/// The anchor (null = centred, unless [at]), the point (v2 — global logical
/// px: the popup opens there instead of at its anchor) and the panel of a
/// popup PopupHost shows; null for the others.
({LinkPick? link, Offset? at, Widget panel})? _layoutOf(EditorPopup? popup) =>
    switch (popup) {
      PenSettingsPopup() => (
        link: LinkPick.pen,
        at: null,
        panel: const PenSettingsPanel(),
      ),
      QuickPenPopup(:final globalPosition, :final presetId) => (
        link: LinkPick.pen,
        at: globalPosition,
        panel: QuickPenPanel(presetId: presetId),
      ),
      ColorPalettePopup(:final globalPosition) => (
        link: LinkPick.pen,
        at: globalPosition,
        panel: const ColorPalettePanel(),
      ),
      // (v2, m5-7/04-editor 6.7.2) under the selection menu's '색'.
      RecolorPopup(:final globalPosition) => (
        link: null,
        at: globalPosition,
        panel: const RecolorPanel(),
      ),
      // (v2, E2-09) the shape tool popup and a selected shape's '스타일'.
      ShapeToolPopup(:final globalPosition, :final anchored) => (
        link: anchored ? LinkPick.shape : null,
        at: globalPosition,
        panel: const ShapeToolPanel(),
      ),
      ShapeStylePopup(:final globalPosition) => (
        link: null,
        at: globalPosition,
        panel: const ShapeStylePanel(),
      ),
      // (v2, E2-10) the text tool popup and a selected text box's '서식'.
      TextToolPopup(:final globalPosition, :final anchored) => (
        link: anchored ? LinkPick.text : null,
        at: globalPosition,
        panel: const TextToolPanel(),
      ),
      TextFormatPopup(:final globalPosition) => (
        link: null,
        at: globalPosition,
        panel: const TextFormatPanel(),
      ),
      EraserSettingsPopup() => (
        link: LinkPick.eraser,
        at: null,
        panel: const EraserSettingsPanel(),
      ),
      SavePresetPopup() => (
        link: null,
        at: null,
        panel: const SavePresetDialog(),
      ),
      PresetManagerPopup() => (
        link: null,
        at: null,
        panel: const PresetManagerSheet(),
      ),
      final AddPagePopup popup => (
        link: null,
        at: null,
        panel: AddPageSheet(popup: popup),
      ),
      _ => null,
    };

/// Which toolbar button a popup hangs from. (v2, E2-13) shape and text.
enum LinkPick { pen, eraser, shape, text }

class _PopupLayer extends ConsumerWidget {
  const _PopupLayer({required this.anchors});

  final PopupAnchors anchors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = _layoutOf(ref.watch(editorPopupProvider));
    if (layout == null) return const SizedBox.shrink();
    final at = layout.at;
    // (04-editor 19) With the top menu hidden the toolbar buttons are not in
    // the tree: a popup that would hang from one (the pencil's quick pen /
    // colour palette without a hover point) opens in the middle instead of
    // following a missing anchor (it would be invisible behind the barrier).
    // (v2.15-ui review) The tray's popups hang from the tray wherever it is
    // mounted (the toolbar or the floating palette — also with the menu
    // hidden), by its rect, read again after it moved ([trayMoved]) and on
    // a new screen size.
    final menuHidden = ref.watch(
      editorDeviceStateProvider.select((s) => s.toolbarHidden),
    );
    final trayBox = switch (layout.link) {
      LinkPick.pen => anchors.penBox,
      LinkPick.eraser => anchors.eraserBox,
      // (v2.16-ui) The rail's shape and text buttons: beside them.
      LinkPick.shape when anchors.toolsBeside => anchors.shapeBox,
      LinkPick.text when anchors.toolsBeside => anchors.textBox,
      _ => null,
    };
    final beside = switch (layout.link) {
      LinkPick.pen || LinkPick.eraser => anchors.trayAxis == Axis.vertical,
      LinkPick.shape || LinkPick.text => anchors.toolsBeside,
      null => false,
    };
    final link = at != null || menuHidden || trayBox != null
        ? null
        : switch (layout.link) {
            LinkPick.shape => anchors.shape,
            LinkPick.text => anchors.text,
            _ => null,
          };
    final placed = at == null && trayBox?.currentContext != null;
    MediaQuery.sizeOf(context); // placed again on a new screen size
    return Stack(
      children: [
        Positioned.fill(
          child: Listener(
            key: PopupHost.barrierKey,
            behavior: HitTestBehavior.opaque,
            onPointerDown: (_) =>
                ref.read(editorPopupProvider.notifier).close(),
            child: link == null && at == null && !placed
                ? ColoredBox(
                    color: Theme.of(context).colorScheme.scrim
                        .withValues(alpha: 0.32),
                  )
                : null,
          ),
        ),
        if (at != null)
          Positioned.fill(
            child: CustomSingleChildLayout(
              delegate: _AtPointLayout(_overlayLocal(context, at)),
              child: layout.panel,
            ),
          )
        else if (placed)
          // (v2.15-ui) The pen tray is the pen anchor: its popups (the wide
          // pen picker) hang centred under it, the eraser's under the
          // eraser — kept inside the screen, above the anchor when there is
          // more room there (a palette low on the screen).
          Positioned.fill(
            child: ValueListenableBuilder<int>(
              valueListenable: anchors.trayMoved,
              builder: (context, _, panel) => CustomSingleChildLayout(
                delegate: _BelowAnchorLayout(
                  anchors._placeBy(_boxRect(context, trayBox!)),
                  centred: layout.link == LinkPick.pen,
                  beside: beside,
                ),
                child: panel,
              ),
              child: layout.panel,
            ),
          )
        else if (link != null)
          CompositedTransformFollower(
            link: link,
            showWhenUnlinked: false,
            targetAnchor: Alignment.bottomLeft,
            offset: const Offset(0, 6),
            child: Align(alignment: Alignment.topLeft, child: layout.panel),
          )
        else
          Positioned.fill(
            child: Padding(
              padding: MediaQuery.viewInsetsOf(context),
              child: Center(child: layout.panel),
            ),
          ),
      ],
    );
  }
}

/// [global] in the coordinates of the overlay the popup layer sits in.
Offset _overlayLocal(BuildContext context, Offset global) {
  final box = Overlay.maybeOf(context)?.context.findRenderObject();
  if (box is RenderBox && box.attached && box.hasSize) {
    return box.globalToLocal(global);
  }
  return global;
}

/// (v2.15-ui) The rect of [box] (the pen tray, its eraser) in the overlay
/// (null when it is not laid out).
Rect? _boxRect(BuildContext context, GlobalKey box) {
  final target = box.currentContext?.findRenderObject();
  if (target is! RenderBox || !target.attached || !target.hasSize) {
    return null;
  }
  final overlay = Overlay.maybeOf(context)?.context.findRenderObject();
  if (overlay is! RenderBox || !overlay.attached) return null;
  final topLeft = overlay.globalToLocal(target.localToGlobal(Offset.zero));
  return topLeft & target.size;
}

/// (v2.15-ui) A pen-tray popup: under the [anchor] (centred on it when
/// [centred], else its left edge at the anchor's), [_gap] below it, moved
/// sideways to stay [_margin] inside the screen. (v2.15-ui review) Above the
/// anchor instead when there is more room above and too little below for
/// [_comfortable] (the floating palette low on the screen); centred on the
/// screen when the anchor is not laid out.
///
/// (v2.16-ui) With [beside]: right of the anchor (a vertical tray, the
/// rail's tools), its top at the anchor's top, moved up to stay inside the
/// screen.
class _BelowAnchorLayout extends SingleChildLayoutDelegate {
  const _BelowAnchorLayout(
    this.anchor, {
    this.centred = true,
    this.beside = false,
  });

  final Rect? anchor;
  final bool centred;
  final bool beside;

  /// (owner review) Clear of the toolbar's edge, not glued to it.
  static const double _gap = 12;
  static const double _margin = 8;

  /// Below the anchor while at least this much room is there.
  static const double _comfortable = 480;

  bool _above(Size size) {
    final a = anchor;
    if (a == null) return false;
    final below = size.height - a.bottom - _gap - _margin;
    final above = a.top - _gap - _margin;
    return below < _comfortable && above > below;
  }

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final a = anchor;
    final size = constraints.biggest;
    if (beside && a != null) {
      return BoxConstraints.loose(
        Size(
          math.max(0, size.width - a.right - _gap - _margin),
          math.max(0, size.height - 2 * _margin),
        ),
      );
    }
    final room = a == null
        ? size.height - 2 * _margin
        : _above(size)
        ? a.top - _gap - _margin
        : size.height - a.bottom - _gap - _margin;
    return BoxConstraints.loose(
      Size(
        math.max(0, size.width - 2 * _margin),
        room.clamp(0, size.height).toDouble(),
      ),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size child) {
    final a = anchor;
    if (a == null) {
      return Offset(
        (size.width - child.width) / 2,
        (size.height - child.height) / 2,
      );
    }
    if (beside) {
      final maxY = size.height - child.height - _margin;
      final y = maxY <= _margin ? _margin : a.top.clamp(_margin, maxY);
      return Offset(a.right + _gap, y.toDouble());
    }
    final maxX = size.width - child.width - _margin;
    final want = centred ? a.center.dx - child.width / 2 : a.left;
    final x = maxX <= _margin ? _margin : want.clamp(_margin, maxX);
    final y = _above(size) ? a.top - _gap - child.height : a.bottom + _gap;
    return Offset(x.toDouble(), y);
  }

  @override
  bool shouldRelayout(_BelowAnchorLayout oldDelegate) =>
      oldDelegate.anchor != anchor ||
      oldDelegate.centred != centred ||
      oldDelegate.beside != beside;
}

/// A popup opened at a point (v2 — the pencil's hover point): its top-left
/// [_gap] px right of and below the point, moved left / up so that it stays
/// [_margin] px inside the screen.
class _AtPointLayout extends SingleChildLayoutDelegate {
  const _AtPointLayout(this.point);

  final Offset point;

  static const double _gap = 12;
  static const double _margin = 8;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    double place(double want, double extent, double child) {
      final max = extent - child - _margin;
      if (max <= _margin) return _margin;
      return want.clamp(_margin, max);
    }

    return Offset(
      place(point.dx + _gap, size.width, childSize.width),
      place(point.dy + _gap, size.height, childSize.height),
    );
  }

  @override
  bool shouldRelayout(_AtPointLayout oldDelegate) => oldDelegate.point != point;
}

class _PopupAnchorsScope extends InheritedWidget {
  const _PopupAnchorsScope({
    required this.anchors,
    required this.host,
    required super.child,
  });

  final PopupAnchors anchors;
  final _PopupHostState host;

  @override
  bool updateShouldNotify(_PopupAnchorsScope oldWidget) =>
      !identical(anchors, oldWidget.anchors);
}

/// Frame of a popup panel: [width] px wide (pen settings 340, quick pen and
/// eraser 300), at most min(600, available) high, scrolls when longer
/// (6.9.3).
class PopupPanelFrame extends StatelessWidget {
  const PopupPanelFrame({
    super.key,
    required this.title,
    required this.children,
    this.width = 340,
  });

  final String title;
  final List<Widget> children;
  final double width;

  /// Inner padding on every side.
  static const double padding = 16;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxHeight = MediaQuery.sizeOf(context).height - 120;
    return Material(
      elevation: 3,
      color: StyleTokens.of(context).panel,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: width,
          minWidth: width,
          maxHeight: maxHeight.clamp(120, 600),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(padding),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: theme.textTheme.titleMedium),
              const SizedBox(height: 12),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}
