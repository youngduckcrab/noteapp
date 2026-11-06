// T24 (m5-7/03-ink 8.1 — api_surface v2.1): every 2nd round contract 7.2.9 name,
// constructor, method and getter, referenced with the contract types (typed
// tear-offs, typed locals, interfaces implemented member by member), so a
// renamed / retyped / removed member breaks the build. Round 1 lives in
// api_surface_test.dart; the exact exported names in export_list_test.dart.
@TestOn('vm')
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/testing.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart';
import 'package:riverpod/riverpod.dart';

final class _Fitter implements InkShapeFitter {
  @override
  InkShapeFit? fit(List<Offset> points, {required double viewScale}) => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('7.2.9 style extras, render method, layers', () {
    const List<String> keys = [
      InkStyleExtras.highlighterStraightening,
      InkStyleExtras.nibAngleDeg,
      InkStyleExtras.nibAspect,
      InkStyleExtras.followBarrelRoll,
      InkStyleExtras.dash,
      InkStyleExtras.laserFadeMs,
      InkStyleExtras.tapeStyle,
    ];
    expect(keys, hasLength(7));
    expect(InkTapeStyle.values, [InkTapeStyle.solid, InkTapeStyle.striped]);
    final style = core.StrokeStyle.defaultsFor(core.PenTool.calligraphy);
    final double angle = style.nibAngleDeg;
    final double aspect = style.nibAspect;
    final bool roll = style.followBarrelRoll;
    final List<double> dash = style.dashPattern;
    final int fade = style.laserFadeMs;
    final InkTapeStyle tape = style.tapeStyle;
    final core.StrokeStyle Function({
      double? nibAngleDeg,
      double? nibAspect,
      bool? followBarrelRoll,
      List<double>? dashPattern,
      int? laserFadeMs,
      InkTapeStyle? tapeStyle,
    })
    withExtras = style.withInkExtras;
    expect([angle, aspect, roll, dash, fade, tape, withExtras], hasLength(7));
    expect(InkRenderMethod.values, [
      InkRenderMethod.filledOutline,
      InkRenderMethod.strokedPolyline,
      InkRenderMethod.nibOutline,
      InkRenderMethod.dashedPolyline,
      InkRenderMethod.transientTrail,
    ]);
    expect(InkLayer.values, [
      InkLayer.highlighter,
      InkLayer.ink,
      InkLayer.cover,
    ]);
    expect(InkRenderLayer.values, [
      InkRenderLayer.background,
      InkRenderLayer.underlay,
      InkRenderLayer.highlighterBase,
      InkRenderLayer.highlighterActive,
      InkRenderLayer.inkBase,
      InkRenderLayer.inkActive,
      InkRenderLayer.annotation,
      InkRenderLayer.cover,
      InkRenderLayer.overlay,
    ]);
  });

  test('7.2.9 content and page controller additions', () {
    final InkPageContent Function({
      required core.Page page,
      required List<core.Stroke> strokes,
      List<core.PageObject> objects,
      required int revision,
    })
    fromCore = InkPageContent.fromCore;
    final content = fromCore(
      page: SyntheticInk.page(),
      strokes: const [],
      revision: 1,
    );
    final List<core.PageObject> objects = content.objects;
    expect(objects, isEmpty);

    final c = createTestPageController();
    addTearDown(c.dispose);
    c.updateContent(content);
    final InkSelection Function(Set<String>) select = c.select;
    final core.PageObject? Function(Offset, {double tolerance}) hitObject =
        c.hitTestObject;
    final void Function(Set<String>) setHidden = c.setHiddenObjectIds;
    final void Function(List<core.PageObject>) setPreview = c.setPreviewObjects;
    final Set<String> hidden = c.hiddenObjectIds;
    final List<core.PageObject> previews = c.previewObjects;
    final InkPlaybackFocus? focus = c.playbackFocus;
    final void Function(InkPlaybackFocus?) setFocus = c.setPlaybackFocus;
    final InkStroke? Function(Offset, {String? recordingId, double tolerance})
    hitRecorded = c.hitTestRecorded;
    final InkStroke? Function(Offset) hitTape = c.hitTestTape;
    final bool Function(String) revealed = c.isTapeRevealed;
    final void Function(String) toggle = c.toggleTape;
    final void Function(bool) revealAll = c.setAllTapesRevealed;
    expect(
      [select({}).isEmpty, hitObject(Offset.zero), hidden, previews, focus],
      [true, null, isEmpty, isEmpty, null],
    );
    setHidden({'x'});
    setPreview(const []);
    setFocus(const InkPlaybackFocus(recordingId: 'r', positionMs: 0));
    expect(
      [hitRecorded(Offset.zero), hitTape(Offset.zero), revealed('s')],
      [null, null, false],
    );
    toggle('s');
    revealAll(true);

    const InkPlaybackFocus f = InkPlaybackFocus(
      recordingId: 'r',
      positionMs: 1,
      style: InkPlaybackStyle.highlightRecent,
      recentWindowMs: 500,
    );
    final List<Object> fields = [
      f.recordingId,
      f.positionMs,
      f.style,
      f.recentWindowMs,
    ];
    expect(fields, ['r', 1, InkPlaybackStyle.highlightRecent, 500]);
    expect(InkPlaybackStyle.values, [
      InkPlaybackStyle.dimUnwritten,
      InkPlaybackStyle.highlightRecent,
    ]);
  });

