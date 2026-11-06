// A small editor stand-in for the recognition actions and sheets
// (m5-7/05-library 6.3, 6.12, 9.2): ProviderScope (CORE's fake store +
// test engines) → MaterialApp → Scaffold → an "editor body" whose context
// the actions get (contract 7.2.10 — the editor body's context, mounted while
// the editor is open). The body can be unmounted on its own (the messenger
// stays) to check the 'no snack bar after the editor is gone' rule. Also: a
// clipboard log on SystemChannels.platform, targets and strokes.
import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_recognition/ink_recognition.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart' as core_testing;

/// iPad Pro 13" (contract 7.4.6) — landscape / portrait.
const Size kIpadLandscape = Size(1376, 1032);
const Size kIpadPortrait = Size(1032, 1376);

/// The fake store's clock in these tests (fixed — no real time in asserts).
final DateTime kHostNow = DateTime.utc(2026, 11, 6, 10);

/// CORE's fake store with its clock fixed at [kHostNow].
core.NoteStore createFixedClockStore() =>
    core_testing.createFakeNoteStore(clock: FakeAsync().getClock(kHostNow));

const String kNoteId = 'note-1';
const String kPageId = 'page-1';

final class RecognitionHost {
  RecognitionHost._(this.tester, this.store, this._showBody, this._bodyKey);

  /// Pumps the host at [size] (logical px = physical, ratio 1).
  static Future<RecognitionHost> pump(
    WidgetTester tester, {
    core.NoteStore? store,
    List<Override> overrides = const [],
    Size size = kIpadLandscape,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final s = store ?? createFixedClockStore();
    if (store == null) addTearDown(s.close);
    final showBody = ValueNotifier<bool>(true);
    addTearDown(showBody.dispose);
    final bodyKey = GlobalKey(debugLabel: 'editor body');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [core.noteStoreProvider.overrideWithValue(s), ...overrides],
        child: MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder<bool>(
              valueListenable: showBody,
              builder: (context, show, _) => show
                  ? SizedBox.expand(key: bodyKey)
                  : const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );
    return RecognitionHost._(tester, s, showBody, bodyKey);
  }

  final WidgetTester tester;
  final core.NoteStore store;
  final ValueNotifier<bool> _showBody;
  final GlobalKey _bodyKey;

  /// The editor body's context (what EDITOR passes to run).
  BuildContext get body => _bodyKey.currentContext!;

  /// Removes the editor body (the Scaffold and its messenger stay).
  Future<void> unmountBody() async {
    _showBody.value = false;
    await tester.pump();
  }

  /// The texts of the snack bars on screen.
  List<String> get snackBars => [
    for (final e
        in find
            .descendant(of: find.byType(SnackBar), matching: find.byType(Text))
            .evaluate())
      (e.widget as Text).data ?? '',
  ];
}

/// SystemChannels.platform calls (Clipboard.setData …), recorded the moment
/// they are sent. [reply] answers each call (default: success at once).
final class PlatformLog {
  PlatformLog(WidgetTester tester) {
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) {
      calls.add(call);
      return reply(call);
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
  }

  final List<MethodCall> calls = [];
  Future<Object?> Function(MethodCall call) reply = (call) async => null;

  /// The text of every Clipboard.setData call.
  List<String?> get clipboardTexts => [
    for (final c in calls)
      if (c.method == 'Clipboard.setData')
        (c.arguments as Map<Object?, Object?>)['text'] as String?,
  ];
}

/// Every command a target executed and how often done() ran.
final class TargetLog {
  final List<core.EditCommand> commands = [];
  int doneCalls = 0;

  /// Thrown by execute instead of recording (ReadOnlyNoteException …).
  Exception? executeError;

