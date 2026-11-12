// Steps 2–8 and 10 of the 2nd round app smoke (V5 v2 — docs/plans/m5-7/
// 01-infra.md 9.1 '앱 스모크 v2 단계', 8.3 H3; contract 7.7 V5 v2.1) and the
// V5b auto shape flow (9.1, C22-07), on the production screens of a start
// made by bootSmokeV2App (test/support/smoke_v2_fakes.dart).
//
// The screens are driven the way a user does: the EDITOR widget keys of
// 04-editor appendix C (ValueKey strings — the key constants live under
// feature_editor's src/, which the app does not import, R7), visible texts
// and accessibility labels. What a step did is read back from the real
// CORE store (flush, then the content reader) and from the INK controller
// of the page view (playbackFocus).
//
// Time: the store was opened in the widget test's fake-async zone, so store
// calls go through settle() / pumpUntil() (real time passes while frames
// pump), as in the 1st round scenario.
//
// Web-safe: no dart:io, no package:web — V6 v2 runs the same steps.
library;

import 'package:feature_editor/feature_editor.dart';
import 'package:feature_library/feature_library.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:ink_recognition/testing.dart' show SyntheticShapes;
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart';

import 'smoke_scenario.dart';
import 'smoke_v2_fakes.dart';

/// EDITOR widget keys (04-editor appendix C) the smoke presses.
abstract final class EditorKeys {
  static const back = ValueKey('editor.toolbar.back');
  static const title = ValueKey('editor.toolbar.title');
  static const pen = ValueKey('editor.toolbar.pen');
  static const lasso = ValueKey('editor.toolbar.lasso');
  static const text = ValueKey('editor.toolbar.text');
  static const shape = ValueKey('editor.toolbar.shape');
  static const overflowTools = ValueKey('editor.toolbar.overflowTools');
  static const insert = ValueKey('editor.toolbar.insert');
  static const insertImage = ValueKey('editor.insert.image');
  static ValueKey<String> insertImageSource(ImageImportSource s) =>
      ValueKey('editor.insert.image.${s.name}');
  static const mic = ValueKey('editor.toolbar.mic');
  static const panelSlot = ValueKey('editor.panelSlot');
  static const textEditor = ValueKey('editor.textEditor');
  static ValueKey<String> shapeKind(ShapeKind kind) =>
      ValueKey('editor.shapePopup.kind.${kind.name}');
  static const selectionMore = ValueKey('editor.selectionMenu.more');
  static const rotate90 = ValueKey('editor.selectionMenu.rotate90');
  static const color = ValueKey('editor.selectionMenu.color');
  static const cut = ValueKey('editor.selectionMenu.cut');
  static const paste = ValueKey('editor.contextMenu.paste');
  static const focusFlash = ValueKey('editor.focusFlash');
  static ValueKey<String> extension(String id) => ValueKey('editor.ext.$id');
  static const recolorSwatchPrefix = 'editor.recolor.swatch.';
  static const recolorMore = ValueKey('editor.recolor.more');
  static const recolorApply = ValueKey('editor.recolor.apply');
  static const colorWheel = ValueKey('editor.color.wheel');
  static const penSettings = ValueKey('editor.popup.penSettings');
  static const penAdvanced = ValueKey('editor.popup.penSettings.advanced');
}

/// media_io recording panel labels (06-pdf 6.16 MediaStringsKo — under
/// media_io's src/, spelled out here like SmokeLabels).
abstract final class RecordingLabels {
  static const String recordSemantics = '녹음 시작';
  static const String startRecording = '녹음 시작';
  static const String stop = '정지';
}

/// The first page view on screen and the pt → screen scale of its page.
final class PageGeometry {
  PageGeometry(this.view, this.pageSize);

  final Rect view;
  final PageSize pageSize;

  double get scale => view.width / pageSize.width;

  Offset toGlobal(Offset pt) => view.topLeft + pt * scale;
}

Future<PageGeometry> pageGeometry(
  WidgetTester tester,
  NoteStore store,
  NoteId noteId,
) async {
  final size = await settle(
    tester,
    'the first page size of $noteId',
    () async => (await store.content.pagesOf(noteId)).first.size,
  );
  return PageGeometry(tester.getRect(find.byType(ink.InkPageView).first), size);
}

/// The committed content of [noteId]'s first page (flush, then loadPage).
Future<PageContent> firstPage(
  WidgetTester tester,
  NoteStore store,
  NoteId noteId,
) => settle(tester, 'the first page of $noteId', () async {
  await store.flush();
  final pages = await store.content.pagesOf(noteId);
  return store.content.loadPage(pages.first.id);
});

