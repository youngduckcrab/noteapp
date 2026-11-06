// L2-12 (m5-7/05-library 8.2, 4.4.4, 6.3, 6.16; contract 7.2.10–7.2.11): the
// action lists (ids, order, labels, icons), isVisible row by row, the run
// dispatch to the sheets (a recording fake — the sheets land with L2-13…17b),
// and the rules every run keeps: one containerOf BEFORE the first microtask,
// no exception out of run (report once + '실행하지 못했어요', read-only →
// '읽기 전용 …'), at most one execute, no snack bar once the editor body is
// unmounted. 6.13.6 direct copy: Clipboard.setData sent in the same
// synchronous stretch as run, the LaTeX / text as is, a refusal → '복사하지
// 못했어요' (not reported), no done().
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_recognition/ink_recognition.dart';
import 'package:ink_recognition/src/actions/action_scope.dart';
import 'package:ink_recognition/src/actions/recognition_actions.dart'
    show buildInsertActions, buildSelectionActions;
import 'package:ink_recognition/src/ui/recognition_sheets.dart';
import 'package:ink_recognition/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart' as core_testing;

import '../support/recognition_test_scope.dart';

/// One sheet call.
typedef SheetCall = ({
  String sheet,
  ActionRun run,
  List<String> inputs,
  bool? copy,
  core.MathObject? math,
});

/// Records every sheet the actions open; [answer] decides what the sheet
/// does (default: finishes at once).
final class FakeSheets implements RecognitionSheets {
  final List<SheetCall> calls = [];
  Future<void> Function(ActionRun run) answer = (run) async {};

  Future<void> _record(
    String sheet,
    ActionRun run, {
    List<core.Stroke> inputs = const [],
    bool? copy,
    core.MathObject? math,
  }) {
    calls.add((
      sheet: sheet,
      run: run,
      inputs: [for (final s in inputs) s.id],
      copy: copy,
      math: math,
    ));
    return answer(run);
  }

  @override
  Future<void> conversion(
    ActionRun run, {
    required List<core.Stroke> inputs,
    required bool copy,
  }) => _record('conversion', run, inputs: inputs, copy: copy);

  @override
  Future<void> toMath(ActionRun run, {required List<core.Stroke> inputs}) =>
      _record('toMath', run, inputs: inputs);

  @override
  Future<void> latexEditor(ActionRun run, core.MathObject math) =>
      _record('latexEditor', run, math: math);

  @override
  Future<void> mathPad(ActionRun run) => _record('mathPad', run);
}

final _ink = glyphStroke('ink-1', 100, 100, 20);
final _ink2 = glyphStroke('ink-2', 140, 100, 20, createdAt: 1730800000001);
final _marker = glyphStroke(
  'hl-1',
  100,
  100,
  20,
  tool: core.PenTool.highlighter,
);
final _tape = glyphStroke('tape-1', 100, 100, 20, tool: core.PenTool.tape);
final _laser = glyphStroke('laser-1', 100, 100, 20, tool: core.PenTool.laser);
final _math = core_testing.PageObjectFixtures.math(
  pageId: kPageId,
  latex: r'\frac{a}{b}',
);
final _box = core_testing.PageObjectFixtures.textBox(
  pageId: kPageId,
  text: '안녕 hello',
);
final _shape = core_testing.PageObjectFixtures.shape(pageId: kPageId);
final _unknown = core.UnknownObject(const {
  'id': 'u-1',
  'pageId': kPageId,
  'type': 'sticker',
  'createdAt': 1,
  'updatedAt': 1,
});

RecognitionAction _byId(List<RecognitionAction> actions, String id) =>
    actions.singleWhere((a) => a.id == id);

/// Captures FlutterError reports inside [body] (restored before the test
/// ends — testWidgets checks FlutterError.onError).
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

