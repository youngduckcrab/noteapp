// E-08: EditorCommands — the three CORE entry points and the ink hand-off
// (04-editor 5.1.3, 6.6.3, 6.8). Runs on the real editor scope (pumpEditor:
// fake store + RecordingNoteSession), rejections injected with rejectNext.
//   - every exception of the 5.1.3 table: onRejected exactly once, null
//     returned, nothing rethrown; the right report / notice;
//   - success: onRejected never runs;
//   - _runHistory catches the ReadOnlyNoteException of undo / redo (N-4 v1.1);
//   - commitInkEdit: empty edit → no command; rejected → discardEdit;
//   - no command from inside a session stream listener (N-2 v1.1).
import 'dart:async';

import 'package:feature_editor/src/commands/editor_commands.dart';
import 'package:feature_editor/src/scope/editor_scope.dart';
import 'package:feature_editor/src/tools/tool_controller.dart';
import 'package:feature_editor/src/ui/editor_strings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:note_core/note_core.dart' as core;

import '../helpers/pump_editor.dart';
import '../helpers/test_data.dart';

final class _Probe {
  _Probe(this.commands) {
    _sub = commands.messages.listen(messages.add);
  }

  final EditorCommands commands;
  final List<String> messages = [];
  final List<FlutterErrorDetails> reports = [];
  late final StreamSubscription<String> _sub;
  FlutterExceptionHandler? _previous;
  int rejected = 0;

  void onRejected() => rejected++;

  void captureReports() {
    _previous = FlutterError.onError;
    FlutterError.onError = reports.add;
  }

  void restore() {
    FlutterError.onError = _previous;
    unawaited(_sub.cancel());
  }
}

Future<(EditorTestHandles, _Probe)> _setUp(WidgetTester tester) async {
  final h = await pumpEditor(
    tester,
    strokesByPageIndex: {
      0: [strokeA],
    },
  );
  final probe = _Probe(h.container.read(editorCommandsProvider))
    ..captureReports();
  return (h, probe);
}

core.EditCommand _add(EditorTestHandles h, String id) => core.AddStrokes(
  pageId: h.pageId(0),
  strokes: [
    lineStroke(id: id, pageId: h.pageId(0), x0: 50, y0: 500, x1: 300, y1: 500),
  ],
);

/// (error, reported, notice) — 5.1.3 '명령 실행 공통 처리'.
final List<(Object, bool, String?)> _table = [
  (
    const core.ReadOnlyNoteException('race'),
    false,
    EditorStrings.readOnlyToast,
  ),
  (const core.PageNotOpenException('not open'), true, null),
  (const core.LastPageDeletionException('last'), true, null),
  (const core.SessionClosedException('closed'), false, null),
  (StateError('re-entered'), true, null),
  (ArgumentError('bad'), true, EditorStrings.commandFailed),
  (const FormatException('other'), true, EditorStrings.commandFailed),
];