/// The page's elements as kind → count (strokes as 'stroke').
Map<String, int> kindsOf(PageContent p) {
  final out = <String, int>{'stroke': p.strokes.length};
  for (final o in p.objects) {
    final k = switch (o) {
      ShapeObject(:final shapeKind) => 'shape:${shapeKind.name}',
      TextBoxObject() => 'text',
      ImageObject() => 'image',
      MathObject() => 'math',
      _ => 'other',
    };
    out[k] = (out[k] ?? 0) + 1;
  }
  return out;
}

Set<String> idsOf(PageContent p) => {
  for (final s in p.strokes) s.id,
  for (final o in p.objects) o.id,
};

bool buttonEnabled(WidgetTester tester, String label) {
  final f = iconButtonLabeled(label);
  if (f.evaluate().isEmpty) return false;
  return tester.widget<IconButton>(f.first).onPressed != null;
}

/// Taps the toolbar tool [key]; a tool that sits in the overflow menu at
/// this width is reached through it (04-editor 6.9.1).
Future<void> tapTool(WidgetTester tester, Key key) async {
  if (find.byKey(key).hitTestable().evaluate().isEmpty) {
    await tester.tap(find.byKey(EditorKeys.overflowTools));
    await pumpUntil(
      tester,
      () => find.byKey(key).hitTestable().evaluate().isNotEmpty,
      reason: 'the overflow tool $key',
    );
  }
  await tester.tap(find.byKey(key).hitTestable().first);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

int _nextPointer = 81000;

/// One synthetic Apple Pencil stroke through [points] (raw PointerEvents with
/// pressure, as the engine sends them — the 1st round stylusStroke) with an
/// optional still [hold] (pumped in [holdSteps] frames, no events) before the
/// up.
Future<void> stylusPath(
  WidgetTester tester,
  List<Offset> points, {
  Duration interval = const Duration(milliseconds: 8),
  Duration hold = Duration.zero,
  int holdSteps = 1,
}) async {
  const device = 9;
  var now = const Duration(seconds: 1);
  final pointer = _nextPointer++;
  await tester.sendEventToBinding(
    PointerAddedEvent(
      timeStamp: now,
      device: device,
      kind: PointerDeviceKind.stylus,
      position: points.first,
    ),
  );
  await tester.sendEventToBinding(
    PointerDownEvent(
      timeStamp: now,
      pointer: pointer,
      device: device,
      kind: PointerDeviceKind.stylus,
      position: points.first,
      buttons: kPrimaryButton,
      pressure: 0.5,
      pressureMin: 0,
      pressureMax: 1,
    ),
  );
  var last = points.first;
  for (final p in points.skip(1)) {
    now += interval;
    await tester.pump(interval);
    await tester.sendEventToBinding(
      PointerMoveEvent(
        timeStamp: now,
        pointer: pointer,
        device: device,
        kind: PointerDeviceKind.stylus,
        position: p,
        delta: p - last,
        buttons: kPrimaryButton,
        pressure: 0.5,
        pressureMin: 0,
        pressureMax: 1,
      ),
    );
    last = p;
  }
  if (hold > Duration.zero) {
    for (var i = 0; i < holdSteps; i++) {
      await tester.pump(hold ~/ holdSteps);
    }
    now += hold;
  }
  now += interval;
  await tester.pump(interval);
  await tester.sendEventToBinding(
    PointerUpEvent(
      timeStamp: now,
      pointer: pointer,
      device: device,
      kind: PointerDeviceKind.stylus,
      position: last,
      pressureMin: 0,
      pressureMax: 1,
    ),
  );
  await tester.sendEventToBinding(
    PointerRemovedEvent(
      timeStamp: now,
      device: device,
      kind: PointerDeviceKind.stylus,
      position: last,
    ),
  );
  await tester.pump();
}

/// The pen tool. A press on the tool already chosen opens its popup
/// (04-editor 6.9) — that popup is closed again by a tap on the toolbar
/// title.
Future<void> selectPen(WidgetTester tester) async {
  await tapTool(tester, EditorKeys.pen);
  if (find.byKey(EditorKeys.penSettings).evaluate().isNotEmpty) {
    await tester.tapAt(tester.getCenter(find.byKey(EditorKeys.title)));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// A short stylus tap (down, a 1 px move, up).
Future<void> stylusTap(WidgetTester tester, Offset at) =>
    stylusPath(tester, [at, at + const Offset(1, 0)]);

/// A closed lasso path around [r] (screen coordinates).
List<Offset> lassoAround(Rect r) => [
  for (var i = 0; i <= 10; i++) Offset.lerp(r.topLeft, r.topRight, i / 10)!,
  for (var i = 1; i <= 10; i++) Offset.lerp(r.topRight, r.bottomRight, i / 10)!,
  for (var i = 1; i <= 10; i++)
    Offset.lerp(r.bottomRight, r.bottomLeft, i / 10)!,
  for (var i = 1; i <= 10; i++) Offset.lerp(r.bottomLeft, r.topLeft, i / 10)!,
];

Rect _boundsPt(PageContent p) {
  Rect? r;
  void add(PageRect b) {
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

Future<void> _pumpUntilPage(
  WidgetTester tester,
  NoteStore store,
  NoteId noteId,
  bool Function(PageContent) done, {
  required String reason,
}) async {
  for (var i = 0; i < 60; i++) {
    final p = await firstPage(tester, store, noteId);
    if (done(p)) return;
    await letRealTimePass(tester, times: 2);
  }
  final p = await firstPage(tester, store, noteId);
  expect(done(p), isTrue, reason: 'gave up waiting for $reason: ${kindsOf(p)}');
}

/// '새 노트' (the grid tile or the empty home's button) → '만들기' → the
/// editor. Returns the new note's id and title.
Future<(NoteId, String)> createNote(
  WidgetTester tester,
  NoteStore store,
) async {
  await pumpUntil(
    tester,
    () => find.text(SmokeLabels.newNote).evaluate().isNotEmpty,
    reason: "the library's '${SmokeLabels.newNote}'",
  );
  await tester.tap(find.text(SmokeLabels.newNote).first);
  await pumpUntil(
    tester,
    () => find.text(SmokeLabels.create).evaluate().isNotEmpty,
    reason: 'the new note dialog',
  );
  await tester.tap(find.text(SmokeLabels.create));
  await pumpUntil(
    tester,
    () => find.byType(ink.InkPageView).evaluate().isNotEmpty,
    reason: 'the editor of the new note',
  );
  final noteId = tester.widget<EditorScreen>(find.byType(EditorScreen)).noteId;
  final note = await settle(
    tester,
    'note $noteId',
    () => store.library.getNote(noteId),
  );
  await letRealTimePass(tester);
  return (noteId, note!.title);
}

/// Back (flush, then onClose) until the library shows.
Future<void> leaveEditor(WidgetTester tester, String what) async {
  await tester.tap(iconButtonLabeled(SmokeLabels.back));
  await pumpUntil(
    tester,
    () =>
        find.byType(EditorScreen).evaluate().isEmpty &&
        find.byType(LibraryScreen).evaluate().isNotEmpty,
    reason: 'back in the library ($what)',
  );
}

/// The library tile [title] → the editor of [noteId].
Future<void> reopenNote(
  WidgetTester tester,
  NoteId noteId,
  String title,
) async {
  await pumpUntil(
    tester,
    () => find.text(title).evaluate().isNotEmpty,
    reason: "the tile '$title'",
  );
  await tester.tap(find.text(title).first);
  await pumpUntil(
    tester,
    () => find.byType(ink.InkPageView).evaluate().isNotEmpty,
    reason: 'the editor of $title opened again',
  );
  expect(tester.widget<EditorScreen>(find.byType(EditorScreen)).noteId, noteId);
  await letRealTimePass(tester);
}

/// Undo with the toolbar until it is disabled; returns the steps.
Future<int> undoAll(WidgetTester tester, {int max = 20}) async {
  var n = 0;
  while (buttonEnabled(tester, SmokeLabels.undo)) {
    await tester.tap(iconButtonLabeled(SmokeLabels.undo));
    await letRealTimePass(tester, times: 3);
    n++;
    expect(n, lessThanOrEqualTo(max));
  }
  return n;
}

Future<int> redoAll(WidgetTester tester, {int max = 20}) async {
  var n = 0;
  while (buttonEnabled(tester, SmokeLabels.redo)) {
    await tester.tap(iconButtonLabeled(SmokeLabels.redo));
    await letRealTimePass(tester, times: 3);
    n++;
    expect(n, lessThanOrEqualTo(max));
  }
  return n;
}

ink.InkPageController _controller(WidgetTester tester) => tester
    .widget<ink.InkPageView>(find.byType(ink.InkPageView).first)
    .controller;

/// What steps 2–10 left for the caller (the search step and the counts).
typedef SmokeV2Result = ({NoteId noteId, String title, PageContent page});

/// Steps 2–8 and 10 of 9.1 on a new note, from the library and back to it.
/// [trace] gets the step about to run.
Future<SmokeV2Result> runSmokeV2Scenario(
  WidgetTester tester,
  SmokeApp app,
  SmokeV2Fakes fakes, {
  void Function(String step)? trace,
}) async {
  final store = app.store;
  final log = trace ?? (_) {};

  log('v2-2 new note');
  final (noteId, title) = await createNote(tester, store);
  var geo = await pageGeometry(tester, store, noteId);
  Offset at(double x, double y) => geo.toGlobal(Offset(x, y));

  // --- 2. a stroke → a text box '안녕 hello' → a rectangle ----------------
  log('v2-2 stroke');
  await stylusPath(tester, [for (var x = 80.0; x <= 260; x += 20) at(x, 120)]);
  await _pumpUntilPage(
    tester,
    store,
    noteId,
    (p) => p.strokes.length == 1,
    reason: 'the pen stroke',
  );
  var undoSteps = 1;

  log('v2-2 text box');
  await tapTool(tester, EditorKeys.text);
  await stylusTap(tester, at(80, 200));
  await pumpUntil(
    tester,
    () => find.byKey(EditorKeys.textEditor).evaluate().isNotEmpty,
    reason: 'the text box editor',
  );
  await tester.enterText(find.byKey(EditorKeys.textEditor), '안녕 hello');
  await tester.pump();
  await tester.tap(find.byKey(EditorKeys.title));
  await _pumpUntilPage(
    tester,
    store,
    noteId,
    (p) => p.objects.whereType<TextBoxObject>().length == 1,
    reason: 'the text box',
  );
  undoSteps++;
  expect(
    (await firstPage(
      tester,
      store,
      noteId,
    )).objects.whereType<TextBoxObject>().single.text,
    '안녕 hello',
  );

  log('v2-2 shape');
  await tapTool(tester, EditorKeys.shape);
  if (find
      .byKey(EditorKeys.shapeKind(ShapeKind.rectangle))
      .evaluate()
      .isEmpty) {
    // The tool's second press opens its popup (kind, count).
    await tapTool(tester, EditorKeys.shape);
  }
  if (find
      .byKey(EditorKeys.shapeKind(ShapeKind.rectangle))
      .hitTestable()
      .evaluate()
      .isNotEmpty) {
    await tester.tap(find.byKey(EditorKeys.shapeKind(ShapeKind.rectangle)));
    await tester.pump();
    // Close the popup without touching the page.
    await tester.tapAt(const Offset(4, 4));
    await tester.pump(const Duration(milliseconds: 50));
  }
  await stylusPath(tester, [
    for (var i = 0; i <= 8; i++)
      Offset.lerp(at(300, 120), at(460, 220), i / 8)!,
  ]);
  await _pumpUntilPage(
    tester,
    store,
    noteId,
    (p) => p.objects.whereType<ShapeObject>().length == 1,
    reason: 'the rectangle',
  );
  undoSteps++;
  final rectangle = (await firstPage(
    tester,
    store,
    noteId,
  )).objects.whereType<ShapeObject>().single;
  expect(rectangle.shapeKind, ShapeKind.rectangle);

  // --- 3. the insert menu → image → photos (slot 1, the fake picker) -------
  log('v2-3 image');
  await tester.tap(find.byKey(EditorKeys.insert));
  await pumpUntil(
    tester,
    () => find.byKey(EditorKeys.insertImage).evaluate().isNotEmpty,
    reason: 'the insert menu',
  );
  // Slot 4: the recognition insert items show in the same menu (step 8).
  for (final id in realRecognitionInsertIds()) {
    expect(find.byKey(EditorKeys.extension(id)), findsOneWidget, reason: id);
  }
  await tester.tap(find.byKey(EditorKeys.insertImage));
  await pumpUntil(
    tester,
    () => find
        .byKey(EditorKeys.insertImageSource(ImageImportSource.photos))
        .evaluate()
        .isNotEmpty,
    reason: 'the image sources',
  );
  await tester.tap(
    find.byKey(EditorKeys.insertImageSource(ImageImportSource.photos)),
  );
  await _pumpUntilPage(
    tester,
    store,
    noteId,
    (p) => p.objects.whereType<ImageObject>().length == 1,
    reason: 'the image',
  );
  undoSteps++;
  expect(fakes.picks, [ImageImportSource.photos]);

  final beforeEdits = await firstPage(tester, store, noteId);
  final beforeKinds = kindsOf(beforeEdits);
  expect(beforeKinds, {
    'stroke': 1,
    'text': 1,
    'shape:rectangle': 1,
    'image': 1,
  });

  // --- 4. lasso all → 90° → colour → cut → paste ---------------------------
  log('v2-4 lasso');
  await tapTool(tester, EditorKeys.lasso);
  final all = _boundsPt(beforeEdits).inflate(24);
  await stylusPath(
    tester,
    lassoAround(
      Rect.fromPoints(at(all.left, all.top), at(all.right, all.bottom)),
    ),
  );
  await pumpUntil(
    tester,
    () => find.byKey(EditorKeys.cut).evaluate().isNotEmpty,
    reason: 'the selection menu',
  );
  // Slot 3: the recognition selection items (step 8).
  final selectionIds = realRecognitionSelectionIds();
  expect(selectionIds, isNotEmpty, reason: 'LIBRARY recog actions merged');

  log('v2-4 rotate');
  await tester.tap(find.byKey(EditorKeys.selectionMore));
  await pumpUntil(
    tester,
    () => find.byKey(EditorKeys.rotate90).evaluate().isNotEmpty,
    reason: 'the ⋯ menu',
  );
  // A mixed selection with a pen stroke: the three ink items show
  // (isVisible — 05-library 4.4.4), recog.editMath (one math object only)
  // does not.
  final shownIds = {
    for (final id in selectionIds)
      if (find.byKey(EditorKeys.extension(id)).evaluate().isNotEmpty) id,
  };
  expect(shownIds, {'recog.toText', 'recog.copyText', 'recog.toMath'});
  await tester.tap(find.byKey(EditorKeys.rotate90));
  await letRealTimePass(tester, times: 4);
  undoSteps++;
  final turned = await firstPage(tester, store, noteId);
  final tb = turned.objectById(rectangle.id)!.bounds;
  final rb = rectangle.bounds;
  expect(tb.right - tb.left, closeTo(rb.bottom - rb.top, 0.5));
  expect(tb.bottom - tb.top, closeTo(rb.right - rb.left, 0.5));

  log('v2-4 colour');
  await pumpUntil(
    tester,
    () => find.byKey(EditorKeys.color).evaluate().isNotEmpty,
    reason: 'the selection menu after the turn',
  );
  await tester.tap(find.byKey(EditorKeys.color));
  await pumpUntil(
    tester,
    () => _swatches().evaluate().isNotEmpty,
    reason: 'the recolour swatches',
  );
  final strokeColor = turned.strokes.single.style.colorArgb;
  final other = [
    for (final e in _swatches().evaluate())
      if (_argbOf(e.widget.key!) != strokeColor) e.widget.key!,
  ];
  if (other.isNotEmpty) {
    await tester.tap(find.byKey(other.first));
  } else {
    // Only the pen's own colour is recent on a new install: '더 많은 색' →
    // a point on the colour wheel → 적용.
    await tester.tap(find.byKey(EditorKeys.recolorMore));
    await pumpUntil(
      tester,
      () => find.byKey(EditorKeys.colorWheel).evaluate().isNotEmpty,
      reason: 'the colour wheel',
    );
    final wheel = tester.getRect(find.byKey(EditorKeys.colorWheel));
    await tester.tapAt(wheel.center + Offset(wheel.width * 0.35, 0));
    await tester.pump();
    await tester.tap(find.byKey(EditorKeys.recolorApply));
  }
  await letRealTimePass(tester, times: 4);
  undoSteps++;
  final recoloured = await firstPage(tester, store, noteId);
  final newColor = recoloured.strokes.single.style.colorArgb;
  expect(newColor, isNot(strokeColor));
  expect(
    (recoloured.objectById(rectangle.id)! as ShapeObject).style.strokeColorArgb,
    newColor,
  );

  log('v2-4 cut');
  await pumpUntil(
    tester,
    () => find.byKey(EditorKeys.cut).evaluate().isNotEmpty,
    reason: 'the selection menu after the colour',
  );
  await tester.tap(find.byKey(EditorKeys.cut));
  await _pumpUntilPage(
    tester,
    store,
    noteId,
    (p) => p.strokes.isEmpty && p.objects.isEmpty,
    reason: 'the cut',
  );
  undoSteps++;

  log('v2-4 paste');
  // The context menu by a long press (1st round key editor.contextMenu.paste).
  await tester.longPressAt(at(300, 400));
  await tester.pump(const Duration(milliseconds: 50));
  if (find.byKey(EditorKeys.paste).evaluate().isEmpty) {
    // A finger long press may belong to the page's scroll on this build —
    // the secondary click opens the same menu (04-editor 6.10).
    final mouse = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await mouse.addPointer(location: at(300, 400));
    await mouse.down(at(300, 400));
    await mouse.up();
    await mouse.removePointer();
    await tester.pump();
  }
  await pumpUntil(
    tester,
    () => find.byKey(EditorKeys.paste).evaluate().isNotEmpty,
    reason: 'the context menu',
  );
  await tester.tap(find.byKey(EditorKeys.paste));
  await _pumpUntilPage(
    tester,
    store,
    noteId,
    (p) => p.strokes.length + p.objects.length == 4,
    reason: 'the paste',
  );
  undoSteps++;
  final pasted = await firstPage(tester, store, noteId);
  expect(kindsOf(pasted), beforeKinds);
  expect(idsOf(pasted).intersection(idsOf(beforeEdits)), isEmpty);
  // Leave the selection of the paste (a tap on an empty spot).
  await tester.tapAt(at(500, 700));
  await tester.pump(const Duration(milliseconds: 50));

  // --- 5. undo chain → redo → close → reopen -------------------------------
  log('v2-5 undo chain');
  final undos = await undoAll(tester);
  expect(undos, undoSteps);
  final empty = await firstPage(tester, store, noteId);
  expect(empty.strokes, isEmpty);
  expect(empty.objects, isEmpty);
  final redos = await redoAll(tester);
  expect(redos, undoSteps);
  final redone = await firstPage(tester, store, noteId);
  expect(idsOf(redone), idsOf(pasted));
  expect(kindsOf(redone), beforeKinds);

  log('v2-5 close / reopen');
  await leaveEditor(tester, 'step 5');
  expect(store.persistenceStatus.pendingOps, 0);
  await reopenNote(tester, noteId, title);
  final reopened = await firstPage(tester, store, noteId);
  expect(idsOf(reopened), idsOf(pasted));
  for (final o in pasted.objects) {
    expect(reopened.objectById(o.id)!.frame, o.frame, reason: o.id);
  }
  expect(reopened.objects.whereType<TextBoxObject>().single.text, '안녕 hello');
  expect(buttonEnabled(tester, SmokeLabels.undo), isFalse);
  geo = await pageGeometry(tester, store, noteId);

  // --- 6. the recording panel (slot 2) → record (fake) → 3 strokes → stop --
  log('v2-6 recording panel');
  await selectPen(tester);
  await tester.tap(find.byKey(EditorKeys.mic));
  await pumpUntil(
    tester,
    () => find.byKey(EditorKeys.panelSlot).evaluate().isNotEmpty,
    reason: 'the recording panel',
  );
  final record = find.descendant(
    of: find.byKey(EditorKeys.panelSlot),
    matching: find.bySemanticsLabel(RecordingLabels.recordSemantics),
  );
  await pumpUntil(
    tester,
    () => record.evaluate().isNotEmpty,
    reason: 'the record button',
  );
  await tester.tap(record.first);
  final recorder = fakes.recorder!;
  // The consent sheet (first recording on this device, contract 7.4.4)
  // shows once the setting is read from the store.
  final consent = find.widgetWithText(
    FilledButton,
    RecordingLabels.startRecording,
  );
  await pumpUntil(
    tester,
    () =>
        consent.evaluate().isNotEmpty ||
        recorder.status.phase == RecorderPhase.recording,
    reason: 'the consent sheet',
  );
  if (consent.evaluate().isNotEmpty) {
    // The sheet slides in first.
    await pumpUntil(
      tester,
      () => consent.hitTestable().evaluate().isNotEmpty,
      reason: 'the consent sheet in place',
    );
    await tester.tap(consent.hitTestable().first);
  }
  await pumpUntil(
    tester,
    () => recorder.status.phase == RecorderPhase.recording,
    reason: 'the fake recorder recording',
  );
  final offsets = <int>[];
  for (final (i, advance) in [(0, 1200), (1, 1800), (2, 2500)]) {
    recorder.advance(Duration(milliseconds: advance));
    offsets.add(recorder.offsetNowMs()!);
    await stylusPath(tester, [
      // Top right, clear of the content above and of the panel, which
      // covers the lower part of the screen.
      for (var x = 490.0; x <= 570; x += 10)
        geo.toGlobal(Offset(x, 30.0 + 25 * i)),
    ]);
    await letRealTimePass(tester, times: 2);
  }
  recorder.advance(const Duration(seconds: 2));
  final stop = find.descendant(
    of: find.byKey(EditorKeys.panelSlot),
    matching: find.widgetWithText(OutlinedButton, RecordingLabels.stop),
  );
  await tester.tap(stop.first);
  await pumpUntil(
    tester,
    () => recorder.status.phase == RecorderPhase.idle,
    reason: 'the stop',
  );
  final recordings = await settle(
    tester,
    'the recordings of $noteId',
    () => store.recordings.recordingsOf(noteId),
  );
  expect(recordings, hasLength(1));
  final recording = recordings.single;
  final afterRecording = await firstPage(tester, store, noteId);
  final recorded = [
    for (final s in afterRecording.strokes)
      if (s.recordingId != null) s,
  ];
  expect(recorded, hasLength(3), reason: '${kindsOf(afterRecording)}');
  expect([for (final s in recorded) s.recordingId], everyElement(recording.id));
  expect([for (final s in recorded) s.recordingOffsetMs], offsets);

  // --- 7. playback: the position moves the INK focus → a finger tap seeks --
  log('v2-7 playback');
  await settle(
    tester,
    'open the recording',
    () => fakes.playback.open(recording),
  );
  await settle(tester, 'play', fakes.playback.play);
  fakes.playback.setPositionMs(offsets[1] + 100);
  await letRealTimePass(tester, times: 2);
  expect(
    _controller(tester).playbackFocus,
    ink.InkPlaybackFocus(
      recordingId: recording.id,
      positionMs: offsets[1] + 100,
    ),
  );
  fakes.playback.setPositionMs(offsets[2] + 100);
  await letRealTimePass(tester, times: 2);
  expect(_controller(tester).playbackFocus?.positionMs, offsets[2] + 100);
  // A finger tap on the second recorded stroke while the panel is open
  // (contract R-5 v2.1): seek to its offset minus the pre-roll.
  final second = recorded[1].bounds;
  final callsBefore = fakes.playback.calls.length;
  await tester.tapAt(
    geo.toGlobal(Offset((second.left + second.right) / 2, second.top + 1)),
  );
  await letRealTimePass(tester, times: 3);
  final seeks = [
    for (final c in fakes.playback.calls.skip(callsBefore))
      if (c.startsWith('seek:')) int.parse(c.substring(5)),
  ];
  expect(seeks, hasLength(1), reason: '${fakes.playback.calls}');
  expect(seeks.single, lessThanOrEqualTo(offsets[1]));
  expect(seeks.single, greaterThanOrEqualTo(0));
  expect(fakes.playback.calls, contains('play'));
  await settle(tester, 'close the player', fakes.playback.close);

  // --- 10. the export structure (INK InkPageVectors v2) ---------------------
  log('v2-10 export counts');
  final finalPage = await firstPage(tester, store, noteId);
  final vectors = ink.InkVectorExport.exportPage(
    ink.InkPageContent.fromCore(
      page: finalPage.page,
      strokes: finalPage.strokes,
      objects: finalPage.objects,
      revision: finalPage.revision,
    ),
  );
  expect(vectors.underlay, hasLength(1));
  expect(vectors.annotations.whereType<ink.InkTextVector>(), hasLength(1));
  expect(
    {
      for (final s in vectors.inkShapes)
        if (s.objectId != null) s.objectId,
    },
    {
      for (final o in finalPage.objects)
        if (o is ShapeObject) o.id,
    },
  );

  log('v2 leave');
  await leaveEditor(tester, 'the v2 flow');
  return (noteId: noteId, title: title, page: finalPage);
}

Finder _swatches() => find.byWidgetPredicate(
  (w) =>
      w.key is ValueKey<String> &&
      (w.key! as ValueKey<String>).value.startsWith(
        EditorKeys.recolorSwatchPrefix,
      ),
);

int _argbOf(Key key) => int.parse(
  (key as ValueKey<String>).value.substring(
    EditorKeys.recolorSwatchPrefix.length,
  ),
  radix: 16,
);

/// Step 9 of 9.1: the library search for [query] → the content hit → the
/// editor at `?page=&focus=` with the hit's rect flashed.
Future<void> runSearchStep(
  WidgetTester tester,
  SmokeApp app,
  NoteId noteId,
  String query, {
  void Function(String step)? trace,
}) async {
  final log = trace ?? (_) {};
  log('9 search field');
  final field = find.widgetWithText(TextField, '노트 검색');
  if (field.evaluate().isEmpty) {
    await tester.tap(find.byTooltip('검색').first);
    await tester.pump();
  }
  await pumpUntil(
    tester,
    () => find.byType(TextField).evaluate().isNotEmpty,
    reason: 'the search field',
  );
  log('9 query');
  await tester.enterText(find.byType(TextField).first, query);
  await tester.testTextInput.receiveAction(TextInputAction.search);
  await pumpUntil(
    tester,
    () => find.textContaining('노트 내용').evaluate().isNotEmpty,
    reason: "the content hits of '$query'",
  );
  log('9 content hit');
  final hit = find.byWidgetPredicate(
    (w) => w.runtimeType.toString() == 'ContentHitRow',
  );
  await pumpUntil(
    tester,
    () => hit.evaluate().isNotEmpty,
    reason: 'a content hit row',
  );
  // The row opens its note once it has read it from the store (a press
  // before that does nothing — LIBRARY ContentHitRow): wait for the note's
  // header title, then press once.
  final title = await settle(
    tester,
    'note $noteId',
    () => app.store.library.getNote(noteId),
  );
  await pumpUntil(
    tester,
    () => find.text(title!.title).evaluate().isNotEmpty,
    reason: "the hit group's note title",
  );
  await letRealTimePass(tester, times: 4);
  await tester.tap(hit.first);
  await pumpUntil(
    tester,
    () => find.byType(EditorScreen).evaluate().isNotEmpty,
    reason: 'the editor at the hit',
  );
  log('9 editor at the hit');
  final editor = tester.widget<EditorScreen>(find.byType(EditorScreen));
  expect(editor.noteId, noteId);
  expect(editor.initialPageId, isNotNull);
  expect(editor.initialFocusRectPt, isNotNull);
  await pumpUntil(
    tester,
    () => find.byKey(EditorKeys.focusFlash).evaluate().isNotEmpty,
    reason: 'the focus flash',
    maxTries: 200,
  );
}

/// V5b (9.1, C22-07 — P-B): the pen follows SyntheticShapes.rectanglePath and
/// holds still past InkTuning.shapeHoldMs → one ShapeObject (rectangle), no
/// stroke, one undo step → undo → nothing → redo → the shape → close →
/// reopen keeps it, and the reopened session has no undo.
Future<void> runShapeAssistScenario(
  WidgetTester tester,
  SmokeApp app, {
  void Function(String step)? trace,
}) async {
  final store = app.store;
  final log = trace ?? (_) {};
  log('v5b new note');
  final (noteId, title) = await createNote(tester, store);
  final geo = await pageGeometry(tester, store, noteId);

  log('v5b loop and hold');
  const box = Rect.fromLTRB(120, 160, 360, 320);
  final path = [
    for (final p in SyntheticShapes.rectanglePath(box)) geo.toGlobal(p),
  ];
  await stylusPath(
    tester,
    path,
    hold: Duration(milliseconds: ink.InkTuning.shapeHoldMs + 200),
    holdSteps: 7,
  );
  await _pumpUntilPage(
    tester,
    store,
    noteId,
    (p) => p.objects.isNotEmpty || p.strokes.isNotEmpty,
    reason: 'the pen result',
  );
  final page = await firstPage(tester, store, noteId);
  expect(page.strokes, isEmpty, reason: 'the stroke became the shape');
  expect(page.objects, hasLength(1));
  final shape = page.objects.single as ShapeObject;
  expect(shape.shapeKind, ShapeKind.rectangle);
  final b = shape.bounds;
  expect(b.left, closeTo(box.left, 12));
  expect(b.right, closeTo(box.right, 12));

  log('v5b undo / redo');
  expect(await undoAll(tester), 1);
  final undone = await firstPage(tester, store, noteId);
  expect(undone.objects, isEmpty);
  expect(undone.strokes, isEmpty);
  expect(await redoAll(tester), 1);
  expect(
    [for (final o in (await firstPage(tester, store, noteId)).objects) o.id],
    [shape.id],
  );

  log('v5b close / reopen');
  await leaveEditor(tester, 'V5b');
  await reopenNote(tester, noteId, title);
  final reopened = await firstPage(tester, store, noteId);
  expect(reopened.strokes, isEmpty);
  expect([for (final o in reopened.objects) o.id], [shape.id]);
  expect(buttonEnabled(tester, SmokeLabels.undo), isFalse);
  await leaveEditor(tester, 'V5b end');
}

/// V15 on the screen (m5-7/01-infra.md H5 — the editor of the note open now):
/// the mic button (FEATURE_MEDIA), the recognition insert item and the
/// auto shape toggle of the pen popup (FEATURE_RECOGNITION), and the image
/// rows of the insert menu (never switched off — D17).
Future<Map<String, bool>> editorSwitchRows(WidgetTester tester) async {
  final rows = <String, bool>{
    '녹음 버튼': find.byKey(EditorKeys.mic).evaluate().isNotEmpty,
  };
  await tester.tap(find.byKey(EditorKeys.insert));
  await pumpUntil(
    tester,
    () => find.byKey(EditorKeys.insertImage).evaluate().isNotEmpty,
    reason: 'the insert menu',
  );
  rows['이미지 삽입'] = find.byKey(EditorKeys.insertImage).evaluate().isNotEmpty;
  rows['인식 메뉴'] = find
      .byKey(EditorKeys.extension('recog.mathPad'))
      .evaluate()
      .isNotEmpty;
  await tester.tapAt(const Offset(4, 700));
  await letRealTimePass(tester, times: 2);
  // The pen popup: the pen tool is chosen on a new note, so a press opens
  // its settings.
  await tapTool(tester, EditorKeys.pen);
  await pumpUntil(
    tester,
    () => find.byKey(EditorKeys.penSettings).evaluate().isNotEmpty,
    reason: 'the pen popup',
  );
  // '고급' (an expansion tile) holds the toggle.
  await tester.ensureVisible(find.byKey(EditorKeys.penAdvanced));
  await tester.pump();
  await tester.tap(find.byKey(EditorKeys.penAdvanced));
  await letRealTimePass(tester, times: 4);
  rows['자동 도형 보정'] = find
      .byKey(const ValueKey('editor.pen.shapeAssist'))
      .evaluate()
      .isNotEmpty;
  // Outside the popup (over the toolbar title): the popup closes.
  await tester.tapAt(tester.getCenter(find.byKey(EditorKeys.title)));
  await letRealTimePass(tester, times: 2);
  expect(find.byKey(EditorKeys.penSettings), findsNothing);
  return rows;
}
