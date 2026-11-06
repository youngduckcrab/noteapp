// m5-7/04-editor 8.2 E2-07c, 6.7.4, 4.3.1, E-7: the selection menu's
// extension items (EditorExtensions.selectionMenuItems) through the whole
// editor (fake CORE, R2-B3 INK, test items of fake_extensions.dart).
// - The context: strokes and objects of the selection in z order, boundsPt
//   = INK's bounds; execute runs ONE command (one undo step) and rethrows on
//   a read-only note.
// - onSelected starts inside the button's onPressed — the bar still shown —
//   with EditorBody's context (mounted after the menu closed); then the bar
//   closes until the item ends. A synchronous exception still closes the
//   menu.
// - isVisible false → hidden; an isVisible exception → hidden + one report,
//   no snack bar; an onSelected exception → one report + '실행하지 못했어요'.
// - No items → nothing on the bar; at most 2 on the bar, the rest in '⋯';
//   a narrow page area moves them to '⋯' first; duplicate ids dropped.
import 'dart:async';

import 'package:feature_editor/feature_editor.dart';
import 'package:feature_editor/src/scope/editor_scope.dart';
import 'package:feature_editor/src/tools/selection.dart';
import 'package:feature_editor/src/tools/tool_state.dart';
import 'package:feature_editor/src/ui/editor_body.dart';
import 'package:feature_editor/src/ui/editor_strings.dart';
import 'package:feature_editor/src/ui/overlays/selection_menu.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart';

import '../helpers/fake_extensions.dart';
import '../helpers/pump_editor.dart';
import '../helpers/test_data.dart';

final core.ShapeObject _shape = PageObjectFixtures.shape(
  pageId: 'x',
  id: 'shape-1',
  rect: const core.PageRect(300, 120, 420, 200),
  createdAt: 5,
);

final core.TextBoxObject _text = PageObjectFixtures.textBox(
  pageId: 'x',
  id: 'text-1',
  rect: const core.PageRect(300, 300, 480, 340),
  createdAt: 6,
);

Future<EditorTestHandles> _pump(
  WidgetTester tester,
  List<RecordingSelectionItem> items, {
  List<EditorSelectionMenuItem>? raw,
  Size logicalSize = const Size(1032, 1376),
}) async {
  final h = await pumpEditor(
    tester,
    logicalSize: logicalSize,
    strokesByPageIndex: {
      0: [strokeA, strokeB],
    },
    objectsByPageIndex: {
      0: [_shape, _text],
    },
    extensions: EditorExtensions(
      selectionMenuItems: raw ?? [for (final i in items) i.item],
    ),
  );
  h.container.read(editorCommandsProvider).selectTool(EditorTool.lasso);
  await tester.pump();
  return h;
}

Future<void> _select(
  WidgetTester tester,
  EditorTestHandles h,
  Set<String> ids,
) async {
  h.container
      .read(editorSelectionProvider.notifier)
      .select(h.pageId(0), ids, origin: SelectionOrigin.lasso);
  await tester.pump();
}

Finder _ext(String id) => find.byKey(SelectionMenu.extensionKey(id));

/// Every extension item widget on screen (bar and '⋯').
Finder get _anyExt => find.byWidgetPredicate(
  (w) =>
      w.key is ValueKey<String> &&
      (w.key! as ValueKey<String>).value.startsWith('editor.ext.'),
);

List<String> _edits(EditorTestHandles h) => [
  for (final c in h.recorder!.calls)
    if (c.startsWith('execute')) c,
];

