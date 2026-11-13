// lib/src/tools/text_pen/text_pen_controller.dart — (text pen, phase 1 —
// m5-7/04-editor 6.21) the group life of the 텍스트 펜.
//
// - Every text pen stroke is an ordinary ballpoint stroke, committed as one
//   step like any pen stroke. Which strokes form the open group lives in
//   memory only. Until the user converts it the group is ordinary
//   handwriting — the background indexer reads it for search like any ink.
// - A stroke joins the open group by textPenJoins (same page; the same row
//   within 2.5 H / 0.6 H of the nearest member, or the next row ≤ 1.2 H
//   below; ≤ 20 rows / 400 strokes / 40,000 points); otherwise it starts a
//   new group and the old one simply stays handwriting.
// - Converting happens ONLY on the bubble tap (or the sheet's [텍스트 상자로]
//   through '고치기'). Unlike the math pen a tool switch or a far stroke never
//   converts in the background: a wrong guess would silently replace the
//   user's handwriting. A switch to another tool (not the eraser) closes the
//   group as handwriting.
// - The page's change stream keeps the group true to the page (undo / redo /
//   remote / eraser pieces — PenGroupMembers). The undo of the last
//   conversion (exactly its strokes back, no group open, the text pen or the
//   eraser active) makes that group the open one again — once.
import 'dart:async';
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show BuildContext;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:note_core/note_core.dart' as core;

import '../../commands/editor_commands.dart';
import '../../commands/extension_runner.dart';
import '../../di/editor_extensions.dart';
import '../../scope/editor_scope.dart';
import '../math_pen/math_pen_group.dart'
    show mathPenLineHeight, strokePointBounds, unionPointBounds;
import '../pen_group/pen_group_members.dart';
import '../tool_controller.dart';
import '../tool_state.dart';
import 'text_pen_group.dart';

/// Where the group's life is.
enum TextPenPhase {
  /// no open group
  idle,

  /// a text pen contact is down
  writing,

  /// a group is open (recognition runs in the session)
  open,

  /// the bubble tap's conversion (or the sheet) runs
  converting,
}

/// One per note screen ([editorTextPenProvider]).
class TextPenController extends ChangeNotifier {
  TextPenController({
    required this._session,
    required this._commands,
    required this._textPen,
    required this._bodyContext,
  });

  final core.NoteSession _session;
  final EditorCommands _commands;
  final EditorTextPen? _textPen;
  final BuildContext? Function() _bodyContext;

  EditorTextPenSession? _recognition;
  PenGroupMembers? _group;
  PenGroupMembers? _lastConverted;
  TextPenPhase _phase = TextPenPhase.idle;
  int _revision = 0;
  int _revisionAtContact = -1;
  EditorPenGroup? _value;
  int _valueRevision = -1;
  final Map<String, StreamSubscription<core.PageContentChange>> _watched = {};
  EditorTool? _tool;
  bool _disposed = false;

  /// Whether the 텍스트 펜 is offered (EditorExtensions.textPen is set).
  bool get enabled => _textPen != null;

  TextPenPhase get phase => _phase;

  /// The recognition session (opened with the first group), or null.
  EditorTextPenSession? get recognition => _recognition;

  /// The open group as a value (strokes of the page, z order), or null.
  EditorPenGroup? get group {
    final g = _group;
    if (g == null) return null;
    if (_valueRevision == _revision && _value != null) return _value;
    final strokes = _strokesOf(g);
    if (strokes.isEmpty) return null;
    _valueRevision = _revision;
    return _value = EditorPenGroup(
      pageId: g.pageId,
      strokes: List.unmodifiable(strokes),
      boundsPt: unionPointBounds(strokes),
    );
  }

  /// The ids of the open group, z order (tests).
  @visibleForTesting
  List<String> get groupIds => List.unmodifiable(_group?.ids ?? const []);

  EditorTextPenSession? _ensureRecognition() {
    final textPen = _textPen;
    if (textPen == null || _disposed) return null;
    return _recognition ??= textPen.open(
      EditorPenContext(
        noteId: _session.noteId,
        pageSizeOf: (pageId) =>
            _session.pages.where((p) => p.id == pageId).firstOrNull?.size,
        execute: _commands.executeForExtension,
        liveStrokes: _liveStrokes,
        bodyContext: _bodyContext,
      ),
    );
  }

  List<core.Stroke>? _liveStrokes(String pageId, List<String> ids) {
    final content = _session.pageIfLoaded(pageId);
    if (content == null) return null;
    final out = <core.Stroke>[];
    for (final id in ids) {
      final s = content.strokeById(id);
      if (s == null) return null;
      out.add(s);
    }
    return out;
  }

  List<core.Stroke> _strokesOf(PenGroupMembers g) {
    final content = _session.pageIfLoaded(g.pageId);
    if (content == null) return const [];
    return [for (final id in g.ids) ?content.strokeById(id)];
  }

