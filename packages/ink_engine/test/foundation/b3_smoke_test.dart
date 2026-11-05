// Foundation step B3 smoke test (03-ink 8 T00, contract 00-overview 7.6 B3):
// synthetic pen input → end() → toCommand() → CORE createFakeNoteStore() session
// execute → pageChanges listener updateContent → pendingIds empty + polyline pixels;
// eraser (both modes) → RemoveStrokes; lasso → selection → move commit →
// TransformElements; thumbnail renderer PNG (decode, size, contentRevision).
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/testing.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart' as core_testing;

void main() {
  late core.NoteStore store;
  late core.NoteSession session;
  late String pageId;
  late InkPageController controller;
  late StreamSubscription<core.PageContentChange> sub;
  final viewKey = GlobalKey();

  InkPageContent inkContentOf(core.PageContent c) => InkPageContent.fromCore(
    page: c.page,
    strokes: c.strokes,
    revision: c.revision,
  );

  /// One pen stroke through [samples], committed through the CORE session.
  InkEdit drawAndCommit(List<InkSample> samples, {core.PenTool? tool}) {
    final s = controller.beginStroke(
      samples.first,
      style: core.StrokeStyle.defaultsFor(tool ?? core.PenTool.marker),
      viewScale: 1,
    );
    s.addSamples(samples.skip(1));
    final edit = s.end(samples.last)!;
    session.execute(edit.toCommand());
    return edit;
  }

  Future<ByteData> capture(WidgetTester tester) async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(viewKey),
    );
    final bytes = await tester.runAsync(() async {
      final image = await boundary.toImage();
      try {
        return (await image.toByteData())!;
      } finally {
        image.dispose();
      }
    });
    return bytes!;
  }

  /// RGBA at logical (x, y) of the captured view (device pixel ratio 1).
  List<int> pixel(ByteData bytes, int width, int x, int y) {
    final o = (y * width + x) * 4;
    return [
      bytes.getUint8(o),
      bytes.getUint8(o + 1),
      bytes.getUint8(o + 2),
      bytes.getUint8(o + 3),
    ];
  }

  setUp(() async {
    store = core_testing.createFakeNoteStore();
    final note = await store.library.createNote(title: 'b3 smoke');
    session = await store.openSession(note.id);
    pageId = session.pages.single.id;
    final loaded = await session.openPage(pageId);
    controller = createTestPageController(pageId: pageId)
      ..updateContent(inkContentOf(loaded));
    sub = session
        .pageChanges(pageId)
        .listen((c) => controller.updateContent(inkContentOf(c.content)));
  });

  tearDown(() async {
    await sub.cancel();
    controller.dispose();
    await session.close();
    await store.close();
  });

  Future<void> pumpView(WidgetTester tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(600, 860);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: RepaintBoundary(
            key: viewKey,
            child: SizedBox(
              width: core.PageSize.a4Portrait.width,
              child: InkPageView(controller: controller),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('pen: end → toCommand → execute → pending cleared, pixels', (
    tester,
  ) async {
    await pumpView(tester);
    final before = await capture(tester);
    final width = core.PageSize.a4Portrait.width.floor();
    expect(pixel(before, width, 200, 100), [255, 255, 255, 255]);

    final samples = SyntheticInk.line(
      const Offset(100, 100),
      const Offset(300, 100),
      samples: 20,
    );
    final s = controller.beginStroke(
      samples.first,
      style: core.StrokeStyle.defaultsFor(core.PenTool.marker),
      viewScale: 1,
    );
    expect(controller.activeSession, same(s));
    s.addSamples(samples.skip(1));
    final edit = s.end(samples.last)!;
    expect(s.isActive, isFalse);
    expect(edit.kind, InkEditKind.addStroke);
    final stroke = edit.added.single;
    expect(stroke.pageId, pageId);
    expect(stroke.version, isNull);
    expect(stroke.points.widthQ(0), core.kNominalWidthQ);
    expect(controller.pendingIds, {stroke.id});

    final command = edit.toCommand();
    expect(command, isA<core.AddStrokes>());
    session.execute(command);
    // N-1: pageChanges → updateContent ran inside execute.
    expect(controller.pendingIds, isEmpty);
    expect(controller.content!.strokes.single.id, stroke.id);
    expect(controller.renderStats.strokeCount, 1);

    await tester.pump();
    final after = await capture(tester);
    final ink = pixel(after, width, 200, 100);
    expect(ink[0], lessThan(80), reason: 'marker ink at the line');
    expect(pixel(after, width, 200, 300), [255, 255, 255, 255]);
    // 6.12 R9: the view reported the viewport after the first frame (DPR 1).
    expect(controller.renderStats.currentBucket, 1.0);
  });

  testWidgets('eraser: stroke and partial modes → RemoveStrokes', (
    tester,
  ) async {
    await pumpView(tester);
    final first = drawAndCommit(
      SyntheticInk.line(const Offset(50, 50), const Offset(150, 50)),
    );
    final eraser = controller.beginErase(
      const InkSample(
        position: Offset(100, 52),
        timeUs: 0,
        kind: InkPointerKind.stylus,
      ),
      spec: const EraserSpec(mode: EraserMode.stroke, radius: 4),
      viewScale: 1,
    );
    expect(eraser.touchedStrokeIds, {first.added.single.id});
    final erase = eraser.end()!;
    expect(erase.kind, InkEditKind.eraseStrokes);
    final eraseCommand = erase.toCommand();
    expect(eraseCommand, isA<core.RemoveStrokes>());
    expect((eraseCommand as core.RemoveStrokes).strokeIds, [
      first.added.single.id,
    ]);
    session.execute(eraseCommand);
    expect(controller.content!.strokes, isEmpty);
    expect(controller.pendingIds, isEmpty);

    final second = drawAndCommit(
      SyntheticInk.line(const Offset(50, 200), const Offset(150, 200)),
    );
    final partial = controller.beginErase(
      const InkSample(
        position: Offset(20, 260),
        timeUs: 0,
        kind: InkPointerKind.stylus,
      ),
      spec: const EraserSpec(mode: EraserMode.partial, radius: 3),
      viewScale: 1,
    );
    expect(partial.touchedStrokeIds, isEmpty);
    // Fast move: the swept capsule between samples still touches the stroke.
    partial.addSample(
      const InkSample(
        position: Offset(100, 150),
        timeUs: 8000,
        kind: InkPointerKind.stylus,
      ),
    );
    expect(partial.touchedStrokeIds, {second.added.single.id});
    final split = partial.end()!;
    expect(split.kind, InkEditKind.splitStrokes);
    expect(split.added, isEmpty);
    final splitCommand = split.toCommand();
    expect(splitCommand, isA<core.RemoveStrokes>());
    session.execute(splitCommand);
    expect(controller.content!.strokes, isEmpty);
    expect(controller.pendingIds, isEmpty);

    // Nothing touched → null.
    final miss = controller.beginErase(
      const InkSample(
        position: Offset(400, 700),
        timeUs: 0,
        kind: InkPointerKind.stylus,
      ),
      spec: const EraserSpec(mode: EraserMode.stroke, radius: 4),
      viewScale: 1,
    );
    expect(miss.end(), isNull);
    await tester.pump();
  });

  testWidgets('lasso → selection → move commit → TransformElements', (
    tester,
  ) async {
    await pumpView(tester);
    final inside = drawAndCommit(
      SyntheticInk.line(const Offset(100, 100), const Offset(140, 120)),
    ).added.single;
    final outside = drawAndCommit(
      SyntheticInk.line(const Offset(400, 600), const Offset(450, 620)),
    ).added.single;

    final lasso = controller.beginLasso(const Offset(60, 60), viewScale: 1)
      ..addPoint(const Offset(200, 60))
      ..addPoint(const Offset(200, 200))
      ..addPoint(const Offset(60, 200));
    expect(lasso.points, hasLength(4));
    final selection = lasso.end()!;
    expect(controller.selection, same(selection));
    expect(selection.strokeIds, {inside.id});
    expect(selection.strokeIds, isNot(contains(outside.id)));

    final before = controller.content!.strokeById(inside.id)!.bounds;
    selection.setPreviewTransform(SelectionGeometry.move(const Offset(10, 20)));
    expect(selection.previewBounds, before.shift(const Offset(10, 20)));
    await tester.pump();
    final edit = selection.commitTransform()!;
    expect(edit.kind, InkEditKind.transformStrokes);
    final command = edit.toCommand();
    expect(command, isA<core.TransformElements>());
    final transform = command as core.TransformElements;
    expect(transform.elementIds, [inside.id]);
    expect(transform.transform, core.Affine2.translation(10, 20));
    expect(transform.scaleStrokeWidth, isTrue);
    session.execute(command);

    expect(controller.pendingIds, isEmpty);
    expect(selection.previewTransform.isIdentity, isTrue);
    final moved = controller.content!.strokeById(inside.id)!.bounds;
    expect(moved.left, closeTo(before.left + 10, 0.02));
    expect(moved.top, closeTo(before.top + 20, 0.02));
    expect(controller.selection, same(selection));
    await tester.pump();
  });

  testWidgets('thumbnail renderer: PNG, size, pageId, contentRevision', (
    tester,
  ) async {
    drawAndCommit(
      SyntheticInk.line(const Offset(100, 100), const Offset(300, 400)),
    );
    final content = session.pageIfLoaded(pageId)!;
    expect(content.page.contentRevision, greaterThan(0));
    final renderer = InkPageThumbnailRenderer(
      backgroundBuilders: const [TemplateBackgroundLayerBuilder()],
    );
    final thumb = (await tester.runAsync(
      () => renderer.render(content, maxSidePx: 256),
    ))!;
    expect(thumb.pageId, pageId);
    expect(thumb.contentRevision, content.page.contentRevision);
    expect(thumb.mimeType, 'image/png');
    expect(thumb.height, 256); // A4 portrait: the long side is the height
    expect(thumb.width, (256 * 595.2756 / 841.8898).round());
    final decoded = await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(thumb.bytes);
      final frame = await codec.getNextFrame();
      final size = (frame.image.width, frame.image.height);
      frame.image.dispose();
      codec.dispose();
      return size;
    });
    expect(decoded, (thumb.width, thumb.height));

    // pdf background without a still renderer that handles it → null (7.2.16 v1.1).
    final pdfContent = core.PageContent(
      page: content.page.copyWith(
        background: const core.PdfBackground(assetId: 'a', pdfPageIndex: 0),
      ),
      strokes: const [],
      revision: 0,
    );
    expect(await tester.runAsync(() => renderer.render(pdfContent)), isNull);
    // still renderer returning null → null; a working one → a PNG.
    final missing = InkPageThumbnailRenderer(
      backgroundBuilders: const [
        SolidBackgroundBuilder(stillReturnsNull: true),
      ],
    );
    expect(await tester.runAsync(() => missing.render(pdfContent)), isNull);
    final solid = InkPageThumbnailRenderer(
      backgroundBuilders: const [SolidBackgroundBuilder()],
    );
    final pdfThumb = await tester.runAsync(
      () => solid.render(pdfContent, maxSidePx: 64),
    );
    expect(pdfThumb!.height, 64);
  });
}
