// lib/src/tools/math_pen/math_pen_controller.dart — (math pen, phase 1) the
// group life of the 수식 펜 (docs/plans/m5-7/research/math-pen-phase1.md 3,
// 4, 7, 8, 9).
//
// - Every math pen stroke is an ordinary ballpoint stroke, committed as one
//   step like any pen stroke (nothing is lost when the note closes). Which
//   strokes form the open group lives in memory only: nothing is stored on
//   the strokes. An unconverted group is never converted when the note or
//   the page is left: it simply stays as handwriting.
// - A stroke joins the open group by mathPenJoins (same page, gaps within
//   1.5 H / 0.6 H of the nearest member, the ink limits); otherwise it
//   starts a new group and the old one is converted in the background
//   (EditorMathConvertTrigger.newGroup) BEFORE the new stroke is committed,
//   so one undo takes back the stroke just written, not the conversion.
// - A stroke whose start is on / near a formula that kept its handwriting
//   reopens it: ONE command removes the formula and adds its handwriting
//   (new ids) and the new stroke; that becomes the open group. Not when
//   the handwriting plus the stroke would go over the ink limits.
// - Conversions: the bubble tap (a sheet may open), a switch to another tool
//   (not the eraser: erasing a part of the group keeps it open; leaving the
//   eraser for a tool other than the math pen converts), a new group far
//   away. Background conversions only use a usable recognition result —
//   else the group stays handwriting — and only while the note's history
//   is as it was when they were triggered (for newGroup: right after the
//   new stroke): an answer that arrives after the user did something else
//   is dropped, so a late step never lands on top of later work or clears
//   redo. A reopened group that does not convert says so (a snackbar).
// - The page's change stream keeps the group true to the page: undo / redo /
//   remote changes / the eraser (a partial-eraser piece keeps its stroke's
//   createdAt, style and recording — Stroke.fragment — and lies inside the
//   erased stroke's bounds, so it stays in the group). The undo of the last
//   conversion (exactly its strokes back, no group open, the math pen or
//   the eraser active) makes that group the open one again — once.
import 'dart:async';
import 'dart:ui' show Offset, Rect;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show BuildContext;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:note_core/note_core.dart' as core;

import '../../commands/editor_commands.dart';
import '../../commands/extension_runner.dart';
import '../../di/editor_extensions.dart';
import '../../scope/editor_scope.dart';
import '../../ui/editor_strings.dart';
import '../tool_controller.dart';
import '../tool_state.dart';
import 'math_pen_group.dart';

/// Where the group's life is (design note 4.1).
enum MathPenPhase {
  /// no open group
  idle,

  /// a math pen contact is down
  writing,

  /// a group is open (recognition runs in the session)
  open,

  /// the bubble tap's conversion runs (a sheet may be open)
  converting,
}

/// The small menu of a tapped formula (design note 8).
@immutable
final class MathFormulaMenu {
  const MathFormulaMenu({required this.pageId, required this.mathId});
  final String pageId;
  final String mathId;

  @override
  bool operator ==(Object other) =>
      other is MathFormulaMenu &&
      other.pageId == pageId &&
      other.mathId == mathId;

  @override
  int get hashCode => Object.hash(pageId, mathId);
}

/// What a partial-eraser piece of a member keeps (Stroke.fragment): the
/// piece belongs to the group when it matches the erased member.
final class _Origin {
  _Origin(core.Stroke s)
    : createdAt = s.createdAt,
      style = s.style,
      recordingId = s.recordingId,
      recordingOffsetMs = s.recordingOffsetMs,
      bounds = strokePointBounds(s).inflate(0.5);

  final int createdAt;
  final core.StrokeStyle style;
  final String? recordingId;
  final int? recordingOffsetMs;
  final Rect bounds;

  bool isPieceOf(core.Stroke piece) {
    if (piece.createdAt != createdAt ||
        piece.style != style ||
        piece.recordingId != recordingId ||
        piece.recordingOffsetMs != recordingOffsetMs) {
      return false;
    }
    final b = strokePointBounds(piece);
    return bounds.contains(b.topLeft) && bounds.contains(b.bottomRight);
  }
}

/// The history as a background conversion found it (see
/// [MathPenController._convertInBackground]).
final class _HistoryMark {
  _HistoryMark(this.state);
  core.HistoryState state;
}