void main() {
  for (final (error, reported, notice) in _table) {
    final name = error.runtimeType.toString();

    testWidgets('_run: $name → onRejected once, null, no rethrow', (
      tester,
    ) async {
      final (h, p) = await _setUp(tester);
      try {
        h.recorder!.rejectNext(error);
        final receipt = p.commands.debugRun(
          _add(h, 'x'),
          onRejected: p.onRejected,
        );
        await tester.pump();
        expect(receipt, isNull);
        expect(p.rejected, 1);
        expect(p.reports, hasLength(reported ? 1 : 0));
        if (reported) {
          expect(p.reports.single.exception, same(error));
          expect(p.reports.single.library, 'feature_editor');
        }
        expect(p.messages, [?notice]);
        expect(h.session.history.undoDepth, 0);
      } finally {
        p.restore();
      }
    });

    testWidgets('_runAsync: $name → onRejected once, null, no rethrow', (
      tester,
    ) async {
      final (h, p) = await _setUp(tester);
      try {
        h.recorder!.rejectNext(error);
        final receipt = await p.commands.debugRunAsync(
          _add(h, 'y'),
          onRejected: p.onRejected,
        );
        await tester.pump();
        expect(receipt, isNull);
        expect(p.rejected, 1);
        expect(p.reports, hasLength(reported ? 1 : 0));
        expect(p.messages, [?notice]);
      } finally {
        p.restore();
      }
    });

    testWidgets('_runHistory: $name → null, no rethrow', (tester) async {
      final (h, p) = await _setUp(tester);
      try {
        h.session.execute(_add(h, 'z'));
        h.recorder!.rejectNext(error);
        final result = await p.commands.debugRunHistory(h.recorder!.undo);
        await tester.pump();
        expect(result, isNull);
        expect(p.reports, hasLength(reported ? 1 : 0));
        expect(p.messages, [?notice]);
        expect(h.session.history.undoDepth, 1); // nothing undone
      } finally {
        p.restore();
      }
    });
  }

  testWidgets('success: receipt, onRejected never runs', (tester) async {
    final (h, p) = await _setUp(tester);
    try {
      final receipt = p.commands.debugRun(
        _add(h, 's'),
        onRejected: p.onRejected,
      );
      expect(receipt, isNotNull);
      final asyncReceipt = await p.commands.debugRunAsync(
        _add(h, 't'),
        onRejected: p.onRejected,
      );
      expect(asyncReceipt, isNotNull);
      final undone = await p.commands.debugRunHistory(h.recorder!.undo);
      expect(undone!.applied, isTrue);
      expect(p.rejected, 0);
      expect(p.reports, isEmpty);
      expect(p.messages, isEmpty);
      expect(h.recorder!.calls, [
        'openPage:${h.pageId(0)}',
        'openPage:${h.pageId(1)}',
        'execute:add-strokes',
        'executeAsync:add-strokes',
        'undo',
      ]);
    } finally {
      p.restore();
    }
  });

  testWidgets('undo / redo catch a racing ReadOnlyNoteException (N-4 v1.1)', (
    tester,
  ) async {
    final (h, p) = await _setUp(tester);
    try {
      h.session.execute(_add(h, 'u'));
      h.recorder!.rejectNext(const core.ReadOnlyNoteException('race'));
      await p.commands.undo(); // does not throw
      await tester.pump();
      expect(h.recorder!.calls.last, 'undo:rejected');
      expect(h.session.history.undoDepth, 1);
      expect(p.messages, [EditorStrings.readOnlyToast]);

      await p.commands.undo();
      expect(h.session.history.undoDepth, 0);
      h.recorder!.rejectNext(const core.ReadOnlyNoteException('race'));
      await p.commands.redo();
      await tester.pump();
      expect(h.recorder!.calls.last, 'redo:rejected');
      expect(h.session.history.redoDepth, 1);
      expect(p.reports, isEmpty);
    } finally {
      p.restore();
    }
  });

  testWidgets('undo / redo are ignored on a read-only note', (tester) async {
    final (h, p) = await _setUp(tester);
    try {
      h.session.execute(_add(h, 'r'));
      await h.store.library.trashItems([core.NoteRef(h.noteId)]);
      await tester.pump();
      expect(h.container.read(editorReadOnlyProvider), isTrue);
      h.recorder!.clearCalls();
      await p.commands.undo();
      await p.commands.redo();
      expect(h.recorder!.calls, isEmpty);
    } finally {
      p.restore();
    }
  });

  testWidgets('commitInkEdit: committed, empty, rejected → discardEdit', (
    tester,
  ) async {
    final (h, p) = await _setUp(tester);
    try {
      final controller = h.controllerOf(0);
      final pen = h.container.read(editorToolProvider).currentPen;

      ink.InkEdit drawEdit(double y) {
        final session = controller.beginStroke(
          ink.InkSample(
            position: Offset(40, y),
            timeUs: 0,
            kind: ink.InkPointerKind.stylus,
          ),
          style: pen,
          viewScale: 1,
        );
        session.addSample(
          ink.InkSample(
            position: Offset(200, y),
            timeUs: 8000,
            kind: ink.InkPointerKind.stylus,
          ),
        );
        return session.end()!;
      }

      // Committed: the pending stroke is replaced by the content in the call.
      final ok = drawEdit(600);
      expect(controller.pendingIds, isNotEmpty);
      expect(p.commands.commitInkEdit(controller, ok), isTrue);
      expect(controller.pendingIds, isEmpty);
      expect(
        controller.content!.strokes.map((s) => s.id),
        contains(ok.added.single.id),
      );

      // Empty edit: no command.
      h.recorder!.clearCalls();
      expect(
        p.commands.commitInkEdit(
          controller,
          ink.InkEdit(pageId: h.pageId(0), kind: ink.InkEditKind.addStroke),
        ),
        isFalse,
      );
      expect(h.recorder!.calls, isEmpty);

      // Rejected: discardEdit drops the pending stroke at once.
      final rejected = drawEdit(700);
      expect(controller.pendingIds, contains(rejected.added.single.id));
      h.recorder!.rejectNext(const core.ReadOnlyNoteException('race'));
      expect(p.commands.commitInkEdit(controller, rejected), isFalse);
      expect(controller.pendingIds, isEmpty);
      expect(
        controller.content!.strokes.map((s) => s.id),
        isNot(contains(rejected.added.single.id)),
      );
      expect(h.session.history.undoDepth, 1);
    } finally {
      p.restore();
    }
  });

  testWidgets('clearCurrentPage: one clear-page step with the eraser filter', (
    tester,
  ) async {
    final (h, p) = await _setUp(tester);
    try {
      h.session.execute(
        core.AddStrokes(
          pageId: h.pageId(0),
          strokes: [highlighterStroke.copyWith(pageId: h.pageId(0))],
        ),
      );
      h.container
          .read(editorToolProvider.notifier)
          .updateEraser(
            (e) => e.copyWith(filter: core.StrokeFilter.highlighterOnly),
          );
      await p.commands.clearCurrentPage();
      expect(h.recorder!.calls.last, 'executeAsync:clear-page');
      expect(h.session.history.undoLabel, 'clear-page');
      expect(h.session.pageIfLoaded(h.pageId(0))!.strokes.map((s) => s.id), [
        strokeA.id,
      ]);
    } finally {
      p.restore();
    }
  });

  testWidgets('no command runs inside a session stream listener', (
    tester,
  ) async {
    final (h, p) = await _setUp(tester);
    try {
      await h.driver.stylusStroke(
        pathThrough(h, 0, const [Offset(80, 640), Offset(160, 660)]),
      );
      await p.commands.undo();
      await p.commands.redo();
      await tester.pump();
      expect(h.recorder!.calls.where((c) => c.startsWith('execute')), [
        'execute:add-strokes',
      ]);
      expect(h.recorder!.executeDuringDelivery, isFalse);
      expect(p.reports, isEmpty);
    } finally {
      p.restore();
    }
  });
}
