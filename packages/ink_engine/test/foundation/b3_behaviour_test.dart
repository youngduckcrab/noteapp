// Foundation step B3 behaviour (03-ink 4.15 table): the simple-but-working bodies other
// areas rely on from day one — InkEdit.toCommand (final), InkPageContent.fromCore,
// InkSampleAdapter, pending hand-off (updateContent / discardPending / discardEdit /
// timeout), selection edits, viewport report (6.12 R9), providers, InkDevTools.
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/dev_tools.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/testing.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart' as core_testing;
import 'package:riverpod/riverpod.dart';

core.Stroke _stroke(
  String id, {
  int createdAt = 0,
  String pageId = 'p1',
  core.PenTool tool = core.PenTool.ballpoint,
  List<ui.Offset> points = const [ui.Offset(10, 10), ui.Offset(20, 10)],
}) => core.Stroke(
  id: id,
  pageId: pageId,
  style: core.StrokeStyle.defaultsFor(tool),
  points: core.StrokePoints.fromList([
    for (final p in points) core.StrokePoint(p.dx, p.dy),
  ]),
  createdAt: createdAt,
);

void main() {
  group('InkEdit.toCommand (contract 7.2.15 table)', () {
    final s = _stroke('a');
    test('every kind maps to its CORE command', () {
      expect(
        InkEdit(
          pageId: 'p1',
          kind: InkEditKind.addStroke,
          added: [s],
        ).toCommand(),
        isA<core.AddStrokes>().having((c) => c.strokes, 'strokes', [s]),
      );
      expect(
        InkEdit(
          pageId: 'p1',
          kind: InkEditKind.duplicateStrokes,
          added: [s],
        ).toCommand(),
        isA<core.AddStrokes>(),
      );
      for (final kind in [
        InkEditKind.eraseStrokes,
        InkEditKind.deleteStrokes,
      ]) {
        expect(
          InkEdit(pageId: 'p1', kind: kind, removedIds: {'b', 'a'}).toCommand(),
          isA<core.RemoveStrokes>().having((c) => c.strokeIds, 'ids', [
            'b',
            'a',
          ]),
        );
      }
      expect(
        InkEdit(
          pageId: 'p1',
          kind: InkEditKind.splitStrokes,
          removedIds: {'a'},
          added: [s],
        ).toCommand(),
        isA<core.SplitStrokes>(),
      );
      expect(
        const InkEdit(
          pageId: 'p1',
          kind: InkEditKind.splitStrokes,
          removedIds: {'a'},
        ).toCommand(),
        isA<core.RemoveStrokes>(),
      );
      final m = core.Affine2.translation(1, 2);
      expect(
        InkEdit(
          pageId: 'p1',
          kind: InkEditKind.transformStrokes,
          targetIds: {'a'},
          transform: m,
        ).toCommand(),
        isA<core.TransformElements>()
            .having((c) => c.transform, 'transform', m)
            .having((c) => c.scaleStrokeWidth, 'scaleStrokeWidth', true),
      );
      expect(
        const InkEdit(
          pageId: 'p1',
          kind: InkEditKind.recolorStrokes,
          targetIds: {'a'},
          colorArgb: 0xFF112233,
        ).toCommand(),
        isA<core.RestyleStrokes>().having(
          (c) => c.patch,
          'patch',
          const core.StrokeStylePatch(colorArgb: 0xFF112233),
        ),
      );
    });

    test('empty edits throw StateError', () {
      for (final kind in InkEditKind.values) {
        final edit = InkEdit(pageId: 'p1', kind: kind);
        expect(edit.isEmpty, isTrue, reason: kind.name);
        expect(edit.toCommand, throwsStateError, reason: kind.name);
      }
    });
  });

  group('InkPageContent.fromCore', () {
    test('sorts, drops deleted strokes, keeps InkStroke identity', () {
      final a = _stroke('a', createdAt: 5);
      final b = _stroke('b', createdAt: 1);
      final gone = _stroke('c', createdAt: 3).copyWith(deletedAt: 9);
      final content = SyntheticInk.pageContent(strokes: [a, b, gone]);
      expect(content.strokes.map((s) => s.id), ['b', 'a']);
      expect(content.zIndexOf('a'), 1);
      expect(content.strokeById('c'), isNull);
      expect(identical(content.strokeById('a'), InkStroke.of(a)), isTrue);
      expect(content.strokeById('a')!.bounds.left, a.bounds.left);
    });

    test('a stroke of another page is an ArgumentError', () {
      expect(
        () => SyntheticInk.pageContent(strokes: [_stroke('x', pageId: 'p2')]),
        throwsArgumentError,
      );
    });
  });

  test('InkSampleAdapter normalizes events (6.3)', () {
    final down = InkSampleAdapter.fromPointerEvent(
      const PointerDownEvent(
        kind: ui.PointerDeviceKind.stylus,
        pressure: 2,
        pressureMin: 0,
        pressureMax: 4,
        tilt: -0.5,
        timeStamp: Duration(milliseconds: 3),
      ),
      pagePosition: const Offset(4, 5),
    );
    expect(down.kind, InkPointerKind.stylus);
    expect(down.tilt, 0.5);
    expect(down.timeUs, 3000);
    expect(down.normalizedPressure, 0.5);
    final up = InkSampleAdapter.fromPointerEvent(
      const PointerUpEvent(kind: ui.PointerDeviceKind.stylus, pressure: 0),
      pagePosition: Offset.zero,
    );
    expect(up.pressure, isNull);
    final mouse = InkSampleAdapter.fromPointerEvent(
      const PointerMoveEvent(kind: ui.PointerDeviceKind.mouse),
      pagePosition: Offset.zero,
    );
    expect([mouse.kind, mouse.pressure], [InkPointerKind.mouse, null]);
  });

  test('PenProfile and StrokeStyle.defaultsFor match 03-ink 6.9', () {
    final rows = {
      core.PenTool.ballpoint: (0xFF1A1A1A, 1.6, 1.0, 0.5),
      core.PenTool.fountain: (0xFF1B2A6B, 2.2, 1.0, 0.55),
      core.PenTool.highlighter: (0xFFFFE600, 12.0, 0.35, 0.3),
      core.PenTool.pencil: (0xFF3C3C3C, 1.4, 0.9, 0.4),
      core.PenTool.marker: (0xFF1A1A1A, 5.0, 1.0, 0.5),
    };
    rows.forEach((tool, row) {
      final s = core.StrokeStyle.defaultsFor(tool);
      expect((s.colorArgb, s.width, s.opacity, s.smoothing), row);
    });
    expect(core.StrokeStyle.defaultsFor(core.PenTool.highlighter).extras, {
      InkStyleExtras.highlighterStraightening: 'off',
    });
    expect(PenProfile.of(core.PenTool.laser), PenProfile.ballpoint);
    expect(PenProfile.fountain.pressureGain, 0.75);
    expect(PenProfile.pencil.textured, isTrue);
    expect(PenProfile.highlighter.groupComposite, isTrue);
    final style = core.StrokeStyle.defaultsFor(core.PenTool.highlighter)
        .copyWith(extras: {'other': 1, 'hlStraight': 'bogus'});
    expect(style.highlighterStraightening, HighlighterStraightening.off);
    final straight = style.withHighlighterStraightening(
      HighlighterStraightening.alwaysStraight,
    );
    expect(straight.extras, {'other': 1, 'hlStraight': 'alwaysStraight'});
  });

  group('pending hand-off (6.12 R6)', () {
    late InkPageController c;
    late FakeInkClock clock;
    setUp(() {
      clock = FakeInkClock();
      c = createTestPageController(clock: clock)
        ..updateContent(
          SyntheticInk.pageContent(strokes: [_stroke('a'), _stroke('b')]),
        );
    });
    tearDown(() => c.dispose());

    InkEdit eraseAll() {
      final e = c.beginErase(
        const InkSample(
          position: Offset(15, 10),
          timeUs: 0,
          kind: InkPointerKind.stylus,
        ),
        spec: const EraserSpec(mode: EraserMode.stroke, radius: 2),
        viewScale: 1,
      );
      return e.end()!;
    }

    test('discardEdit drops every id of the edit at once', () {
      final edit = eraseAll();
      expect(edit.removedIds, {'a', 'b'});
      expect(c.pendingIds, {'a', 'b'});
      expect(c.hitTest(const Offset(15, 10)), isNull);
      c.discardEdit(edit);
      expect(c.pendingIds, isEmpty);
      expect(c.hitTest(const Offset(15, 10))!.id, 'b');
    });

    test('discardPending drops one id only', () {
      eraseAll();
      c.discardPending('a');
      expect(c.pendingIds, {'b'});
    });

    test('updateContent resolves the pending edit', () {
      final edit = eraseAll();
      c.updateContent(SyntheticInk.pageContent(revision: 2));
      expect(c.pendingIds, isEmpty);
      expect(c.renderStats.pendingCommits, 0);
      expect(edit.toCommand(), isA<core.RemoveStrokes>());
    });

    test('the timeout drops a forgotten pending edit with a warning', () {
      c.diagnostics.enabled = true;
      eraseAll();
      clock.advanceMs(3001);
      c.updateContent(
        SyntheticInk.pageContent(
          strokes: [_stroke('a'), _stroke('b')],
          revision: 2,
        ),
      );
      expect(c.pendingIds, isEmpty);
      expect(c.diagnostics.snapshot.warnings, 1);
    });

    test('a new session cancels the active one; ended sessions throw', () {
      final first = SyntheticInk.line(Offset.zero, const Offset(5, 5));
      final s1 = c.beginStroke(
        first.first,
        style: core.StrokeStyle.defaultsFor(core.PenTool.pencil),
        viewScale: 2,
      );
      final lasso = c.beginLasso(Offset.zero, viewScale: 2);
      expect(s1.isActive, isFalse);
      expect(c.activeSession, same(lasso));
      expect(() => s1.addSample(first.last), throwsStateError);
      lasso.cancel();
      expect(c.activeSession, isNull);
      expect(
        () => c.beginErase(
          first.first,
          spec: const EraserSpec(mode: EraserMode.stroke, radius: 0),
          viewScale: 1,
        ),
        throwsArgumentError,
      );
    });
  });

  group('selection edits', () {
    late InkPageController c;
    setUp(() {
      c =
          createTestPageController(
            services: testInkCoreServices(idPrefix: 'n', startMillis: 500),
          )..updateContent(
            SyntheticInk.pageContent(
              strokes: [
                _stroke('a', createdAt: 1),
                _stroke('b', createdAt: 2, tool: core.PenTool.highlighter),
              ],
            ),
          );
    });
    tearDown(() => c.dispose());

    test('select ignores unknown ids; duplicate / recolor / delete', () {
      final sel = c.select({'b', 'a', 'zz'});
      expect(sel.strokeIds.toList(), ['a', 'b']);
      expect(c.selection, same(sel));
      final dup = sel.duplicate();
      expect(dup.kind, InkEditKind.duplicateStrokes);
      expect(dup.added.map((s) => s.id), ['n-000001', 'n-000002']);
      expect(dup.added.map((s) => s.createdAt), [500, 501]);
      expect(dup.added.first.points.x(0), 26);
      expect(dup.added.first.style.width, sel.strokes.first.style.width);
      expect(dup.added.every((s) => s.version == null), isTrue);
      final recolor = sel.recolor(0x00123456);
      expect(recolor.colorArgb, 0xFF123456);
      expect(sel.delete().removedIds, {'a', 'b'});
      expect(c.select(const {'zz'}).isEmpty, isTrue);
      expect(c.selection, isNull);
      expect(sel.isDisposed, isTrue);
    });

    test('identity preview → no transform edit; strokes gone → disposed', () {
      final sel = c.select({'a'});
      expect(sel.commitTransform(), isNull);
      sel.setPreviewTransform(SelectionGeometry.move(const Offset(3, 0)));
      final edit = sel.commitTransform()!;
      c.discardEdit(edit);
      expect(sel.previewTransform.isIdentity, isTrue);
      c.updateContent(SyntheticInk.pageContent(revision: 5));
      expect(sel.isDisposed, isTrue);
      expect(c.selection, isNull);
    });
  });

  testWidgets('InkPageView reports the viewport after layout (6.12 R9)', (
    tester,
  ) async {
    tester.view
      ..devicePixelRatio = 2
      ..physicalSize = const Size(1400, 1800);
    addTearDown(tester.view.reset);
    final c = createTestPageController()
      ..updateContent(SyntheticInk.pageContent(strokes: [_stroke('a')]));
    addTearDown(c.dispose);
    var notified = 0;
    c.addListener(() => notified++);
    Widget view(double ancestorScale) => Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: core.PageSize.a4Portrait.width,
          child: InkPageView(controller: c, ancestorScale: ancestorScale),
        ),
      ),
    );
    await tester.pumpWidget(view(1));
    expect(c.renderStats.currentBucket, 2.0);
    await tester.pumpWidget(view(1.5));
    expect(c.renderStats.currentBucket, 3.0);
    await tester.pumpWidget(view(5));
    expect(c.renderStats.currentBucket, isNull);
    expect(notified, 0);
    expect(tester.takeException(), isNull);
  });

  test('providers build a controller from the CORE store', () {
    final store = core_testing.createFakeNoteStore();
    final container = ProviderContainer(
      overrides: [core.noteStoreProvider.overrideWithValue(store)],
    );
    addTearDown(() async {
      container.dispose();
      await store.close();
    });
    final sub = container.listen(inkPageControllerProvider('p1'), (_, _) {});
    final controller = sub.read();
    expect(controller.pageId, 'p1');
    // (v2.0) default = defaultPageBackgroundBuilders(ref) = [image, template]
    expect(controller.backgroundBuilders, [
      isA<ImageBackgroundLayerBuilder>(),
      const TemplateBackgroundLayerBuilder(),
    ]);
    expect(controller.services.newStrokeId(), isNotEmpty);
    container.read(pressureModeProvider.notifier).set(PressureMode.alwaysReal);
    expect(controller.pressureMode(), PressureMode.alwaysReal);
    expect(container.read(inkPageThumbnailRendererProvider), isNotNull);
    expect(inkPageControllerProvider.name, 'inkPageControllerProvider');
    expect(
      pageBackgroundBuildersProvider.name,
      'pageBackgroundBuildersProvider',
    );
    sub.close();
  });

  test(
    'InkDevTools.syntheticStrokes is deterministic and stays on the page',
    () {
      List<core.Stroke> make() => InkDevTools.syntheticStrokes(
        pageId: 'p1',
        pageSize: core.PageSize.a4Portrait,
        count: 20,
        newId: core.SequentialIdGenerator(prefix: 'g').newId,
        createdAt: 100,
        seed: 7,
      );
      final a = make(), b = make();
      expect(a, hasLength(20));
      for (var i = 0; i < a.length; i++) {
        expect(a[i].points.contentEquals(b[i].points), isTrue);
        expect(a[i].createdAt, 100 + i);
        expect(a[i].version, isNull);
        expect(
          a[i].style,
          core.StrokeStyle.defaultsFor(core.PenTool.ballpoint),
        );
        expect(a[i].points.length, inInclusiveRange(40, 160));
        final r = a[i].points.pointBounds;
        expect(r.left >= 0 && r.top >= 0, isTrue);
        expect(r.right <= 595.2756 && r.bottom <= 841.8898, isTrue);
      }
      final hl = InkDevTools.syntheticStrokes(
        pageId: 'p1',
        pageSize: core.PageSize.a4Portrait,
        count: 1,
        newId: () => 'h',
        createdAt: 0,
        tool: core.PenTool.highlighter,
      ).single;
      expect(hl.points.maxWidthQ, core.kNominalWidthQ);
      expect(core.AddStrokes(pageId: 'p1', strokes: a), isNotNull);
    },
  );
}
