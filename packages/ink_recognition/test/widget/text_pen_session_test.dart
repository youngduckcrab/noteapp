// (text pen, phase 1 — m5-7/05-library 6.24) recog's text pen session with
// FakeHandwritingRecognizer, inside the small editor stand-in
// (RecognitionHost: ProviderScope → MaterialApp → body):
// - recognition starts 500 ms after the last update; the group's lines go to
//   the engine one after another with the sheet's rule (preContext, writing
//   area) in recog.language; pieces of one row are merged back; answers are
//   cached; a new contact drops a stale answer (only the newest counts);
// - the bubble tap: ONE CompositeCommand('recog-text-pen') — the strokes out,
//   a text box with the joined lines in — after waiting for the answer in
//   flight (no second request); changed strokes or a clear while the box was
//   built → no command; no usable answer → the conversion sheet;
// - one undo (a real fake-store session) gives the exact strokes back;
// - the model not downloaded → the model card ([받기] → ensureModel → the
//   session goes on by itself); no engine; a failure → [다시];
// - '고치기' opens the conversion sheet on the group's strokes;
// - the interactive priority is held while a request waits, released after.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/testing.dart' as ink_testing;
import 'package:ink_recognition/ink_recognition.dart';
import 'package:ink_recognition/src/actions/object_builders.dart';
import 'package:ink_recognition/src/common/recognition_priority.dart';
import 'package:ink_recognition/src/l10n/recognition_strings.dart';
import 'package:ink_recognition/src/settings/recognition_settings_keys.dart';
import 'package:ink_recognition/src/text_pen/text_pen_bubble.dart';
import 'package:ink_recognition/src/text_pen/text_pen_session.dart';
import 'package:ink_recognition/src/ui/conversion_sheet.dart';
import 'package:ink_recognition/src/ui/recognition_sheet.dart';
import 'package:ink_recognition/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

import '../support/recognition_test_scope.dart';

/// The page: strokes by id; liveStrokes reads it.
final class _Page {
  final Map<String, core.Stroke> strokes = {};
  final List<core.EditCommand> commands = [];

  List<core.Stroke>? live(String pageId, List<String> ids) {
    final out = <core.Stroke>[];
    for (final id in ids) {
      final s = strokes[id];
      if (s == null) return null;
      out.add(s);
    }
    return out;
  }

  void execute(core.EditCommand command) {
    commands.add(command);
    if (command case core.CompositeCommand(:final commands)) {
      for (final c in commands) {
        if (c case core.RemoveElements(:final elementIds)) {
          elementIds.forEach(strokes.remove);
        }
      }
    }
  }
}

/// Row [row] (from 0) of three glyphs, 20 pt tall, 60 pt apart vertically.
List<core.Stroke> _row(int row, {double x = 100, String prefix = 'r'}) => [
  for (var j = 0; j < 3; j++)
    glyphStroke(
      '$prefix${row}g$j',
      x + 14.0 * j,
      100 + 60.0 * row,
      20,
      createdAt: 1730800000000 + 10 * row + j,
    ),
];

RecognitionTarget _group(
  List<core.Stroke> strokes, {
  _Page? page,
  void Function(core.EditCommand command)? execute,
  String pageId = kPageId,
}) {
  if (page != null) {
    for (final s in strokes) {
      page.strokes[s.id] = s;
    }
  }
  Rect? r;
  for (final s in strokes) {
    final b = s.points.pointBounds;
    final x = Rect.fromLTRB(b.left, b.top, b.right, b.bottom);
    r = r == null ? x : r.expandToInclude(x);
  }
  return RecognitionTarget(
    noteId: kNoteId,
    pageId: pageId,
    pageSize: core.PageSize.a4Portrait,
    strokes: strokes,
    areaPt: r!,
    execute: execute ?? page!.execute,
    done: () {},
  );
}

/// An engine that answers `<lang>:<first stroke id>` (+ '?' / '!').
FakeHandwritingRecognizer _engine({Duration latency = Duration.zero}) {
  late final FakeHandwritingRecognizer engine;
  engine = FakeHandwritingRecognizer(
    latency: latency,
    answer: (line) => '${engine.calls.last.$2}:${line.traces.first.strokeId}',
  );
  return engine;
}

Future<(RecognitionHost, TextPenSession, _Page)> _pump(
  WidgetTester tester,
  HandwritingRecognizer engine, {
  core.NoteStore? store,
  List<core.Stroke>? Function(String pageId, List<String> ids)? live,
  void Function(core.EditCommand command)? execute,
}) async {
  final host = await RecognitionHost.pump(
    tester,
    store: store,
    overrides: [handwritingRecognizerProvider.overrideWithValue(engine)],
  );
  final page = _Page();
  final session = TextPenSession(
    RecognitionPenContext(
      noteId: kNoteId,
      execute: execute ?? page.execute,
      liveStrokes: live ?? page.live,
      bodyContext: () => host.body,
    ),
  );
  addTearDown(session.dispose);
  return (host, session, page);
}

