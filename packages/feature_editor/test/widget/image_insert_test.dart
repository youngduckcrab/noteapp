// m5-7/04-editor 8.2 E2-12, 6.12.1–6.12.2, 6.8: the image flows through the
// whole editor (fake CORE, R2-B3 INK, FakeImageImporter).
// - Insert menu '이미지 › 사진 보관함' → pick starts inside the press, while the
//   menu is still open, with EditorBody's context (review S-6), then the menu
//   closes → ONE AddObjects([ImageObject]) — the asset id and pixel size of
//   the import, placed by ObjectPlacement.forImage — and the image selected
//   with origin insert (the tool stays).
// - A pen drag on the image body right after the insert moves it: ONE
//   TransformElements, no stroke (review M-4).
// - null → nothing; a synchronous or a later exception → one report +
//   '이미지를 넣지 못했어요'; a press while the picker is open is ignored.
// - No slot or no sources → no [+], no sheet row, no '이미지 붙여넣기'.
// - The context menu '이미지 붙여넣기' (source clipboard) is centred on the
//   press point, origin paste; ⌘V pastes an image only when the app
//   clipboard is empty.
import 'dart:async';

import 'package:feature_editor/src/objects/object_placement.dart';
import 'package:feature_editor/src/scope/editor_scope.dart';
import 'package:feature_editor/src/state/popup.dart';
import 'package:feature_editor/src/tools/selection.dart';
import 'package:feature_editor/src/tools/tool_controller.dart';
import 'package:feature_editor/src/tools/tool_state.dart';
import 'package:feature_editor/src/ui/editor_body.dart';
import 'package:feature_editor/src/ui/editor_strings.dart';
import 'package:feature_editor/src/ui/overlays/context_menu.dart';
import 'package:feature_editor/src/ui/pages/add_page_sheet.dart';
import 'package:feature_editor/src/ui/toolbar/insert_menu.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart';

import '../helpers/fake_image_importer.dart';
import '../helpers/pump_editor.dart';
import '../helpers/test_data.dart';

const _allSources = {
  core.ImageImportSource.photos,
  core.ImageImportSource.camera,
  core.ImageImportSource.files,
  core.ImageImportSource.clipboard,
};

Future<EditorTestHandles> _pump(
  WidgetTester tester, {
  Set<core.ImageImportSource>? sources,
  bool slot = true,
}) => pumpEditor(
  tester,
  imageImporter: slot
      ? (s) => sources == null
            ? FakeImageImporter(store: s)
            : FakeImageImporter(store: s, sources: sources)
      : null,
);

List<String> _edits(EditorTestHandles h) => [
  for (final c in h.recorder!.calls)
    if (c.startsWith('execute')) c,
];

EditorSelection? _selection(EditorTestHandles h) =>
    h.container.read(editorSelectionProvider);

core.PageContent _page(EditorTestHandles h, [int index = 0]) =>
    h.session.pageIfLoaded(h.pageId(index))!;

List<core.ImageObject> _images(EditorTestHandles h, [int index = 0]) =>
    _page(h, index).objects.whereType<core.ImageObject>().toList();

Rect _rectOf(core.PageRect r) =>
    Rect.fromLTRB(r.left, r.top, r.right, r.bottom);

/// onPressed of the menu row under [finder].
VoidCallback? _onPressed(WidgetTester tester, Finder finder) => tester
    .widget<TextButton>(
      find.descendant(
        of: finder,
        matching: find.byWidgetPredicate((w) => w is TextButton),
      ),
    )
    .onPressed;

bool _menuOpen(WidgetTester tester) =>
    tester.state<InsertMenuState>(find.byType(InsertMenu)).isOpen;

/// [+] → '이미지' (the submenu).
Future<void> _openImageMenu(WidgetTester tester) async {
  await tester.tap(find.byKey(InsertMenu.buttonKey));
  await tester.pump();
  await tester.tap(find.byKey(InsertMenu.imageKey));
  await tester.pump();
}

