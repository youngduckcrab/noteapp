// lib/src/tools/interaction_host.dart — 04-editor 6.6.2, 6.6.9.
//
// E-08: the skeleton (policy, decision order, navigation, wheel / trackpad,
// taps → undo / redo, hover cursor) and the pen. E-09: the eraser (its ring
// follows the pen while erasing). E-10: the lasso, the selection transform,
// one-finger tap → dismiss, and the long-press / secondary-click context
// menu. E-14: the stroke eyedropper (①). Developer metrics (E-19) plug into
// the marked places. (v2) E2-04a: the gesture at contact picks a temporary
// eraser / lasso for that contact (m5-7/04-editor 6.2.3, 6.3.3, 6.3.6 4).
// E2-04b: the text session in the input policy (6.3.4), two- / three-finger
// taps by GestureSettings.actionFor and the pen dot hook (6.3.5). E2-16: the
// pen stroke's recording meta at contact (6.15.1 — R-1). E2-17: tap-to-seek
// (6.3.5 ③, 6.15.3 — R-5 (v2.1)) for one-finger taps and pen / finger dots.
// E2-05: two- / three-finger taps and the finger long press run their
// GestureSettings action through EditorActionRunner (6.4.2, 6.4.3). E2-06:
// the selection priority (a′) (6.6.2), taps that select an object (6.3.5 ④)
// and (part 2) the frame v2 hit test — rotated frames and the rotate handle
// with its angle tag (6.6.4, 6.6.6). E2-08: a single object's edge, vertex
// and text width handles → ObjectEditInteraction (6.6.5). E2-09: the shape
// tool (6.9.2 — ShapeInteraction, a new shape selected with origin drawn).
// E2-10: the text tool (6.11.1 — TextToolInteraction, the new box outline)
// and the router-side ends of a text edit session (6.11.5 — a pen / mouse
// contact, a one-finger tap, the long press). E2-18: the Apple Pencil hover
// pose cursor (6.5.3), iPadOS '펜슬로만 그리기' in the input policy and the
// barrel roll → calligraphy nib angle at pen down (6.5.4).
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/painting.dart' show Color, Rect, Size;
import 'package:flutter/services.dart' show HapticFeedback, HardwareKeyboard;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:note_core/note_core.dart' as core;

import '../actions/editor_action_runner.dart';
import '../commands/editor_commands.dart';
import '../di/stylus_extras.dart';
import '../document/mounted_pages.dart';
import '../input/input_sample.dart';
import '../input/input_targets.dart';
import '../input/stylus_contact.dart';
import '../objects/object_factory.dart';
import '../playback/playback_highlighter.dart';
import '../playback/recording_link.dart';
import '../playback/tap_to_seek.dart';
import '../scope/editor_scope.dart';
import '../state/color_palette.dart';
import '../state/panel.dart';
import '../state/popup.dart';
import '../state/settings/editor_device_state.dart';
import '../state/settings/editor_settings.dart';
import '../state/settings/editor_settings_notifier.dart';
import '../state/settings/pre_roll.dart';
import '../stylus/barrel_roll.dart';
import '../stylus/stylus_extras_listener.dart' show penOnlyEffectiveWith;
import '../text/text_box_placement.dart';
import '../text/text_edit_session.dart';
import '../ui/dev/dev_metrics.dart';
import '../ui/editor_strings.dart';
import '../viewport/viewport_constants.dart';
import '../viewport/viewport_controller.dart';
import 'erase_interaction.dart';
import 'eyedropper_interaction.dart';
import 'lasso_interaction.dart';
import 'math_pen/math_pen_controller.dart';
import 'object_edit_interaction.dart';
import 'pen_interaction.dart';
import 'selection.dart';
import 'selection_hit_test.dart';
import 'selection_priority.dart';
import 'selection_transform_interaction.dart';
import 'shape_assist_for.dart';
import 'shape_drafts.dart';
import 'shape_interaction.dart';
import 'shape_samples.dart';
import 'text_tool_interaction.dart';
import 'tool_controller.dart';
import 'tool_interaction.dart';
import 'tool_options.dart';
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

/// (v2, 6.6.6) The angle tag while the rotate handle is dragged: [radians]
/// is the absolute angle (a single object whose frame rotates) or the
/// relative one (several elements, a polyline shape).
@immutable
final class RotationLabelState {
  const RotationLabelState(this.radians);
  final double radians;

  /// Whole degrees, as the tag shows them.
  int get degrees => (radians * 180 / math.pi).round();

  @override
  bool operator ==(Object other) =>
      other is RotationLabelState && other.radians == radians;

  @override
  int get hashCode => radians.hashCode;
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
  final ValueNotifier<RotationLabelState?> _rotationLabel = ValueNotifier(null);
  final ValueNotifier<NewTextBoxOutlineState?> _newTextBoxOutline =
      ValueNotifier(null);
  Timer? _hoverTimer;
  ToolInteraction? _lastStarted;
  bool _disposed = false;

  /// (v2, E2-18 — 6.5.4) The last barrel roll of this note screen
  /// (StylusExtrasListener notes it; the pen down reads it).
  final BarrelRollTracker barrelRoll = BarrelRollTracker();

  ValueListenable<CursorState?> get cursor => _cursor;