  void _changed() {
    _revision++;
    if (!_disposed) notifyListeners();
  }

  void _setGroup(PenGroupMembers? g) {
    _group = g;
    _phase = g == null ? TextPenPhase.idle : TextPenPhase.open;
    _watch();
    _changed();
    final value = group;
    if (value == null) {
      _recognition?.clear();
    } else {
      _ensureRecognition()?.update(value);
    }
  }

  /// Subscribes to the pages of the open group and of the last conversion.
  void _watch() {
    final pages = {?_group?.pageId, ?_lastConverted?.pageId};
    for (final id in _watched.keys.toList()) {
      if (!pages.contains(id)) unawaited(_watched.remove(id)!.cancel());
    }
    for (final id in pages) {
      _watched[id] ??= _session.pageChanges(id).listen(_onPageChange);
    }
  }

  // ---- contacts ----

  /// A text pen contact went down: the session stops its timer.
  void contactStarted() {
    if (!enabled || _disposed) return;
    _phase = TextPenPhase.writing;
    _revisionAtContact = _revision;
    _recognition?.interrupt();
    notifyListeners();
  }

  /// The contact ended (committed, refused, a dot or cancelled). When it did
  /// not change the group, recognition resumes for it.
  void contactEnded() {
    if (!enabled || _disposed) return;
    if (_phase == TextPenPhase.writing) {
      _phase = _group == null ? TextPenPhase.idle : TextPenPhase.open;
    }
    if (_revision == _revisionAtContact) {
      final value = group;
      if (value != null) _recognition?.update(value);
    }
    notifyListeners();
  }

  bool _joins(PenGroupMembers g, core.Stroke stroke) {
    final strokes = _strokesOf(g);
    if (strokes.isEmpty) return false;
    var points = 0;
    for (final s in strokes) {
      points += s.points.length;
    }
    return textPenJoins(
      members: [for (final s in strokes) strokePointBounds(s)],
      stroke: strokePointBounds(stroke),
      groupPoints: points,
      strokePoints: stroke.points.length,
    );
  }

  /// Commits the stroke of a text pen contact (PenInteraction.commit): it
  /// joins the open group or starts a new one (the old one stays
  /// handwriting). Returns whether the stroke is committed.
  bool commitStroke(
    ink.InkPageController controller,
    ink.InkEdit edit, {
    required String pageId,
  }) {
    if (!enabled ||
        _disposed ||
        edit.kind != ink.InkEditKind.addStroke ||
        edit.added.length != 1) {
      return _commands.commitInkEdit(controller, edit);
    }
    final stroke = edit.added.single;
    final old = _group;
    final joins = old != null && old.pageId == pageId && _joins(old, stroke);
    if (!_commands.commitInkEdit(controller, edit)) return false;
    if (joins) {
      old.add(stroke);
      _setGroup(old);
    } else {
      _setGroup(PenGroupMembers(pageId, [stroke]));
    }
    return true;
  }

  // ---- conversion ----

  /// The bubble tap: converts the open group (the session may open the
  /// sheet). Completes true when the text box was added.
  Future<bool> convertOpenGroup() => _run((session, value) {
    return session.convert(value);
  });

  /// '고치기' / a long press on the bubble: the conversion sheet on the open
  /// group. Completes true when the text box was added.
  Future<bool> fixOpenGroup() => _run((session, value) => session.fix(value));

