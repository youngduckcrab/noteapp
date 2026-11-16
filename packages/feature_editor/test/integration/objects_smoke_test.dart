// E2-21 (m5-7/04-editor 8.3, contract 7.7.1 step 6): the editor's page
// objects on the real CORE (openTestNoteStore — DB v2, drift on an
// in-memory SQLite database) and the real INK, driven through the whole
// screen. P-A only: inkShapeFitterProvider is not overridden, so the default
// NoShapeFitter keeps shapeAssistFor `off` and the pen step gives the same
// result with or without INK T39 / E2-15 (the auto-shape step is E2-21b,
// shape_assist_smoke_test.dart).
//
//   open the note (one stroke + one ellipse already on page 0) → a pen
//   stroke → the text tool: a box '회의록 abc' → the shape tool: a rectangle
//   → the insert menu: an image (FakeImageImporter puts a PNG asset into the
//   real AssetStore) → the lasso around everything → ⋯ 90° 돌리기 → 색 →
//   잘라내기 → the context menu 붙여넣기 → (contract v1.5 C15-04 order) undo
//   to the end of the chain = the note as it was opened → redo to the end =
//   the state after the paste → leave → open again: everything kept
//   (content.objects kinds and count), and the reopened session's undoDepth
//   is 0 (noteSessionProvider is autoDispose — the same assertion as the
//   round-1 real_core_ink_smoke_test).
//
// Skipped by default (dart_test.yaml `integration` skip); runs with
// `ws test --run-skipped -t integration --package feature_editor`. The store
// is opened and closed inside tester.runAsync so its real timers stay out of
// the fake-async zone.
@Tags(['integration'])
@TestOn('vm')
library;

import 'dart:async';

import 'package:feature_editor/feature_editor.dart';
import 'package:feature_editor/src/state/color_palette.dart';
import 'package:feature_editor/src/text/text_box_editor.dart';
import 'package:feature_editor/src/text/text_edit_session.dart';
import 'package:feature_editor/src/tools/selection.dart';
import 'package:feature_editor/src/ui/color/recolor_panel.dart';
import 'package:feature_editor/src/ui/overlays/context_menu.dart';
import 'package:feature_editor/src/ui/overlays/selection_menu.dart';
import 'package:feature_editor/src/ui/toolbar/editor_toolbar.dart';
import 'package:feature_editor/src/ui/toolbar/insert_menu.dart';
import 'package:feature_editor/src/ui/toolbar/undo_redo_buttons.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart';
import 'package:note_core/testing_vm.dart';

import '../helpers/fake_image_importer.dart';
import '../helpers/pump_editor.dart';
import '../helpers/test_data.dart';

const int _red = 0xFFE53935;

final core.ShapeObject _seedEllipse = PageObjectFixtures.shape(
  pageId: 'x',
  id: 'seed-ellipse',
  kind: core.ShapeKind.ellipse,
  rect: const core.PageRect(360, 120, 460, 180),
  createdAt: 2,
);

core.PageContent _page(EditorTestHandles h) =>
    h.session.pageIfLoaded(h.pageId(0))!;

/// The page's elements as (kind → count) — strokes as 'stroke'.
Map<String, int> _kinds(core.PageContent p) {
  final out = <String, int>{'stroke': p.strokes.length};
  for (final o in p.objects) {
    final k = switch (o) {
      core.ShapeObject(:final shapeKind) => 'shape:${shapeKind.name}',
      core.TextBoxObject() => 'text',
      core.ImageObject() => 'image',
      core.MathObject() => 'math',
      _ => 'other',
    };
    out[k] = (out[k] ?? 0) + 1;
  }
  return out;
}

Set<String> _ids(core.PageContent p) => {
  for (final s in p.strokes) s.id,
  for (final o in p.objects) o.id,
};

Rect _boundsOf(core.PageContent p) {
  Rect? r;
  void add(core.PageRect b) {
    final x = Rect.fromLTRB(b.left, b.top, b.right, b.bottom);
    r = r == null ? x : r!.expandToInclude(x);
  }

  for (final s in p.strokes) {
    add(s.bounds);
  }
  for (final o in p.objects) {
    add(o.bounds);
  }
  return r!;
}