final class _Group {
  _Group(
    this.pageId,
    List<core.Stroke> strokes, {
    this.reopenedFrom,
    this.reopenedIds = const {},
    this.restored = false,
  }) {
    strokes.forEach(add);
  }

  final String pageId;
  final List<String> ids = [];
  final Set<String> known = {};
  final Map<String, _Origin> originOf = {};
  final core.MathObject? reopenedFrom;
  final Set<String> reopenedIds;

  /// Brought back by undoing its conversion: the user chose the handwriting,
  /// so a tool switch or a new group leaves it handwriting (only the bubble
  /// converts it) until it is written on with the math pen again (erasing
  /// a part keeps the choice).
  bool restored;

  void add(core.Stroke s) {
    if (!ids.contains(s.id)) ids.add(s.id);
    known.add(s.id);
    originOf[s.id] = _Origin(s);
  }
}

/// One per note screen ([editorMathPenProvider]).
class MathPenController extends ChangeNotifier {
  MathPenController({
    required this._session,
    required this._commands,
    required this._mathPen,
    required this._bodyContext,
    required this._newId,
    required this._now,
  });

  final core.NoteSession _session;
  final EditorCommands _commands;
  final EditorMathPen? _mathPen;
  final BuildContext? Function() _bodyContext;
  final String Function() _newId;
  final core.EpochMillis Function() _now;

  EditorMathPenSession? _recognition;
  _Group? _group;
  _Group? _lastConverted;
  MathPenPhase _phase = MathPenPhase.idle;
  MathFormulaMenu? _menu;
  int _revision = 0;
  int _revisionAtContact = -1;
  EditorMathGroup? _value;
  int _valueRevision = -1;
  final Map<String, StreamSubscription<core.PageContentChange>> _watched = {};
  EditorTool? _tool;
  bool _disposed = false;

  /// Whether the 수식 펜 is offered (EditorExtensions.mathPen is set).
  bool get enabled => _mathPen != null;

  MathPenPhase get phase => _phase;

  /// The tapped formula's menu, or null.
  MathFormulaMenu? get formulaMenu => _menu;

  /// The recognition session (opened with the first group or menu), or null.
  EditorMathPenSession? get recognition => _recognition;

  /// The open group as a value (strokes of the page, z order), or null.
  EditorMathGroup? get group {
    final g = _group;
    if (g == null) return null;
    if (_valueRevision == _revision && _value != null) return _value;
    final strokes = _strokesOf(g);
    if (strokes.isEmpty) return null;
    _valueRevision = _revision;
    return _value = EditorMathGroup(
      pageId: g.pageId,
      strokes: List.unmodifiable(strokes),
      boundsPt: unionPointBounds(strokes),
      reopenedFrom: g.reopenedFrom,
      reopenedStrokeIds: Set.unmodifiable(
        g.reopenedIds.where(g.known.contains),
      ),
    );
  }

  /// The ids of the open group, z order (tests).
  @visibleForTesting
  List<String> get groupIds => List.unmodifiable(_group?.ids ?? const []);