  RecognitionTarget target({
    List<core.Stroke> strokes = const [],
    List<core.PageObject> objects = const [],
    Rect areaPt = const Rect.fromLTWH(100, 100, 300, 120),
    core.PageSize pageSize = core.PageSize.a4Portrait,
  }) => RecognitionTarget(
    noteId: kNoteId,
    pageId: kPageId,
    pageSize: pageSize,
    strokes: strokes,
    objects: objects,
    areaPt: areaPt,
    execute: (command) {
      final error = executeError;
      if (error != null) throw error;
      commands.add(command);
    },
    done: () => doneCalls++,
  );
}

/// A stroke through [points] (page pt) with [tool] and [colorArgb].
core.Stroke strokeOf(
  String id,
  List<(double, double)> points, {
  core.PenTool tool = core.PenTool.ballpoint,
  int colorArgb = 0xFF1A1A1A,
  int createdAt = 1730800000000,
  String pageId = kPageId,
}) => core.Stroke(
  id: id,
  pageId: pageId,
  style: core.StrokeStyle(tool: tool, colorArgb: colorArgb, width: 2),
  points: core.StrokePoints.fromList([
    for (final (i, (x, y)) in points.indexed)
      core.StrokePoint(x, y, t: 8.0 * i),
  ]),
  createdAt: createdAt,
);

/// A vertical "glyph" stroke [height] pt tall whose top-left is ([x], [y]).
core.Stroke glyphStroke(
  String id,
  double x,
  double y,
  double height, {
  core.PenTool tool = core.PenTool.ballpoint,
  int colorArgb = 0xFF1A1A1A,
  int createdAt = 1730800000000,
  String pageId = kPageId,
}) => strokeOf(
  id,
  [(x, y), (x + height * 0.3, y + height * 0.5), (x, y + height)],
  tool: tool,
  colorArgb: colorArgb,
  createdAt: createdAt,
  pageId: pageId,
);

/// Lets [future] finish while the test clock runs (pumps between microtasks).
Future<void> settle(WidgetTester tester, Future<void> future) async {
  var done = false;
  unawaited(future.whenComplete(() => done = true));
  for (var i = 0; i < 20 && !done; i++) {
    await tester.pump();
  }
  expect(done, isTrue, reason: 'the run finished');
}

/// Pumps frames until [future] completes and returns its value (the fake
/// store needs no time).
Future<T> waitFor<T>(WidgetTester tester, Future<T> future) async {
  var done = false;
  T? value;
  Object? error;
  StackTrace? stack;
  unawaited(
    future.then(
      (v) {
        value = v;
        done = true;
      },
      onError: (Object e, StackTrace s) {
        error = e;
        stack = s;
        done = true;
      },
    ),
  );
  for (var i = 0; i < 50 && !done; i++) {
    await tester.pump();
  }
  if (!done) throw StateError('the future did not complete');
  if (error case final e?) Error.throwWithStackTrace(e, stack!);
  return value as T;
}

/// A note with one page in a host's store and an open NoteSession on it,
/// for 9.3 'one command = one undo step': its targets execute into the
/// session (and record in a TargetLog), so a test reads the undo depth and
/// undoes the sheet's command.
final class SessionDoc {
  SessionDoc._(this.noteId, this.pageId, this.session);

  /// Opens the session; [strokes] / [objects] (built for the page id) are
  /// put on the page first, one command each (before a test reads the
  /// depth). The test closes it ([close]).
  static Future<SessionDoc> open(
    WidgetTester tester,
    core.NoteStore store, {
    List<core.Stroke> Function(String pageId)? strokes,
    List<core.PageObject> Function(String pageId)? objects,
  }) async {
    final note = await waitFor(
      tester,
      store.library.createNote(
        title: 'note',
        pages: const [core.PageDraft.blankA4],
      ),
    );
    final pageId = (await waitFor(
      tester,
      store.content.pagesOf(note.id),
    )).single.id;
    final session = await waitFor(tester, store.openSession(note.id));
    await waitFor(tester, session.openPage(pageId));
    final s = strokes?.call(pageId) ?? const [];
    if (s.isNotEmpty) {
      await waitFor(
        tester,
        session.execute(core.AddStrokes(pageId: pageId, strokes: s)).persisted,
      );
    }
    final o = objects?.call(pageId) ?? const [];
    if (o.isNotEmpty) {
      await waitFor(
        tester,
        session.execute(core.AddObjects(pageId: pageId, objects: o)).persisted,
      );
    }
    return SessionDoc._(note.id, pageId, session);
  }

  final core.NoteId noteId;
  final core.PageId pageId;
  final core.NoteSession session;

  int get undoDepth => session.history.undoDepth;

  /// A target on this page whose execute goes to the session.
  RecognitionTarget target(
    TargetLog log, {
    List<core.Stroke> strokes = const [],
    List<core.PageObject> objects = const [],
    Rect areaPt = const Rect.fromLTWH(100, 100, 300, 120),
  }) => RecognitionTarget(
    noteId: noteId,
    pageId: pageId,
    pageSize: core.PageSize.a4Portrait,
    strokes: strokes,
    objects: objects,
    areaPt: areaPt,
    execute: (command) {
      session.execute(command);
      log.commands.add(command);
    },
    done: () => log.doneCalls++,
  );

  /// The page as the session has it now.
  Future<core.PageContent> content(WidgetTester tester) =>
      waitFor(tester, session.openPage(pageId));

  Future<void> undo(WidgetTester tester) async {
    await waitFor(tester, session.undo());
  }

  /// Closes the session (each test, before the host's store closes).
  Future<void> close(WidgetTester tester) => waitFor(tester, session.close());
}