  Future<bool> _run(
    Future<bool> Function(EditorTextPenSession session, EditorPenGroup value)
    body,
  ) async {
    final session = _recognition;
    final g = _group;
    final value = group;
    if (session == null || g == null || value == null || _disposed) {
      return false;
    }
    if (_phase == TextPenPhase.converting) return false;
    _phase = TextPenPhase.converting;
    notifyListeners();
    bool ok;
    try {
      ok = await body(session, value);
    } on Object catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'feature_editor',
          context: ErrorDescription('while converting a text pen group'),
        ),
      );
      ok = false;
    }
    if (_disposed) return ok;
    if (ok) {
      // The strokes are gone now; the undo of this step brings them back as
      // this group.
      _lastConverted = PenGroupMembers(g.pageId, value.strokes);
      _watch();
    }
    if (identical(_group, g)) {
      final converted = {for (final s in value.strokes) s.id};
      final left = [
        for (final s in _strokesOf(g))
          if (!converted.contains(s.id)) s,
      ];
      if (ok && left.isNotEmpty) {
        // Strokes joined while the tap waited: they stay the open group.
        _setGroup(PenGroupMembers(g.pageId, left));
      } else if (ok) {
        _group = null;
        _phase = TextPenPhase.idle;
        _watch();
        _changed();
        session.clear();
      } else {
        _phase = TextPenPhase.open;
        notifyListeners();
        final again = group;
        if (again != null) session.update(again);
      }
    } else if (_phase == TextPenPhase.converting) {
      _phase = _group == null ? TextPenPhase.idle : TextPenPhase.open;
      notifyListeners();
    }
    return ok;
  }

  /// The insert menu's '손글씨를 텍스트로' with an ink selection: the
  /// conversion sheet on [strokes] (page [pageId]). The open group, if any,
  /// stays handwriting and closes. Completes true when the box was added.
  Future<bool> convertStrokes(String pageId, List<core.Stroke> strokes) async {
    if (!enabled || _disposed || strokes.isEmpty) return false;
    if (_group != null) _setGroup(null);
    final session = _ensureRecognition();
    if (session == null) return false;
    try {
      return await session.fix(
        EditorPenGroup(
          pageId: pageId,
          strokes: List.unmodifiable(strokes),
          boundsPt: unionPointBounds(strokes),
        ),
      );
    } on Object catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'feature_editor',
          context: ErrorDescription('while converting selected handwriting'),
        ),
      );
      return false;
    }
  }

  /// The active tool changed to [next]: a switch to a tool other than the
  /// text pen and the eraser closes the open group — it stays handwriting
  /// (never a background conversion).
  void toolChanged(EditorTool? previous, EditorTool next) {
    _tool = next;
    if (!enabled || _disposed || _group == null) return;
    if (next == EditorTool.textPen || next == EditorTool.eraser) return;
    if (_phase == TextPenPhase.converting) return; // the sheet decides
    _setGroup(null);
  }

  /// The note became read-only: the group closes (it stays handwriting).
  void readOnlyChanged(bool readOnly) {
    if (!readOnly || _disposed) return;
    _lastConverted = null;
    _setGroup(null);
  }

  // ---- the page (undo / redo / remote / eraser) ----

  void _onPageChange(core.PageContentChange change) {
    if (_disposed) return;
    final content = change.content;
    final pageId = content.page.id;
    final g = _group;
    if (g != null && g.pageId == pageId) {
      switch (g.sync(change)) {
        case PenGroupSync.members:
          _setGroup(g.ids.isEmpty ? null : g);
          return;
        case PenGroupSync.updatedInPlace:
          _setGroup(g);
          return;
        case PenGroupSync.none:
          break;
      }
    }
    final last = _lastConverted;
    if (last != null && last.cameBackIn(change)) {
      // The undo of the last conversion — once.
      _lastConverted = null;
      if (_group == null &&
          (_tool == EditorTool.textPen || _tool == EditorTool.eraser)) {
        _setGroup(
          PenGroupMembers(pageId, [
            for (final id in last.ids) content.strokeById(id)!,
          ]),
        );
      } else {
        _watch();
      }
    }
  }

  /// Where the bubble keeps away from (page pt): the group's bounds grown by
  /// bubbleAboveFactor × H up and bubbleBelowFactor × H down — where the
  /// next row starts, so the bubble (which takes the pointer) never sits on
  /// it.
  Rect? get bubbleAnchorPt {
    final value = group;
    if (value == null) return null;
    final h = mathPenLineHeight([
      for (final s in value.strokes) strokePointBounds(s).height,
    ]);
    final b = value.boundsPt;
    return Rect.fromLTRB(
      b.left,
      b.top - TextPenTuning.bubbleAboveFactor * h,
      b.right,
      b.bottom + TextPenTuning.bubbleBelowFactor * h,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    for (final sub in _watched.values) {
      unawaited(sub.cancel());
    }
    _watched.clear();
    // Leaving the note never converts: the group stays handwriting.
    final recognition = _recognition;
    _recognition = null;
    recognition?.clear();
    recognition?.dispose();
    super.dispose();
  }
}

/// Per note: the text pen controller (EditorExtensions.textPen; disabled
/// without it).
final editorTextPenProvider = Provider<TextPenController>(
  (ref) {
    final runner = ref.watch(editorExtensionRunnerProvider);
    final controller = TextPenController(
      session: ref.watch(editorSessionValueProvider),
      commands: ref.watch(editorCommandsProvider),
      textPen: ref.watch(editorExtensionsProvider.select((e) => e.textPen)),
      bodyContext: () => runner.bodyContext,
    );
    controller.toolChanged(null, ref.read(editorToolProvider).activeTool);
    ref.listen(
      editorToolProvider.select((s) => s.activeTool),
      controller.toolChanged,
    );
    ref.listen(editorReadOnlyProvider, (_, readOnly) {
      controller.readOnlyChanged(readOnly);
    });
    ref.onDispose(controller.dispose);
    return controller;
  },
  dependencies: [
    editorSessionValueProvider,
    editorCommandsProvider,
    editorExtensionRunnerProvider,
    editorReadOnlyProvider,
  ],
  name: 'editorTextPenProvider',
);