  test(
    '7.2.9 beginStroke(shapeAssist:), StrokeSession, laser end() → null',
    () {
      final c = createTestPageController();
      addTearDown(c.dispose);
      c.updateContent(SyntheticInk.pageContent());
      final StrokeSession Function(
        InkSample, {
        required core.StrokeStyle style,
        required double viewScale,
        InkStrokeMeta meta,
        ShapeAssist shapeAssist,
      })
      begin = c.beginStroke;
      final s = SyntheticInk.line(const Offset(10, 10), const Offset(80, 40));
      final session = begin(
        s.first,
        style: core.StrokeStyle.defaultsFor(core.PenTool.laser),
        viewScale: 1,
      )..addSamples(s.skip(1));
      final InkGestureSession asGesture = session;
      final ValueListenable<InkShapeFit?> preview = session.shapePreview;
      final ShapeAssist assist = session.shapeAssist;
      expect(
        [asGesture.isActive, preview.value, assist],
        [true, null, ShapeAssist.off],
      );
      expect(session.end(s.last), isNull);
      expect(c.pendingIds, isEmpty);
      expect(ShapeAssist.values, [ShapeAssist.off, ShapeAssist.holdToSnap]);
    },
  );

  test('7.2.9 shape port and provider', () {
    final InkShapeFitter fitter = _Fitter();
    final InkShapeFit? Function(List<Offset>, {required double viewScale}) fit =
        fitter.fit;
    expect(fit(const [], viewScale: 1), isNull);
    const InkShapeFitter none = NoShapeFitter();
    expect(none.fit(const [], viewScale: 1), isNull);
    final geometry = core.ShapeGeometry.ellipse(
      const core.PageRect(0, 0, 10, 10),
    );
    final InkShapeFit value = InkShapeFit(
      kind: core.ShapeKind.ellipse,
      geometry: geometry,
      score: 0.5,
    );
    final List<Object> fields = [value.kind, value.geometry, value.score];
    expect(fields, [core.ShapeKind.ellipse, geometry, 0.5]);
    final Provider<InkShapeFitter> provider = inkShapeFitterProvider;
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(provider), isA<NoShapeFitter>());
  });

  test('7.2.9 selection, lasso, eraser, edit', () {
    final c = createTestPageController();
    addTearDown(c.dispose);
    final shape = PageObjectFixtures.shape(pageId: 'p1', id: 'sh');
    c.updateContent(SyntheticInk.pageContentWith(objects: [shape]));
    final sel = c.select({'sh'});
    final Set<String> objectIds = sel.objectIds;
    final Set<String> allIds = sel.allIds;
    final List<core.PageObject> objects = sel.objects;
    expect(
      [objectIds, allIds, objects],
      [
        {'sh'},
        {'sh'},
        [shape],
      ],
    );
    const lasso = LassoOptions();
    final bool includeObjects = lasso.includeObjects;
    const eraser = EraserSpec(mode: EraserMode.stroke, radius: 4);
    final bool eraseShapes = eraser.eraseShapes;
    expect([includeObjects, eraseShapes], [true, true]);
    expect(const LassoOptions(includeObjects: false).includeObjects, isFalse);
    expect(
      const EraserSpec(
        mode: EraserMode.partial,
        radius: 4,
        eraseShapes: false,
      ).eraseShapes,
      isFalse,
    );
    final edit = InkEdit(
      pageId: 'p1',
      kind: InkEditKind.addShape,
      addedObjects: [shape],
      updatedObjects: const [],
      removedObjectIds: const {},
    );
    final List<core.PageObject> added = edit.addedObjects;
    final List<core.PageObject> updated = edit.updatedObjects;
    final Set<String> removedObjects = edit.removedObjectIds;
    expect(
      [added, updated, removedObjects],
      [
        [shape],
        isEmpty,
        isEmpty,
      ],
    );
    expect(edit.toCommand(), isA<core.AddObjects>());
  });

  test('7.2.9 backgrounds and the image cache', () async {
    final store = createFakeNoteStore();
    addTearDown(store.close);
    const spec = InkBackgroundSpec(
      kind: InkBackgroundKind.image,
      assetId: 'a',
      imageFit: core.ImageFit.cover,
    );
    final core.ImageFit? fit = spec.imageFit;
    expect(fit, core.ImageFit.cover);
    final InkImageCache cache = InkImageCache(
      assets: store.assets,
      budgetBytes: 1 << 20,
      pool: InkCachePool(InkRenderConfig.nativeDefaults),
    );
    addTearDown(cache.dispose);
    final ImageBackgroundLayerBuilder builder = ImageBackgroundLayerBuilder(
      assets: store.assets,
      images: cache,
    );
    final PageBackgroundLayerBuilder asBuilder = builder;
    final PageBackgroundStillRenderer asStill = builder;
    final core.AssetStore assets = builder.assets;
    final InkImageCache images = builder.images;
    expect(
      [asBuilder.handles(spec), assets, images],
      [true, same(store.assets), same(cache)],
    );
    final ui.Image? still = await asStill.renderStill(
      spec,
      pageSize: const Size(100, 100),
      pixelSize: const Size(10, 10),
    );
    expect(still!.width, 10);
    still.dispose();
    final int budget = cache.budgetBytes;
    final ui.Image? Function(
      String, {
      required int longSidePx,
      int? pixelWidth,
      int? pixelHeight,
    })
    peek = cache.peek;
    final Future<ui.Image?> Function(
      String, {
      required int longSidePx,
      int? pixelWidth,
      int? pixelHeight,
    })
    load = cache.load;
    final Stream<({String assetId, int bucket})> changes = cache.changes;
    final ({
      int images,
      int bytes,
      int pinnedBytes,
      int queued,
      int failures,
      int downgraded,
    })
    stats = cache.stats;
    expect(
      [budget, peek('a', longSidePx: 10), stats.images],
      [1 << 20, null, 0],
    );
    expect(await load('a', longSidePx: 10), isNull);
    expect(changes, isA<Stream<({String assetId, int bucket})>>());
    final Provider<InkImageCache> cacheProvider = inkImageCacheProvider;
    final List<PageBackgroundLayerBuilder> Function(Ref) defaults =
        defaultPageBackgroundBuilders;
    expect([cacheProvider, defaults], hasLength(2));
    const config = InkRenderConfig(imageCacheBytes: 7, mathRasterCacheBytes: 9);
    final int? imageBytes = config.imageCacheBytes;
    final int mathBytes = config.mathRasterCacheBytes;
    expect([imageBytes, mathBytes], [7, 9]);
    expect(InkRenderConfig.nativeDefaults.imageCacheBytes, isNull);
    expect(
      InkRenderConfig.nativeDefaults.mathRasterCacheBytes,
      8 * 1024 * 1024,
    );
  });

  test('7.2.9 vector export v2', () {
    final vectors = InkVectorExport.exportPage(SyntheticInk.pageContent());
    final List<InkImageVector> underlay = vectors.underlay;
    final List<InkAnnotationVector> annotations = vectors.annotations;
    final List<InkFillShape> cover = vectors.cover;
    expect([underlay, annotations, cover], [isEmpty, isEmpty, isEmpty]);
    final image = InkVectorFixtures.imageVector(
      assetId: 'a',
      frame: const core.ElementFrame(core.PageRect(0, 0, 1, 1)),
      pixelWidth: 1,
      pixelHeight: 1,
    );
    final List<Object> imageFields = [
      image.assetId,
      image.frame,
      image.pixelWidth,
      image.pixelHeight,
    ];
    expect(imageFields, hasLength(4));
    final text = PageObjectFixtures.textBox(pageId: 'p1');
    final InkAnnotationVector annotation = InkVectorFixtures.textVector(
      object: text,
    );
    final core.ElementFrame frame = annotation.frame;
    expect(frame, text.frame);
    final textVector = annotation as InkTextVector;
    final core.TextBoxObject object = textVector.object;
    final List<InkTextLine> lines = textVector.lines;
    expect([object, lines], [text, isEmpty]);
    final line = InkVectorFixtures.textLine(
      text: 't',
      x: 1,
      baselineY: 2,
      width: 3,
    );
    final List<Object> lineFields = [
      line.text,
      line.x,
      line.baselineY,
      line.width,
    ];
    expect(lineFields, ['t', 1.0, 2.0, 3.0]);
    final math = InkVectorFixtures.mathVector(
      object: PageObjectFixtures.math(pageId: 'p1'),
    );
    final core.MathObject mathObject = math.object;
    expect(mathObject.latex, r'\frac{a}{b}');
    final fill = InkVectorFixtures.fillShape(
      strokeId: 's',
      tool: core.PenTool.ballpoint,
      path: InkVectorPath(Uint8List(0), Float32List(0)),
      colorArgb: 0xFF000000,
    );
    final String? objectId = fill.objectId;
    expect(objectId, isNull);
  });

  test('7.2.9 math, fonts, text layout', () {
    final String? Function(String) validate = InkMathRenderer.validate;
    final InkMathLayout? Function(String, {required double fontSizePt}) layout =
        InkMathRenderer.layout;
    final Future<ui.Image?> Function(
      String, {
      required int colorArgb,
      required double fontSizePt,
      required double pixelsPerPt,
    })
    rasterize = InkMathRenderer.rasterize;
    expect([validate, layout, rasterize], hasLength(3));
    final InkMathLayout? l = layout(r'x', fontSizePt: 18);
    final Size size = l!.sizePt;
    final double baseline = l.baselinePt;
    expect(size.height > 0 && baseline > 0, isTrue);
    const preview = MathPreview(
      latex: 'x',
      fontSize: 18,
      color: Color(0xFF000000),
    );
    final StatelessWidget asWidget = preview;
    final String latex = preview.latex;
    final double fontSize = preview.fontSize;
    final Color color = preview.color;
    final ValueChanged<String>? onError = preview.onError;
    expect(
      [asWidget, latex, fontSize, color, onError],
      [same(preview), 'x', 18.0, const Color(0xFF000000), null],
    );
    const String family = InkFonts.noteSans;
    final Future<void> Function() ensureLoaded = InkFonts.ensureLoaded;
    final Future<Uint8List> Function({bool bold}) bytes =
        InkFonts.noteSansBytes;
    final bool Function(String) covers = InkFonts.covers;
    expect(
      [family, ensureLoaded, bytes, covers('a')],
      ['NoteSans', isNotNull, isNotNull, true],
    );
    final Future<Size> Function(
      String,
      core.TextBoxStyle, {
      required double widthPt,
    })
    measure = InkTextLayout.measure;
    final Size? Function(String, core.TextBoxStyle, {required double widthPt})
    measureSync = InkTextLayout.measureSync;
    final TextStyle Function(core.TextBoxStyle) textStyleOf =
        InkTextLayout.textStyleOf;
    final StrutStyle Function(core.TextBoxStyle) strutStyleOf =
        InkTextLayout.strutStyleOf;
    final Future<ui.Image?> Function(
      core.TextBoxObject, {
      required double pixelsPerPt,
    })
    textRaster = InkTextLayout.rasterize;
    expect([
      measure,
      measureSync,
      textStyleOf,
      strutStyleOf,
      textRaster,
    ], hasLength(5));
  });

  test('testing.dart v2 (m5-7/03-ink 4.12, contract 7.6)', () {
    final InkPageController Function({
      String pageId,
      InkRenderConfig config,
      InkCoreServices? services,
      InkClock? clock,
      PressureMode mode,
      List<PageBackgroundLayerBuilder> backgroundBuilders,
      InkShapeFitter? shapeFitter,
    })
    make = createTestPageController;
    make(shapeFitter: FakeInkShapeFitter()).dispose();
    final fake = FakeInkShapeFitter(minPoints: 3);
    final InkShapeFitter asFitter = fake;
    final int calls = fake.calls;
    final List<List<Offset>> received = fake.received;
    final int minPoints = fake.minPoints;
    expect([asFitter, calls, received, minPoints], [same(fake), 0, isEmpty, 3]);
    final List<InkSample> Function({required Rect bounds, int holdMs, int hz})
    loop = SyntheticInk.loopThenHold;
    expect(loop(bounds: const Rect.fromLTWH(0, 0, 100, 50)), isNotEmpty);
    final InkPageContent Function({
      String pageId,
      List<core.Stroke> strokes,
      List<core.PageObject> objects,
      int revision,
    })
    withObjects = SyntheticInk.pageContentWith;
    expect(withObjects().objects, isEmpty);
    final Future<void> Function() katex = loadKatexFontsForTest;
    final void Function(Future<Uint8List> Function({required bool bold})?)
    setSource = debugSetInkFontSource;
    final Future<void> Function() testFonts = useInkTestFonts;
    final Future<Uint8List> Function({
      required int width,
      required int height,
      int argb,
    })
    png = testPngBytes;
    expect([katex, setSource, testFonts, png], hasLength(4));
  });
}
