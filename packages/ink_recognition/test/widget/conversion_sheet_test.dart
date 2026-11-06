// L2-15 (m5-7/05-library 8.2, 6.13, 6.12, 6.7.4, 6.22): the text conversion
// sheet (recog.sheet.toText) of recog.toText / recog.copyText with strokes —
// a card per line (field + up to 4 chips), the sheet's own language (only
// untouched lines recognized again, answers cached per language), [텍스트
// 상자로] → ONE CompositeCommand → done(), [복사] → the clipboard (started
// synchronously inside the press) → flush → loadPage → update(mergeConfirmed)
// (6.13.5 ①–④), no engine → the fixed sentence, the model card ([받기], the
// 5 s Wi-Fi wait → [지금 셀룰러로 받기] twice → wifiOnly: false), an engine
// failure → [다시], more than 20 lines → 20 + a notice.
import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/testing.dart' as ink_testing;
import 'package:ink_recognition/ink_recognition.dart';
import 'package:ink_recognition/src/actions/object_builders.dart';
import 'package:ink_recognition/src/l10n/recognition_strings.dart';
import 'package:ink_recognition/src/settings/recognition_settings_keys.dart';
import 'package:ink_recognition/src/ui/conversion_sheet.dart';
import 'package:ink_recognition/src/ui/model_downloads.dart';
import 'package:ink_recognition/src/ui/recognition_sheet.dart';
import 'package:ink_recognition/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart' as core_testing;

import '../support/model_engine.dart';
import '../support/recognition_test_scope.dart';

Finder get _sheet => find.byKey(kConversionSheetKey);
Finder get _status => find.byKey(kConversionStatusKey);
Finder get _primary => find.byKey(kSheetPrimaryKey);
Finder get _secondary => find.byKey(kSheetSecondaryKey);
Finder _line(int i) => find.byKey(conversionLineKey(i));