  EditorMathPenSession? _ensureRecognition() {
    final mathPen = _mathPen;
    if (mathPen == null || _disposed) return null;
    return _recognition ??= mathPen.open(
      EditorMathPenContext(
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

  List<core.Stroke> _strokesOf(_Group g) {
    final content = _session.pageIfLoaded(g.pageId);
    if (content == null) return const [];
    return [for (final id in g.ids) ?content.strokeById(id)];
  }

  void _changed() {
    _revision++;
    if (!_disposed) notifyListeners();
  }

  void _setGroup(_Group? g) {
    _group = g;
    _phase = g == null ? MathPenPhase.idle : MathPenPhase.open;
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

  /// A math pen contact went down: the session stops its timer and cancels
  /// the request in flight; a formula menu closes.
  void contactStarted() {
    if (!enabled || _disposed) return;
    _menu = null;
    _phase = MathPenPhase.writing;
    _revisionAtContact = _revision;
    _recognition?.interrupt();
    notifyListeners();
  }

  /// The contact ended (committed, refused, taken as a dot or cancelled).
  /// When it did not change the group, recognition resumes for it.
  void contactEnded() {
    if (!enabled || _disposed) return;
    if (_phase == MathPenPhase.writing) {
      _phase = _group == null ? MathPenPhase.idle : MathPenPhase.open;
    }
    if (_revision == _revisionAtContact) {
      final value = group;
      if (value != null) _recognition?.update(value);
    }
    notifyListeners();
  }

  /// The formula a stroke starting at [pagePoint] would reopen (design note
  /// 7.1), or null.
  core.MathObject? reopenTargetAt(String pageId, Offset pagePoint) {
    final content = _session.pageIfLoaded(pageId);
    if (content == null || !enabled) return null;
    return reopenCandidateAt(content.objects, pagePoint);
  }

  /// The formula exactly under [pagePoint] (a tap or a pen dot), or null.
  core.MathObject? mathAtPoint(String pageId, Offset pagePoint) {
    final content = _session.pageIfLoaded(pageId);
    if (content == null || !enabled) return null;
    return mathAt(content.objects, pagePoint);
  }

  bool _joins(_Group g, core.Stroke stroke) {
    final strokes = _strokesOf(g);
    if (strokes.isEmpty) return false;
    var points = 0;
    for (final s in strokes) {
      points += s.points.length;
    }
    return mathPenJoins(
      members: [for (final s in strokes) strokePointBounds(s)],
      stroke: strokePointBounds(stroke),
      groupPoints: points,
      strokePoints: stroke.points.length,
    );
  }

  /// Commits the stroke of a math pen contact (PenInteraction.commit):
  /// joins the open group, reopens [reopen] with it (one command), or starts
  /// a new group — the old one converts in the background first, so the
  /// stroke lands after it in the history. Returns whether the stroke is
  /// committed.
  bool commitStroke(
    ink.InkPageController controller,
    ink.InkEdit edit, {
    required String pageId,
    core.MathObject? reopen,
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
    core.MathObject? target;
    if (!joins && reopen != null) {
      final live = _session.pageIfLoaded(pageId)?.objectById(reopen.id);
      // Not over the ink limits with the new stroke: the next conversion
      // would have to drop the handwriting.
      if (live is core.MathObject &&
          live.ink.isNotEmpty &&
          mathInkWithin(live.ink, extra: stroke)) {
        target = live;
      }
    }
    final mark = !joins && old != null
        ? _convertInBackground(EditorMathConvertTrigger.newGroup)
        : null;
    if (target != null) {
      final strokes = reopenedStrokes(target, newId: _newId, now: _now());
      final result = _commands.commitInkEditWith(
        controller,
        edit,
        before: [
          core.RemoveElements(pageId: pageId, elementIds: [target.id]),
          core.AddStrokes(pageId: pageId, strokes: strokes),
        ],
        label: 'editor-math-reopen-write',
      );
      if (!result.committed) return false;
      mark?.state = _session.history;
      _setGroup(
        result.withBefore
            ? _Group(
                pageId,
                [...strokes, stroke],
                reopenedFrom: target,
                reopenedIds: {for (final s in strokes) s.id},
              )
            : _Group(pageId, [stroke]),
      );
      return true;
    }
    if (!_commands.commitInkEdit(controller, edit)) return false;
    // The late answer of the old group may still land right after this
    // stroke, but not after anything else.
    mark?.state = _session.history;
    if (joins) {
      old
        ..add(stroke)
        ..restored = false;
      _setGroup(old);
    } else {
      _setGroup(_Group(pageId, [stroke]));
    }
    return true;
  }

  // ---- conversion ----

  /// Hands the open group to the session ([trigger] never opens a sheet)
  /// and closes it at once; a failed conversion leaves it handwriting. The
  /// session converts only while the history is still [_HistoryMark.state]
  /// (the caller may move the mark past its own next step). A ready answer
  /// converts synchronously, before this returns.
  _HistoryMark _convertInBackground(EditorMathConvertTrigger trigger) {
    final mark = _HistoryMark(_session.history);
    final g = _group;
    final value = group;
    _group = null;
    _phase = MathPenPhase.idle;
    _watch();
    _changed();
    final session = _recognition;
    if (session == null) return mark;
    if (g != null && value != null && !g.restored) {
      // convert reads a ready result before its first await; then the
      // display state goes.
      unawaited(
        _convert(
          session,
          g,
          value,
          trigger,
          stillWanted: () => !_disposed && _session.history == mark.state,
        ),
      );
    }
    session.clear();
    return mark;
  }

  Future<bool> _convert(
    EditorMathPenSession session,
    _Group g,
    EditorMathGroup value,
    EditorMathConvertTrigger trigger, {
    bool Function()? stillWanted,
  }) async {
    bool ok;
    try {
      ok = await session.convert(value, trigger, stillWanted: stillWanted);
    } on Object catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'feature_editor',
          context: ErrorDescription('while converting a math pen group'),
        ),
      );
      ok = false;
    }
    if (_disposed) return ok;
    if (ok) {
      // The strokes are gone now; the undo of this step brings them back as
      // this group.
      _lastConverted = _Group(
        g.pageId,
        value.strokes,
        reopenedFrom: value.reopenedFrom,
        reopenedIds: value.reopenedStrokeIds,
      );
      _watch();
    } else if (trigger != EditorMathConvertTrigger.bubbleTap &&
        value.reopenedFrom != null) {
      // A reopened formula that stays handwriting: say so (undo brings the
      // formula back).
      _commands.showMessage(EditorStrings.mathKeptHandwriting);
    }
    return ok;
  }

  /// The bubble tap: converts the open group (the session may open a
  /// sheet). Completes true when the formula was added.
  Future<bool> convertOpenGroup() async {
    final session = _recognition;
    final g = _group;
    final value = group;
    if (session == null || g == null || value == null || _disposed) {
      return false;
    }
    if (_phase == MathPenPhase.converting) return false;
    _phase = MathPenPhase.converting;
    notifyListeners();
    final ok = await _convert(
      session,
      g,
      value,
      EditorMathConvertTrigger.bubbleTap,
    );
    if (_disposed) return ok;
    if (identical(_group, g)) {
      final converted = {for (final s in value.strokes) s.id};
      final left = [
        for (final s in _strokesOf(g))
          if (!converted.contains(s.id)) s,
      ];
      if (ok && left.isNotEmpty) {
        // Strokes joined while the tap waited: they stay the open group.
        _setGroup(_Group(g.pageId, left));
      } else if (ok) {
        _group = null;
        _phase = MathPenPhase.idle;
        _watch();
        _changed();
        session.clear();
      } else {
        _phase = MathPenPhase.open;
        notifyListeners();
        final again = group;
        if (again != null) session.update(again);
      }
    }
    return ok;
  }

  /// The active tool changed from [previous] to [next]: a switch to a tool
  /// other than the math pen and the eraser converts the open group in the
  /// background (design note 4.2, 9); a formula menu closes.
  void toolChanged(EditorTool? previous, EditorTool next) {
    _tool = next;
    if (!enabled || _disposed) return;
    if (next != EditorTool.math && _menu != null) {
      _menu = null;
      notifyListeners();
    }
    if (_group == null) return;
    if (next == EditorTool.math || next == EditorTool.eraser) return;
    _convertInBackground(EditorMathConvertTrigger.toolSwitch);
  }

  /// The note became read-only: the group closes (no conversion — it stays
  /// handwriting) and a formula menu closes.
  void readOnlyChanged(bool readOnly) {
    if (!readOnly || _disposed) return;
    _menu = null;
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
      // A member moved / recoloured in place: its pieces follow the new one.
      for (final id in change.updated) {
        final s = g.known.contains(id) ? content.strokeById(id) : null;
        if (s != null) g.originOf[id] = _Origin(s);
      }
      final gone = [
        for (final id in g.ids)
          if (content.strokeById(id) == null) id,
      ];
      if (gone.isNotEmpty && change.added.isNotEmpty) {
        // Partial-eraser pieces: the erased member's createdAt, style and
        // recording, inside its bounds (a pasted copy of the same ink is
        // elsewhere).
        final origins = [for (final id in gone) ?g.originOf[id]];
        for (final id in change.added) {
          final s = content.strokeById(id);
          if (s != null &&
              !g.known.contains(id) &&
              origins.any((o) => o.isPieceOf(s))) {
            g.add(s);
          }
        }
      }
      final ids = [
        for (final s in content.strokes)
          if (g.known.contains(s.id)) s.id,
      ];
      if (!listEquals(ids, g.ids)) {
        g.ids
          ..clear()
          ..addAll(ids);
        _setGroup(ids.isEmpty ? null : g);
        return;
      }
      if (change.updated.any(g.known.contains)) {
        _setGroup(g); // a member changed in place (a remote edit, a recolour)
        return;
      }
    }
    final last = _lastConverted;
    if (last != null &&
        last.pageId == pageId &&
        last.ids.isNotEmpty &&
        last.ids.any(
          (id) => change.added.contains(id) || change.updated.contains(id),
        ) &&
        last.ids.every((id) => content.strokeById(id) != null)) {
      // The undo of the last conversion — once: the next changes of the
      // page never bring it back again.
      _lastConverted = null;
      if (_group == null &&
          (_tool == EditorTool.math || _tool == EditorTool.eraser)) {
        // That handwriting is the open group again.
        _setGroup(
          _Group(
            pageId,
            [for (final id in last.ids) content.strokeById(id)!],
            reopenedFrom: last.reopenedFrom,
            reopenedIds: last.reopenedIds,
            restored: true,
          ),
        );
      } else {
        _watch();
      }
    }
  }

  // ---- the formula menu (design note 8) ----

  /// Opens the menu of [math] (a finger tap or a pen dot on it with the
  /// math pen).
  void openFormulaMenu(core.MathObject math) {
    if (!enabled || _disposed) return;
    _ensureRecognition();
    _menu = MathFormulaMenu(pageId: math.pageId, mathId: math.id);
    notifyListeners();
  }

  void closeFormulaMenu() {
    if (_menu == null || _disposed) return;
    _menu = null;
    notifyListeners();
  }

  /// The menu's formula as it is now, or null (gone).
  core.MathObject? get menuFormula {
    final menu = _menu;
    if (menu == null) return null;
    final o = _session.pageIfLoaded(menu.pageId)?.objectById(menu.mathId);
    return o is core.MathObject ? o : null;
  }

  /// '고치기': the session's LaTeX editor on the menu's formula.
  Future<void> fixFormula() async {
    final math = menuFormula;
    closeFormulaMenu();
    final session = _ensureRecognition();
    if (math == null || session == null) return;
    await session.fix(math);
  }

  /// '손글씨로 열기': the formula turns back into its handwriting (ONE
  /// command, new ids) — the open group. True when it ran.
  bool reopenFormula(core.MathObject math) {
    if (!enabled || _disposed) return false;
    closeFormulaMenu();
    final live = _session.pageIfLoaded(math.pageId)?.objectById(math.id);
    if (live is! core.MathObject || live.ink.isEmpty) return false;
    final strokes = reopenedStrokes(live, newId: _newId, now: _now());
    // The open group converts first: the reopen is the newest step.
    final mark = _group != null
        ? _convertInBackground(EditorMathConvertTrigger.newGroup)
        : null;
    if (!_commands.runCommand(reopenCommand(live, strokes))) return false;
    mark?.state = _session.history;
    _ensureRecognition();
    _setGroup(
      _Group(
        live.pageId,
        strokes,
        reopenedFrom: live,
        reopenedIds: {for (final s in strokes) s.id},
      ),
    );
    return true;
  }

  /// Where the bubble keeps away from (page pt): the group's bounds grown
  /// by bubbleClearanceFactor × H up and down — the zone where an exponent,
  /// a fraction or the next stroke of a symbol starts, so the bubble (which
  /// takes the pointer) never sits on it.
  Rect? get bubbleAnchorPt {
    final value = group;
    if (value == null) return null;
    final h = mathPenLineHeight([
      for (final s in value.strokes) strokePointBounds(s).height,
    ]);
    final b = value.boundsPt;
    return Rect.fromLTRB(
      b.left,
      b.top - MathPenTuning.bubbleClearanceFactor * h,
      b.right,
      b.bottom + MathPenTuning.bubbleClearanceFactor * h,
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

/// Per note: the math pen controller (EditorExtensions.mathPen; disabled
/// without it).
final editorMathPenProvider = Provider<MathPenController>(
  (ref) {
    final runner = ref.watch(editorExtensionRunnerProvider);
    final controller = MathPenController(
      session: ref.watch(editorSessionValueProvider),
      commands: ref.watch(editorCommandsProvider),
      mathPen: ref.watch(editorExtensionsProvider.select((e) => e.mathPen)),
      bodyContext: () => runner.bodyContext,
      newId: () => ref.read(core.idGeneratorProvider).newId(),
      now: () => ref.read(core.clockProvider).now().millisecondsSinceEpoch,
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
  name: 'editorMathPenProvider',
);