/// Lets the real store's async work (drift on a background isolate, asset
/// hashing) finish, pumping frames in between.
Future<void> _flush(WidgetTester tester, [int rounds = 6]) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _stylusTap(EditorTestHandles h, Offset pagePt) async {
  final at = h.toGlobal(0, pagePt);
  await h.driver.down(1, at, kind: PointerDeviceKind.stylus);
  await h.driver.wait(const Duration(milliseconds: 20));
  await h.driver.move(1, at + const Offset(1, 0));
  await h.driver.wait(const Duration(milliseconds: 20));
  await h.driver.up(1);
}

Future<void> _stylusDrag(EditorTestHandles h, Offset a, Offset b) async {
  final from = h.toGlobal(0, a), to = h.toGlobal(0, b);
  await h.driver.down(1, from, kind: PointerDeviceKind.stylus);
  for (var i = 1; i <= 8; i++) {
    await h.driver.wait(const Duration(milliseconds: 8));
    await h.driver.move(1, Offset.lerp(from, to, i / 8)!);
  }
  await h.driver.wait(const Duration(milliseconds: 8));
  await h.driver.up(1);
}

Future<void> _leave(WidgetTester tester, bool Function() closed) async {
  await tester.tap(find.byKey(EditorToolbar.backKey));
  for (var i = 0; i < 30 && !closed(); i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
  }
  expect(closed(), isTrue);
}

