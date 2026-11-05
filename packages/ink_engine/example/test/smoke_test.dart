// ink lab smoke test (03-ink T23): the lab opens a note on the CORE fake
// store, a stylus stroke with each pen is committed through the CORE session,
// the stroke eraser and the partial eraser remove strokes, the lasso selects
// and moves a stroke (TransformElements), synthetic strokes load, the paper
// cycles, and the developer numbers show the stylus pressure.
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_lab/src/ink_lab.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart' as core_testing;

void main() {
  late core.NoteStore store;

  setUp(() => store = core_testing.createFakeNoteStore());
  tearDown(() => store.close());

  Future<InkLabPageState> pumpLab(WidgetTester tester) async {
    tester.view
      ..devicePixelRatio = 2
      ..physicalSize = const Size(1032, 1376) * 2; // iPad Pro 13" portrait
    addTearDown(tester.view.reset);
    await tester.pumpWidget(InkLabApp(store: store));
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }
    final state = tester.state<InkLabPageState>(find.byType(InkLabPage));
    expect(state.controller, isNotNull, reason: 'the note page is open');
    expect(find.byType(InkPageView), findsOneWidget);
    return state;
  }

  List<core.Stroke> strokesOf(InkLabPageState lab) =>
      lab.session!.pageIfLoaded(lab.pageId!)!.strokes;

  /// Page pt → global position of the page view.
  Offset at(WidgetTester tester, InkLabPageState lab, Offset pagePt) {
    final view = find.byType(InkPageView);
    final topLeft = tester.getTopLeft(view);
    final width = tester.getSize(view).width;
    final scale = width / lab.controller!.content!.pageSize.width;
    return topLeft + pagePt * scale;
  }

  var nextPointer = 20;

  /// One stylus drag through page points [from] → [to] (pressure rising),
  /// sent as raw pointer events.
  Future<void> stylusLine(
    WidgetTester tester,
    InkLabPageState lab,
    Offset from,
    Offset to, {
    PointerDeviceKind kind = PointerDeviceKind.stylus,
    int steps = 24,
  }) async {
    final pointer = nextPointer++;
    Offset pos(int i) => at(tester, lab, Offset.lerp(from, to, i / steps)!);
    Duration time(int i) => Duration(milliseconds: 8 * i);
    double pressure(int i) => 0.3 + 0.5 * i / steps;
    await tester.sendEventToBinding(
      PointerDownEvent(
        timeStamp: time(0),
        pointer: pointer,
        kind: kind,
        position: pos(0),
        pressure: pressure(0),
        pressureMin: 0,
        pressureMax: 1,
      ),
    );
    for (var i = 1; i <= steps; i++) {
      await tester.sendEventToBinding(
        PointerMoveEvent(
          timeStamp: time(i),
          pointer: pointer,
          kind: kind,
          position: pos(i),
          pressure: pressure(i),
          pressureMin: 0,
          pressureMax: 1,
          buttons: kPrimaryButton,
        ),
      );
    }
    await tester.sendEventToBinding(
      PointerUpEvent(
        timeStamp: time(steps + 1),
        pointer: pointer,
        kind: kind,
        position: pos(steps),
        pressureMin: 0,
        pressureMax: 1,
      ),
    );
    await tester.pump();
  }

  Future<void> choose(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(ValueKey(key)));
    await tester.pump();
  }

  testWidgets('pens, erasers, lasso, synthetic strokes, paper, numbers', (
    tester,
  ) async {
    final lab = await pumpLab(tester);
    expect(strokesOf(lab), isEmpty);

    // the five pens: one committed CORE stroke each
    final pens = [
      LabTool.ballpoint,
      LabTool.fountain,
      LabTool.highlighter,
      LabTool.pencil,
      LabTool.marker,
    ];
    for (var i = 0; i < pens.length; i++) {
      await choose(tester, 'tool-${pens[i].name}');
      final y = 80.0 + 60 * i;
      await stylusLine(tester, lab, Offset(60, y), Offset(400, y + 10));
      final strokes = strokesOf(lab);
      expect(strokes, hasLength(i + 1));
      expect(strokes.last.style.tool, pens[i].pen);
    }
    expect(lab.controller!.pendingIds, isEmpty);

    // developer numbers: the stylus pressure reached INK
    final numbers = lab.diagnostics.snapshot;
    expect(numbers.lastKind, InkPointerKind.stylus);
    expect(numbers.stylusCapability, PressureCapability.supported);
    expect(find.textContaining('stylusCapability: supported'), findsOneWidget);

    // stroke eraser across the ballpoint line
    await choose(tester, 'tool-strokeEraser');
    await stylusLine(
      tester,
      lab,
      const Offset(200, 60),
      const Offset(200, 100),
    );
    expect(
      strokesOf(lab).map((s) => s.style.tool),
      isNot(contains(core.PenTool.ballpoint)),
    );

    // the inverted stylus (eraser end) erases whatever tool is chosen
    await choose(tester, 'tool-fountain');
    await stylusLine(
      tester,
      lab,
      const Offset(200, 125),
      const Offset(200, 165),
      kind: PointerDeviceKind.invertedStylus,
    );
    expect(strokesOf(lab), hasLength(3));

    // partial eraser across the pencil line: the original stroke goes (whole
    // in the B3 body; split into new fragments from INK T16)
    final pencil = strokesOf(lab)
        .singleWhere((s) => s.style.tool == core.PenTool.pencil);
    await choose(tester, 'tool-partialEraser');
    await stylusLine(
      tester,
      lab,
      const Offset(220, 245),
      const Offset(220, 290),
    );
    expect(strokesOf(lab).any((s) => s.id == pencil.id), isFalse);

    // lasso around the marker line, then drag it down 100 pt
    await choose(tester, 'tool-lasso');
    final marker = strokesOf(lab)
        .singleWhere((s) => s.style.tool == core.PenTool.marker);
    final g = await tester.createGesture(kind: PointerDeviceKind.stylus);
    final loop = [
      const Offset(40, 300),
      const Offset(420, 300),
      const Offset(420, 350),
      const Offset(40, 350),
      const Offset(40, 302),
    ];
    await g.down(at(tester, lab, loop.first));
    for (final p in loop.skip(1)) {
      await g.moveTo(at(tester, lab, p));
    }
    await g.up();
    await tester.pump();
    expect(lab.controller!.selection?.strokeIds, {marker.id});
    final before = marker.bounds;
    final center = Offset(
      (before.left + before.right) / 2,
      (before.top + before.bottom) / 2,
    );
    final drag = await tester.createGesture(kind: PointerDeviceKind.stylus);
    await drag.down(at(tester, lab, center));
    await drag.moveTo(at(tester, lab, center + const Offset(0, 50)));
    await drag.moveTo(at(tester, lab, center + const Offset(0, 100)));
    await drag.up();
    await tester.pump();
    final moved = strokesOf(lab).singleWhere((s) => s.id == marker.id);
    expect(moved.bounds.top, closeTo(before.top + 100, 0.5));

    // delete the selection, then undo brings it back
    await choose(tester, 'delete-selection');
    expect(strokesOf(lab).any((s) => s.id == marker.id), isFalse);
    await choose(tester, 'undo');
    await tester.pump();
    expect(strokesOf(lab).any((s) => s.id == marker.id), isTrue);

    // synthetic strokes (EDITOR developer menu stand-in)
    final n = strokesOf(lab).length;
    await choose(tester, 'synthetic-1000');
    expect(strokesOf(lab), hasLength(n + 1000));
    expect(lab.controller!.content!.strokes, hasLength(n + 1000));

    // paper: next template, dark paper
    await choose(tester, 'template');
    expect(
      lab.controller!.content!.background.template?.kind,
      core.PageTemplateKind.lined,
    );
    await choose(tester, 'dark-paper');
    expect(lab.controller!.content!.background.isDarkPaper, isTrue);

    // pressure mode cycles through the provider
    await choose(tester, 'pressure-mode');
    expect(find.textContaining('Pressure: alwaysReal'), findsOneWidget);

    // zoom 2×: the page view is twice as wide
    final w1 = tester.getSize(find.byType(InkPageView)).width;
    await choose(tester, 'zoom-2');
    expect(
      tester.getSize(find.byType(InkPageView)).width,
      closeTo(2 * w1, 0.5),
    );

    // a finger scrolls instead of drawing unless 'Finger draws' is on
    final count = strokesOf(lab).length;
    await choose(tester, 'tool-ballpoint');
    await tester.dragFrom(
      at(tester, lab, const Offset(100, 100)),
      const Offset(0, -40),
      kind: PointerDeviceKind.touch,
    );
    await tester.pump();
    expect(strokesOf(lab), hasLength(count));

    // close the lab: the container and its diagnostics timers go away
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
