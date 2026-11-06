// m5-7/04-editor 8.2 E2-07c, 4.3.1, 6.21: ExtensionRunner — the slot
// callback rules. ① a second press of an unfinished item is ignored; ② the
// callback starts synchronously with the body context; ③ then close (also
// after a synchronous exception); ④ then the Future. Exceptions are reported
// ('while running <id>') and show '실행하지 못했어요' while the body is mounted;
// a callback that ends after the body went away has its result dropped.
import 'dart:async';

import 'package:feature_editor/feature_editor.dart';
import 'package:feature_editor/src/commands/extension_runner.dart';
import 'package:feature_editor/src/ui/editor_strings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart';

/// A body whose context the runner gets.
class _Body extends StatefulWidget {
  const _Body();

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

Future<BuildContext> _pumpBody(WidgetTester tester) async {
  await tester.pumpWidget(
    const Directionality(textDirection: TextDirection.ltr, child: _Body()),
  );
  return tester.element(find.byType(_Body));
}

/// Runs [body] with FlutterError reports collected.
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
  late List<String> notices;
  late ExtensionRunner runner;

  setUp(() {
    notices = [];
    runner = ExtensionRunner(notify: notices.add);
  });

  testWidgets('starts synchronously with the body context, then closes, '
      'then awaits; the value comes back', (tester) async {
    final body = await _pumpBody(tester);
    runner.bindBody(() => body);
    final order = <String>[];
    final hold = Completer<int>();
    BuildContext? got;
    final done = runner.run<int>('a', (context) {
      got = context;
      order.add('start');
      return hold.future;
    }, close: () => order.add('close'));
    // Both ran before run() returned — no await in between.
    expect(order, ['start', 'close']);
    expect(got, same(body));
    expect(runner.isRunning('a'), isTrue);
    hold.complete(7);
    expect(await done, 7);
    expect(runner.isRunning('a'), isFalse);
    expect(notices, isEmpty);
  });

  testWidgets('a second press of an unfinished item is ignored (no start, '
      'no close); another item runs; after it finished it runs again', (
    tester,
  ) async {
    final body = await _pumpBody(tester);
    runner.bindBody(() => body);
    final hold = Completer<void>();
    var starts = 0, closes = 0;
    final first = runner.run<void>('a', (_) {
      starts++;
      return hold.future;
    }, close: () => closes++);
    final second = runner.run<int>('a', (_) {
      starts++;
      return Future.value(1);
    }, close: () => closes++);
    expect(starts, 1);
    expect(closes, 1);
    expect(await second, isNull);

    var other = 0;
    await runner.run<void>('b', (_) async => other++);
    expect(other, 1);

    hold.complete();
    await first;
    await runner.run<void>('a', (_) async => starts++);
    expect(starts, 2);
  });

  testWidgets('a synchronous exception: close still runs, one report '
      "('while running <id>'), '실행하지 못했어요', not running any more", (
    tester,
  ) async {
    final body = await _pumpBody(tester);
    runner.bindBody(() => body);
    var closed = false;
    Object? result = 'x';
    final reported = await _reports(() async {
      result = await runner.run<int>(
        'boom',
        (_) => throw StateError('sync'),
        close: () => closed = true,
      );
    });
    expect(closed, isTrue);
    expect(result, isNull);
    expect(reported, hasLength(1));
    expect(reported.single.exception, isA<StateError>());
    expect(reported.single.library, 'feature_editor');
    expect(reported.single.context.toString(), contains('while running boom'));
    expect(notices, [EditorStrings.commandFailed]);
    expect(runner.isRunning('boom'), isFalse);
  });

  testWidgets('a failed Future: one report and the given failure text', (
    tester,
  ) async {
    final body = await _pumpBody(tester);
    runner.bindBody(() => body);
    final reported = await _reports(() async {
      final value = await runner.run<int>(
        'late',
        (_) async => throw ArgumentError('async'),
        failure: EditorStrings.imageInsertFailed,
      );
      expect(value, isNull);
    });
    expect(reported, hasLength(1));
    expect(reported.single.exception, isA<ArgumentError>());
    expect(notices, [EditorStrings.imageInsertFailed]);
  });

