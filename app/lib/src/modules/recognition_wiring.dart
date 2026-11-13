/// recog actions → editor slots (docs/plans/m5-7/01-infra.md 4.6.5, 6.7
/// '자리 변환'; contract 7.3.1 X30 v2.1 — CP13 승인).
library;

import 'package:feature_editor/feature_editor.dart'
    show
        DevOverlaySection,
        EditorInsertContext,
        EditorInsertMenuItem,
        EditorMathConvertTrigger,
        EditorMathGroup,
        EditorMathPen,
        EditorMathPenContext,
        EditorMathPenSession,
        EditorSelectionContext,
        EditorSelectionMenuItem;
import 'package:feature_library/feature_library.dart'
    show LibraryInkSearch, LibraryInkSearchPhase, LibraryInkSearchState;
import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier;
import 'package:flutter/widgets.dart'
    show BuildContext, Listenable, Rect, Widget;
import 'package:flutter_riverpod/flutter_riverpod.dart' show Ref;
import 'package:ink_recognition/ink_recognition.dart'
    show
        HandwritingSearchPhase,
        HandwritingSearchReadiness,
        HandwritingSearchStatus,
        handwritingSearchReadinessProvider,
        RecognitionAction,
        RecognitionMathPen,
        RecognitionMathPenContext,
        RecognitionMathPenSession,
        RecognitionTarget,
        recognitionDevOverlayLinesProvider;
import 'package:note_core/note_core.dart' as core;

RecognitionTarget recognitionTargetOfSelection(
  EditorSelectionContext selection,
) => RecognitionTarget(
  noteId: selection.noteId,
  pageId: selection.pageId,
  pageSize: selection.pageSize,
  strokes: selection.strokes,
  objects: selection.objects,
  areaPt: selection.boundsPt,
  execute: selection.execute,
  done: selection.clearSelection,
);

/// execute is wrapped: the id of the last object added by the command
/// (AddObjects, also inside CompositeCommand — last wins) is remembered;
/// done() → insert.selectObject(thatId) when one was added, else nothing
/// (계약 7.3.1 X30 v2.1 — CP13 승인). recog calls done only after a
/// replacement (toText · toMath).
RecognitionTarget recognitionTargetOfInsert(EditorInsertContext insert) {
  String? lastAdded;
  return RecognitionTarget(
    noteId: insert.noteId,
    pageId: insert.pageId,
    pageSize: insert.pageSize,
    areaPt: insert.visibleRectPt,
    execute: (command) {
      insert.execute(command);
      // Only after the command ran: a throwing command added nothing.
      lastAdded = _lastAddedObjectId(command) ?? lastAdded;
    },
    done: () {
      final id = lastAdded;
      if (id != null) insert.selectObject(id);
    },
  );
}

String? _lastAddedObjectId(core.EditCommand command) => switch (command) {
  core.AddObjects(:final objects) when objects.isNotEmpty => objects.last.id,
  core.CompositeCommand(:final commands) =>
    commands.reversed
        .map(_lastAddedObjectId)
        .firstWhere((id) => id != null, orElse: () => null),
  _ => null,
};

/// EditorSelectionMenuItem(id, label, icon, onSelected: (ctx, s) =>
/// a.run(ctx, recognitionTargetOfSelection(s)), isVisible: a.isVisible over
/// the same target). onSelected calls a.run synchronously and returns its
/// Future (계약 7.2.10 v2.1 — slot callbacks start synchronously).
EditorSelectionMenuItem selectionMenuItemOf(RecognitionAction action) {
  final isVisible = action.isVisible;
  return EditorSelectionMenuItem(
    id: action.id,
    label: action.label,
    icon: action.icon,
    onSelected: (context, selection) =>
        action.run(context, recognitionTargetOfSelection(selection)),
    isVisible: isVisible == null
        ? null
        : (selection) => isVisible(recognitionTargetOfSelection(selection)),
  );
}

/// RecognitionAction.isVisible is not used: EditorInsertMenuItem has no
/// visibility hook (Q10 — recog.mathPad has none).
EditorInsertMenuItem insertMenuItemOf(RecognitionAction action) =>
    EditorInsertMenuItem(
      id: action.id,
      label: action.label,
      icon: action.icon,
      onSelected: (context, insert) =>
          action.run(context, recognitionTargetOfInsert(insert)),
    );

/// (v2.1, CP4 = CP-L2 승인) DevOverlaySection(id: 'recog.indexer', title:
/// '손글씨 색인', lines: ref.watch(recognitionDevOverlayLinesProvider)) — the
/// same shape as the media section.
DevOverlaySection recognitionIndexerSection(Ref ref) => DevOverlaySection(
  id: 'recog.indexer',
  title: '손글씨 색인',
  lines: ref.watch(recognitionDevOverlayLinesProvider),
);

/// (math pen, phase 1 — docs/plans/m5-7/research/math-pen-phase1.md 11.1)
/// recog's math pen as the editor's slot: the editor's context becomes
/// recog's, every EditorMathGroup a RecognitionTarget (strokes, areaPt =
/// boundsPt, execute = the editor's, done does nothing), the triggers
/// interactive = bubbleTap. The same shape as [selectionMenuItemOf].
EditorMathPen editorMathPenOf(RecognitionMathPen pen) => EditorMathPen(
  open: (context) => _MathPenSessionAdapter(
    context,
    pen.open(
      RecognitionMathPenContext(
        noteId: context.noteId,
        execute: context.execute,
        liveStrokes: context.liveStrokes,
        bodyContext: context.bodyContext,
      ),
    ),
  ),
);