  /// The open context menu (long press / secondary click), or null.
  ValueListenable<ContextMenuRequest?> get contextMenu => _contextMenu;

  void closeContextMenu() {
    if (!_disposed) _contextMenu.value = null;
  }

  /// (v2, 6.6.6) The angle tag while the rotate handle is dragged, or null.
  ValueListenable<RotationLabelState?> get rotationLabel => _rotationLabel;

  /// (v2, 6.11.1) The new text box's outline while the text tool drags, or
  /// null (the NewTextBoxOutline overlay).
  ValueListenable<NewTextBoxOutlineState?> get newTextBoxOutline =>
      _newTextBoxOutline;

  /// The interaction most recently returned by [beginInteraction] (tests,
  /// developer metrics).
  ToolInteraction? get lastStarted => _lastStarted;

  core.NoteSession get session => _session;

  // ---- InputTargets ----

  @override
  InputPolicy get policy {
    final settings = _ref.read(editorSettingsProvider);
    return InputPolicy(
      // (v2, 6.5.3 — S-12(c)) auto is pen only from the start when iPadOS
      // '펜슬로만 그리기' is on (the source's capabilities).
      penOnly: penOnlyEffectiveWith(
        settings,
        _ref.read(stylusExtrasProvider).capabilities,
      ),
      palm: settings.palmRejection,
      gestures: settings.gestures,
      stylusSeen: settings.stylusSeen,
      eyedropperActive: _ref.read(editorToolProvider).eyedropperActive,
      textSessionActive: _ref.read(editorTextEditProvider) != null,
    );
  }

