// E-08: pen strokes through the whole editor (04-editor 6.6.2, 6.6.3, 6.7):
// PointerDriver → Listener → InputRouter → InteractionHost → PenInteraction →
// INK StrokeSession → EditorCommands.commitInkEdit → fake CORE session.
import 'package:feature_editor/src/scope/editor_scope.dart';
import 'package:feature_editor/src/state/color_palette.dart';
import 'package:feature_editor/src/tools/pen_interaction.dart';
import 'package:feature_editor/src/tools/tool_controller.dart';
import 'package:feature_editor/src/ui/editor_strings.dart';
import 'package:feature_editor/src/viewport/editor_page_view.dart';
import 'package:feature_editor/src/viewport/viewport_constants.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:note_core/note_core.dart' as core;

import '../helpers/pump_editor.dart';
import '../helpers/test_data.dart';

/// Page points of a short diagonal stroke in the upper part of a page.
const List<Offset> _points = [
  Offset(100, 150),
  Offset(130, 170),
  Offset(170, 190),
  Offset(220, 205),
  Offset(280, 215),
];

List<String> _executes(EditorTestHandles h) => [
  for (final c in h.recorder!.calls)
    if (c.startsWith('execute')) c,
];

ink.InkPageView _inkViewOf(WidgetTester tester, String pageId) =>
    tester.widget<ink.InkPageView>(
      find.descendant(
        of: find.byWidgetPredicate(
          (w) => w is EditorPageView && w.page.id == pageId,
        ),
        matching: find.byType(ink.InkPageView),
      ),
    );