/// A few frames: the fake importer's asset put and the async command.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
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

/// A secondary click at [at] (page 0 pt) → the context menu.
Future<void> _contextMenuAt(
  WidgetTester tester,
  EditorTestHandles h,
  Offset at,
) async {
  await h.driver.down(
    7,
    h.toGlobal(0, at),
    kind: PointerDeviceKind.mouse,
    buttons: kSecondaryMouseButton,
  );
  await h.driver.up(7);
  await tester.pump();
}

Future<void> _ctrlV(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
}

void main() {
  testWidgets('사진 보관함 → pick inside the press (menu open, body context), '
      'then the menu closes → one AddObjects([ImageObject]): asset, px, '
      'placement; selected with origin insert, the tool kept', (tester) async {
    final h = await _pump(tester);
    final importer = h.imageImporter!;
    await _openImageMenu(tester);
    // The fake's default sources, in ImageImportSource order.
    expect(
      find.byKey(InsertMenu.imageSourceKey(core.ImageImportSource.photos)),
      findsOneWidget,
    );
    expect(
      find.byKey(InsertMenu.imageSourceKey(core.ImageImportSource.files)),
      findsOneWidget,
    );
    expect(
      find.byKey(InsertMenu.imageSourceKey(core.ImageImportSource.camera)),
      findsNothing,
    );
    expect(
      find.byKey(InsertMenu.imageSourceKey(core.ImageImportSource.clipboard)),
      findsNothing,
    );
    expect(
      tester
          .getTopLeft(
            find.byKey(
              InsertMenu.imageSourceKey(core.ImageImportSource.photos),
            ),
          )
          .dy,
      lessThan(
        tester
            .getTopLeft(
              find.byKey(
                InsertMenu.imageSourceKey(core.ImageImportSource.files),
              ),
            )
            .dy,
      ),
    );

    bool? openAtPick;
    importer.onPick = (_) => openAtPick = _menuOpen(tester);
    final visible = ObjectPlacement.visibleRectPt(h.viewport, 0);
    await tester.tap(
      find.byKey(InsertMenu.imageSourceKey(core.ImageImportSource.photos)),
    );
    // pick ran inside the tap, before the menu closed.
    expect(importer.calls, hasLength(1));
    expect(openAtPick, isTrue);
    expect(_menuOpen(tester), isFalse);
    final call = importer.calls.single;
    expect(call.source, core.ImageImportSource.photos);
    expect(call.context, tester.element(find.byType(EditorBody)));
    expect(call.contextMounted, isTrue);
    await _settle(tester);
    expect(call.context.mounted, isTrue); // the body, not the menu

    expect(_edits(h), ['executeAsync:add-objects']);
    expect(h.session.history.undoDepth, 1);
    final image = _images(h).single;
    expect(image.assetId, importer.putAssetIds.single);
    expect(image.pixelWidth, 400);
    expect(image.pixelHeight, 300);
    expect(image.frame.rotation, 0);
    final expected = ObjectPlacement.forImage(
      pageSize: h.session.pages.first.size,
      visibleRectPt: visible,
      pixelWidth: 400,
      pixelHeight: 300,
    );
    final rect = _rectOf(image.frame.rect);
    expect(rect.left, closeTo(expected.left, 0.01));
    expect(rect.top, closeTo(expected.top, 0.01));
    expect(rect.width, closeTo(expected.width, 0.01));
    expect(rect.height, closeTo(expected.height, 0.01));
    expect(rect.width / rect.height, closeTo(400 / 300, 0.001));
    expect(_selection(h)?.elementIds, {image.id});
    expect(_selection(h)?.origin, SelectionOrigin.insert);
    expect(h.container.read(editorToolProvider).activeTool, EditorTool.pen);
    expect(find.text(EditorStrings.imageInsertFailed), findsNothing);
  });

  testWidgets('a pen drag on the image body right after the insert → one '
      'TransformElements (move), no stroke', (tester) async {
    final h = await _pump(tester);
    await _openImageMenu(tester);
    await tester.tap(
      find.byKey(InsertMenu.imageSourceKey(core.ImageImportSource.photos)),
    );
    await _settle(tester);
    final image = _images(h).single;
    final before = _rectOf(image.frame.rect);
    expect(h.container.read(editorToolProvider).activeTool, EditorTool.pen);
    h.recorder!.clearCalls();

    final frame = selectionRectOnScreen(
      h.viewport,
      h.mountedPages,
      _selection(h),
    )!.shift(h.viewportOrigin);
    const by = Offset(60, 40);
    final from = frame.center;
    await h.driver.stylusStroke([
      from,
      from + by * 0.25,
      from + by * 0.5,
      from + by * 0.75,
      from + by,
    ]);
    await tester.pump();
    expect(_edits(h), ['execute:transform']);
    expect(_page(h).strokes, isEmpty);
    final moved = _rectOf(_images(h).single.frame.rect);
    final delta = by / h.viewport.camera.scale;
    expect(moved.left, closeTo(before.left + delta.dx, 0.05));
    expect(moved.top, closeTo(before.top + delta.dy, 0.05));
    expect(moved.width, closeTo(before.width, 0.05));
    expect(_selection(h)?.elementIds, {image.id});
  });

  testWidgets('pick → null: no command, no notice', (tester) async {
    final h = await _pump(tester);
    final importer = h.imageImporter!..cancelNext = true;
    await _openImageMenu(tester);
    final reported = await _reports(() async {
      await tester.tap(
        find.byKey(InsertMenu.imageSourceKey(core.ImageImportSource.files)),
      );
      await _settle(tester);
    });
    expect(importer.calls.single.source, core.ImageImportSource.files);
    expect(_edits(h), isEmpty);
    expect(reported, isEmpty);
    expect(find.byType(SnackBar), findsNothing);
    expect(_menuOpen(tester), isFalse);
    expect(_selection(h), isNull);
  });

  testWidgets('pick throws (synchronously, then later) → one report each + '
      '이미지를 넣지 못했어요, no command', (tester) async {
    final h = await _pump(tester);
    final importer = h.imageImporter!
      ..throwNext = StateError('sync boom')
      ..throwSynchronously = true;
    await _openImageMenu(tester);
    var reported = await _reports(() async {
      await tester.tap(
        find.byKey(InsertMenu.imageSourceKey(core.ImageImportSource.photos)),
      );
      await _settle(tester);
    });
    expect(importer.calls, hasLength(1));
    expect(reported, hasLength(1));
    expect(reported.single.exception, isA<StateError>());
    expect(reported.single.library, 'feature_editor');
    expect(_menuOpen(tester), isFalse); // closed after the throw too
    expect(find.text(EditorStrings.imageInsertFailed), findsOneWidget);
    expect(_edits(h), isEmpty);
    await tester.pump(const Duration(seconds: 5)); // snack bar timer
    await tester.pump(const Duration(seconds: 1));

    importer.throwNext = StateError('later boom');
    await _openImageMenu(tester);
    reported = await _reports(() async {
      await tester.tap(
        find.byKey(InsertMenu.imageSourceKey(core.ImageImportSource.photos)),
      );
      await _settle(tester);
    });
    expect(importer.calls, hasLength(2));
    expect(reported, hasLength(1));
    expect(reported.single.exception, isA<StateError>());
    expect(find.text(EditorStrings.imageInsertFailed), findsOneWidget);
    expect(_edits(h), isEmpty);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('a press while the picker is open is ignored (items disabled), '
      'one image when it returns', (tester) async {
    final h = await _pump(tester);
    final hold = Completer<void>();
    final importer = h.imageImporter!..holdNext = hold;
    await _openImageMenu(tester);
    await tester.tap(
      find.byKey(InsertMenu.imageSourceKey(core.ImageImportSource.photos)),
    );
    await tester.pump();
    expect(importer.calls, hasLength(1));

    await _openImageMenu(tester);
    final item = find.byKey(
      InsertMenu.imageSourceKey(core.ImageImportSource.files),
    );
    expect(_onPressed(tester, item), isNull);
    await tester.tap(item, warnIfMissed: false);
    await tester.pump();
    expect(importer.calls, hasLength(1));
    // The add-page sheet's image sources are disabled too.
    h.container.read(editorPopupProvider.notifier).close();
    await tester.tap(find.byKey(InsertMenu.buttonKey)); // closes the menu
    await tester.pump();
    h.container.read(editorPopupProvider.notifier).open(const AddPagePopup());
    await tester.pump();
    await tester.pump();
    final chip = find.byKey(
      AddPageSheet.imageSourceKey(core.ImageImportSource.photos),
    );
    await tester.ensureVisible(chip);
    expect(tester.widget<ActionChip>(chip).onPressed, isNull);
    h.container.read(editorPopupProvider.notifier).close();
    await tester.pump();

    hold.complete();
    await _settle(tester);
    expect(_edits(h), ['executeAsync:add-objects']);
    expect(_images(h), hasLength(1));
    // Enabled again.
    await _openImageMenu(tester);
    expect(_onPressed(tester, item), isNotNull);
  });

  for (final (name, slot, sources) in [
    ('no image slot', false, null),
    ('a slot without sources', true, <core.ImageImportSource>{}),
  ]) {
    testWidgets('$name → no [+], no add-page image row, no 이미지 붙여넣기', (
      tester,
    ) async {
      final h = await _pump(tester, slot: slot, sources: sources);
      expect(find.byKey(InsertMenu.buttonKey), findsNothing);
      h.container.read(editorPopupProvider.notifier).open(const AddPagePopup());
      await tester.pump();
      await tester.pump();
      expect(find.byKey(AddPageSheet.panelKey), findsOneWidget);
      for (final s in core.ImageImportSource.values) {
        expect(find.byKey(AddPageSheet.imageSourceKey(s)), findsNothing);
      }
      expect(find.text(EditorStrings.image), findsNothing);
      h.container.read(editorPopupProvider.notifier).close();
      await tester.pump();
      await _contextMenuAt(tester, h, const Offset(300, 400));
      expect(find.byKey(EditorContextMenu.lassoKey), findsOneWidget);
      expect(find.byKey(EditorContextMenu.pasteImageKey), findsNothing);
    });
  }

  testWidgets('context menu 이미지 붙여넣기 → pick(clipboard) inside the tap, '
      'menu still open; the image centred on the press point, origin paste', (
    tester,
  ) async {
    final h = await _pump(tester, sources: _allSources);
    final importer = h.imageImporter!..pixelWidth = 200;
    importer.pixelHeight = 100;
    const at = Offset(300, 400);
    await _contextMenuAt(tester, h, at);
    expect(find.byKey(EditorContextMenu.pasteImageKey), findsOneWidget);
    final host = h.container.read(editorInteractionHostProvider);
    bool? openAtPick;
    importer.onPick = (_) => openAtPick = host.contextMenu.value != null;
    await tester.tap(find.byKey(EditorContextMenu.pasteImageKey));
    expect(importer.calls.single.source, core.ImageImportSource.clipboard);
    expect(
      importer.calls.single.context,
      tester.element(find.byType(EditorBody)),
    );
    expect(openAtPick, isTrue);
    expect(host.contextMenu.value, isNull);
    await _settle(tester);
    expect(_edits(h), ['executeAsync:add-objects']);
    final rect = _rectOf(_images(h).single.frame.rect);
    expect(rect.center.dx, closeTo(at.dx, 0.5));
    expect(rect.center.dy, closeTo(at.dy, 0.5));
    expect(rect.width, closeTo(100, 0.01)); // 200 px × 0.5
    expect(_selection(h)?.origin, SelectionOrigin.paste);
    expect(h.container.read(editorToolProvider).activeTool, EditorTool.pen);
  });

  testWidgets('a read-only note: no 이미지 붙여넣기 in the context menu, [+] '
      'disabled', (tester) async {
    final h = await _pump(tester, sources: _allSources);
    await h.store.library.trashItems([core.NoteRef(h.noteId)]);
    await tester.pump();
    expect(h.container.read(editorReadOnlyProvider), isTrue);
    expect(
      tester.widget<IconButton>(find.byKey(InsertMenu.buttonKey)).onPressed,
      isNull,
    );
    await _contextMenuAt(tester, h, const Offset(300, 400));
    expect(find.byKey(EditorContextMenu.pasteImageKey), findsNothing);
  });

  testWidgets('⌘V: an empty app clipboard + the clipboard source → an image '
      'at the visible centre (origin paste); with app clipboard content → '
      'the app paste, no pick', (tester) async {
    final h = await pumpEditor(
      tester,
      strokesByPageIndex: {
        0: [strokeA],
      },
      imageImporter: (s) => FakeImageImporter(store: s, sources: _allSources),
    );
    final importer = h.imageImporter!;
    final visible = ObjectPlacement.visibleRectPt(h.viewport, 0);
    await _ctrlV(tester);
    expect(importer.calls.single.source, core.ImageImportSource.clipboard);
    await _settle(tester);
    expect(_edits(h), ['executeAsync:add-objects']);
    final rect = _rectOf(_images(h).single.frame.rect);
    expect(rect.center.dx, closeTo(visible.center.dx, 0.5));
    expect(rect.center.dy, closeTo(visible.center.dy, 0.5));
    expect(_selection(h)?.origin, SelectionOrigin.paste);

    // Copy the stroke: ⌘V is the app paste now.
    h.container.read(editorSelectionProvider.notifier).select(h.pageId(0), {
      strokeA.id,
    });
    await tester.pump();
    h.container.read(editorCommandsProvider).copySelection();
    h.recorder!.clearCalls();
    await _ctrlV(tester);
    await _settle(tester);
    expect(importer.calls, hasLength(1));
    expect(_edits(h), ['executeAsync:add-strokes']);
  });

  testWidgets('⌘V without the clipboard source and an empty app clipboard → '
      'nothing', (tester) async {
    final h = await _pump(tester); // photos, files
    await _ctrlV(tester);
    await _settle(tester);
    expect(h.imageImporter!.calls, isEmpty);
    expect(_edits(h), isEmpty);
  });

  testWidgets('the page object limit → the notice, no command', (tester) async {
    final h = await pumpEditor(
      tester,
      objectsByPageIndex: {
        0: [
          for (var i = 0; i < core.PageObjectLimits.maxObjectsPerPage; i++)
            PageObjectFixtures.shape(
              pageId: 'x',
              id: 'fill-$i',
              rect: core.PageRect(
                20 + (i % 40) * 13.0,
                20 + (i ~/ 40) * 15.0,
                28 + (i % 40) * 13.0,
                28 + (i ~/ 40) * 15.0,
              ),
              createdAt: 100 + i,
            ),
        ],
      },
      imageImporter: (s) => FakeImageImporter(store: s),
    );
    await _openImageMenu(tester);
    await tester.tap(
      find.byKey(InsertMenu.imageSourceKey(core.ImageImportSource.photos)),
    );
    await _settle(tester);
    expect(h.imageImporter!.calls, hasLength(1));
    expect(_edits(h), isEmpty);
    expect(
      find.text(
        EditorStrings.objectLimitReached(
          core.PageObjectLimits.maxObjectsPerPage,
        ),
      ),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 5));
  });
}