  @override
  ToolInteraction? beginInteraction(
    InputSample sample, {
    required InteractionSource source,
    EditorGesture? gesture,
  }) {
    if (_disposed) return null;
    _hideCursor(); // a pen touching the screen hides the hover cursor
    closeContextMenu();
    final tools = _ref.read(editorToolProvider);
    // ① eyedropper (allowed on read-only notes; no settleNow — 6.6.2).
    if (tools.eyedropperActive) {
      final eyedropper = EyedropperInteraction.start(
        down: sample,
        source: source,
        viewport: _viewport,
        pages: _pages,
        session: _session,
        onPicked: _onEyedropperPicked,
      );
      _lastStarted = eyedropper;
      return eyedropper;
    }
    // ② read-only note → no tool input (6.17.2) — temporary tools included;
    // (v2, m5-7/04-editor 6.14.3) except an already active laser, which
    // stores nothing (it starts straight at the page — no selection).
    final readOnly = _ref.read(editorReadOnlyProvider);
    if (readOnly &&
        !(tools.activeTool == EditorTool.pen &&
            tools.penType == core.PenTool.laser &&
            _temporaryToolFor(gesture) == null)) {
      return null;
    }
    // (v2, 6.3.6 3) a pen / mouse contact while a text session is open (a
    // finger never gets here during one — 6.3.4): the session ends
    // (penContact — its one command runs inside end()) and the contact goes
    // on with the current tool.
    if (_ref.read(editorTextEditProvider) != null) {
      unawaited(
        _ref
            .read(editorTextEditProvider.notifier)
            .end(reason: TextEditEndReason.penContact),
      );
    }
    final selections = _ref.read(editorSelectionProvider.notifier);
    // (v2, 6.3.6 4) a pen button / eraser tip at contact → a temporary tool
    // for this contact only; ToolState does not change (6.2.3).
    final temporary = _temporaryToolFor(gesture);
    // (math pen) without EditorExtensions.mathPen a stored math tool acts as
    // the pen.
    final tool = _effective(temporary ?? tools.activeTool);
    // ③ (v2 6.3.6 5 — selection priority (a′), 6.6.2) a handle → the
    // selection's handle drag whatever the tool; the body → a move with the
    // lasso tool or a lasso / paste / insert selection, else the selection
    // is dropped and the tool runs. A temporary lasso always starts a new
    // lasso (E2-04a).
    // (E2-10) a down that drops a selection on its body: the text tool's tap
    // there is a new box, not that object selected again (6.11.1).
    var droppedBody = false;
    if (!readOnly && (tool != EditorTool.lasso || temporary == null)) {
      final at = _selectionHitAt(sample.position);
      if (at != null) {
        final selection = _ref.read(editorSelectionProvider)!;
        switch (selectionPriority(selection.origin, tool, at.kind)) {
          case SelectionPriority.handle:
          case SelectionPriority.move:
            final transform = _beginTransform(
              sample,
              source,
              handle: at.handle,
              tool: tool,
            );
            if (transform != null) {
              _lastStarted = transform;
              return transform;
            }
          case SelectionPriority.drop:
            droppedBody = at.kind == SelectionHitKind.body;
            selections.clear();
        }
      }
    }
    // ④ gap / outside the pages → nothing; (v2 6.3.6 6) the selection is
    // cleared for every tool.
    final hit = _viewport.hitPage(sample.position);
    if (hit == null) {
      selections.clear();
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
    switch (tool) {
      case EditorTool.pen:
        _viewport.settleNow(); // viewScale = layout scale (6.3.4, 7.2.15 v1.1)
        // (v2, E2-18 — 6.5.4) a recent barrel roll turns the calligraphy
        // nib of this stroke only.
        final style = barrelRoll.styleAtPenDown(
          tools.currentPen,
          downTimeStamp: sample.timeStamp,
          capabilities: _ref.read(stylusExtrasProvider).capabilities,
        );
        interaction = PenInteraction.start(
          down: sample,
          source: source,
          controller: mount.controller,
          pageIndex: hit.index,
          viewport: _viewport,
          style: style,
          commands: _commands,
          onCommitted: _onStrokeCommitted,
          // R-1: the recorder's status read now, synchronously, right before
          // beginStroke (on the web this is the contact move — 6.3.2).
          meta: RecordingLink.metaFor(
            _ref.read(core.audioRecorderServiceProvider),
            _session.noteId,
            style.tool,
          ),
          // (v2, E2-15 — 6.10) holdToSnap / off for this pen.
          shapeAssist: shapeAssistFor(
            _ref.read(editorSettingsProvider),
            style.tool,
            _ref.read(ink.inkShapeFitterProvider),
          ),
          // (v2, E2-20 — 6.20) only while '도형 표본 모으기' is on.
          onSample: _ref.read(editorDeviceStateProvider).collectShapeSamples
              ? _recordShapeSample
              : null,
        );
      case EditorTool.math:
        // (math pen, phase 1 — design note 3, 7) a ballpoint stroke in the
        // ballpoint style; the controller commits it (join / reopen / new
        // group). No shape assist, no recording meta change.
        _viewport.settleNow(); // viewScale = layout scale (6.3.4, 7.2.15 v1.1)
        final mathPen = _ref.read(editorMathPenProvider)..contactStarted();
        final reopen = mathPen.reopenTargetAt(hit.pageId, hit.pagePoint);
        final style = tools.penStyles[core.PenTool.ballpoint]!;
        interaction = PenInteraction.start(
          down: sample,
          source: source,
          controller: mount.controller,
          pageIndex: hit.index,
          viewport: _viewport,
          style: style,
          commands: _commands,
          onCommitted: _onStrokeCommitted,
          meta: RecordingLink.metaFor(
            _ref.read(core.audioRecorderServiceProvider),
            _session.noteId,
            style.tool,
          ),
          commit: (controller, edit) => mathPen.commitStroke(
            controller,
            edit,
            pageId: hit.pageId,
            reopen: reopen,
          ),
          onFinished: mathPen.contactEnded,
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
          // A temporary eraser never switches tools (6.2.3).
          onCommitted: temporary == null && eraser.returnToPreviousTool
              ? _returnFromEraser
              : null,
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
      case EditorTool.shape:
        selections.clear();
        interaction = ShapeInteraction.start(
          down: sample,
          source: source,
          controller: mount.controller,
          pageId: hit.pageId,
          pageIndex: hit.index,
          options: _ref.read(editorToolOptionsProvider),
          viewport: _viewport,
          snap: _shapeSnap,
          onCommit: (kind, geometry, style) =>
              _onShapeDrawn(hit.pageId, kind, geometry, style),
          onTap: _onShapeTap,
        );
      case EditorTool.text:
        // (v2, 6.11.1) a tap: the text box there edited, another object
        // selected, else a new box; a drag: a new box as wide as the drag.
        selections.clear();
        final style = _ref.read(editorToolOptionsProvider).textStyle;
        interaction = TextToolInteraction.start(
          down: sample,
          source: source,
          pageId: hit.pageId,
          pageIndex: hit.index,
          lineHeightPt: style.fontSizePt * style.lineHeight,
          viewport: _viewport,
          onOutline: (outline) {
            if (!_disposed) _newTextBoxOutline.value = outline;
          },
          onTap: (screen) => _onTextTap(screen, selectObject: !droppedBody),
          onDrag: (rect) => _onTextDrag(hit.pageId, rect),
        );
    }
    _lastStarted = interaction;
    return interaction;
  }

  /// (math pen) [tool], or the pen for the math tool without
  /// EditorExtensions.mathPen.
  EditorTool _effective(EditorTool tool) =>
      tool == EditorTool.math && !_ref.read(editorMathPenProvider).enabled
      ? EditorTool.pen
      : tool;

  /// (math pen, design note 8) With the math pen, a formula under [screen]
  /// opens its menu (a finger tap, or a finger / mouse dot inside its frame
  /// — a stylus dot is written). Not on a read-only note.
  bool _openFormulaMenuAt(Offset screen) {
    if (_ref.read(editorToolProvider).activeTool != EditorTool.math ||
        _ref.read(editorReadOnlyProvider)) {
      return false;
    }
    final mathPen = _ref.read(editorMathPenProvider);
    if (!mathPen.enabled) return false;
    final hit = _viewport.hitPage(screen);
    if (hit == null) return false;
    final math = mathPen.mathAtPoint(hit.pageId, hit.pagePoint);
    if (math == null) return false;
    _ref.read(editorSelectionProvider.notifier).clear();
    mathPen.openFormulaMenu(math);
    return true;
  }

  /// The temporary tool of a gesture at contact (6.3.3): eraserWhileHeld →
  /// eraser, lassoWhileHeld → lasso, none (or no gesture) → null.
  EditorTool? _temporaryToolFor(EditorGesture? gesture) {
    if (gesture == null) return null;
    final action = _ref
        .read(editorSettingsProvider)
        .gestures
        .actionFor(gesture);
    return switch (action) {
      EditorAction.eraserWhileHeld => EditorTool.eraser,
      EditorAction.lassoWhileHeld => EditorTool.lasso,
      _ => null,
    };
  }

  /// 6.6.8: the stroke's colour (opacity kept) + '색을 가져왔어요', or '여기엔
  /// 획이 없어요'; either way the eyedropper ends.
  void _onEyedropperPicked(int? argb) {
    if (_disposed) return;
    final tools = _ref.read(editorToolProvider.notifier);
    if (argb != null) {
      tools.setColor(argb);
      _commands.notify(EditorStrings.eyedropperPicked);
    } else {
      _commands.notify(EditorStrings.eyedropperMissed);
    }
    tools.setEyedropper(false);
  }

  /// (E2-09, 6.9.2) Shift held → always snap, Alt → never (a hardware
  /// keyboard; without one the thresholds).
  static ShapeSnap _shapeSnap() {
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isAltPressed) return ShapeSnap.off;
    if (keyboard.isShiftPressed) return ShapeSnap.always;
    return ShapeSnap.normal;
  }

  /// (E2-09, 6.9.2 ③) A shape drawn: ObjectFactory → ONE AddObjects
  /// (EditorCommands.addObjects — the limit notice, the rejection) → the
  /// new shape selected with origin drawn (its handles at once).
  void _onShapeDrawn(
    String pageId,
    core.ShapeKind kind,
    core.ShapeGeometry geometry,
    core.ShapeStyle style,
  ) {
    if (_disposed) return;
    final shape = ObjectFactory.shape(
      pageId: pageId,
      kind: kind,
      geometry: geometry,
      style: style,
      newId: _ref.read(core.idGeneratorProvider).newId,
      createdAt: _ref.read(core.clockProvider).now().millisecondsSinceEpoch,
    );
    if (!_commands.addObjects(pageId, [shape])) return;
    _ref.read(editorSelectionProvider.notifier).select(pageId, {
      shape.id,
    }, origin: SelectionOrigin.drawn);
  }

  /// (E2-09) A shape tool tap (a diagonal under 8 px — 6.9.2 ③): the object
  /// there selected (6.3.5 ④, origin tap), else nothing (the down already
  /// dropped the selection).
  void _onShapeTap(Offset screen) {
    if (!_disposed) _tapSelectObject(screen);
  }

  /// (E2-10, 6.11.1) A text tool tap: the text box under it → its edit
  /// session; another object → selected (origin tap — 6.3.5 ④) unless
  /// [selectObject] is false (the down dropped that object's tap selection
  /// — its body down is a new box); else a new box by the tap rule
  /// (newTextBoxAt) in ToolOptions.textStyle.
  void _onTextTap(Offset screen, {required bool selectObject}) {
    if (_disposed ||
        _editTextBoxAt(screen) ||
        (selectObject && _tapSelectObject(screen))) {
      return;
    }
    final hit = _viewport.hitPage(screen);
    if (hit == null) return;
    final page = _viewport.pages[hit.index];
    _startNewTextBox(
      hit.pageId,
      newTextBoxAt(
        id: _ref.read(core.idGeneratorProvider).newId(),
        pageId: hit.pageId,
        point: hit.pagePoint,
        pageWidth: page.size.width,
        style: _ref.read(editorToolOptionsProvider).textStyle.normalized(),
        createdAt: _ref.read(core.clockProvider).now().millisecondsSinceEpoch,
      ),
    );
  }

  /// (E2-10, 6.11.1) A text tool drag: a new box over the outline.
  void _onTextDrag(String pageId, Rect rectPt) {
    if (_disposed) return;
    _startNewTextBox(
      pageId,
      ObjectFactory.textBox(
        pageId: pageId,
        rectPt: rectPt,
        style: _ref.read(editorToolOptionsProvider).textStyle,
        newId: _ref.read(core.idGeneratorProvider).newId,
        createdAt: _ref.read(core.clockProvider).now().millisecondsSinceEpoch,
      ),
    );
  }

  /// A new box's session — not when the page is full (the notice instead:
  /// its AddObjects would go over the limit — 5.1.1).
  void _startNewTextBox(String pageId, core.TextBoxObject box) {
    final content = _session.pageIfLoaded(pageId);
    if (content != null && ObjectFactory.exceedsLimit(content, 1)) {
      _commands.notify(
        EditorStrings.objectLimitReached(
          core.PageObjectLimits.maxObjectsPerPage,
        ),
      );
      return;
    }
    _ref.read(editorTextEditProvider.notifier).start(box, isNew: true);
  }

  /// (E2-10, 6.3.5 ⑤) The text tool on a text box under [screen]: its edit
  /// session (an existing box). Not on a read-only note.
  bool _editTextBoxAt(Offset screen) {
    if (_ref.read(editorToolProvider).activeTool != EditorTool.text ||
        _ref.read(editorReadOnlyProvider)) {
      return false;
    }
    final hit = _viewport.hitPage(screen);
    if (hit == null) return false;
    final mount = _pages[hit.pageId];
    if (mount == null || mount.isDisposed || !mount.isLoaded.value) {
      return false;
    }
    final object = mount.controller.hitTestObject(
      _viewport.screenToPage(hit.index, screen),
    );
    if (object is! core.TextBoxObject) return false;
    // The stored box (INK's copy may lag a remote edit by a frame).
    final stored = _session.pageIfLoaded(hit.pageId)?.objectById(object.id);
    _ref.read(editorSelectionProvider.notifier).clear();
    _ref
        .read(editorTextEditProvider.notifier)
        .start(stored is core.TextBoxObject ? stored : object, isNew: false);
    return true;
  }

  void _onLassoSelected(String pageId, Set<String> ids) {
    if (_disposed) return;
    _ref.read(editorSelectionProvider.notifier).select(pageId, ids);
  }

  /// (v2) Where [screen] lands on the selection frame (6.6.4 — rotated
  /// frames, the rotate handle): a handle (with it), the body or outside;
  /// null when there is no selection on screen.
  ({SelectionHitKind kind, FrameHandle? handle})? _selectionHitAt(
    Offset screen,
  ) {
    final frame = selectionFrameOnScreen(
      _viewport,
      _pages,
      _ref.read(editorSelectionProvider),
    );
    if (frame == null) return null;
    final handle = frame.hitHandle(screen);
    if (handle != null) return (kind: SelectionHitKind.handle, handle: handle);
    if (frame.hitBody(screen)) {
      return (kind: SelectionHitKind.body, handle: null);
    }
    return (kind: SelectionHitKind.outside, handle: null);
  }

  /// ③: a handle → resize from that corner or (v2) rotate, the body → move
  /// (6.6.5) after the move-start threshold; (v2) a body tap before it is a
  /// selection tap (6.6.2): the text tool on a single text box starts editing
  /// it, else nothing. (E2-08) A single object's edge / vertex handle →
  /// ObjectEditInteraction (UpdateObjects); the modes (vertex mode, aspect
  /// unlock) survive the re-selection after either drag.
  ToolInteraction? _beginTransform(
    InputSample sample,
    InteractionSource source, {
    required FrameHandle? handle,
    required EditorTool tool,
  }) {
    final selection = _ref.read(editorSelectionProvider);
    if (selection == null) return null;
    final mount = _pages[selection.pageId];
    final sel = inkSelectionOf(_pages, selection);
    final index = _viewport.pages.indexWhere((p) => p.id == selection.pageId);
    if (mount == null || sel == null || index < 0) return null;
    _viewport.settleNow(); // viewScale = layout scale (6.3.4, 7.2.15 v1.1)
    final size = _viewport.pages[index].size;
    final notifier = _ref.read(editorSelectionProvider.notifier)
      ..setDragging(true);
    void reselect(Set<String> ids) {
      if (_disposed) return;
      notifier.select(
        selection.pageId,
        ids,
        origin: selection.origin,
        vertexMode: selection.vertexMode,
        aspectUnlocked: selection.aspectUnlocked,
      );
    }

    final single = singleObjectOf(sel);
    if (handle != null &&
        single != null &&
        ObjectEditInteraction.handles(single, handle)) {
      return ObjectEditInteraction.start(
        down: sample,
        source: source,
        controller: mount.controller,
        session: _session,
        pageId: selection.pageId,
        pageIndex: index,
        object: single,
        handle: handle,
        viewport: _viewport,
        commands: _commands,
        // The same id again (UpdateObjects keeps it) — dropped when a remote
        // delete took it during the drag (select filters by INK's content).
        onSettled: () => reselect({single.id}),
        onFinished: () {
          if (!_disposed) notifier.setDragging(false);
        },
      );
    }
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
      // TransformElements keeps ids: select them again (6.6.5), (v2) the
      // origin kept (6.6.3).
      onCommitted: reselect,
      onFinished: () {
        if (_disposed) return;
        _rotationLabel.value = null;
        notifier.setDragging(false);
      },
      onTap: () => _selectionTap(tool),
      onRotate: (radians) {
        if (!_disposed) _rotationLabel.value = RotationLabelState(radians);
      },
    );
  }