void main() {
  testWidgets('a stylus stroke → one add-strokes step, one stroke', (
    tester,
  ) async {
    final h = await pumpEditor(tester);
    await h.driver.stylusStroke(pathThrough(h, 0, _points));

    expect(_executes(h), ['execute:add-strokes']);
    expect(h.session.history.undoDepth, 1);
    expect(h.session.history.undoLabel, 'add-strokes');
    final strokes = h.session.pageIfLoaded(h.pageId(0))!.strokes;
    expect(strokes, hasLength(1));
    final pen = h.container.read(editorToolProvider).currentPen;
    expect(strokes.single.style, pen.normalized());
    expect(strokes.single.pageId, h.pageId(0));
    // The controller shows the committed stroke; nothing is pending.
    final controller = h.controllerOf(0);
    expect(controller.pendingIds, isEmpty);
    expect(controller.content!.strokes.map((s) => s.id), [strokes.single.id]);
    expect(h.recorder!.executeDuringDelivery, isFalse);
  });

  testWidgets('zoomed 200% and scrolled: points land on the page pt', (
    tester,
  ) async {
    final h = await pumpEditor(tester, pages: 3);
    final viewport = h.viewport;
    viewport.zoomBy(2, viewport.viewportSize.center(Offset.zero));
    await tester.pump(ViewportConstants.settleDelay * 2);
    viewport.panBy(const Offset(120, 900));
    await tester.pump(ViewportConstants.settleDelay * 2);
    await h.settlePages();
    expect(viewport.zoom, closeTo(2, 1e-9));

    final hit = viewport.hitPage(viewport.viewportSize.center(Offset.zero))!;
    final centre = viewport.screenToPage(
      hit.index,
      viewport.viewportSize.center(Offset.zero),
    );
    // A straight path in page pt. INK (03-ink 6.6–6.7) does not store the
    // samples one to one: its One Euro filter moves a point only towards the
    // previous filtered one (one alpha for both axes, so along this line), F1
    // ends the stroke at the raw last sample and F7 (RDP) drops the collinear
    // points in between. What is checked is the screen → page pt mapping at
    // 200 % and scrolled: both ends land on their page pt and no stored point
    // leaves the path.
    final start = centre, end = centre + const Offset(5 * 7.3, 5 * 3.1);
    final pagePoints = [
      for (var i = 0; i < 6; i++) Offset.lerp(start, end, i / 5)!,
    ];
    await h.driver.stylusStroke(pathThrough(h, hit.index, pagePoints));

    final stroke = h.session.pageIfLoaded(hit.pageId)!.strokes.single;
    final points = stroke.points;
    expect(points.length, greaterThanOrEqualTo(2));
    // CORE quantization unit (0.01 pt) + 0.01 pt.
    const tolerance = 0.02;
    final last = points.length - 1;
    expect(points.x(0), closeTo(start.dx, tolerance));
    expect(points.y(0), closeTo(start.dy, tolerance));
    expect(points.x(last), closeTo(end.dx, tolerance));
    expect(points.y(last), closeTo(end.dy, tolerance));
    final path = end - start;
    final direction = path / path.distance;
    for (var i = 0; i < points.length; i++) {
      final d = Offset(points.x(i), points.y(i)) - start;
      // Distance from the line, and the position along it (within the ends).
      final across = d.dx * direction.dy - d.dy * direction.dx;
      final along = d.dx * direction.dx + d.dy * direction.dy;
      expect(across.abs(), lessThanOrEqualTo(tolerance), reason: 'point $i');
      expect(along, inInclusiveRange(-tolerance, path.distance + tolerance));
    }
  });

  testWidgets('a stroke that starts in the gap between pages is ignored', (
    tester,
  ) async {
    final h = await pumpEditor(tester);
    final viewport = h.viewport;
    // The middle of the gap under page 0.
    final rect0 = viewport.pageRectOnScreen(0);
    final gapY =
        rect0.bottom + ViewportConstants.pageGap * viewport.camera.scale / 2;
    viewport.panBy(Offset(0, rect0.bottom - 400));
    await tester.pump(ViewportConstants.settleDelay * 2);
    await h.settlePages();
    final rect = viewport.pageRectOnScreen(0);
    final gap = Offset(rect.center.dx, rect.bottom + (gapY - rect0.bottom));
    expect(viewport.hitPage(gap), isNull);

    await h.driver.stylusStroke([
      h.viewportToGlobal(gap),
      h.viewportToGlobal(gap + const Offset(0, -200)),
      h.viewportToGlobal(gap + const Offset(40, -260)),
    ]);
    expect(_executes(h), isEmpty);
    expect(h.session.pageIfLoaded(h.pageId(0))!.strokes, isEmpty);
  });

  testWidgets('a page that is still loading takes no stroke', (tester) async {
    final h = await pumpEditor(tester, settle: false);
    h.recorder!.holdPageLoads();
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }
    expect(h.mountedPages[h.pageId(0)]!.isLoaded.value, isFalse);

    await h.driver.stylusStroke(pathThrough(h, 0, _points));
    expect(_executes(h), isEmpty);

    h.recorder!.releasePageLoads();
    await h.settlePages();
    await h.driver.stylusStroke(pathThrough(h, 0, _points));
    expect(_executes(h), ['execute:add-strokes']);
  });

  testWidgets('right after the commit nothing is pending (same frame)', (
    tester,
  ) async {
    final h = await pumpEditor(tester);
    final points = pathThrough(h, 0, _points);
    final driver = h.driver;
    await driver.down(1, points.first, kind: PointerDeviceKind.stylus);
    for (final p in points.skip(1)) {
      await driver.wait(const Duration(milliseconds: 4));
      await driver.move(1, p);
    }
    // Pen up without pumping a frame afterwards.
    await tester.sendEventToBinding(
      PointerUpEvent(
        timeStamp: driver.now,
        pointer: driver.eventPointerOf(1),
        device: 1,
        kind: PointerDeviceKind.stylus,
        position: points.last,
      ),
    );
    final controller = h.controllerOf(0);
    expect(_executes(h), ['execute:add-strokes']);
    expect(controller.pendingIds, isEmpty);
    expect(controller.content!.strokes, hasLength(1));
    await tester.pump();
  });

  testWidgets('a cancelled stroke runs no command and leaves no trace', (
    tester,
  ) async {
    final h = await pumpEditor(tester);
    final points = pathThrough(h, 0, _points);
    await h.driver.down(1, points.first, kind: PointerDeviceKind.stylus);
    await h.driver.move(1, points[1]);
    await h.driver.move(1, points[2]);
    await h.driver.cancel(1);

    expect(_executes(h), isEmpty);
    final controller = h.controllerOf(0);
    expect(controller.pendingIds, isEmpty);
    expect(controller.activeSession, isNull);
    expect(controller.content!.strokes, isEmpty);
  });

  testWidgets(
    'a committed stroke puts its colour first in the recent colours',
    (tester) async {
      final h = await pumpEditor(tester);
      final tools = h.container.read(editorToolProvider.notifier);
      tools.setColor(0xFF2255AA);
      await h.driver.stylusStroke(pathThrough(h, 0, _points));
      tools.setColor(0xFFAA3311);
      await h.driver.stylusStroke(
        pathThrough(h, 0, [for (final p in _points) p + const Offset(0, 80)]),
      );
      expect(h.container.read(editorColorPaletteProvider).recent, [
        0xFFAA3311,
        0xFF2255AA,
      ]);
    },
  );

  testWidgets('a read-only note: no interaction, no command', (tester) async {
    final h = await pumpEditor(tester);
    await h.store.library.trashItems([core.NoteRef(h.noteId)]);
    await tester.pump();
    expect(h.session.isReadOnly, isTrue);
    expect(h.container.read(editorReadOnlyProvider), isTrue);

    await h.driver.stylusStroke(pathThrough(h, 0, _points));
    expect(_executes(h), isEmpty);
    expect(h.container.read(editorInteractionHostProvider).lastStarted, isNull);
    expect(h.controllerOf(0).pendingIds, isEmpty);
    expect(h.controllerOf(0).activeSession, isNull);
  });

  testWidgets(
    'a rejected commit (read-only race): discardEdit, nothing left, notice',
    (tester) async {
      final h = await pumpEditor(tester);
      final palette = h.container.read(editorColorPaletteProvider);
      h.recorder!.rejectNext(const core.ReadOnlyNoteException('race'));

      await h.driver.stylusStroke(pathThrough(h, 0, _points));
      await tester.pump(); // snackbar entrance

      expect(_executes(h), ['execute:add-strokes:rejected']);
      final controller = h.controllerOf(0);
      expect(controller.pendingIds, isEmpty);
      expect(controller.content!.strokes, isEmpty);
      expect(h.session.pageIfLoaded(h.pageId(0))!.strokes, isEmpty);
      expect(h.session.history.undoDepth, 0);
      expect(h.container.read(editorColorPaletteProvider), palette);
      expect(find.text(EditorStrings.readOnlyToast), findsOneWidget);

      // The next stroke commits normally.
      await h.driver.stylusStroke(pathThrough(h, 0, _points));
      expect(h.session.history.undoDepth, 1);
      await tester.pump(const Duration(seconds: 5)); // snackbar timer
    },
  );

  testWidgets('pen down within 150 ms of a pinch settles the viewport first', (
    tester,
  ) async {
    final h = await pumpEditor(tester);
    final viewport = h.viewport;
    final fit = viewport.camera.scale;
    await h.driver.pinch(
      center: h.viewportToGlobal(viewport.viewportSize.center(Offset.zero)),
      startSpan: 200,
      endSpan: 300,
    );
    expect(viewport.isInteracting.value, isTrue); // settle delay running
    expect(viewport.camera.scale, greaterThan(fit * 1.2));
    expect(viewport.settledScale.value, fit);

    final hit = viewport.hitPage(viewport.viewportSize.center(Offset.zero))!;
    final centre = viewport.screenToPage(
      hit.index,
      viewport.viewportSize.center(Offset.zero),
    );
    final points = pathThrough(h, hit.index, [
      centre,
      centre + const Offset(20, 10),
      centre + const Offset(40, 15),
    ]);
    await h.driver.down(1, points.first, kind: PointerDeviceKind.stylus);

    final pen =
        h.container.read(editorInteractionHostProvider).lastStarted!
            as PenInteraction;
    expect(viewport.isInteracting.value, isFalse);
    expect(viewport.settledScale.value, viewport.camera.scale);
    expect(pen.viewScale, viewport.camera.scale);
    final view = _inkViewOf(tester, hit.pageId);
    expect(view.ancestorScale, 1);
    expect(view.isScaling, isFalse);
    // viewScale = InkPageView's layout scale (logical px per pt).
    final laidOut = tester.getSize(
      find.byWidgetPredicate(
        (w) => w is EditorPageView && w.page.id == hit.pageId,
      ),
    );
    expect(
      laidOut.width / h.session.pages[hit.index].size.width,
      closeTo(pen.viewScale, 1e-9),
    );

    for (final p in points.skip(1)) {
      await h.driver.move(1, p);
    }
    await h.driver.up(1);
    final stroke = h.session.pageIfLoaded(hit.pageId)!.strokes.single;
    expect(stroke.points.x(0), closeTo(centre.dx, 0.02));
    expect(stroke.points.y(0), closeTo(centre.dy, 0.02));
  });
}