/// Runs microtasks and zero-time timers until [future] completes (the fake
/// store needs no time).
Future<T> _wait<T>(WidgetTester tester, Future<T> future) async {
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

/// A glyph-like stroke [h] pt tall whose top-left is ([x], [y]).
core.Stroke _glyph(
  String id,
  String pageId,
  double x,
  double y, {
  double h = 40,
  int createdAt = 1730800000000,
  int colorArgb = 0xFF1A1A1A,
  core.PenTool tool = core.PenTool.ballpoint,
}) => core.Stroke(
  id: id,
  pageId: pageId,
  style: core.StrokeStyle(tool: tool, colorArgb: colorArgb, width: 2),
  points: core.StrokePoints.fromList([
    core.StrokePoint(x, y, t: 0),
    core.StrokePoint(x + h * 0.3, y + h * 0.5, t: 8),
    core.StrokePoint(x, y + h, t: 16),
  ]),
  createdAt: createdAt,
);

/// Line [line] (from 0): three glyphs `l<line>g<j>`, 100 pt apart per line.
List<core.Stroke> _lineStrokes(String pageId, int line) => [
  for (var j = 0; j < 3; j++)
    _glyph(
      'l${line}g$j',
      pageId,
      100 + 50.0 * j,
      100 + 100.0 * line,
      createdAt: 1730800000000 + 100 * line + j,
    ),
];

List<core.Stroke> _lines(String pageId, int count) => [
  for (var i = 0; i < count; i++) ..._lineStrokes(pageId, i),
];

/// One note with one page in the host's store and an open session on it.
final class _Doc {
  _Doc(this.store, this.note, this.pageId, this.session);

  final core.NoteStore store;
  final core.Note note;
  final core.PageId pageId;
  final core.NoteSession session;

  static Future<_Doc> create(
    WidgetTester tester,
    core.NoteStore store, {
    List<core.Stroke> Function(String pageId)? strokes,
  }) async {
    final note = await _wait(
      tester,
      store.library.createNote(
        title: 'note',
        pages: const [core.PageDraft.blankA4],
      ),
    );
    final pageId = (await _wait(
      tester,
      store.content.pagesOf(note.id),
    )).single.id;
    final session = await _wait(tester, store.openSession(note.id));
    await _wait(tester, session.openPage(pageId));
    final doc = _Doc(store, note, pageId, session);
    final s = strokes?.call(pageId) ?? const [];
    if (s.isNotEmpty) doc.add(s);
    await _wait(tester, store.flush());
    return doc;
  }

  void add(List<core.Stroke> strokes) =>
      session.execute(core.AddStrokes(pageId: pageId, strokes: strokes));

  Future<core.HandwritingText?> stored(WidgetTester tester) =>
      _wait(tester, store.handwriting.forPage(pageId));

  Future<void> close(WidgetTester tester) => _wait(tester, session.close());

  /// sourceRevOf the page's committed input strokes (the store stamps
  /// updatedAt when it writes them).
  Future<String> rev(WidgetTester tester) async {
    final content = await _wait(tester, store.content.loadPage(pageId));
    return core.HandwritingText.sourceRevOf(
      content.strokes.where(core.HandwritingText.isRecognitionInput),
    );
  }
}

/// Commands and done() calls of a target.
final class _Log {
  final List<core.EditCommand> commands = [];
  int done = 0;
}

/// The selection [strokes] of [doc]; execute goes to the doc's session
/// (unless [execute] is given).
RecognitionTarget _target(
  _Doc doc,
  _Log log,
  List<core.Stroke> strokes, {
  void Function(core.EditCommand command)? execute,
}) {
  final b = strokes
      .map((s) => s.points.pointBounds)
      .reduce((a, b) => a.expandToInclude(b));
  return RecognitionTarget(
    noteId: doc.note.id,
    pageId: doc.pageId,
    pageSize: core.PageSize.a4Portrait,
    strokes: strokes,
    areaPt: Rect.fromLTRB(b.left, b.top, b.right, b.bottom),
    execute:
        execute ??
        (command) {
          doc.session.execute(command);
          log.commands.add(command);
        },
    done: () => log.done++,
  );
}

Future<RecognitionHost> _host(
  WidgetTester tester, {
  HandwritingRecognizer? engine,
  core.NoteStore? store,
  List<Override> overrides = const [],
}) => RecognitionHost.pump(
  tester,
  store: store,
  overrides: [
    if (engine != null) handwritingRecognizerProvider.overrideWithValue(engine),
    ...overrides,
  ],
);

/// Opens the sheet of recog.toText ([copy] false) / recog.copyText; `done`
/// is the run (it completes when the sheet closes).
Future<({Future<void> done})> _open(
  WidgetTester tester,
  RecognitionHost host,
  RecognitionTarget target, {
  bool copy = false,
}) async {
  final action = recognitionSelectionActions().singleWhere(
    (a) => a.id == (copy ? 'recog.copyText' : 'recog.toText'),
  );
  final run = action.run(host.body, target);
  await tester.pump(); // the sheet opens at once
  await tester.pump(const Duration(milliseconds: 400)); // its animation
  expect(_sheet, findsOneWidget);
  return (done: run);
}

Future<void> _cancel(WidgetTester tester, Future<void> run) async {
  await tester.tap(find.byKey(kSheetCancelKey));
  await tester.pumpAndSettle();
  await run;
}

String _text(WidgetTester tester, int i) =>
    tester.widget<TextField>(_line(i)).controller!.text;

List<String> _chips(WidgetTester tester, int i) => [
  for (
    var j = 0;
    find.byKey(conversionChipKey(i, j)).evaluate().isNotEmpty;
    j++
  )
    (tester.widget<ActionChip>(find.byKey(conversionChipKey(i, j))).label
                as Text)
            .data ??
        '',
];

String? _statusText(WidgetTester tester) => _status.evaluate().isEmpty
    ? null
    : tester.widget<SheetNotice>(_status).text;

bool _enabled(WidgetTester tester, Finder button) =>
    tester.widget<ButtonStyleButton>(button).onPressed != null;

/// Presses [button] the way the user does, but calls onPressed directly so
/// the test can look at what happened before any microtask ran.
void _press(WidgetTester tester, Finder button) =>
    tester.widget<ButtonStyleButton>(button).onPressed!();

int Function() _handwritingChanges(core.NoteStore store) {
  var n = 0;
  final sub = store.changes.listen((b) {
    n += b.changes.where((c) => c.kind == core.EntityKind.handwriting).length;
  });
  addTearDown(sub.cancel);
  return () => n;
}

Future<List<FlutterErrorDetails>> _reports(Future<void> Function() body) async {
  final reported = <FlutterErrorDetails>[];
  final previous = FlutterError.onError;
  FlutterError.onError = reported.add;
  try {
    await body();
  } finally {
    FlutterError.onError = previous;
  }
  return reported;
}

/// An engine that answers `<lang>:<first stroke id>` (+ '?' / '!').
FakeHandwritingRecognizer _langEngine({Duration latency = Duration.zero}) {
  late final FakeHandwritingRecognizer engine;
  engine = FakeHandwritingRecognizer(
    latency: latency,
    answer: (line) => '${engine.calls.last.$2}:${line.traces.first.strokeId}',
  );
  return engine;
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await ink_testing.useInkTestFonts();
  });

  group('lines and chips (6.13.1–6.13.2)', () {
    testWidgets('a card per line, the first candidate in the field, the '
        'others as chips; lines in order with preContext and the writing '
        'area', (tester) async {
      final engine = _langEngine();
      final host = await _host(tester, engine: engine);
      final doc = await _Doc.create(
        tester,
        host.store,
        strokes: (p) => [
          ..._lines(p, 2),
          _glyph('hl', p, 90, 150, h: 4, tool: core.PenTool.highlighter),
        ],
      );
      final log = _Log();
      final run = await _open(
        tester,
        host,
        _target(doc, log, [..._lines(doc.pageId, 2)]),
      );
      expect(_line(0), findsOneWidget);
      expect(_line(1), findsOneWidget);
      expect(_line(2), findsNothing);
      expect(_text(tester, 0), 'ko:l0g0');
      expect(_text(tester, 1), 'ko:l1g0');
      expect(_chips(tester, 0), ['ko:l0g0?', 'ko:l0g0!']);
      expect(find.text('1줄'), findsOneWidget);
      expect(_statusText(tester), isNull); // ready
      expect(engine.calls, hasLength(2));
      final (first, firstLang) = engine.calls[0];
      final (second, _) = engine.calls[1];
      expect(firstLang, 'ko');
      expect(first.traces.map((t) => t.strokeId), ['l0g0', 'l0g1', 'l0g2']);
      expect(first.preContext, '');
      expect(second.preContext, 'ko:l0g0');
      expect(first.writingAreaPt!.width, core.PageSize.a4Portrait.width);
      expect(first.writingAreaPt!.height, closeTo(40 * 1.5, 0.01));
      // recog.toText: [텍스트 상자로] primary, [복사] secondary
      expect(
        find.descendant(of: _primary, matching: find.text('텍스트 상자로')),
        findsOneWidget,
      );
      expect(_enabled(tester, _primary), isTrue);
      expect(_enabled(tester, _secondary), isTrue);
      await _cancel(tester, run.done);
      expect(log.commands, isEmpty);
      expect(log.done, 0);
      await doc.close(tester);
    });

    testWidgets('while recognizing: 인식 중… i/n줄, the primary disabled', (
      tester,
    ) async {
      final engine = _langEngine(latency: const Duration(milliseconds: 100));
      final host = await _host(tester, engine: engine);
      final doc = await _Doc.create(tester, host.store);
      final log = _Log();
      final raw = recognitionSelectionActions()
          .singleWhere((a) => a.id == 'recog.toText')
          .run(host.body, _target(doc, log, _lines(doc.pageId, 3)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(_sheet, findsOneWidget);
      expect(_statusText(tester), '인식 중… 1/3줄');
      expect(_enabled(tester, _primary), isFalse);
      await tester.pump(const Duration(milliseconds: 100));
      expect(_statusText(tester), '인식 중… 2/3줄');
      expect(_text(tester, 0), 'ko:l0g0');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(_statusText(tester), isNull);
      expect(_enabled(tester, _primary), isTrue);
      await _cancel(tester, raw);
      await doc.close(tester);
    });

    testWidgets('a chip puts its text in the field (the first candidate '
        'becomes a chip)', (tester) async {
      final host = await _host(tester, engine: _langEngine());
      final doc = await _Doc.create(tester, host.store);
      final run = await _open(
        tester,
        host,
        _target(doc, _Log(), _lines(doc.pageId, 1)),
      );
      await tester.tap(find.byKey(conversionChipKey(0, 1)));
      await tester.pump();
      expect(_text(tester, 0), 'ko:l0g0!');
      expect(_chips(tester, 0), ['ko:l0g0', 'ko:l0g0?']);
      await _cancel(tester, run.done);
      await doc.close(tester);
    });

    testWidgets('more than 20 lines → 20 cards + 나머지 n줄 …; [텍스트 상자로] '
        'replaces the strokes of those 20 lines only', (tester) async {
      final engine = FakeHandwritingRecognizer();
      final host = await _host(tester, engine: engine);
      final doc = await _Doc.create(tester, host.store);
      final strokes = [
        for (var i = 0; i < 21; i++)
          for (var j = 0; j < 3; j++)
            _glyph(
              'r${i}g$j',
              doc.pageId,
              60 + 25.0 * j,
              40 + 36.0 * i,
              h: 20,
              createdAt: 1730800000000 + 10 * i + j,
            ),
      ];
      doc.add(strokes);
      final log = _Log();
      final run = await _open(tester, host, _target(doc, log, strokes));
      expect(_line(19), findsOneWidget);
      expect(_line(20), findsNothing);
      expect(engine.calls, hasLength(20));
      expect(find.text('나머지 1줄은 선택을 나눠 변환해 주세요.'), findsOneWidget);
      await tester.tap(_primary);
      await tester.pumpAndSettle();
      await run.done;
      final command = log.commands.single as core.CompositeCommand;
      final remove = command.commands[0] as core.RemoveElements;
      expect(remove.elementIds, hasLength(60));
      expect(remove.elementIds, isNot(contains('r20g0')));
      await doc.close(tester);
    });
  });

  group('language (6.13.3)', () {
    testWidgets('starts in recog.language; a change recognizes only the '
        'untouched lines; edited / picked lines keep their text; switching '
        'back is immediate; the setting stays', (tester) async {
      final engine = _langEngine();
      final host = await _host(tester, engine: engine);
      await _wait(
        tester,
        host.store.settings.set(RecognitionSettingsKeys.language, 'en'),
      );
      final doc = await _Doc.create(tester, host.store);
      final run = await _open(
        tester,
        host,
        _target(doc, _Log(), _lines(doc.pageId, 3)),
      );
      expect([for (final c in engine.calls) c.$2], ['en', 'en', 'en']);
      expect(_text(tester, 2), 'en:l2g0');
      await tester.enterText(_line(0), '손으로 고친 줄');
      await tester.tap(find.byKey(conversionChipKey(1, 0))); // 'en:l1g0?'
      await tester.pump();
      await tester.tap(find.byKey(conversionLanguageKey('ko')));
      await tester.pumpAndSettle();
      expect(engine.calls, hasLength(4)); // line 3 only
      expect(engine.calls.last.$2, 'ko');
      expect(engine.calls.last.$1.traces.first.strokeId, 'l2g0');
      expect(_text(tester, 0), '손으로 고친 줄');
      expect(_text(tester, 1), 'en:l1g0?');
      expect(_text(tester, 2), 'ko:l2g0');
      await tester.tap(find.byKey(conversionLanguageKey('en')));
      await tester.pumpAndSettle();
      expect(engine.calls, hasLength(4)); // cached
      expect(_text(tester, 2), 'en:l2g0');
      expect(_text(tester, 0), '손으로 고친 줄');
      expect(
        await _wait(
          tester,
          host.store.settings.get(RecognitionSettingsKeys.language),
        ),
        'en',
      );
      await _cancel(tester, run.done);
      await doc.close(tester);
    });
  });

  group('[텍스트 상자로] (6.13.4)', () {
    testWidgets('ONE CompositeCommand (strokes out, the box in) → done once '
        '→ undo is one step back to the ink', (tester) async {
      final host = await _host(tester, engine: _langEngine());
      final doc = await _Doc.create(
        tester,
        host.store,
        strokes: (p) => [
          ..._lines(p, 2),
          _glyph('hl', p, 90, 150, h: 4, tool: core.PenTool.highlighter),
        ],
      );
      final selection = [
        ..._lines(doc.pageId, 2),
        _glyph('hl', doc.pageId, 90, 150, h: 4, tool: core.PenTool.highlighter),
      ];
      final log = _Log();
      final depth = doc.session.history.undoDepth;
      final run = await _open(tester, host, _target(doc, log, selection));
      await tester.enterText(_line(1), '  둘째 줄  ');
      await tester.pump();
      await tester.tap(_primary);
      await tester.pumpAndSettle();
      await run.done;
      expect(_sheet, findsNothing);
      expect(log.done, 1);
      final command = log.commands.single as core.CompositeCommand;
      expect(command.label, kToTextLabel);
      final remove = command.commands[0] as core.RemoveElements;
      final add = command.commands[1] as core.AddObjects;
      expect(remove.pageId, doc.pageId);
      expect(remove.elementIds, [
        for (final s in _lines(doc.pageId, 2)) s.id,
      ]); // not the highlighter
      final box = add.objects.single as core.TextBoxObject;
      expect(box.text, 'ko:l0g0\n둘째 줄');
      expect(doc.session.history.undoDepth, depth + 1);
      var content = await _wait(tester, doc.session.openPage(doc.pageId));
      expect(content.strokes.map((s) => s.id), ['hl']);
      expect(content.objects.single.id, box.id);
      await _wait(tester, doc.session.undo());
      content = await _wait(tester, doc.session.openPage(doc.pageId));
      expect(content.strokes, hasLength(7));
      expect(content.objects, isEmpty);
      await doc.close(tester);
    });

    testWidgets('more than 10,000 characters → the primary disabled + the '
        'notice; [복사] still works', (tester) async {
      final engine = FakeHandwritingRecognizer(answer: (_) => 'ㄱ' * 5001);
      final host = await _host(tester, engine: engine);
      final doc = await _Doc.create(tester, host.store);
      final run = await _open(
        tester,
        host,
        _target(doc, _Log(), _lines(doc.pageId, 2)),
      );
      expect(_enabled(tester, _primary), isFalse);
      expect(find.text(RecognitionStrings.textTooLong), findsOneWidget);
      expect(_enabled(tester, _secondary), isTrue);
      await _cancel(tester, run.done);
      await doc.close(tester);
    });

    testWidgets('read-only note → 읽기 전용 …, the sheet stays, not '
        'reported', (tester) async {
      final host = await _host(tester, engine: _langEngine());
      final doc = await _Doc.create(tester, host.store);
      final log = _Log();
      final reported = await _reports(() async {
        final run = await _open(
          tester,
          host,
          _target(
            doc,
            log,
            _lines(doc.pageId, 1),
            execute: (_) => throw const core.ReadOnlyNoteException('n'),
          ),
        );
        await tester.tap(_primary);
        await tester.pumpAndSettle();
        expect(_sheet, findsOneWidget);
        expect(find.text('읽기 전용 노트라 바꿀 수 없어요.'), findsOneWidget);
        await _cancel(tester, run.done);
      });
      expect(reported, isEmpty);
      expect(log.done, 0);
      await doc.close(tester);
    });
  });

  group('[복사] and confirmed lines (6.13.5)', () {
    testWidgets('recog.copyText: the clipboard call happens inside the press '
        '(④); flush → update: every line confirmed, all → fresh sourceRev; '
        'the sheet closes, 복사했어요; no command, no done', (tester) async {
      final platform = PlatformLog(tester);
      final host = await _host(tester, engine: _langEngine());
      final doc = await _Doc.create(
        tester,
        host.store,
        strokes: (p) => _lines(p, 2),
      );
      final changes = _handwritingChanges(host.store);
      final log = _Log();
      final run = await _open(
        tester,
        host,
        _target(doc, log, _lines(doc.pageId, 2)),
        copy: true,
      );
      expect(
        find.descendant(of: _primary, matching: find.text('복사')),
        findsOneWidget,
      );
      expect(_secondary, findsNothing);
      await tester.enterText(_line(0), '고친 첫 줄');
      await tester.pump();
      platform.calls.clear();
      _press(tester, _primary);
      expect(platform.clipboardTexts, ['고친 첫 줄\nko:l1g0']); // synchronous
      await tester.pumpAndSettle();
      await run.done;
      expect(_sheet, findsNothing);
      expect(host.snackBars, ['복사했어요.']);
      expect(log.commands, isEmpty);
      expect(log.done, 0);
      final stored = (await doc.stored(tester))!;
      expect(stored.sourceRev, await doc.rev(tester));
      expect(stored.engineId, 'fake:ko');
      expect(stored.lines, hasLength(2));
      final [first, second] = stored.lines;
      expect(first.text, '고친 첫 줄');
      expect(first.userConfirmed, isTrue);
      expect(first.alternatives, ['ko:l0g0', 'ko:l0g0?', 'ko:l0g0!']);
      expect(first.strokeIds, ['l0g0', 'l0g1', 'l0g2']);
      expect(first.languageTag, 'ko');
      expect(second.text, 'ko:l1g0');
      expect(second.alternatives, ['ko:l1g0?', 'ko:l1g0!']);
      expect(second.userConfirmed, isTrue);
      expect(changes(), 1);
      await doc.close(tester);
    });

    testWidgets('part of a page (③) → the stored sourceRev and engine stay, '
        'the other stored lines stay', (tester) async {
      PlatformLog(tester);
      final host = await _host(tester, engine: _langEngine());
      final doc = await _Doc.create(
        tester,
        host.store,
        strokes: (p) => _lines(p, 2),
      );
      final secondIds = [for (final s in _lineStrokes(doc.pageId, 1)) s.id];
      await _wait(
        tester,
        host.store.handwriting.put(
          core.HandwritingText(
            noteId: doc.note.id,
            pageId: doc.pageId,
            engineId: 'other/2:ko',
            sourceRev: '0123456789abcdef',
            lines: [
              core.HandwritingLine(
                text: '저장된 둘째 줄',
                rect: const core.PageRect(100, 200, 260, 240),
                strokeIds: secondIds,
              ),
            ],
            createdAt: 1,
          ),
        ),
      );
      final run = await _open(
        tester,
        host,
        _target(doc, _Log(), _lineStrokes(doc.pageId, 0)),
        copy: true,
      );
      _press(tester, _primary);
      await tester.pumpAndSettle();
      await run.done;
      final stored = (await doc.stored(tester))!;
      expect(stored.sourceRev, '0123456789abcdef');
      expect(stored.engineId, 'other/2:ko');
      expect(stored.lines.map((l) => l.text), ['ko:l0g0', '저장된 둘째 줄']);
      expect(stored.lines.map((l) => l.userConfirmed), [true, false]);
      await doc.close(tester);
    });

    testWidgets('right after writing (②): strokes not committed yet → flush '
        'first → the stored sourceRev covers them (all)', (tester) async {
      PlatformLog(tester);
      final faults = core_testing.FakeNoteStoreFaults();
      final store = core_testing.createFakeNoteStore(
        clock: FakeAsync().getClock(kHostNow),
        faults: faults,
      );
      addTearDown(store.close);
      final host = await _host(tester, engine: _langEngine(), store: store);
      final doc = await _Doc.create(
        tester,
        store,
        strokes: (p) => _lineStrokes(p, 0),
      );
      faults.commitDelay = const Duration(seconds: 2);
      doc.add(_lineStrokes(doc.pageId, 1)); // in the session, not committed
      final all = _lines(doc.pageId, 2);
      final run = await _open(
        tester,
        host,
        _target(doc, _Log(), all),
        copy: true,
      );
      _press(tester, _primary);
      await tester.pump(const Duration(seconds: 2)); // the session's commit
      await tester.pump(const Duration(seconds: 2)); // the update's commit
      await tester.pumpAndSettle();
      await run.done;
      final stored = (await _wait(
        tester,
        store.handwriting.forPage(doc.pageId),
      ))!;
      expect(stored.sourceRev, await doc.rev(tester));
      expect(
        (await _wait(tester, store.content.loadPage(doc.pageId))).strokes,
        hasLength(6),
      );
      expect(stored.engineId, 'fake:ko'); // all
      expect(stored.lines, hasLength(2));
      faults.commitDelay = Duration.zero;
      await doc.close(tester);
    });

    testWidgets('the indexer running on the page (①): copy during its job → '
        'the job dropped and run again, the confirmed line kept; changes = '
        'the copy + the indexer', (tester) async {
      PlatformLog(tester);
      final engine = _langEngine(latency: const Duration(milliseconds: 100));
      final host = await _host(tester, engine: engine);
      final doc = await _Doc.create(tester, host.store);
      final enabled = ValueNotifier(true);
      final foreground = ValueNotifier(true);
      addTearDown(enabled.dispose);
      addTearDown(foreground.dispose);
      final indexer = HandwritingIndexer(
        store: host.store,
        recognizer: engine,
        enabled: enabled,
        foreground: foreground,
      )..start();
      await tester.pump();
      final changes = _handwritingChanges(host.store);
      doc.add(_lines(doc.pageId, 3));
      await _wait(tester, host.store.flush());
      // t ≈ 0: the sheet on line 1 only; it recognizes that line (100 ms).
      final run = await _open(
        tester,
        host,
        _target(doc, _Log(), _lineStrokes(doc.pageId, 0)),
        copy: true,
      );
      await tester.enterText(_line(0), '고친 첫 줄');
      await tester.pump();
      expect(engine.calls, hasLength(1));
      // The indexer's job after 3 s of quiet: line 1, then line 2 in flight.
      await tester.pump(const Duration(milliseconds: 2600));
      await tester.pump(const Duration(milliseconds: 150));
      expect(engine.calls.length, 3, reason: 'line 2 of the job in flight');
      _press(tester, _primary);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      await run.done;
      final stored = (await doc.stored(tester))!;
      expect(stored.lines, hasLength(3));
      expect(stored.lines[0].text, '고친 첫 줄');
      expect(stored.lines[0].userConfirmed, isTrue);
      expect(stored.lines.skip(1).map((l) => l.userConfirmed), [false, false]);
      expect(stored.sourceRev, await doc.rev(tester));
      // the sheet 1 + the dropped job 2 + lines 2 and 3 again (line 1 reused)
      expect(engine.calls, hasLength(5));
      expect(changes(), 2);
      await _wait(tester, indexer.dispose());
      await doc.close(tester);
    });

    testWidgets('the clipboard refuses → 복사하지 못했어요, the sheet stays, '
        'nothing written', (tester) async {
      final platform = PlatformLog(tester);
      platform.reply = (call) async => call.method == 'Clipboard.setData'
          ? throw PlatformException(code: 'denied', message: 'no activation')
          : null;
      final host = await _host(tester, engine: _langEngine());
      final doc = await _Doc.create(
        tester,
        host.store,
        strokes: (p) => _lines(p, 1),
      );
      final run = await _open(
        tester,
        host,
        _target(doc, _Log(), _lines(doc.pageId, 1)),
        copy: true,
      );
      _press(tester, _primary);
      await tester.pumpAndSettle();
      expect(_sheet, findsOneWidget);
      expect(find.text('복사하지 못했어요.'), findsOneWidget);
      expect(await doc.stored(tester), isNull);
      await _cancel(tester, run.done);
      await doc.close(tester);
    });
  });

  group('no engine, models, failures (6.13.1, 6.7.4, 6.22)', () {
    testWidgets('UnsupportedHandwritingRecognizer → the fixed sentence '
        '(web) / 이 기기에서는 … (desktop), [닫기], no primary', (tester) async {
      final host = await _host(tester); // the default engine
      final doc = await _Doc.create(tester, host.store);
      for (final web in [true, false]) {
        ConversionSheetDebug.isWeb = web;
        try {
          final run = await _open(
            tester,
            host,
            _target(doc, _Log(), _lines(doc.pageId, 1)),
          );
          expect(
            _statusText(tester),
            web
                ? '이 기기(웹)에서는 손글씨 인식을 쓸 수 없어요. 안드로이드 앱에서 쓸 수 있어요.'
                : RecognitionStrings.unsupported,
          );
          expect(_primary, findsNothing);
          expect(_line(0), findsNothing);
          expect(
            find.descendant(
              of: find.byKey(kSheetCancelKey),
              matching: find.text('닫기'),
            ),
            findsOneWidget,
          );
          await _cancel(tester, run.done);
        } finally {
          ConversionSheetDebug.isWeb = null;
        }
      }
      await doc.close(tester);
    });

    testWidgets('model not downloaded → the model card → [받기] → '
        'ensureModel once → recognition goes on', (tester) async {
      final engine = FakeHandwritingRecognizer()
        ..modelStates['ko'] = RecognitionModelState.notDownloaded;
      final host = await _host(tester, engine: engine);
      final doc = await _Doc.create(tester, host.store);
      final run = await _open(
        tester,
        host,
        _target(doc, _Log(), _lines(doc.pageId, 2)),
      );
      expect(_statusText(tester), '한국어 인식 모델을 받아야 해요(약 20MB).');
      expect(engine.calls, isEmpty);
      await tester.pump(); // the row's modelState answer
      final row = find.byKey(const ValueKey('recog.sheet.model.ko'));
      await tester.tap(find.descendant(of: row, matching: find.text('받기')));
      await tester.pumpAndSettle();
      expect(engine.ensureModelCalls, 1);
      expect(engine.calls, hasLength(2));
      expect(_statusText(tester), isNull);
      expect(_text(tester, 1), '줄 2');
      await _cancel(tester, run.done);
      await doc.close(tester);
    });

    testWidgets('ModelNotReady from the engine → the model card → [받기] → '
        'the line again', (tester) async {
      final engine = FakeHandwritingRecognizer()
        ..failNext = ModelNotReady('ko');
      final host = await _host(tester, engine: engine);
      final doc = await _Doc.create(tester, host.store);
      final run = await _open(
        tester,
        host,
        _target(doc, _Log(), _lines(doc.pageId, 1)),
      );
      expect(_statusText(tester), '한국어 인식 모델을 받아야 해요(약 20MB).');
      // The model went between modelState and the call (deleted elsewhere):
      // the row follows modelChanges and offers [받기].
      await _wait(tester, engine.deleteModel('ko'));
      await tester.pumpAndSettle();
      expect(_statusText(tester), '한국어 인식 모델을 받아야 해요(약 20MB).');
      final row = find.byKey(const ValueKey('recog.sheet.model.ko'));
      await tester.tap(find.descendant(of: row, matching: find.text('받기')));
      await tester.pumpAndSettle();
      expect(engine.ensureModelCalls, 1);
      expect(engine.calls, hasLength(2)); // the failed call + again
      expect(_text(tester, 0), '줄 2');
      await _cancel(tester, run.done);
      await doc.close(tester);
    });

    testWidgets('Android: a Wi-Fi-only download still running after 5 s → '
        '[지금 셀룰러로 받기] twice → ensureModel(wifiOnly: false)', (tester) async {
      final engine = ControlledModelEngine();
      final host = await _host(tester, engine: engine);
      final doc = await _Doc.create(tester, host.store);
      final run = await _open(
        tester,
        host,
        _target(doc, _Log(), _lines(doc.pageId, 1)),
      );
      await tester.pump(); // the row's modelState answer
      final row = find.byKey(const ValueKey('recog.sheet.model.ko'));
      await tester.tap(find.descendant(of: row, matching: find.text('받기')));
      await tester.pump();
      expect(engine.ensureCalls, [('ko', true)]);
      await tester.pump(kWifiWaitBeforeCellular);
      await tester.pump();
      expect(find.text(RecognitionStrings.waitingForWifi), findsOneWidget);
      final cellular = find.byKey(
        const ValueKey('recog.sheet.model.ko.cellular'),
      );
      await tester.tap(cellular);
      await tester.pump();
      expect(engine.ensureCalls, hasLength(1)); // the warning first
      expect(find.text(RecognitionStrings.cellularConfirm), findsOneWidget);
      await tester.tap(cellular);
      await tester.pump();
      expect(engine.ensureCalls, [('ko', true), ('ko', false)]);
      engine.finish(1);
      await tester.pumpAndSettle();
      expect(row, findsNothing); // the card went, the line was recognized
      expect(_statusText(tester), isNull);
      expect(_line(0), findsOneWidget);
      await _cancel(tester, run.done);
      await doc.close(tester);
    });

    testWidgets('an engine failure → 인식하지 못했어요 [다시] (not reported) → '
        'again', (tester) async {
      final engine = FakeHandwritingRecognizer()
        ..failNext = RecognizerEngineError('internal', 'boom');
      final host = await _host(tester, engine: engine);
      final doc = await _Doc.create(tester, host.store);
      final reported = await _reports(() async {
        final run = await _open(
          tester,
          host,
          _target(doc, _Log(), _lines(doc.pageId, 1)),
        );
        expect(_statusText(tester), RecognitionStrings.recognizeFailed);
        await tester.tap(
          find.descendant(of: _status, matching: find.text('다시')),
        );
        await tester.pumpAndSettle();
        expect(_statusText(tester), isNull);
        expect(_text(tester, 0), '줄 2');
        await _cancel(tester, run.done);
      });
      expect(reported, isEmpty);
      await doc.close(tester);
    });
  });

  test('the 6.7.4 / 6.13.2 numbers', () {
    expect(kWifiWaitBeforeCellular, const Duration(seconds: 5));
    expect(kMaxConversionLines, 20);
    expect(kMaxLineChips, 4);
  });
}
