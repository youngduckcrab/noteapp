// lib/src/tools/interaction_host.dart — 04-editor 6.6.2, 6.6.9.
//
// E-08: the skeleton (policy, decision order, navigation, wheel / trackpad,
// taps → undo / redo, hover cursor) and the pen. E-09: the eraser (its ring
// follows the pen while erasing). E-10: the lasso, the selection transform,
// one-finger tap → dismiss, and the long-press / secondary-click context
// menu. The eyedropper (E-14), popups (E-13) and developer metrics (E-19)
// plug into the marked places.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/painting.dart' show Color, Size;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:note_core/note_core.dart' as core;

import '../commands/editor_commands.dart';
import '../document/mounted_pages.dart';
import '../input/input_sample.dart';
import '../input/input_targets.dart';
import '../scope/editor_scope.dart';
import '../state/color_palette.dart';
import '../state/settings/editor_settings_notifier.dart';
import '../viewport/viewport_constants.dart';
import '../viewport/viewport_controller.dart';
import 'erase_interaction.dart';
import 'lasso_interaction.dart';
import 'pen_interaction.dart';
import 'selection.dart';
import 'selection_hit_test.dart';
import 'selection_transform_interaction.dart';
import 'tool_controller.dart';
import 'tool_interaction.dart';
import 'tool_state.dart';

sealed class CursorState {
  const CursorState({required this.position});
  final Offset position; // screen
}

final class PenDotCursor extends CursorState {
  const PenDotCursor({
    required super.position,
    required this.diameter,
    required this.color,
  });
  final double
  diameter; // max(4, 2 * style.previewRadius * scale) px (ink.StrokeStyleInk)
  final Color color; // pen colour at 50% alpha
}

final class EraserRingCursor extends CursorState {
  const EraserRingCursor({required super.position, required this.diameter});
  final double diameter; // eraser.diameter * scale px
}

/// A context menu requested by a long press or a secondary click away from
/// the selection (6.6.2): [position] in viewport coordinates.
@immutable
final class ContextMenuRequest {
  const ContextMenuRequest({required this.position});
  final Offset position;

  @override
  bool operator ==(Object other) =>
      other is ContextMenuRequest && other.position == position;

  @override
  int get hashCode => position.hashCode;
}

/// The hover cursor hides when no hover event came for this long (6.6.9).
const Duration kHoverCursorTimeout = Duration(milliseconds: 300);

/// Implements InputTargets; creates ToolInteractions; owns the hot-path notifiers
/// the EDITOR overlays listen to. Live stroke, lasso path and selection preview are
/// painted by ink.InkPageView, not here.
class InteractionHost implements InputTargets {
  InteractionHost({
    required this._ref,
    required this._session,
    required this._viewport,
    required this._pages,
    required this._commands,
  });

  final Ref _ref;
  final core.NoteSession _session;
  final ViewportController _viewport;
  final MountedPages _pages;
  final EditorCommands _commands;
  final ValueNotifier<CursorState?> _cursor = ValueNotifier(null);
  final ValueNotifier<ContextMenuRequest?> _contextMenu = ValueNotifier(null);
  Timer? _hoverTimer;
  ToolInteraction? _lastStarted;
  bool _disposed = false;

  ValueListenable<CursorState?> get cursor => _cursor;

  /// The open context menu (long press / secondary click), or null.
  ValueListenable<ContextMenuRequest?> get contextMenu => _contextMenu;

  void closeContextMenu() {
    if (!_disposed) _contextMenu.value = null;
  }

  /// The interaction most recently returned by [beginInteraction] (tests,
  /// developer metrics).
  ToolInteraction? get lastStarted => _lastStarted;

  core.NoteSession get session => _session;

  // ---- InputTargets ----

  @override
  InputPolicy get policy {
    final settings = _ref.read(editorSettingsProvider);
    return InputPolicy(
      penOnly: settings.isPenOnlyEffective,
      palm: settings.palmRejection,
      gestures: settings.gestures,
      stylusSeen: settings.stylusSeen,
      eyedropperActive: _ref.read(editorToolProvider).eyedropperActive,
    );
  }