/// [body] with FlutterError reports collected.
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
  testWidgets('the context: strokes and objects of the selection in z '
      'order, boundsPt = INK bounds; onSelected starts inside onPressed with '
      'the bar still up and EditorBody\'s context; the bar closes until the '
      'item ends', (tester) async {
    final item = RecordingSelectionItem(id: 'test.ctx', label: '시험');
    final h = await _pump(tester, [item]);
    await _select(tester, h, {_text.id, strokeB.id, _shape.id, strokeA.id});
    final bounds = h.controllerOf(0).selection!.bounds;
    expect(_ext('test.ctx'), findsOneWidget);

    var barUpAtCall = false;
    final hold = item.holdNext = Completer<void>();
    item.onRun = (_) {
      barUpAtCall = find.byKey(SelectionMenu.copyKey).evaluate().isNotEmpty;
    };
    await tester.tap(_ext('test.ctx'));
    expect(item.calls, hasLength(1)); // started inside the tap
    await tester.pump();

    final call = item.calls.single;
    expect(barUpAtCall, isTrue);
    expect(call.contextMounted, isTrue);
    expect(call.context, same(tester.element(find.byType(EditorBody))));
    final ctx = call.menu;
    expect(ctx.noteId, h.noteId);
    expect(ctx.pageId, h.pageId(0));
    expect(ctx.pageSize, h.session.pages.first.size);
    expect([for (final s in ctx.strokes) s.id], [strokeA.id, strokeB.id]);
    expect([for (final o in ctx.objects) o.id], [_shape.id, _text.id]);
    expect(ctx.boundsPt, bounds);

    // The bar is closed while the item runs; the context stays mounted and
    // the selection stays.
    expect(find.byKey(SelectionMenu.copyKey), findsNothing);
    expect(call.context.mounted, isTrue);
    expect(h.container.read(editorSelectionProvider), isNotNull);

    // The value copy made at the press does not follow later changes.
    h.container.read(editorSelectionProvider.notifier).clear();
    await tester.pump();
    expect(ctx.strokes, hasLength(2));
    hold.complete();
    await tester.pump();
  });

  testWidgets('the bar comes back when the item ends (the selection kept)', (
    tester,
  ) async {
    final item = RecordingSelectionItem(id: 'test.hold');
    final h = await _pump(tester, [item]);
    await _select(tester, h, {strokeA.id});
    final hold = item.holdNext = Completer<void>();
    await tester.tap(_ext('test.hold'));
    await tester.pump();
    expect(find.byKey(SelectionMenu.copyKey), findsNothing);
    hold.complete();
    await tester.pump();
    await tester.pump();
    expect(find.byKey(SelectionMenu.copyKey), findsOneWidget);
    expect(_ext('test.hold'), findsOneWidget);
  });

  testWidgets('execute once = one undo step; clearSelection ends the '
      'selection', (tester) async {
    final item = RecordingSelectionItem(
      id: 'test.exec',
      command: (s) => core.RemoveStrokes(
        pageId: s.pageId,
        strokeIds: [for (final st in s.strokes) st.id],
      ),
    );
    final h = await _pump(tester, [item]);
    await _select(tester, h, {strokeA.id, strokeB.id});
    await tester.tap(_ext('test.exec'));
    await tester.pump();
    await tester.pump();

    expect(_edits(h), ['execute:remove-strokes']);
    expect(h.session.history.undoDepth, 1);
    expect(h.session.pageIfLoaded(h.pageId(0))!.strokes, isEmpty);
    expect(item.executeErrors, isEmpty);
    expect(h.container.read(editorSelectionProvider), isNull); // revalidated

    // clearSelection of a context.
    await _select(tester, h, {_shape.id});
    h.container
        .read(editorCommandsProvider)
        .selectionContext()!
        .clearSelection();
    await tester.pump();
    expect(h.container.read(editorSelectionProvider), isNull);
  });

  testWidgets('a read-only note: the item stays enabled; execute rethrows '
      'ReadOnlyNoteException (read-only refreshed); the failed item → one '
      'report + 실행하지 못했어요', (tester) async {
    final item = RecordingSelectionItem(
      id: 'test.ro',
      command: (s) => core.RemoveStrokes(
        pageId: s.pageId,
        strokeIds: [for (final st in s.strokes) st.id],
      ),
    );
    final h = await _pump(tester, [item]);
    await h.store.library.trashItems([core.NoteRef(h.noteId)]);
    await tester.pump();
    await _select(tester, h, {strokeA.id});
    final button = find.descendant(
      of: _ext('test.ro'),
      matching: find.bySubtype<ButtonStyleButton>(),
      matchRoot: true,
    );
    expect(tester.widget<ButtonStyleButton>(button).enabled, isTrue);

    final reported = await _reports(() async {
      await tester.tap(_ext('test.ro'));
      await tester.pump();
      await tester.pump();
    });
    expect(item.executeErrors.single, isA<core.ReadOnlyNoteException>());
    expect(h.container.read(editorReadOnlyProvider), isTrue);
    expect(h.session.history.undoDepth, 0);
    expect(reported, hasLength(1));
    expect(reported.single.library, 'feature_editor');
    expect(
      reported.single.context.toString(),
      contains('while running test.ro'),
    );
    expect(find.text(EditorStrings.commandFailed), findsOneWidget);
    await tester.pump(const Duration(seconds: 5)); // snackbar timer
  });

  testWidgets('3 items: 2 on the bar (list order), the third in ⋯ before '
      '선택 해제; a synchronous exception there still closes ⋯ (one report, '
      'the snack bar)', (tester) async {
    final a = RecordingSelectionItem(id: 'test.a', label: '가');
    final b = RecordingSelectionItem(id: 'test.b', label: '나');
    final c = RecordingSelectionItem(id: 'test.c', label: '다');
    final h = await _pump(tester, [a, b, c]);
    await _select(tester, h, {strokeA.id});

    expect(_ext('test.a'), findsOneWidget);
    expect(_ext('test.b'), findsOneWidget);
    expect(_ext('test.c'), findsNothing);
    expect(
      tester.getTopLeft(_ext('test.a')).dx,
      lessThan(tester.getTopLeft(_ext('test.b')).dx),
    );
    await tester.tap(find.byKey(SelectionMenu.moreKey));
    await tester.pump();
    expect(_ext('test.c'), findsOneWidget);
    expect(
      tester.getTopLeft(_ext('test.c')).dy,
      lessThan(tester.getTopLeft(find.byKey(SelectionMenu.clearKey)).dy),
    );

    var menuOpenAtCall = false;
    c
      ..throwSync = StateError('sync boom')
      ..onRun = (_) {
        menuOpenAtCall = find
            .byKey(SelectionMenu.clearKey)
            .evaluate()
            .isNotEmpty;
      };
    final reported = await _reports(() async {
      await tester.tap(_ext('test.c'));
      await tester.pump();
      await tester.pump();
    });
    expect(c.calls, hasLength(1));
    expect(menuOpenAtCall, isTrue);
    expect(find.byKey(SelectionMenu.clearKey), findsNothing); // ⋯ closed
    expect(_ext('test.c'), findsNothing);
    expect(reported, hasLength(1));
    expect(reported.single.exception, isA<StateError>());
    expect(find.text(EditorStrings.commandFailed), findsOneWidget);
    expect(h.container.read(editorSelectionProvider), isNotNull);
    await tester.pump(const Duration(seconds: 5)); // snackbar timer
  });

  testWidgets('isVisible false → hidden; isVisible throws → hidden, one '
      'report for this menu opening, no snack bar', (tester) async {
    final hidden = RecordingSelectionItem(
      id: 'test.hidden',
      isVisible: (s) => s.objects.isNotEmpty,
    );
    final broken = RecordingSelectionItem(
      id: 'test.broken',
      isVisible: (_) => throw StateError('isVisible boom'),
    );
    final shown = RecordingSelectionItem(id: 'test.shown');
    final h = await _pump(tester, [hidden, broken, shown]);
    final reported = await _reports(() async {
      await _select(tester, h, {strokeA.id}); // strokes only
      // Rebuilds of the same menu (a CORE change of the page): no new
      // report.
      final before = hidden.visibleCalls;
      h.session.execute(
        core.AddStrokes(
          pageId: h.pageId(0),
          strokes: [
            lineStroke(
              id: 'extra',
              pageId: h.pageId(0),
              x0: 500,
              y0: 800,
              x1: 560,
              y1: 800,
              createdAt: 9,
            ),
          ],
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(hidden.visibleCalls, greaterThan(before));
    });
    expect(_ext('test.hidden'), findsNothing);
    expect(_ext('test.broken'), findsNothing);
    expect(_ext('test.shown'), findsOneWidget);
    expect(hidden.visibleCalls, greaterThan(0));
    expect(reported, hasLength(1));
    expect(reported.single.exception, isA<StateError>());
    expect(reported.single.library, 'feature_editor');
    expect(find.byType(SnackBar), findsNothing);

    // Another selection (a new opening): isVisible true for objects.
    final again = await _reports(() async {
      await _select(tester, h, {strokeA.id, _shape.id});
    });
    expect(_ext('test.hidden'), findsOneWidget);
    expect(again, hasLength(1)); // the broken one, once for this opening
  });

  testWidgets('onSelected fails later → one report + 실행하지 못했어요', (
    tester,
  ) async {
    final item = RecordingSelectionItem(id: 'test.async')
      ..throwAsync = ArgumentError('async boom');
    final h = await _pump(tester, [item]);
    await _select(tester, h, {strokeA.id});
    final reported = await _reports(() async {
      await tester.tap(_ext('test.async'));
      await tester.pump();
      await tester.pump();
    });
    expect(reported, hasLength(1));
    expect(reported.single.exception, isA<ArgumentError>());
    expect(find.text(EditorStrings.commandFailed), findsOneWidget);
    expect(h.session.history.undoDepth, 0);
    await tester.pump(const Duration(seconds: 5)); // snackbar timer
  });

  testWidgets('no items → nothing on the bar or in ⋯', (tester) async {
    final h = await _pump(tester, const []);
    await _select(tester, h, {strokeA.id});
    expect(find.byKey(SelectionMenu.copyKey), findsOneWidget);
    expect(_anyExt, findsNothing);
    await tester.tap(find.byKey(SelectionMenu.moreKey));
    await tester.pump();
    expect(_anyExt, findsNothing);
  });

  testWidgets('a narrow page area moves the items to ⋯ first (no overflow); '
      'a duplicate id is dropped and reported once', (tester) async {
    const long = '아주 긴 이름의 확장 항목 하나 둘 셋';
    final a = RecordingSelectionItem(id: 'test.long1', label: '$long 1');
    final b = RecordingSelectionItem(id: 'test.long2', label: '$long 2');
    final dup = RecordingSelectionItem(id: 'test.long1', label: '겹친 항목');
    late EditorTestHandles h;
    final reported = await _reports(() async {
      h = await _pump(
        tester,
        const [],
        raw: [a.item, b.item, dup.item],
        logicalSize: const Size(690, 900),
      );
      await _select(tester, h, {strokeA.id});
    });
    expect(tester.takeException(), isNull);
    expect(reported, hasLength(1)); // the duplicate id
    expect(reported.single.exception, isA<ArgumentError>());
    // The bar: the four built-in buttons and ⋯ at most — no room for both.
    final onBar = [
      for (final id in ['test.long1', 'test.long2'])
        if (_ext(id).evaluate().isNotEmpty) id,
    ];
    expect(onBar.length, lessThan(2));
    final bar = tester.getRect(find.byType(SelectionMenu));
    expect(bar.width, lessThanOrEqualTo(690));
    await tester.tap(find.byKey(SelectionMenu.moreKey));
    await tester.pump();
    for (final id in ['test.long1', 'test.long2']) {
      expect(_ext(id), findsOneWidget, reason: id);
    }
    expect(find.text('겹친 항목'), findsNothing);
  });
}