  testWidgets('the screen closed before the callback ended: the result is '
      'dropped, no message (an error is still reported)', (tester) async {
    final body = await _pumpBody(tester);
    runner.bindBody(() => body);
    final hold = Completer<core.ImportedImage?>();
    final done = runner.run<core.ImportedImage?>('pick', (_) => hold.future);
    final failing = Completer<void>();
    final fails = runner.run<void>('fails', (_) => failing.future);

    await tester.pumpWidget(const SizedBox()); // the body goes away
    expect(body.mounted, isFalse);
    expect(runner.bodyContext, isNull);
    hold.complete(null);
    expect(await done, isNull);

    final reported = await _reports(() async {
      failing.completeError(StateError('after close'));
      await fails;
    });
    expect(reported, hasLength(1));
    expect(notices, isEmpty);

    // Nothing starts without a mounted body.
    var started = false;
    await runner.run<void>('again', (_) async => started = true);
    expect(started, isFalse);
  });

  testWidgets('a value finished after the screen closed is dropped too', (
    tester,
  ) async {
    final body = await _pumpBody(tester);
    runner.bindBody(() => body);
    final hold = Completer<int>();
    final done = runner.run<int>('v', (_) => hold.future);
    await tester.pumpWidget(const SizedBox());
    hold.complete(3);
    expect(await done, isNull);
  });

  testWidgets('no body bound, or disposed: ignored', (tester) async {
    var started = 0;
    expect(await runner.run<int>('x', (_) async => ++started), isNull);
    final body = await _pumpBody(tester);
    runner.bindBody(() => body);
    expect(await runner.run<int>('x', (_) async => ++started), 1);
    runner.dispose();
    expect(await runner.run<int>('x', (_) async => ++started), isNull);
    expect(started, 1);
  });

  test('withoutDuplicates keeps the first of an id and reports each '
      'duplicate id once', () async {
    final reported = await _reports(() async {
      final once = runner.withoutDuplicates([
        'a',
        'b',
        'a',
        'c',
        'b',
      ], (s) => s);
      expect(once, ['a', 'b', 'c']);
      // Built again (another frame): no new report.
      expect(runner.withoutDuplicates(['a', 'a'], (s) => s), ['a']);
    });
    expect(reported, hasLength(2));
  });

  test('visible: no isVisible → shown; its value; an exception → hidden and '
      'handed to onError', () {
    final context = EditorSelectionContext(
      noteId: 'n',
      pageId: 'p',
      pageSize: core.PageSize.a4Portrait,
      strokes: const [],
      objects: const [],
      boundsPt: Rect.zero,
      execute: (_) {},
      clearSelection: () {},
    );
    Future<void> noop(BuildContext c, EditorSelectionContext s) async {}
    final errors = <Object>[];
    void onError(Object e, StackTrace s) => errors.add(e);
    expect(
      ExtensionRunner.visible(
        EditorSelectionMenuItem(
          id: 'a',
          label: 'A',
          icon: Icons.star,
          onSelected: noop,
        ),
        context,
        onError: onError,
      ),
      isTrue,
    );
    expect(
      ExtensionRunner.visible(
        EditorSelectionMenuItem(
          id: 'b',
          label: 'B',
          icon: Icons.star,
          onSelected: noop,
          isVisible: (s) => s.strokes.isNotEmpty,
        ),
        context,
        onError: onError,
      ),
      isFalse,
    );
    expect(
      ExtensionRunner.visible(
        EditorSelectionMenuItem(
          id: 'c',
          label: 'C',
          icon: Icons.star,
          onSelected: noop,
          isVisible: (_) => throw StateError('isVisible'),
        ),
        context,
        onError: onError,
      ),
      isFalse,
    );
    expect(errors.single, isA<StateError>());
  });

  test('selectionContextFor: null without a selection', () async {
    final store = createFakeNoteStore();
    addTearDown(store.close);
    final note = await store.library.createNote(
      title: 'n',
      pages: [
        core.PageDraft(
          size: core.PageSize.a4Portrait,
          background: const core.BlankBackground(),
        ),
      ],
    );
    final session = await store.openSession(note.id);
    addTearDown(session.close);
    expect(
      selectionContextFor(
        session: session,
        selection: null,
        sel: null,
        execute: (_) {},
        clearSelection: () {},
      ),
      isNull,
    );
  });
}