  @override
  ToolInteraction? beginInteraction(
    InputSample sample, {
    required InteractionSource source,
  }) {
    if (_disposed) return null;
    _hideCursor(); // a pen touching the screen hides the hover cursor
    closeContextMenu();
    final tools = _ref.read(editorToolProvider);
    // ① eyedropper (allowed on read-only notes) — E-14.
    if (tools.eyedropperActive) return null;
    // ② read-only note → no tool input (6.17.2).
    if (_ref.read(editorReadOnlyProvider)) return null;
    final selections = _ref.read(editorSelectionProvider.notifier);
    // ③ lasso tool on the selection → selection transform.
    if (tools.activeTool == EditorTool.lasso) {
      final transform = _beginTransform(sample, source);
      if (transform != null) {
        _lastStarted = transform;
        return transform;
      }
    }
    // ④ gap / outside the pages → nothing (the lasso clears the selection).
    final hit = _viewport.hitPage(sample.position);
    if (hit == null) {
      if (tools.activeTool == EditorTool.lasso) selections.clear();
      return null;
    }
    // Touching another page clears the selection.
    final selected = _ref.read(editorSelectionProvider);
    if (selected != null && selected.pageId != hit.pageId) selections.clear();
    // ⑤ only mounted, loaded pages take tool input (contract E-2, 6.4.4).
    final mount = _pages[hit.pageId];
    if (mount == null || !mount.isLoaded.value) return null;
    // ⑥ the tool's interaction.
    final ToolInteraction? interaction;
    switch (tools.activeTool) {
      case EditorTool.pen:
        _viewport.settleNow(); // viewScale = layout scale (6.3.4, 7.2.15 v1.1)
        interaction = PenInteraction.start(
          down: sample,
          source: source,
          controller: mount.controller,
          pageIndex: hit.index,
          viewport: _viewport,
          style: tools.currentPen,
          commands: _commands,
          onCommitted: _onStrokeCommitted,
        );
      case EditorTool.eraser:
        _viewport.settleNow(); // viewScale = layout scale (6.3.4, 7.2.15 v1.1)
        final eraser = tools.eraser;
        final scale = _viewport.camera.scale;
        interaction = EraseInteraction.start(
          down: sample,
          source: source,
          controller: mount.controller,
          pageIndex: hit.index,
          viewport: _viewport,
          eraser: eraser,
          commands: _commands,
          // While erasing the ring follows the pen (6.6.9); no hover timeout.
          onPosition: (position) =>
              _showEraserRing(position, eraser.diameter * scale),
          onFinished: _hideCursor,
          onCommitted: eraser.returnToPreviousTool ? _returnFromEraser : null,
        );
      case EditorTool.lasso:
        selections.clear();
        _viewport.settleNow(); // viewScale = layout scale (6.3.4, 7.2.15 v1.1)
        interaction = LassoInteraction.start(
          down: sample,
          source: source,
          controller: mount.controller,
          pageIndex: hit.index,
          pageId: hit.pageId,
          viewport: _viewport,
          onSelected: _onLassoSelected,
        );
    }
    _lastStarted = interaction;
    return interaction;
  }

  void _onLassoSelected(String pageId, Set<String> strokeIds) {
    if (_disposed) return;
    _ref.read(editorSelectionProvider.notifier).select(pageId, strokeIds);
  }

  /// ③: a handle → resize from that corner, the body → move (6.6.5).
  ToolInteraction? _beginTransform(
    InputSample sample,
    InteractionSource source,
  ) {
    final selection = _ref.read(editorSelectionProvider);
    final rect = selectionRectOnScreen(_viewport, _pages, selection);
    if (selection == null || rect == null) return null;
    final handle = SelectionHitTest.hitHandle(rect, sample.position);
    if (handle == null && !SelectionHitTest.hitBody(rect, sample.position)) {
      return null;
    }
    final mount = _pages[selection.pageId];
    final sel = inkSelectionOf(_pages, selection);
    final index = _viewport.pages.indexWhere((p) => p.id == selection.pageId);
    if (mount == null || sel == null || index < 0) return null;
    _viewport.settleNow(); // viewScale = layout scale (6.3.4, 7.2.15 v1.1)
    final size = _viewport.pages[index].size;
    final notifier = _ref.read(editorSelectionProvider.notifier)
      ..setDragging(true);
    return SelectionTransformInteraction.start(
      down: sample,
      source: source,
      controller: mount.controller,
      selection: sel,
      pageIndex: index,
      pageSize: Size(size.width, size.height),
      handle: handle,
      viewport: _viewport,
      commands: _commands,
      onCommitted: (ids) {
        // TransformElements keeps ids: select them again (6.6.5).
        if (!_disposed) notifier.select(selection.pageId, ids);
      },
      onFinished: () {
        if (!_disposed) notifier.setDragging(false);
      },
    );
  }

  void _onStrokeCommitted(core.StrokeStyle style) {
    if (_disposed) return;
    _ref.read(editorColorPaletteProvider.notifier).pushRecent(style.colorArgb);
  }

  /// A committed erase with "return to the previous tool" on (6.6.4 #3).
  void _returnFromEraser() {
    if (_disposed) return;
    _ref.read(editorToolProvider.notifier).returnFromEraser();
  }

  void _showEraserRing(Offset position, double diameter) {
    if (_disposed) return;
    _hoverTimer?.cancel();
    _hoverTimer = null;
    _cursor.value = EraserRingCursor(position: position, diameter: diameter);
  }

  /// True only if the lasso tool is active, a selection exists and [screen]
  /// hits its frame (a corner handle or the inflated body — 6.6.5).
  @override
  bool hitsSelection(Offset screen) {
    if (_disposed) return false;
    if (_ref.read(editorToolProvider).activeTool != EditorTool.lasso) {
      return false;
    }
    return _onSelection(screen);
  }

