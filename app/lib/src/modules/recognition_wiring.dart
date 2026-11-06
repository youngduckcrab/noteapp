/// recog actions → editor slots (docs/plans/m5-7/01-infra.md 4.6.5, 6.7
/// '자리 변환'; contract 7.3.1 X30 v2.1 — CP13 승인).
library;

import 'package:feature_editor/feature_editor.dart'
    show
        DevOverlaySection,
        EditorInsertContext,
        EditorInsertMenuItem,
        EditorSelectionContext,
        EditorSelectionMenuItem;
import 'package:flutter_riverpod/flutter_riverpod.dart' show Ref;
import 'package:ink_recognition/ink_recognition.dart'
    show
        RecognitionAction,
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