void main() {
  testWidgets('real CORE + real INK: stroke, text box, rectangle, image, '
      'lasso all → 90°, colour, cut, paste → undo to the start → redo → '
      'reopen (C15-04)', (tester) async {
    final store = (await tester.runAsync(openTestNoteStore))!;
    final h = await pumpEditor(
      tester,
      store: store,
      title: '객체 스모크',
      pages: 2,
      strokesByPageIndex: {
        0: [strokeA],
      },
      objectsByPageIndex: {
        0: [_seedEllipse],
      },
      imageImporter: (s) => FakeImageImporter(store: s),
      recordSession: false, // CORE's own noteSessionProvider
    );
    await _flush(tester, 2);
    final firstSession = h.session;
    expect(h.session.history.undoDepth, 0);
    final opened = _page(h);
    final openedIds = _ids(opened);
    final openedKinds = _kinds(opened);
    expect(openedKinds, {'stroke': 1, 'shape:ellipse': 1});

    // --- a pen stroke ------------------------------------------------------
    await h.driver.stylusStroke(
      pathThrough(h, 0, [
        for (var x = 100.0; x <= 300; x += 25) Offset(x, 250),
      ]),
    );
    await _flush(tester, 2);
    expect(h.session.history.undoLabel, 'add-strokes');
    expect(h.session.history.undoDepth, 1);
    expect(_page(h).strokes, hasLength(2));

    // --- the text tool: a box '회의록 abc' ----------------------------------
    await tester.tap(find.byKey(EditorToolbar.textKey));
    await tester.pump();
    await _stylusTap(h, const Offset(100, 320));
    await tester.pump();
    await tester.pump();
    final textEdit = h.container.read(editorTextEditProvider);
    expect(textEdit?.isNew, isTrue);
    await tester.enterText(find.byKey(textEditorKey), '회의록 abc');
    await tester.pump();
    // The toolbar title is outside the editor's tap group → tapOutside.
    await tapToolbarBlank(tester);
    await tester.pump();
    await tester.runAsync(
      () => h.container.read(editorTextEditProvider.notifier).ending,
    );
    await _flush(tester, 2);
    expect(h.container.read(editorTextEditProvider), isNull);
    expect(h.session.history.undoLabel, 'add-objects');
    expect(h.session.history.undoDepth, 2);
    final text = _page(h).objects.whereType<core.TextBoxObject>().single;
    expect(text.text, '회의록 abc');

    // --- the shape tool: a rectangle (the default kind) ----------------------
    await tester.tap(find.byKey(EditorToolbar.shapeKey));
    await tester.pump();
    await _stylusDrag(h, const Offset(120, 420), const Offset(300, 520));
    await _flush(tester, 2);
    expect(h.session.history.undoLabel, 'add-objects');
    expect(h.session.history.undoDepth, 3);
    final rectangles = [
      for (final o in _page(h).objects)
        if (o is core.ShapeObject && o.shapeKind == core.ShapeKind.rectangle) o,
    ];
    expect(rectangles, hasLength(1));

    // --- the insert menu: an image ----------------------------------------
    await tester.tap(find.byKey(InsertMenu.buttonKey));
    await tester.pump();
    await tester.tap(find.byKey(InsertMenu.imageKey));
    await tester.pump();
    await tester.tap(
      find.byKey(InsertMenu.imageSourceKey(core.ImageImportSource.photos)),
    );
    await _flush(tester, 8);
    expect(h.imageImporter!.calls, hasLength(1));
    expect(h.session.history.undoDepth, 4);
    final image = _page(h).objects.whereType<core.ImageObject>().single;
    expect(image.assetId, h.imageImporter!.putAssetIds.single);

    final beforeEdits = _page(h);
    final beforeEditKinds = _kinds(beforeEdits);
    expect(beforeEditKinds, {
      'stroke': 2,
      'shape:ellipse': 1,
      'text': 1,
      'shape:rectangle': 1,
      'image': 1,
    });

    // --- the lasso around everything ---------------------------------------
    await tester.tap(find.byKey(EditorToolbar.lassoKey));
    await tester.pump();
    await h.driver.stylusStroke(
      lassoAround(h, 0, _boundsOf(beforeEdits).inflate(20)),
    );
    await _flush(tester, 2);
    final selection = h.container.read(editorSelectionProvider);
    expect(selection?.elementIds, _ids(beforeEdits));
    expect(selection?.origin, SelectionOrigin.lasso);

    // --- ⋯ 90° 돌리기 -----------------------------------------------------
    await tester.tap(find.byKey(SelectionMenu.moreKey));
    await tester.pump();
    await tester.tap(find.byKey(SelectionMenu.rotate90Key));
    await _flush(tester, 2);
    expect(h.session.history.undoLabel, 'transform');
    expect(h.session.history.undoDepth, 5);
    // A rectangle is polyline geometry: a quarter turn swaps its bounds'
    // width and height (the points turn, not frame.rotation).
    final before = rectangles.single.bounds;
    final turned = _page(h).objectById(rectangles.single.id)!.bounds;
    expect(
      turned.right - turned.left,
      closeTo(before.bottom - before.top, 0.05),
    );
    expect(
      turned.bottom - turned.top,
      closeTo(before.right - before.left, 0.05),
    );

    // --- 색: red -------------------------------------------------------------
    h.container.read(editorColorPaletteProvider.notifier).pushRecent(_red);
    await tester.pump();
    await tester.tap(find.byKey(SelectionMenu.colorKey));
    await tester.pump();
    await tester.tap(find.byKey(RecolorPanel.swatchKey(_red)));
    await _flush(tester, 2);
    expect(h.session.history.undoDepth, 6);
    final recoloured = _page(h);
    for (final s in recoloured.strokes) {
      expect(s.style.colorArgb, _red, reason: 'stroke ${s.id}');
    }
    expect(
      (recoloured.objectById(rectangles.single.id)! as core.ShapeObject)
          .style
          .strokeColorArgb,
      _red,
    );
    expect(
      (recoloured.objectById(text.id)! as core.TextBoxObject).style.colorArgb,
      _red,
    );

    // --- 잘라내기 ------------------------------------------------------------
    await tester.tap(find.byKey(SelectionMenu.cutKey));
    await _flush(tester, 2);
    expect(h.session.history.undoLabel, 'remove-elements');
    expect(h.session.history.undoDepth, 7);
    expect(_page(h).strokes, isEmpty);
    expect(_page(h).objects, isEmpty);
    expect(h.container.read(editorSelectionProvider), isNull);

    // --- 붙여넣기 (the context menu) --------------------------------------
    await h.driver.down(
      7,
      h.toGlobal(0, const Offset(300, 400)),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await h.driver.up(7);
    await tester.pump();
    await tester.tap(find.byKey(EditorContextMenu.pasteKey));
    await _flush(tester, 4);
    expect(h.session.history.undoDepth, 8);
    final pasted = _page(h);
    expect(_kinds(pasted), beforeEditKinds);
    expect(
      _ids(pasted).intersection(_ids(beforeEdits)),
      isEmpty,
      reason: 'pasted elements get new ids',
    );
    expect(h.container.read(editorSelectionProvider)?.elementIds, _ids(pasted));
    expect(
      h.container.read(editorSelectionProvider)?.origin,
      SelectionOrigin.paste,
    );
    final pastedIds = _ids(pasted);

    // --- undo to the end of the chain = the note as it was opened ----------
    var undos = 0;
    while (h.session.history.canUndo) {
      await tester.tap(find.byKey(UndoRedoButtons.undoKey));
      await _flush(tester, 2);
      undos++;
      expect(undos, lessThanOrEqualTo(8));
    }
    expect(undos, 8);
    expect(h.session.history.undoDepth, 0);
    expect(_ids(_page(h)), openedIds);
    expect(_kinds(_page(h)), openedKinds);
    expect(_page(h).strokeById(strokeA.id)!.style, strokeA.style);
    expect(_page(h).objectById(_seedEllipse.id)!.frame, _seedEllipse.frame);
    expect(h.controllerOf(0).content!.objects.map((o) => o.id).toSet(), {
      _seedEllipse.id,
    });

    // --- redo to the end = the state after the paste ------------------------
    var redos = 0;
    while (h.session.history.canRedo) {
      await tester.tap(find.byKey(UndoRedoButtons.redoKey));
      await _flush(tester, 2);
      redos++;
      expect(redos, lessThanOrEqualTo(8));
    }
    expect(redos, 8);
    expect(h.session.history.undoDepth, 8);
    expect(_ids(_page(h)), pastedIds);
    expect(_kinds(_page(h)), beforeEditKinds);
    final finalPage = _page(h);

    // --- leave, open again --------------------------------------------------
    await _leave(tester, () => h.closeCount > 0);
    expect(store.persistenceStatus.pendingOps, 0);
    await tester.pumpWidget(const SizedBox());
    for (var i = 0; i < 5 && !firstSession.isClosed; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
    }
    expect(firstSession.isClosed, isTrue);

    var closedAgain = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [core.noteStoreProvider.overrideWithValue(store)],
        child: MaterialApp(
          home: EditorScreen(
            key: ValueKey('again-${h.noteId}'),
            noteId: h.noteId,
            onClose: () => closedAgain++,
          ),
        ),
      ),
    );
    await tester.pump();
    await h.settlePages();
    await _flush(tester, 2);
    expect(identical(h.session, firstSession), isFalse);
    expect(h.session.history.undoDepth, 0);
    final reopened = _page(h);
    expect(_ids(reopened), pastedIds);
    expect(_kinds(reopened), beforeEditKinds);
    expect(reopened.objects, hasLength(finalPage.objects.length));
    for (final o in finalPage.objects) {
      expect(reopened.objectById(o.id)!.frame, o.frame, reason: o.id);
    }
    expect(
      reopened.objects.whereType<core.TextBoxObject>().single.text,
      '회의록 abc',
    );
    expect(h.controllerOf(0).content!.objects.map((o) => o.id).toSet(), {
      for (final o in reopened.objects) o.id,
    });

    await _leave(tester, () => closedAgain > 0);
    await tester.pumpWidget(const SizedBox());
    // The image asset's write queue was started from the fake-async zone,
    // so close the store there too and let both clocks run until it is done.
    var closed = false;
    unawaited(store.close().then((_) => closed = true));
    for (var i = 0; i < 50 && !closed; i++) {
      await _flush(tester, 1);
    }
    expect(closed, isTrue);
  });
}