  /// (v2, 6.6.2) A tap on the selection body: with the text tool, a single
  /// text box starts its edit session (the selection goes); otherwise
  /// nothing.
  void _selectionTap(EditorTool tool) {
    if (_disposed || tool != EditorTool.text) return;
    final sel = inkSelectionOf(_pages, _ref.read(editorSelectionProvider));
    if (sel == null || sel.strokeIds.isNotEmpty || sel.objects.length != 1) {
      return;
    }
    final box = sel.objects.single;
    if (box is! core.TextBoxObject) return;
    _ref.read(editorSelectionProvider.notifier).clear();
    _ref.read(editorTextEditProvider.notifier).start(box, isNew: false);
  }

  /// (v2, 6.3.5 ④) A one-finger tap with the lasso or shape tool on an
  /// object selects it (origin lasso / tap); the text tool selects an object
  /// that is not a text box (origin tap — a text box is the text tool's own
  /// tap, 6.3.5 ⑤, E2-10). Not on a read-only note.
  bool _tapSelectObject(Offset screen) {
    final tool = _ref.read(editorToolProvider).activeTool;
    if (tool != EditorTool.lasso &&
        tool != EditorTool.shape &&
        tool != EditorTool.text) {
      return false;
    }
    if (_ref.read(editorReadOnlyProvider)) return false;
    final hit = _viewport.hitPage(screen);
    if (hit == null) return false;
    final mount = _pages[hit.pageId];
    if (mount == null || mount.isDisposed || !mount.isLoaded.value) {
      return false;
    }
    final object = mount.controller.hitTestObject(
      _viewport.screenToPage(hit.index, screen),
    );
    if (object == null) return false;
    if (tool == EditorTool.text && object is core.TextBoxObject) return false;
    _ref.read(editorSelectionProvider.notifier).select(
      hit.pageId,
      {object.id},
      origin: tool == EditorTool.lasso
          ? SelectionOrigin.lasso
          : SelectionOrigin.tap,
    );
    return true;
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

  /// (v2, 6.3.5) A pen dot before its stroke ends: ② a memorization tape
  /// under it is toggled (E2-14), else ③ tap-to-seek on a stroke of the open
  /// recording. A finger in finger drawing takes the finger condition
  /// (TapKind.finger), a pen or a mouse the pen-dot one. Not taken → the dot
  /// stays a dot stroke.
  @override
  bool interceptPenDot(
    InputSample sample, {
    required InteractionSource source,
  }) {
    if (_disposed) return false;
    if (_toggleTapeAt(sample.position)) return true;
    // (math pen) ④m a finger (finger drawing) or mouse dot inside a
    // formula's frame → its menu. A STYLUS dot there is written (a decimal
    // point, a multiplication dot, the dot of an i — design note 7: it
    // reopens the formula); a pen user opens the menu with a finger tap.
    if (source != InteractionSource.stylus &&
        _openFormulaMenuAt(sample.position)) {
      return true;
    }
    return _tapToSeek(
      sample.position,
      source == InteractionSource.finger ? TapKind.finger : TapKind.penDot,
    );
  }

  /// ② (6.3.5, 6.14.4): the memorization tape under [screen] (INK
  /// hitTestTape on its mounted, loaded page) is revealed / covered again —
  /// per controller, never stored (U10), no command. Allowed on a read-only
  /// note (nothing is stored).
  bool _toggleTapeAt(Offset screen) {
    final hit = _viewport.hitPage(screen);
    if (hit == null) return false;
    final mount = _pages[hit.pageId];
    if (mount == null || mount.isDisposed || !mount.isLoaded.value) {
      return false;
    }
    final tape = mount.controller.hitTestTape(
      _viewport.screenToPage(hit.index, screen),
    );
    if (tape == null) return false;
    mount.controller.toggleTape(tape.id);
    return true;
  }

  /// Tap-to-seek tolerance in logical px (12 / scale pt on the page — 6.15.3).
  static const double _tapToSeekTolerancePx = 12;

  /// ③ (6.15.3): in the tap-to-seek state, a stroke of the open recording
  /// under [screen] → `seekMs(max(0, offset − preRollMs))`, markSeek, play.
  /// Every value is read synchronously now (6.3.5).
  bool _tapToSeek(Offset screen, TapKind kind) {
    final playback = _ref.read(core.audioPlaybackServiceProvider);
    final status = playback.status;
    final active = tapToSeekActive(
      kind: kind,
      tapToSeekSetting: _ref.read(editorSettingsProvider).tapToSeek,
      recorderPhase: _ref.read(core.audioRecorderServiceProvider).status.phase,
      panelOpen: _ref.read(editorPanelProvider),
      playback: status,
      noteRecordingIds: _ref.read(editorNoteRecordingIdsProvider),
    );
    final recordingId = status.recordingId;
    if (!active || recordingId == null) return false;
    final hit = _viewport.hitPage(screen);
    if (hit == null) return false;
    final mount = _pages[hit.pageId];
    if (mount == null || mount.isDisposed || !mount.isLoaded.value) {
      return false;
    }
    final stroke = mount.controller.hitTestRecorded(
      _viewport.screenToPage(hit.index, screen),
      recordingId: recordingId,
      tolerance: _tapToSeekTolerancePx / _viewport.camera.scale,
    );
    if (stroke == null) return false;
    final offset =
        _session
            .pageIfLoaded(hit.pageId)
            ?.strokeById(stroke.id)
            ?.recordingOffsetMs ??
        stroke.source.recordingOffsetMs;
    if (offset == null) return false;
    final position = tapToSeekPositionMs(
      offset,
      _ref.read(editorPreRollMsProvider),
    );
    unawaited(_seekAndPlay(playback, position));
    return true;
  }

  /// R-5: seek, mark the highlight active, play. Failures are reported only
  /// (the panel shows the player's state — 6.21).
  Future<void> _seekAndPlay(
    core.AudioPlaybackService playback,
    int positionMs,
  ) async {
    final logic = _ref.read(editorPlaybackHighlightProvider);
    try {
      await playback.seekMs(positionMs);
      logic.markSeek();
      await playback.play();
    } on Object catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'feature_editor',
          context: ErrorDescription('while seeking from a tapped stroke'),
        ),
      );
    }
  }

  /// (v2) A selection exists and [screen] hits a handle, or its body when a
  /// body drag moves it (selectionPriority — 6.6.2).
  @override
  bool hitsSelection(Offset screen) {
    if (_disposed) return false;
    // (v2, 6.3.6) the rule of step ③: a handle always, the body when it
    // moves (the lasso tool, or a lasso / paste / insert selection).
    final at = _selectionHitAt(screen);
    final selection = _ref.read(editorSelectionProvider);
    if (at == null || selection == null) return false;
    return selectionPriority(
          selection.origin,
          _ref.read(editorToolProvider).activeTool,
          at.kind,
        ) !=
        SelectionPriority.drop;
  }

  bool _onSelection(Offset screen) {
    final at = _selectionHitAt(screen);
    return at != null && at.kind != SelectionHitKind.outside;
  }

  @override
  void navigationStart() {
    closeContextMenu();
    // (6.11.7) a pan held past the document end may pull to add a page.
    _viewport.beginGesture(allowPullToAdd: !_ref.read(editorReadOnlyProvider));
  }

  @override
  void navigationUpdate(NavigationUpdate update) => _viewport.updateGesture(
    baselineFocal: update.baselineFocal,
    focal: update.focal,
    scaleRatio: update.scaleRatio,
    rebased: update.rebased,
  );

  @override
  void navigationEnd(Velocity velocity) {
    // (6.11.7) released past the threshold: the '+ 페이지' command.
    if (!_viewport.endGesture(velocity)) return;
    if (_disposed || _ref.read(editorReadOnlyProvider)) return;
    unawaited(HapticFeedback.lightImpact());
    unawaited(_commands.addPageAtEndLikeLast());
  }

  @override
  void navigationCancel() => _viewport.cancelGesture();

  /// 1 = (v2) ⓪ an open text session ends (canvasTap — the tap is used up),
  /// else dismiss (context menu → popup → (v2) tap-to-seek ③ → object
  /// selection ④ → the text tool's text box ⑤ → selection cleared),
  /// 2 / 3 = the action of twoFingerTap / threeFingerTap through the action
  /// runner (v2 6.4.2 — undo, redo or toggleEraser). The router only sends
  /// 2 / 3 when the action is not none.
  @override
  void tapGesture(int fingerCount, Offset centroid) {
    switch (fingerCount) {
      case 1:
        if (_ref.read(editorTextEditProvider) != null) {
          unawaited(
            _ref
                .read(editorTextEditProvider.notifier)
                .end(reason: TextEditEndReason.canvasTap),
          );
        } else if (_contextMenu.value != null) {
          closeContextMenu();
        } else if (_ref.read(editorPopupProvider) != null) {
          _ref.read(editorPopupProvider.notifier).close();
        } else if (_ref.read(editorMathPenProvider).formulaMenu != null) {
          // (math pen) an open formula menu closes.
          _ref.read(editorMathPenProvider).closeFormulaMenu();
        } else if (_toggleTapeAt(centroid)) {
          // ② (v2, E2-14) a memorization tape revealed / covered.
        } else if (_tapToSeek(centroid, TapKind.finger)) {
          // ③ taken: the selection stays.
        } else if (_openFormulaMenuAt(centroid)) {
          // ④m (math pen) the formula's menu.
        } else if (_tapSelectObject(centroid)) {
          // ④ (v2) the object under the tap is the selection now.
        } else if (_editTextBoxAt(centroid)) {
          // ⑤ (v2) the text tool edits the text box under the tap.
        } else {
          _commands.clearSelection();
        }
      case 2:
        _runGesture(EditorGesture.twoFingerTap, centroid);
      case 3:
        _runGesture(EditorGesture.threeFingerTap, centroid);
      default:
        break;
    }
  }

  void _runGesture(EditorGesture gesture, Offset at) {
    if (_disposed) return;
    final action = _ref
        .read(editorSettingsProvider)
        .gestures
        .actionFor(gesture);
    _ref.read(editorActionRunnerProvider).run(action, GestureSource(at));
  }

  /// (v2) The fingerLongPress action (6.4.2 — contextMenu by default; the
  /// router does not time a long press whose action is none). An open text
  /// session ends first (longPress — 6.3.4 ②), then the action runs.
  @override
  void longPress(Offset screen) {
    if (_disposed) return;
    if (_ref.read(editorTextEditProvider) != null) {
      unawaited(
        _ref
            .read(editorTextEditProvider.notifier)
            .end(reason: TextEditEndReason.longPress),
      );
    }
    _runGesture(EditorGesture.fingerLongPress, screen);
  }

  /// The mouse right button: always the context menu ([openContextMenuAt]).
  @override
  void secondaryClick(Offset screen) => openContextMenuAt(screen);

  /// On the selection → its menu (already shown while a selection exists);
  /// elsewhere → the context menu (붙여넣기 when the clipboard has strokes,
  /// 올가미 도구). Nothing on a read-only note (both items edit).
  /// EditorAction.contextMenu (6.4.1 — the 1st-round `_menuAt`).
  void openContextMenuAt(Offset screen) {
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
    final metrics = _ref.read(editorDevMetricsProvider);
    if (metrics.isRunning) metrics.recordHover('flutter(${sample.kind.name})');
    final tools = _ref.read(editorToolProvider);
    final scale = _viewport.camera.scale;
    final CursorState? next;
    if (tools.eyedropperActive) {
      next = null;
    } else {
      switch (_effective(tools.activeTool)) {
        case EditorTool.pen when sample.kind != PointerDeviceKind.mouse:
          next = _penDot(tools.currentPen, sample.position, scale);
        case EditorTool.math when sample.kind != PointerDeviceKind.mouse:
          next = _penDot(
            tools.penStyles[core.PenTool.ballpoint]!,
            sample.position,
            scale,
          );
        // (v2, E2-18 — 6.5.3) on the native iPad the pencil hover is a mouse
        // hover; the pen dot comes from the hover pose there, so a mouse
        // hover leaves it alone.
        case EditorTool.pen || EditorTool.math
            when _ref.read(stylusExtrasProvider).capabilities.hoverPose:
          return;
        case EditorTool.eraser:
          next = EraserRingCursor(
            position: sample.position,
            diameter: tools.eraser.diameter * scale,
          );
        case EditorTool.pen:
        case EditorTool.math:
        case EditorTool.lasso:
        case EditorTool.shape:
        case EditorTool.text:
          next = null;
      }
    }
    _cursor.value = next;
    _hoverTimer?.cancel();
    _hoverTimer = next == null ? null : Timer(kHoverCursorTimeout, _hideCursor);
  }

  /// The 1st-round pen dot: max(4, 2 × previewRadius × scale) px, the pen
  /// colour at 50 %, × [sizeFactor] (the hover pose — 6.5.3).
  static PenDotCursor _penDot(
    core.StrokeStyle style,
    Offset position,
    double scale, {
    double sizeFactor = 1,
  }) => PenDotCursor(
    position: position,
    diameter:
        math.max(4, 2 * ink.StrokeStyleInk(style).previewRadius * scale) *
        sizeFactor,
    color: Color(style.colorArgb).withValues(alpha: 0.5),
  );

  /// (v2, E2-18 — 6.5.3) A StylusHoverPose at [position] (viewport px) on a
  /// source with capabilities.hoverPose: the pen tool's pen dot there, the
  /// 1st-round diameter × (1 + 0.5 × height) — at height 0 (touching) the
  /// real width, up to 1.5 × at the top of the hover range (height 0..1,
  /// UIKit zOffset; none → 0) — hidden after [kHoverCursorTimeout] without
  /// a pose. Other tools keep the Flutter hover's cursor.
  void poseHover(Offset position, {double? height}) {
    if (_disposed) return;
    final tools = _ref.read(editorToolProvider);
    final tool = _effective(tools.activeTool);
    // (math pen) the math pen's ballpoint dot too.
    if (tools.eyedropperActive ||
        (tool != EditorTool.pen && tool != EditorTool.math)) {
      return;
    }
    if (_commands.interactionActive) return; // touching: no hover cursor
    final h = (height ?? 0).clamp(0.0, 1.0);
    _cursor.value = _penDot(
      tool == EditorTool.math
          ? tools.penStyles[core.PenTool.ballpoint]!
          : tools.currentPen,
      position,
      _viewport.camera.scale,
      sizeFactor: 1 + 0.5 * h,
    );
    _hoverTimer?.cancel();
    _hoverTimer = Timer(kHoverCursorTimeout, _hideCursor);
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

  /// (v2, E2-20 — 6.20) A pen session's shape sample into the ring buffer.
  void _recordShapeSample(
    List<Offset> points,
    double viewScale,
    ink.InkEdit? edit,
  ) {
    if (_disposed) return;
    _ref
        .read(editorShapeSamplesProvider)
        .add(
          ShapeSample(
            points: points,
            viewScale: viewScale,
            result: resultOf(edit),
            at: _ref.read(core.clockProvider).now().millisecondsSinceEpoch,
          ),
        );
  }

  /// Developer metrics: palm rejections (6.12.1, only while collecting).
  @override
  void palmRejected(InputSample sample) {
    if (_disposed) return;
    final metrics = _ref.read(editorDevMetricsProvider);
    if (metrics.isRunning) metrics.recordPalmRejected();
  }

  /// Pointers down now (developer metrics).
  final Set<int> _downPointers = {};

  /// Developer metrics: the last pointer kind and how many are down (6.12.1).
  @override
  void observe(PointerEvent event, InputSample sample) {
    if (_disposed) return;
    switch (event) {
      case PointerDownEvent():
        _downPointers.add(event.pointer);
      case PointerUpEvent() || PointerCancelEvent() || PointerRemovedEvent():
        _downPointers.remove(event.pointer);
      default:
        break;
    }
    final metrics = _ref.read(editorDevMetricsProvider);
    if (!metrics.isRunning) return;
    final rule = StylusContact.platformRule;
    final stylus =
        event.kind == PointerDeviceKind.stylus ||
        event.kind == PointerDeviceKind.invertedStylus;
    metrics.recordPointer(
      event,
      drawing: _downPointers.isNotEmpty,
      activePointers: _downPointers.length,
      contactRule: rule.name,
      // (v2, 6.20) a stylus event that is not a contact (hover, a web pen
      // in the air with the barrel button held) shows '공중'.
      contact: !stylus || StylusContact.isContact(rule, event),
    );
  }

  void dispose() {
    _disposed = true;
    _hoverTimer?.cancel();
    _hoverTimer = null;
    _cursor.dispose();
    _contextMenu.dispose();
    _rotationLabel.dispose();
    _newTextBoxOutline.dispose();
  }
}
