// lib/src/tools/interaction_host.dart — 04-editor 6.6.2, 6.6.9.
//
// E-08: the skeleton (policy, decision order, navigation, wheel / trackpad,
// taps → undo / redo, hover cursor) and the pen. E-09: the eraser (its ring
// follows the pen while erasing). The lasso and selection transform,
// long-press / secondary-click menus (E-10), eyedropper (E-14) and developer
// metrics (E-19) plug into the marked places.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/painting.dart' show Color;
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
import 'pen_interaction.dart';
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
  Timer? _hoverTimer;
  ToolInteraction? _lastStarted;
  bool _disposed = false;

  ValueListenable<CursorState?> get cursor => _cursor;

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
    final tools = _ref.read(editorToolProvider);
    // ① eyedropper (allowed on read-only notes) — E-14.
    if (tools.eyedropperActive) return null;
    // ② read-only note → no tool input (6.17.2).
    if (_ref.read(editorReadOnlyProvider)) return null;
    // ③ lasso tool on the selection → selection transform — E-10.
    // ④ gap / outside the pages → nothing.
    final hit = _viewport.hitPage(sample.position);
    if (hit == null) return null;
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
      case EditorTool.lasso: // E-10
        interaction = null;
    }
    _lastStarted = interaction;
    return interaction;
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
  /// hits it — E-10.
  @override
  bool hitsSelection(Offset screen) => false;

  @override
  void navigationStart() => _viewport.beginGesture();

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

  /// 1 = dismiss (popup → selection, E-10/E-13), 2 = undo, 3 = redo. The
  /// router already applied GestureSettings.
  @override
  void tapGesture(int fingerCount, Offset centroid) {
    switch (fingerCount) {
      case 2:
        unawaited(_commands.undo());
      case 3:
        unawaited(_commands.redo());
      default:
        break;
    }
  }

  /// Selection menu / context menu — E-10.
  @override
  void longPress(Offset screen) {}

  /// Selection menu / context menu — E-10.
  @override
  void secondaryClick(Offset screen) {}

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
  }
}
