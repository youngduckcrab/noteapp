// m5-7/04-editor 8.2 E2-12, 6.13.1–6.13.2, 4.3.1: the insert menu [+].
// - An insert item gets EditorInsertContext: the current page, visibleRectPt
//   = the visible part of that page (ObjectPlacement.visibleRectPt), its
//   onSelected starts inside the press (the menu still open, EditorBody's
//   context), then the menu closes; execute = one command; selectObject(id)
//   selects that object with origin insert (ignored for an id not on the
//   page).
// - The image submenu comes first, then the items in list order; duplicate
//   ids dropped (one report); a running item is disabled.
// - Neither image sources nor items → no [+]; a read-only note → disabled.
import 'dart:async';

import 'package:feature_editor/feature_editor.dart';
import 'package:feature_editor/src/objects/object_placement.dart';
import 'package:feature_editor/src/scope/editor_scope.dart';
import 'package:feature_editor/src/tools/selection.dart';
import 'package:feature_editor/src/ui/editor_body.dart';
import 'package:feature_editor/src/ui/toolbar/editor_toolbar.dart';
import 'package:feature_editor/src/ui/toolbar/insert_menu.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart';

import '../helpers/fake_extensions.dart';
import '../helpers/fake_image_importer.dart';
import '../helpers/pump_editor.dart';

Future<EditorTestHandles> _pump(
  WidgetTester tester,
  List<EditorInsertMenuItem> items, {
  bool image = false,
}) => pumpEditor(
  tester,
  extensions: EditorExtensions(insertMenuItems: items),
  imageImporter: image ? (s) => FakeImageImporter(store: s) : null,
);

List<String> _edits(EditorTestHandles h) => [
  for (final c in h.recorder!.calls)
    if (c.startsWith('execute')) c,
];

EditorSelection? _selection(EditorTestHandles h) =>
    h.container.read(editorSelectionProvider);

Finder _ext(String id) => find.byKey(InsertMenu.extensionKey(id));

bool _menuOpen(WidgetTester tester) =>
    tester.state<InsertMenuState>(find.byType(InsertMenu)).isOpen;

VoidCallback? _onPressed(WidgetTester tester, Finder finder) => tester
    .widget<TextButton>(
      find.descendant(
        of: finder,
        matching: find.byWidgetPredicate((w) => w is TextButton),
      ),
    )
    .onPressed;

Future<void> _openMenu(WidgetTester tester) async {
  await tester.tap(find.byKey(InsertMenu.buttonKey));
  await tester.pump();
}