/// The RecognitionTarget of [group] (the page size from the editor).
RecognitionTarget recognitionTargetOfMathGroup(
  EditorMathPenContext context,
  EditorMathGroup group,
) => RecognitionTarget(
  noteId: context.noteId,
  pageId: group.pageId,
  pageSize: context.pageSizeOf(group.pageId) ?? core.PageSize.a4Portrait,
  strokes: group.strokes,
  areaPt: group.boundsPt,
  execute: context.execute,
  done: _nothing,
);

void _nothing() {}

Rect _rectOf(core.PageRect r) =>
    Rect.fromLTRB(r.left, r.top, r.right, r.bottom);

final class _MathPenSessionAdapter implements EditorMathPenSession {
  _MathPenSessionAdapter(this._context, this._inner);

  final EditorMathPenContext _context;
  final RecognitionMathPenSession _inner;

  RecognitionTarget _target(EditorMathGroup group) =>
      recognitionTargetOfMathGroup(_context, group);

  @override
  void update(EditorMathGroup group) => _inner.update(
    _target(group),
    reopenedFrom: group.reopenedFrom,
    reopenedStrokeIds: group.reopenedStrokeIds,
  );

  @override
  void interrupt() => _inner.interrupt();

  @override
  void clear() => _inner.clear();

  @override
  Future<bool> convert(
    EditorMathGroup group,
    EditorMathConvertTrigger trigger, {
    bool Function()? stillWanted,
  }) => _inner.convert(
    _target(group),
    interactive: trigger == EditorMathConvertTrigger.bubbleTap,
    stillWanted: stillWanted,
  );

  @override
  Future<void> fix(core.MathObject math) => _inner.fix(
    RecognitionTarget(
      noteId: _context.noteId,
      pageId: math.pageId,
      pageSize: _context.pageSizeOf(math.pageId) ?? core.PageSize.a4Portrait,
      objects: [math],
      areaPt: _rectOf(math.frame.bounds),
      execute: _context.execute,
      done: _nothing,
    ),
  );

  @override
  Listenable get changes => _inner.changes;

  @override
  Widget buildBubble(
    BuildContext context,
    EditorMathGroup group,
    void Function() onConvert,
  ) => _inner.buildBubble(context, _target(group), onConvert);

  @override
  void dispose() => _inner.dispose();
}

/// (handwriting search — m5-7/05-library 6.19a) recog's handwriting search
/// readiness as the library's ink search slot: the status mapped phase by
/// phase (unavailable → ready: nothing to say), the actions passed on. null
/// without an indexer (the web, no engine).
LibraryInkSearch? libraryInkSearchOf(Ref ref) {
  final readiness = ref.watch(handwritingSearchReadinessProvider);
  if (readiness == null) return null;
  final adapter = _InkSearchAdapter(readiness);
  ref.onDispose(adapter.dispose);
  return adapter;
}

LibraryInkSearchState libraryInkSearchStateOf(
  HandwritingSearchStatus s,
) => LibraryInkSearchState(
  phase: switch (s.phase) {
    HandwritingSearchPhase.unavailable ||
    HandwritingSearchPhase.ready => LibraryInkSearchPhase.ready,
    HandwritingSearchPhase.autoIndexOff => LibraryInkSearchPhase.autoIndexOff,
    HandwritingSearchPhase.modelMissing => LibraryInkSearchPhase.modelMissing,
    HandwritingSearchPhase.modelDownloading =>
      LibraryInkSearchPhase.modelDownloading,
    HandwritingSearchPhase.waitingForWifi =>
      LibraryInkSearchPhase.waitingForWifi,
    HandwritingSearchPhase.modelFailed => LibraryInkSearchPhase.modelFailed,
    HandwritingSearchPhase.indexing => LibraryInkSearchPhase.indexing,
    HandwritingSearchPhase.unsupported => LibraryInkSearchPhase.unsupported,
  },
  remainingPages: s.remainingPages,
  confirmCellularFirst: s.confirmCellularFirst,
);

final class _InkSearchAdapter implements LibraryInkSearch {
  _InkSearchAdapter(this._inner)
    : _state = ValueNotifier(libraryInkSearchStateOf(_inner.status.value)) {
    _inner.status.addListener(_sync);
  }

  final HandwritingSearchReadiness _inner;
  final ValueNotifier<LibraryInkSearchState> _state;

  void _sync() => _state.value = libraryInkSearchStateOf(_inner.status.value);

  @override
  ValueListenable<LibraryInkSearchState> get state => _state;

  @override
  Future<void> turnOnAutoIndex() => _inner.turnOnAutoIndex();

  @override
  Future<void> downloadModel({bool cellular = false}) =>
      _inner.downloadModel(cellular: cellular);

  @override
  void searchOpened() => _inner.searchOpened();

  void dispose() {
    _inner.status.removeListener(_sync);
    _state.dispose();
  }
}