/// Shows the session's bubble content on screen (the editor's frame stand-in).
Future<void> _showBubble(
  WidgetTester tester,
  TextPenSession session,
  RecognitionTarget group, {
  VoidCallback? onConvert,
  VoidCallback? onFix,
}) async {
  final overlay = OverlayEntry(
    builder: (context) => Align(
      alignment: Alignment.topLeft,
      child: Material(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: session.buildBubble(
            context,
            group,
            onConvert ?? () {},
            onFix ?? () {},
          ),
        ),
      ),
    ),
  );
  final navigator = tester.state<NavigatorState>(find.byType(Navigator));
  navigator.overlay!.insert(overlay);
  addTearDown(overlay.remove);
  await tester.pump();
}

bool _held(RecognitionHost host) => ProviderScope.containerOf(
  host.body,
  listen: false,
).read(recognitionPriorityProvider).interactive.value;

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await ink_testing.useInkTestFonts();
  });

  testWidgets('recognition starts 500 ms after the last update; the lines '
      'go to the engine in order with the sheet\'s rule; answers are cached', (
    tester,
  ) async {
    final engine = _engine();
    final (_, session, page) = await _pump(tester, engine);
    final g = _group([..._row(0), ..._row(1)], page: page);
    session.update(g);
    expect(session.view.value, isA<TextPenWaiting>());
    await tester.pump(const Duration(milliseconds: 499));
    expect(engine.calls, isEmpty);
    session.update(g); // a new update restarts the wait
    await tester.pump(const Duration(milliseconds: 499));
    expect(engine.calls, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();
    await tester.pump();
    expect(engine.calls, hasLength(2));
    final (first, lang) = engine.calls[0];
    expect(lang, 'ko');
    expect(first.preContext, '');
    expect(first.writingAreaPt!.width, core.PageSize.a4Portrait.width);
    expect(engine.calls[1].$1.preContext, 'ko:r0g0');
    final answer = session.view.value as TextPenAnswer;
    expect(answer.result.text, 'ko:r0g0\nko:r1g0');
    expect(answer.result.lines.first, ['ko:r0g0', 'ko:r0g0?', 'ko:r0g0!']);
    // Same strokes again (undo brought them back): the cache, no request.
    session.update(g);
    expect(session.view.value, isA<TextPenAnswer>());
    await tester.pump(const Duration(seconds: 1));
    expect(engine.calls, hasLength(2));
    expect(kTextPenRecognizeDelay, const Duration(milliseconds: 500));
  });

  testWidgets('recog.language is read for every request (English)', (
    tester,
  ) async {
    final engine = _engine();
    final (host, session, page) = await _pump(tester, engine);
    await settle(
      tester,
      host.store.settings.set(RecognitionSettingsKeys.language, 'en'),
    );
    session.update(_group(_row(0), page: page));
    await tester.pump(kTextPenRecognizeDelay);
    await tester.pump();
    await tester.pump();
    expect(engine.calls.single.$2, 'en');
    expect((session.view.value as TextPenAnswer).result.languageTag, 'en');
  });

  test('textPenLinesOf: pieces of one written row are one line; rows stay '
      'apart; highlighter strokes are left out', () {
    final row = [..._row(0), ..._row(0, x: 400, prefix: 'far')];
    final lines = textPenLinesOf(row);
    expect(lines, hasLength(1));
    expect(lines.single.strokes, hasLength(6));
    expect(lines.single.strokes.first.id, 'r0g0');
    expect(textPenLinesOf([..._row(0), ..._row(1)]), hasLength(2));
    final hl = glyphStroke('hl', 100, 300, 20, tool: core.PenTool.highlighter);
    expect(textPenLinesOf([hl]), isEmpty);
  });

  testWidgets('a new contact drops the stale answer; only the newest counts', (
    tester,
  ) async {
    final engine = _engine(latency: const Duration(milliseconds: 100));
    final (_, session, page) = await _pump(tester, engine);
    final g1 = _group(_row(0), page: page);
    session.update(g1);
    await tester.pump(kTextPenRecognizeDelay);
    await tester.pump(const Duration(milliseconds: 50)); // in flight
    session.interrupt();
    final g2 = _group([..._row(0), ..._row(1)], page: page);
    session.update(g2);
    await tester.pump(const Duration(milliseconds: 60)); // the old one ends
    expect(session.view.value, isA<TextPenWaiting>(), reason: 'g1 dropped');
    await tester.pump(kTextPenRecognizeDelay);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      (session.view.value as TextPenAnswer).result.text,
      'ko:r0g0\nko:r1g0',
    );
  });

  testWidgets('the bubble tap: ONE composite (strokes out, the text box in, '
      'recog-text-pen); it waits for the request in flight (no second '
      'request)', (tester) async {
    final engine = _engine(latency: const Duration(milliseconds: 100));
    final (_, session, page) = await _pump(tester, engine);
    final strokes = [..._row(0), ..._row(1)];
    final g = _group(strokes, page: page);
    session.update(g);
    await tester.pump(kTextPenRecognizeDelay);
    await tester.pump(const Duration(milliseconds: 10)); // line 1 in flight
    var done = false;
    bool? ok;
    unawaited(
      session.convert(g).then((v) {
        ok = v;
        done = true;
      }),
    );
    for (var i = 0; i < 20 && !done; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(ok, isTrue);
    expect(engine.calls, hasLength(2), reason: 'the same request');
    final c = page.commands.single as core.CompositeCommand;
    expect(c.label, kTextPenLabel);
    expect((c.commands[0] as core.RemoveElements).elementIds, [
      for (final s in strokes) s.id,
    ]);
    final box =
        (c.commands[1] as core.AddObjects).objects.single as core.TextBoxObject;
    expect(box.text, 'ko:r0g0\nko:r1g0');
    expect(box.frame.rect.top, g.areaPt.top);
  });

  testWidgets('changed strokes, or a clear while the box was built → no '
      'command', (tester) async {
    final engine = _engine();
    final (_, session, page) = await _pump(tester, engine);
    final g = _group(_row(0), page: page);
    session.update(g);
    await tester.pump(kTextPenRecognizeDelay);
    await tester.pump();
    await tester.pump();
    expect(session.view.value, isA<TextPenAnswer>());

    // A clear right after the tap (the group went) — checked after the
    // box's await.
    final pending = session.convert(g);
    session.clear();
    await settle(tester, pending);
    expect(await pending, isFalse);
    expect(page.commands, isEmpty);

    // A stroke changed meanwhile (another updatedAt).
    session.update(g);
    page.strokes['r0g1'] = page.strokes['r0g1']!.copyWith(updatedAt: 99);
    final changed = session.convert(g);
    await settle(tester, changed);
    expect(await changed, isFalse);
    expect(page.commands, isEmpty);
  });

  testWidgets('one undo gives the exact strokes back (a real session)', (
    tester,
  ) async {
    final store = createFixedClockStore();
    addTearDown(store.close);
    final note = await tester.runAsync(
      () => store.library.createNote(
        title: 'note',
        pages: const [core.PageDraft.blankA4],
      ),
    );
    final pageId = (await tester.runAsync(
      () => store.content.pagesOf(note!.id),
    ))!.single.id;
    final noteSession = (await tester.runAsync(
      () => store.openSession(note!.id),
    ))!;
    addTearDown(() => tester.runAsync(noteSession.close));
    await tester.runAsync(() => noteSession.openPage(pageId));
    noteSession.execute(
      core.AddStrokes(
        pageId: pageId,
        strokes: [for (final s in _row(0)) s.copyWith(pageId: pageId)],
      ),
    );
    final before = noteSession.pageIfLoaded(pageId)!.strokes;
    final depth = noteSession.history.undoDepth;

    List<core.Stroke>? live(String p, List<String> ids) {
      final content = noteSession.pageIfLoaded(p);
      final out = <core.Stroke>[];
      for (final id in ids) {
        final s = content?.strokeById(id);
        if (s == null) return null;
        out.add(s);
      }
      return out;
    }

    final (_, session, _) = await _pump(
      tester,
      _engine(),
      store: store,
      live: live,
      execute: noteSession.execute,
    );
    final g = _group(before, execute: noteSession.execute, pageId: pageId);
    session.update(g);
    await tester.pump(kTextPenRecognizeDelay);
    await tester.pump();
    await tester.pump();
    final converting = session.convert(g);
    await settle(tester, converting);
    expect(await converting, isTrue);
    expect(noteSession.history.undoDepth, depth + 1);
    expect(noteSession.history.undoLabel, kTextPenLabel);
    var content = noteSession.pageIfLoaded(pageId)!;
    expect(content.strokes, isEmpty);
    expect(content.objects.whereType<core.TextBoxObject>(), hasLength(1));

    await tester.runAsync(noteSession.undo);
    content = noteSession.pageIfLoaded(pageId)!;
    expect(content.objects, isEmpty);
    expect(content.strokes.map((s) => s.id), before.map((s) => s.id));
    for (var i = 0; i < before.length; i++) {
      expect(content.strokes[i].points.contentEquals(before[i].points), isTrue);
    }
  });

  testWidgets('the model not downloaded: the model card ([받기]); after the '
      'download the session goes on by itself', (tester) async {
    final engine = _engine()
      ..modelStates['ko'] = RecognitionModelState.notDownloaded;
    final (_, session, page) = await _pump(tester, engine);
    final g = _group(_row(0), page: page);
    session.update(g);
    await tester.pump(kTextPenRecognizeDelay);
    await tester.pump();
    await tester.pump();
    expect(session.view.value, isA<TextPenNeedsModel>());
    expect((session.view.value as TextPenNeedsModel).languageTag, 'ko');
    expect(engine.calls, isEmpty);
    await _showBubble(tester, session, g);
    await tester.pump(); // the row asks the engine's modelState
    expect(
      find.text(RecognitionStrings.modelNeeded(RecognitionStrings.korean)),
      findsOneWidget,
    );
    final download = find.text(RecognitionStrings.download);
    expect(download, findsOneWidget);
    await tester.tap(download);
    await tester.pump();
    await tester.pump();
    expect(engine.ensureModelCalls, 1);
    await tester.pump(kTextPenRecognizeDelay);
    await tester.pump();
    await tester.pump();
    expect(engine.calls, hasLength(1));
    expect(session.view.value, isA<TextPenAnswer>());
    await tester.pump(const Duration(seconds: 6)); // the Wi-Fi wait timer
  });

  testWidgets('no engine: the bubble says so; the tap opens the sheet (it '
      'says the same)', (tester) async {
    final engine = FakeHandwritingRecognizer(isAvailable: false);
    final (_, session, page) = await _pump(tester, engine);
    final g = _group(_row(0), page: page);
    session.update(g);
    expect(session.view.value, isA<TextPenNoEngine>());
    await _showBubble(tester, session, g);
    expect(find.text(RecognitionStrings.unsupported), findsOneWidget);
    final pending = session.convert(g);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(kConversionSheetKey), findsOneWidget);
    await tester.tap(find.byKey(kSheetCancelKey));
    await tester.pumpAndSettle();
    expect(await pending, isFalse);
    expect(page.commands, isEmpty);
  });

  testWidgets('an engine failure: [다시] recognizes again', (tester) async {
    final engine = _engine()
      ..failNext = RecognizerEngineError('timeout', 'slow');
    final (_, session, page) = await _pump(tester, engine);
    final g = _group(_row(0), page: page);
    session.update(g);
    await tester.pump(kTextPenRecognizeDelay);
    await tester.pump();
    await tester.pump();
    expect(session.view.value, isA<TextPenFailed>());
    await _showBubble(tester, session, g);
    await tester.tap(find.byKey(TextPenBubbleKeys.retry));
    await tester.pump(kTextPenRecognizeDelay);
    await tester.pump();
    await tester.pump();
    expect(session.view.value, isA<TextPenAnswer>());
    expect(find.byKey(TextPenBubbleKeys.text), findsOneWidget);
    expect(find.text(RecognitionStrings.textPenHint), findsOneWidget);
  });

  testWidgets('고치기: the conversion sheet on the group\'s strokes; its '
      '[텍스트 상자로] is the one command → fix completes true', (tester) async {
    final engine = _engine();
    final (_, session, page) = await _pump(tester, engine);
    final g = _group(_row(0), page: page);
    session.update(g);
    await tester.pump(kTextPenRecognizeDelay);
    await tester.pump();
    var fixes = 0;
    await _showBubble(tester, session, g, onFix: () => fixes++);
    await tester.tap(find.byKey(TextPenBubbleKeys.fix));
    expect(fixes, 1);

    final pending = session.fix(g);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(kConversionSheetKey), findsOneWidget);
    await tester.pump();
    await tester.tap(find.byKey(kSheetPrimaryKey));
    await tester.pumpAndSettle();
    expect(await pending, isTrue);
    final c = page.commands.single as core.CompositeCommand;
    expect(c.label, kToTextLabel);
  });

  testWidgets('the interactive priority: held from the update until the '
      'answer, released by interrupt / clear', (tester) async {
    final engine = _engine(latency: const Duration(milliseconds: 100));
    final (host, session, page) = await _pump(tester, engine);
    final g = _group(_row(0), page: page);
    expect(_held(host), isFalse);
    session.update(g);
    expect(_held(host), isTrue);
    session.interrupt();
    expect(_held(host), isFalse);
    session.update(g);
    await tester.pump(kTextPenRecognizeDelay);
    await tester.pump(const Duration(milliseconds: 50));
    expect(_held(host), isTrue, reason: 'in flight');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
    expect(session.view.value, isA<TextPenAnswer>());
    expect(_held(host), isFalse);
    session.update(_group([..._row(0), ..._row(1)], page: page));
    expect(_held(host), isTrue);
    session.clear();
    expect(_held(host), isFalse);
  });
}