  bool _onSelection(Offset screen) {
    final rect = selectionRectOnScreen(
      _viewport,
      _pages,
      _ref.read(editorSelectionProvider),
    );
    if (rect == null) return false;
    return SelectionHitTest.hitHandle(rect, screen) != null ||
        SelectionHitTest.hitBody(rect, screen);
  }

  @override
  void navigationStart() {
    closeContextMenu();
    _viewport.beginGesture();
  }

  @override
  void navigationUpdate(NavigationUpdate update) => _viewport.updateGesture(
    baselineFocal: update.baselineFocal,
    focal: update.focal,
    scaleRatio: update.scaleRatio,
    rebased: update.rebased,
  );

  @override
  void navigationEnd(Velocity velocity) => _viewport.endGesture(velocity);

  @override
  void navigationCancel() => _viewport.cancelGesture();

  /// 1 = dismiss (context menu → popup (E-13) → selection), 2 = undo,
  /// 3 = redo. The router already applied GestureSettings.
  @override
  void tapGesture(int fingerCount, Offset centroid) {
    switch (fingerCount) {
      case 1:
        if (_contextMenu.value != null) {
          closeContextMenu();
        } else {
          _commands.clearSelection();
        }
      case 2:
        unawaited(_commands.undo());
      case 3:
        unawaited(_commands.redo());
      default:
        break;
    }
  }

  /// On the selection → its menu (already shown while a selection exists);
  /// elsewhere → the context menu (붙여넣기 when the clipboard has strokes,
  /// 올가미 도구). Nothing on a read-only note (both items edit).
  @override
  void longPress(Offset screen) => _menuAt(screen);

  /// Same as [longPress] (mouse right button).
  @override
  void secondaryClick(Offset screen) => _menuAt(screen);

  void _menuAt(Offset screen) {
    if (_disposed) return;
    if (_onSelection(screen)) {
      closeContextMenu();
      return;
    }
    if (_ref.read(editorReadOnlyProvider)) return;
    _contextMenu.value = ContextMenuRequest(position: screen);
  }

  /// Pen tool → PenDotCursor (stylus only), eraser → EraserRingCursor (stylus
  /// or mouse), lasso → none. Hidden after [kHoverCursorTimeout] without hover.
  @override
  void hover(InputSample sample) {
    if (_disposed) return;
    final tools = _ref.read(editorToolProvider);
    final scale = _viewport.camera.scale;
    final CursorState? next;
    if (tools.eyedropperActive) {
      next = null;
    } else {
      switch (tools.activeTool) {
        case EditorTool.pen when sample.kind != PointerDeviceKind.mouse:
          final style = tools.currentPen;
          next = PenDotCursor(
            position: sample.position,
            diameter: math.max(
              4,
              2 * ink.StrokeStyleInk(style).previewRadius * scale,
            ),
            color: Color(style.colorArgb).withValues(alpha: 0.5),
          );
        case EditorTool.eraser:
          next = EraserRingCursor(
            position: sample.position,
            diameter: tools.eraser.diameter * scale,
          );
        case EditorTool.pen:
        case EditorTool.lasso:
          next = null;
      }
    }
    _cursor.value = next;
    _hoverTimer?.cancel();
    _hoverTimer = next == null ? null : Timer(kHoverCursorTimeout, _hideCursor);
  }

  void _hideCursor() {
    _hoverTimer?.cancel();
    _hoverTimer = null;
    if (!_disposed) _cursor.value = null;
  }

  /// Wheel: scroll (wheel direction), or zoom about [at] with Ctrl / ⌘
  /// (factor = exp(−dy / 300), 6.3.1).
  @override
  void scrollSignal(Offset scrollDelta, Offset at, {required bool zoom}) {
    if (zoom) {
      _viewport.zoomBy(
        math.exp(-scrollDelta.dy / ViewportConstants.wheelZoomDivisor),
        at,
      );
    } else {
      _viewport.panBy(scrollDelta);
    }
  }

  /// Trackpad / pointer scale signal: [panDelta] is in finger direction, so
  /// the content follows it (panBy takes the wheel direction).
  @override
  void panZoomSignal({
    required Offset panDelta,
    required double scaleFactor,
    required Offset focal,
  }) {
    if (panDelta != Offset.zero) _viewport.panBy(-panDelta);
    if (scaleFactor != 1 && scaleFactor > 0) {
      _viewport.zoomBy(scaleFactor, focal);
    }
  }

  @override
  void stylusDetected() {
    if (_disposed) return;
    _ref.read(editorSettingsProvider.notifier).markStylusSeen();
  }

  /// Developer metrics (palm rejections) — E-19.
  @override
  void palmRejected(InputSample sample) {}

  /// Developer metrics (pointer rate) — E-19.
  @override
  void observe(PointerEvent event, InputSample sample) {}

  void dispose() {
    _disposed = true;
    _hoverTimer?.cancel();
    _hoverTimer = null;
    _cursor.dispose();
    _contextMenu.dispose();
  }
}