void main() {
  group('lists (4.4.4)', () {
    test('selection: ids, order, labels, icons', () {
      final actions = recognitionSelectionActions();
      expect(
        [for (final a in actions) a.id],
        ['recog.toText', 'recog.copyText', 'recog.toMath', 'recog.editMath'],
      );
      expect(
        [for (final a in actions) a.label],
        ['텍스트로 변환', '텍스트 복사', '수식으로 변환', '수식 편집'],
      );
      expect(
        [for (final a in actions) a.icon],
        [
          Icons.short_text,
          Icons.content_copy,
          Icons.functions,
          Icons.edit_note,
        ],
      );
      expect([
        for (final a in actions) a.isVisible != null,
      ], everyElement(true));
      expect(
        [for (final a in buildSelectionActions(sheets: FakeSheets())) a.id],
        [for (final a in actions) a.id],
      );
    });

    test('insert: recog.mathPad · 수식 · functions, no visibility hook', () {
      final actions = recognitionInsertActions();
      expect(actions, hasLength(1));
      expect(actions.single.id, 'recog.mathPad');
      expect(actions.single.label, '수식');
      expect(actions.single.icon, Icons.functions);
      expect(actions.single.isVisible, isNull);
    });
  });

  group('isVisible (4.4.4 table — the target only, no provider)', () {
    final log = TargetLog();
    final actions = recognitionSelectionActions();
    List<String> visible({
      List<core.Stroke> strokes = const [],
      List<core.PageObject> objects = const [],
    }) {
      final t = log.target(strokes: strokes, objects: objects);
      return [
        for (final a in actions)
          if (a.isVisible!(t)) a.id,
      ];
    }

    const ink = ['recog.toText', 'recog.copyText', 'recog.toMath'];
    test('ink strokes → toText, copyText, toMath', () {
      expect(visible(strokes: [_ink]), ink);
      expect(visible(strokes: [_marker, _ink]), ink);
    });
    test('only highlighter / tape / laser strokes → nothing', () {
      expect(visible(strokes: [_marker]), isEmpty);
      expect(visible(strokes: [_marker, _tape, _laser]), isEmpty);
    });
    test('no strokes, one MathObject → copyText, editMath', () {
      expect(visible(objects: [_math]), ['recog.copyText', 'recog.editMath']);
    });
    test('no strokes, one TextBoxObject → copyText', () {
      expect(visible(objects: [_box]), ['recog.copyText']);
    });
    test('one shape / one unknown object / two objects / empty → nothing', () {
      expect(visible(objects: [_shape]), isEmpty);
      expect(visible(objects: [_unknown]), isEmpty);
      expect(visible(objects: [_math, _box]), isEmpty);
      expect(visible(objects: [_math, _math]), isEmpty);
      expect(visible(), isEmpty);
    });
    test('a MathObject with strokes: ink rules only (no editMath)', () {
      expect(visible(strokes: [_ink], objects: [_math]), ink);
      expect(visible(strokes: [_marker], objects: [_math]), isEmpty);
    });
    test('an UnknownObject in the selection: strokes decide', () {
      expect(visible(strokes: [_ink], objects: [_unknown]), ink);
    });
    test('no engine does not hide anything (isVisible reads no provider — '
        'called here with no ProviderScope at all)', () {
      expect(visible(strokes: [_ink, _ink2]), ink);
    });
  });

  group('run (6.3, 6.16)', () {
    late FakeSheets sheets;
    late TargetLog log;
    setUp(() {
      sheets = FakeSheets();
      log = TargetLog();
      RecognitionActionScope.debugLookups = 0;
    });

    List<RecognitionAction> all() => [
      ...buildSelectionActions(sheets: sheets),
      ...buildInsertActions(sheets: sheets),
    ];

    /// The target each action's main path takes.
    RecognitionTarget targetFor(String id) => switch (id) {
      'recog.editMath' => log.target(objects: [_math]),
      'recog.mathPad' => log.target(),
      _ => log.target(strokes: [_marker, _ink, _ink2]),
    };

    testWidgets('each action: one containerOf and its sheet opened before '
        'the first microtask', (tester) async {
      final host = await RecognitionHost.pump(tester);
      for (final action in all()) {
        RecognitionActionScope.debugLookups = 0;
        sheets.calls.clear();
        final pending = action.run(host.body, targetFor(action.id));
        expect(RecognitionActionScope.debugLookups, 1, reason: action.id);
        expect(sheets.calls, hasLength(1), reason: action.id);
        await settle(tester, pending);
        expect(RecognitionActionScope.debugLookups, 1, reason: action.id);
      }
    });

    testWidgets('dispatch: which sheet, with which strokes', (tester) async {
      final host = await RecognitionHost.pump(tester);
      final selection = buildSelectionActions(sheets: sheets);
      final strokes = [_marker, _ink, _tape, _ink2];
      for (final id in ['recog.toText', 'recog.copyText', 'recog.toMath']) {
        await _byId(selection, id).run(host.body, log.target(strokes: strokes));
      }
      await _byId(
        selection,
        'recog.editMath',
      ).run(host.body, log.target(objects: [_math]));
      final pad = buildInsertActions(sheets: sheets).single;
      final insert = log.target(areaPt: const Rect.fromLTWH(0, 0, 800, 600));
      await pad.run(host.body, insert);

      expect(
        [for (final c in sheets.calls) c.sheet],
        ['conversion', 'conversion', 'toMath', 'latexEditor', 'mathPad'],
      );
      expect(
        [for (final c in sheets.calls) c.copy],
        [false, true, null, null, null],
      );
      // recognition inputs only, z order kept
      for (final c in sheets.calls.take(3)) {
        expect(c.inputs, ['ink-1', 'ink-2']);
      }
      expect(sheets.calls[3].math, same(_math));
      expect(identical(sheets.calls[4].run.target, insert), isTrue);
      expect(
        [for (final c in sheets.calls) c.run.actionId],
        [
          'recog.toText',
          'recog.copyText',
          'recog.toMath',
          'recog.editMath',
          'recog.mathPad',
        ],
      );
      expect(log.commands, isEmpty);
      expect(log.doneCalls, 0);
    });

    testWidgets('the scope reads the app container lazily', (tester) async {
      final store = createFixedClockStore();
      addTearDown(store.close);
      final recognizer = FakeHandwritingRecognizer();
      final math = FakeMathRecognizer();
      final host = await RecognitionHost.pump(
        tester,
        store: store,
        overrides: [
          handwritingRecognizerProvider.overrideWithValue(recognizer),
          mathRecognizerProvider.overrideWithValue(math),
        ],
      );
      await buildInsertActions(sheets: sheets).single
          .run(host.body, log.target());
      final scope = sheets.calls.single.run.scope;
      expect(
        scope.container,
        same(ProviderScope.containerOf(host.body, listen: false)),
      );
      expect(scope.handwriting, same(recognizer));
      expect(scope.math, same(math));
      expect(scope.store, same(store));
      expect(scope.content, same(store.content));
      expect(scope.handwritingRepo, same(store.handwriting));
      expect(scope.settings, same(store.settings));
      expect(scope.renderer, isNull);
      expect(scope.newId(), isNot(scope.newId()));
      expect(scope.nowMs(), kHostNow.millisecondsSinceEpoch);
    });

    testWidgets('an exception in a sheet: run completes, reported once, '
        '실행하지 못했어요', (tester) async {
      final host = await RecognitionHost.pump(tester);
      final pad = buildInsertActions(sheets: sheets).single;
      final reported = await _reports(() async {
        sheets.answer = (run) => throw StateError('boom');
        await expectLater(pad.run(host.body, log.target()), completes);
        sheets.answer = (run) async => throw const FormatException('late');
        await expectLater(pad.run(host.body, log.target()), completes);
        await tester.pump();
      });
      expect(reported, hasLength(2));
      expect(reported.map((r) => r.library), everyElement('ink_recognition'));
      expect(
        reported.map((r) => r.context.toString()),
        everyElement('while running recog.mathPad'),
      );
      expect(reported[0].exception, isA<StateError>());
      expect(reported[1].exception, isA<FormatException>());
      expect(host.snackBars, contains('실행하지 못했어요.'));
    });

    testWidgets('every action × every failure in its sheet (throws at once, '
        'a failed Future, execute throws): run completes, reported once '
        'under its id, 실행하지 못했어요 (9.3 G-1)', (tester) async {
      final host = await RecognitionHost.pump(tester);
      final messenger = ScaffoldMessenger.of(host.body);
      final command = core.AddObjects(pageId: kPageId, objects: [_math]);
      final failures = <String, (Future<void> Function(ActionRun), Matcher)>{
        'throws at once': (
          (run) => throw StateError('boom'),
          isA<StateError>(),
        ),
        'a failed Future': (
          (run) async => throw const FormatException('late'),
          isA<FormatException>(),
        ),
        'execute throws': (
          (run) async => run.execute(command),
          isA<core.SessionClosedException>(),
        ),
      };
      final ids = <String>[];
      for (final action in all()) {
        ids.add(action.id);
        for (final MapEntry(key: kind, value: (answer, exception))
            in failures.entries) {
          final reason = '${action.id} × $kind';
          sheets
            ..calls.clear()
            ..answer = answer;
          log.executeError = kind == 'execute throws'
              ? const core.SessionClosedException('note-1')
              : null;
          final reported = await _reports(() async {
            await expectLater(
              action.run(host.body, targetFor(action.id)),
              completes,
              reason: reason,
            );
            await tester.pump();
          });
          expect(sheets.calls, hasLength(1), reason: reason);
          expect(reported, hasLength(1), reason: reason);
          expect(reported.single.exception, exception, reason: reason);
          expect(reported.single.library, 'ink_recognition', reason: reason);
          expect(
            reported.single.context.toString(),
            'while running ${action.id}',
            reason: reason,
          );
          expect(host.snackBars, ['실행하지 못했어요.'], reason: reason);
          messenger
            ..clearSnackBars()
            ..removeCurrentSnackBar();
          await tester.pump();
        }
      }
      expect(ids, [
        'recog.toText',
        'recog.copyText',
        'recog.toMath',
        'recog.editMath',
        'recog.mathPad',
      ]);
      expect(log.commands, isEmpty);
      expect(log.doneCalls, 0);
    });

    testWidgets('read-only note: 읽기 전용 노트라 바꿀 수 없어요, not reported', (
      tester,
    ) async {
      final host = await RecognitionHost.pump(tester);
      log.executeError = core.ReadOnlyNoteException('n1');
      sheets.answer = (run) async {
        run.execute(core.AddObjects(pageId: kPageId, objects: [_math]));
      };
      final reported = await _reports(() async {
        await buildInsertActions(sheets: sheets).single
            .run(host.body, log.target());
        await tester.pump();
      });
      expect(reported, isEmpty);
      expect(host.snackBars, ['읽기 전용 노트라 바꿀 수 없어요.']);
    });

    testWidgets('execute at most once per run', (tester) async {
      final host = await RecognitionHost.pump(tester);
      final command = core.AddObjects(pageId: kPageId, objects: [_math]);
      sheets.answer = (run) async {
        expect(run.executed, isFalse);
        run.execute(command);
        expect(run.executed, isTrue);
        run.execute(command); // a bug: refused
      };
      final reported = await _reports(() async {
        await buildInsertActions(sheets: sheets).single
            .run(host.body, log.target());
      });
      expect(log.commands, [command]);
      expect(reported.single.exception, isA<StateError>());
    });

    testWidgets('the editor body unmounted during the run → no snack bar '
        '(still reported)', (tester) async {
      final host = await RecognitionHost.pump(tester);
      final gate = Completer<void>();
      sheets.answer = (run) async {
        await gate.future;
        throw StateError('after the editor closed');
      };
      final reported = await _reports(() async {
        final pending = buildInsertActions(sheets: sheets).single
            .run(host.body, log.target());
        await host.unmountBody();
        gate.complete();
        await settle(tester, pending);
      });
      expect(reported, hasLength(1));
      expect(host.snackBars, isEmpty);
    });

    testWidgets('no ProviderScope above the context: reported once, run '
        'completes', (tester) async {
      late BuildContext bare;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                bare = context;
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      );
      final reported = await _reports(() async {
        await expectLater(
          buildInsertActions(sheets: sheets).single.run(bare, log.target()),
          completes,
        );
        await tester.pump();
      });
      expect(reported, hasLength(1));
      expect(reported.single.exception, isA<StateError>());
      expect(sheets.calls, isEmpty);
      expect(find.text('실행하지 못했어요.'), findsOneWidget);
    });

    testWidgets('called although invisible (highlighter only): 변환할 손글씨가 '
        '없어요, no sheet', (tester) async {
      final host = await RecognitionHost.pump(tester);
      for (final id in ['recog.toText', 'recog.copyText', 'recog.toMath']) {
        await _byId(
          buildSelectionActions(sheets: sheets),
          id,
        ).run(host.body, log.target(strokes: [_marker]));
      }
      await _byId(
        buildSelectionActions(sheets: sheets),
        'recog.editMath',
      ).run(host.body, log.target(objects: [_box]));
      await tester.pump();
      expect(sheets.calls, isEmpty);
      expect(host.snackBars, contains('변환할 손글씨가 없어요.'));
    });
  });

  group('direct copy (6.13.6 — no strokes, one object)', () {
    late TargetLog log;
    setUp(() => log = TargetLog());

    RecognitionAction copyText() =>
        _byId(buildSelectionActions(sheets: FakeSheets()), 'recog.copyText');

    testWidgets('a MathObject → its LaTeX, sent before the first microtask; '
        '복사했어요; selection kept', (tester) async {
      final host = await RecognitionHost.pump(tester);
      final platform = PlatformLog(tester);
      RecognitionActionScope.debugLookups = 0;
      final pending = copyText().run(host.body, log.target(objects: [_math]));
      expect(RecognitionActionScope.debugLookups, 1);
      expect(platform.clipboardTexts, [r'\frac{a}{b}']); // synchronous
      await settle(tester, pending);
      await tester.pump();
      expect(host.snackBars, ['복사했어요.']);
      expect(log.doneCalls, 0);
      expect(log.commands, isEmpty);
    });

    testWidgets('a TextBoxObject → its text', (tester) async {
      final host = await RecognitionHost.pump(tester);
      final platform = PlatformLog(tester);
      final pending = copyText().run(host.body, log.target(objects: [_box]));
      expect(platform.clipboardTexts, ['안녕 hello']);
      await settle(tester, pending);
    });

    testWidgets('the platform refuses → 복사하지 못했어요, not reported', (
      tester,
    ) async {
      final host = await RecognitionHost.pump(tester);
      final platform = PlatformLog(tester)
        ..reply = (call) async => call.method == 'Clipboard.setData'
            ? throw PlatformException(code: 'NotAllowedError')
            : null;
      final reported = await _reports(() async {
        await copyText().run(host.body, log.target(objects: [_math]));
        await tester.pump();
      });
      expect(platform.clipboardTexts, hasLength(1));
      expect(reported, isEmpty);
      expect(host.snackBars, ['복사하지 못했어요.']);
    });

    testWidgets('editor body gone before the copy finished → no snack bar', (
      tester,
    ) async {
      final host = await RecognitionHost.pump(tester);
      final gate = Completer<void>();
      final platform = PlatformLog(tester)
        ..reply = (call) async {
          await gate.future;
          return null;
        };
      final pending = copyText().run(host.body, log.target(objects: [_box]));
      expect(platform.clipboardTexts, ['안녕 hello']);
      await host.unmountBody();
      gate.complete();
      await settle(tester, pending);
      await tester.pump();
      expect(host.snackBars, isEmpty);
    });
  });
}