/// A math object centred in [visible] (page pt) — what a math pad inserts.
core.MathObject _mathIn(String pageId, Rect visible) {
  final c = visible.center;
  return PageObjectFixtures.math(
    pageId: pageId,
    id: 'math-1',
    rect: core.PageRect(c.dx - 60, c.dy - 20, c.dx + 60, c.dy + 20),
    createdAt: 9,
  );
}

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
  testWidgets('an insert item: context = the current page and its visible '
      'part; onSelected inside the press (menu open, body context), then the '
      'menu closes; execute → one command; selectObject → selected (insert)', (
    tester,
  ) async {
    final pad = RecordingInsertItem(
      id: 'recog.mathPad',
      label: '수식',
      command: (insert) => core.AddObjects(
        pageId: insert.pageId,
        objects: [_mathIn(insert.pageId, insert.visibleRectPt)],
      ),
      selectAfter: 'math-1',
    );
    final h = await _pump(tester, [pad.item]);
    // The current page is page 1.
    await h.viewport.jumpToPage(1, animate: false);
    await tester.pump(const Duration(milliseconds: 200));
    await h.settlePages();
    expect(h.viewport.currentPageIndex.value, 1);
    final visible = ObjectPlacement.visibleRectPt(h.viewport, 1);
    expect(visible.width, greaterThan(0));

    await _openMenu(tester);
    expect(find.byKey(InsertMenu.imageKey), findsNothing); // no image slot
    expect(_ext('recog.mathPad'), findsOneWidget);
    bool? openAtRun;
    pad.onRun = (_) => openAtRun = _menuOpen(tester);
    final hold = Completer<void>();
    pad.holdNext = hold;
    await tester.tap(_ext('recog.mathPad'));
    expect(pad.calls, hasLength(1));
    expect(openAtRun, isTrue);
    expect(_menuOpen(tester), isFalse);
    final call = pad.calls.single;
    expect(call.context, tester.element(find.byType(EditorBody)));
    expect(call.contextMounted, isTrue);
    final insert = call.menu;
    expect(insert.noteId, h.noteId);
    expect(insert.pageId, h.pageId(1));
    expect(insert.pageSize, h.session.pages[1].size);
    expect(insert.visibleRectPt, visible);
    await tester.pump();
    expect(call.context.mounted, isTrue);

    // Running → disabled; a second press does nothing.
    await _openMenu(tester);
    expect(_onPressed(tester, _ext('recog.mathPad')), isNull);
    await tester.tap(_ext('recog.mathPad'), warnIfMissed: false);
    expect(pad.calls, hasLength(1));
    await tester.tap(find.byKey(InsertMenu.buttonKey)); // close
    await tester.pump();

    hold.complete();
    await tester.pump();
    await tester.pump();
    expect(pad.executeErrors, isEmpty);
    expect(_edits(h), ['execute:add-objects']);
    expect(h.session.history.undoDepth, 1);
    final math = h.session.pageIfLoaded(h.pageId(1))!.objectById('math-1');
    expect(math, isA<core.MathObject>());
    expect(_selection(h)?.pageId, h.pageId(1));
    expect(_selection(h)?.elementIds, {'math-1'});
    expect(_selection(h)?.origin, SelectionOrigin.insert);

    await _openMenu(tester);
    expect(_onPressed(tester, _ext('recog.mathPad')), isNotNull);
  });

  testWidgets('selectObject of an id not on the page is ignored (the '
      'selection stays)', (tester) async {
    final item = RecordingInsertItem(id: 'test.ghost', selectAfter: 'nope');
    final h = await pumpEditor(
      tester,
      objectsByPageIndex: {
        0: [
          PageObjectFixtures.shape(
            pageId: 'x',
            id: 'shape-1',
            rect: const core.PageRect(300, 120, 420, 200),
            createdAt: 5,
          ),
        ],
      },
      extensions: EditorExtensions(insertMenuItems: [item.item]),
    );
    h.container.read(editorSelectionProvider.notifier).select(h.pageId(0), {
      'shape-1',
    }, origin: SelectionOrigin.lasso);
    await tester.pump();
    await _openMenu(tester);
    await tester.tap(_ext('test.ghost'));
    await tester.pump();
    await tester.pump();
    expect(item.calls, hasLength(1));
    expect(_edits(h), isEmpty);
    expect(_selection(h)?.elementIds, {'shape-1'});
    expect(_selection(h)?.origin, SelectionOrigin.lasso);
  });

  testWidgets('order: the image submenu first, then the items in list order; '
      'a duplicate id dropped with one report', (tester) async {
    final a = RecordingInsertItem(id: 'test.a', label: '가');
    final b = RecordingInsertItem(id: 'test.b', label: '나');
    final dup = RecordingInsertItem(id: 'test.a', label: '다');
    late EditorTestHandles h;
    final reported = await _reports(() async {
      h = await _pump(tester, [a.item, b.item, dup.item], image: true);
      await _openMenu(tester);
    });
    expect(reported, hasLength(1));
    expect(reported.single.exception, isA<ArgumentError>());
    expect(find.byKey(InsertMenu.imageKey), findsOneWidget);
    expect(_ext('test.a'), findsOneWidget);
    expect(find.text('다'), findsNothing);
    final imageTop = tester.getTopLeft(find.byKey(InsertMenu.imageKey)).dy;
    final aTop = tester.getTopLeft(_ext('test.a')).dy;
    final bTop = tester.getTopLeft(_ext('test.b')).dy;
    expect(imageTop, lessThan(aTop));
    expect(aTop, lessThan(bTop));
    // Every row is a 44 px target at least (contract 7.4.8).
    expect(tester.getSize(_ext('test.a')).height, greaterThanOrEqualTo(44));
    expect(
      tester.getSize(find.byKey(InsertMenu.imageKey)).height,
      greaterThanOrEqualTo(44),
    );
    await tester.tap(find.byKey(InsertMenu.imageKey));
    await tester.pump();
    expect(
      tester
          .getSize(
            find.byKey(
              InsertMenu.imageSourceKey(core.ImageImportSource.photos),
            ),
          )
          .height,
      greaterThanOrEqualTo(44),
    );
    expect(h.imageImporter!.calls, isEmpty);
  });

  testWidgets('no image slot and no items → no [+]', (tester) async {
    await _pump(tester, const []);
    expect(find.byKey(InsertMenu.buttonKey), findsNothing);
    expect(find.byType(InsertMenu), findsNothing);
    // The toolbar still shows its 1st-round buttons.
    expect(find.byKey(EditorToolbar.lassoKey), findsOneWidget);
  });

  testWidgets('image only → [+] with the image submenu, no extension rows', (
    tester,
  ) async {
    await _pump(tester, const [], image: true);
    await _openMenu(tester);
    expect(find.byKey(InsertMenu.imageKey), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('editor.ext.'),
      ),
      findsNothing,
    );
  });

  testWidgets('a read-only note → [+] disabled', (tester) async {
    final item = RecordingInsertItem();
    final h = await _pump(tester, [item.item]);
    expect(
      tester.widget<IconButton>(find.byKey(InsertMenu.buttonKey)).onPressed,
      isNotNull,
    );
    await h.store.library.trashItems([core.NoteRef(h.noteId)]);
    await tester.pump();
    expect(h.container.read(editorReadOnlyProvider), isTrue);
    expect(
      tester.widget<IconButton>(find.byKey(InsertMenu.buttonKey)).onPressed,
      isNull,
    );
    await tester.tap(find.byKey(InsertMenu.buttonKey), warnIfMissed: false);
    await tester.pump();
    expect(_ext(item.id), findsNothing);
    expect(item.calls, isEmpty);
  });
}
