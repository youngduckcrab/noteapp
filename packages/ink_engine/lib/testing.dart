/// Test helpers of ink_engine (03-ink 4.14; 2nd round m5-7/03-ink 4.12 and the contract
/// 7.6 block) — for test/ only (other areas' tests and INK's own); no flutter_test
/// dependency, web safe (loadKatexFontsForTest answers on the VM only). Never import from
/// lib/ (7.1 rule 2).
///
/// Ids come from core.SequentialIdGenerator (there is no `SequentialIds` here, 7.4.6);
/// synthetic CORE strokes come from InkDevTools.syntheticStrokes or CORE StrokeFixtures;
/// page objects from CORE PageObjectFixtures.
library;

import 'dart:convert' show base64Decode;
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter/widgets.dart';
import 'package:note_core/note_core.dart' as core;

import 'src/background/background_builder.dart';
import 'src/background/background_spec.dart';
import 'src/background/template_builder.dart';
import 'src/diagnostics/diagnostics.dart';
import 'src/diagnostics/ink_clock.dart';
import 'src/export/vector_export.dart';
import 'src/geometry/vector_path.dart';
import 'src/input/ink_sample.dart';
import 'src/input/pressure_capability.dart';
import 'src/input/pressure_mode.dart';
import 'src/interop/core_interop.dart' as interop;
import 'src/pen/pen_profile.dart';
import 'src/render/cache_pool.dart';
import 'src/render/ink_page_content.dart';
import 'src/render/ink_page_controller.dart';
import 'src/render/pencil_grain.dart';
import 'src/render/render_config.dart';
import 'src/shape/shape_assist.dart';
import 'src/testing/ink_test_font.dart';
import 'src/text/fonts.dart';

abstract final class SyntheticInk {
  /// Straight line samples at [hz].
  static List<InkSample> line(
    Offset from,
    Offset to, {
    int samples = 32,
    double hz = 120,
    int startUs = 0,
    InkPointerKind kind = InkPointerKind.stylus,
    double? pressure = 0.5,
    double tilt = 0,
  }) {
    if (samples < 1) {
      throw ArgumentError.value(samples, 'samples', 'must be >= 1');
    }
    final dtUs = 1000000 / hz;
    return [
      for (var i = 0; i < samples; i++)
        InkSample(
          position: samples == 1
              ? from
              : Offset.lerp(from, to, i / (samples - 1))!,
          timeUs: startUs + (i * dtUs).round(),
          kind: kind,
          pressure: pressure,
          tilt: tilt,
        ),
    ];
  }

  /// Sine wave samples; [pressureAt] maps progress 0..1 → raw pressure (null → constant 0.5).
  static List<InkSample> wave(
    Offset origin, {
    double length = 200,
    double amplitude = 20,
    int samples = 120,
    double hz = 120,
    double? Function(double t)? pressureAt,
    InkPointerKind kind = InkPointerKind.stylus,
  }) {
    if (samples < 1) {
      throw ArgumentError.value(samples, 'samples', 'must be >= 1');
    }
    final dtUs = 1000000 / hz;
    return [
      for (var i = 0; i < samples; i++)
        () {
          final t = samples == 1 ? 0.0 : i / (samples - 1);
          return InkSample(
            position:
                origin +
                Offset(t * length, amplitude * math.sin(t * 2 * math.pi)),
            timeUs: (i * dtUs).round(),
            kind: kind,
            pressure: pressureAt == null ? 0.5 : pressureAt(t),
          );
        }(),
    ];
  }

  /// A core.Page for tests (noteId 'n1', sortKey 'a0', createdAt / updatedAt 0).
  static core.Page page({
    String pageId = 'p1',
    core.PageSize size = core.PageSize.a4Portrait,
    core.PageBackground background = const core.BlankBackground(),
  }) => core.Page(
    id: pageId,
    noteId: 'n1',
    sortKey: 'a0',
    size: size,
    background: background,
    createdAt: 0,
    updatedAt: 0,
  );

  /// InkPageContent.fromCore(page: page(...), strokes: strokes, revision: revision).
  static InkPageContent pageContent({
    String pageId = 'p1',
    List<core.Stroke> strokes = const [],
    core.PageSize size = core.PageSize.a4Portrait,
    core.PageBackground background = const core.BlankBackground(),
    int revision = 1,
  }) => InkPageContent.fromCore(
    page: page(pageId: pageId, size: size, background: background),
    strokes: strokes,
    revision: revision,
  );

  /// (v2.0) Samples that draw a closed loop then hold still for [holdMs] (shape assist tests):
  /// the ellipse inscribed in [bounds], clockwise from its top, back to the start, then the
  /// same position at [hz] for [holdMs]. Stylus, pressure 0.5.
  static List<InkSample> loopThenHold({
    required Rect bounds,
    int holdMs = 600,
    int hz = 120,
  }) {
    if (hz < 1) throw ArgumentError.value(hz, 'hz', 'must be >= 1');
    if (holdMs < 0) throw ArgumentError.value(holdMs, 'holdMs', 'must be >= 0');
    final dtUs = 1000000 / hz;
    final c = bounds.center;
    final rx = bounds.width / 2, ry = bounds.height / 2;
    const loopSamples = 96;
    final out = <InkSample>[];
    var i = 0;
    for (; i <= loopSamples; i++) {
      final a = -math.pi / 2 + 2 * math.pi * i / loopSamples;
      out.add(
        InkSample(
          position: Offset(c.dx + rx * math.cos(a), c.dy + ry * math.sin(a)),
          timeUs: (i * dtUs).round(),
          kind: InkPointerKind.stylus,
          pressure: 0.5,
        ),
      );
    }
    final end = out.last.position;
    final holdSamples = (holdMs * hz / 1000).ceil();
    for (var k = 1; k <= holdSamples; k++, i++) {
      out.add(
        InkSample(
          position: end,
          timeUs: (i * dtUs).round(),
          kind: InkPointerKind.stylus,
          pressure: 0.5,
        ),
      );
    }
    return out;
  }

  /// (v2.0) InkPageContent with strokes AND objects (v2 fromCore).
  static InkPageContent pageContentWith({
    String pageId = 'p1',
    List<core.Stroke> strokes = const [],
    List<core.PageObject> objects = const [],
    int revision = 1,
  }) => InkPageContent.fromCore(
    page: page(pageId: pageId),
    strokes: strokes,
    objects: objects,
    revision: revision,
  );
}

/// (v2.0) Scripted fitter: returns the constructor's `fit` ([result]) when the stroke's point
/// count ≥ [minPoints], counts calls. The settable field is [result] — a field named `fit`
/// would clash with InkShapeFitter.fit (m5-7/03-ink 4.12 wrote `InkShapeFit? fit;`).
final class FakeInkShapeFitter implements InkShapeFitter {
  FakeInkShapeFitter({InkShapeFit? fit, this.minPoints = 8}) : result = fit;

  /// What the next calls return (when enough points); null = not a shape.
  InkShapeFit? result;
  final int minPoints;
  int _calls = 0;
  final List<List<Offset>> _received = [];

  int get calls => _calls;

  /// The points of every call, in order (copies).
  List<List<Offset>> get received => List.unmodifiable(_received);

  @override
  InkShapeFit? fit(List<Offset> points, {required double viewScale}) {
    _calls++;
    _received.add(List.unmodifiable(points));
    return points.length >= minPoints ? result : null;
  }
}

final class FakeInkClock implements InkClock {
  FakeInkClock({int startUs = 0, this.alignedWithEventTimestamps = true})
    : us = startUs;

  int us;

  void advanceMs(double ms) => us += (ms * 1000).round();

  @override
  int nowUs() => us;

  @override
  final bool alignedWithEventTimestamps;
}

/// Ids from core.SequentialIdGenerator(prefix: idPrefix) ('s-000001', ...);
/// nowMillis starts at [startMillis] and advances 1 ms per call.
InkCoreServices testInkCoreServices({
  String idPrefix = 's',
  core.EpochMillis startMillis = 1000,
}) {
  final ids = core.SequentialIdGenerator(prefix: idPrefix);
  var now = startMillis;
  return InkCoreServices(newStrokeId: ids.newId, nowMillis: () => now++);
}

final class MemoryPressureStore implements PressureCapabilityStore {
  PressureCapabilityState _state = const PressureCapabilityState();

  @override
  PressureCapability capabilityOf(InkPointerKind kind) =>
      _state.capabilityOf(kind);

  @override
  void report(
    InkPointerKind kind,
    PressureCapability capability, {
    double? constantValue,
  }) {
    if (kind != InkPointerKind.stylus &&
        kind != InkPointerKind.invertedStylus) {
      return;
    }
    _state = PressureCapabilityState(
      stylus: capability,
      stylusConstantValue: capability == PressureCapability.unsupported
          ? constantValue
          : null,
    );
  }
}

/// Opaque solid background for [kind] (stand-in for PDF pages); also a still renderer
/// (returns null when [stillReturnsNull], simulating missing PDF bytes).
final class SolidBackgroundBuilder
    implements PageBackgroundLayerBuilder, PageBackgroundStillRenderer {
  const SolidBackgroundBuilder({
    this.kind = InkBackgroundKind.pdf,
    this.colorArgb = 0xFFDDDDDD,
    this.stillReturnsNull = false,
  });
  final InkBackgroundKind kind;
  final int colorArgb;
  final bool stillReturnsNull;

  @override
  bool handles(InkBackgroundSpec background) => background.kind == kind;

  @override
  Widget build(BuildContext context, PageBackgroundContext ctx) => SizedBox(
    width: ctx.pageSize.width * ctx.viewScale,
    height: ctx.pageSize.height * ctx.viewScale,
    child: ColoredBox(color: Color(interop.opaqueArgb(colorArgb))),
  );

  @override
  Future<ui.Image?> renderStill(
    InkBackgroundSpec background, {
    required Size pageSize,
    required Size pixelSize,
  }) async {
    if (stillReturnsNull) return null;
    final w = math.max(1, pixelSize.width.round());
    final h = math.max(1, pixelSize.height.round());
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawRect(
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      Paint()..color = Color(interop.opaqueArgb(colorArgb)),
    );
    final picture = recorder.endRecording();
    try {
      return await picture.toImage(w, h);
    } finally {
      picture.dispose();
    }
  }
}

/// Controller wired with fakes (no Riverpod needed).
/// (v2.0) + [shapeFitter] (default NoShapeFitter). v1.4 arguments unchanged.
/// Image objects: pass backgroundBuilders: [ImageBackgroundLayerBuilder(assets: store.assets,
/// images: InkImageCache(assets: store.assets)), const TemplateBackgroundLayerBuilder()]
/// (the controller finds its image cache in that list — 6.20); without it → placeholders.
InkPageController createTestPageController({
  String pageId = 'p1',
  InkRenderConfig config = const InkRenderConfig(rasterTiles: false),
  InkCoreServices? services, // default testInkCoreServices()
  InkClock? clock, // default FakeInkClock()
  PressureMode mode = PressureMode.auto,
  List<PageBackgroundLayerBuilder> backgroundBuilders = const [
    TemplateBackgroundLayerBuilder(),
  ],
  InkShapeFitter? shapeFitter,
}) {
  final c = clock ?? FakeInkClock();
  final fitter = shapeFitter ?? const NoShapeFitter();
  return InkPageController(
    pageId: pageId,
    services: services ?? testInkCoreServices(),
    config: config,
    cachePool: InkCachePool(config),
    pressureStore: MemoryPressureStore(),
    pressureMode: () => mode,
    diagnostics: InkDiagnostics(clock: c),
    clock: c,
    pencilGrain: PencilGrain(),
    backgroundBuilders: backgroundBuilders,
    shapeFitter: () => fitter,
  );
}

/// KaTeX fonts of flutter_math_fork through FontLoader (VM only — rootBundle does not answer
/// under `flutter test --platform chrome` [확인]). Call once in setUpAll.
Future<void> loadKatexFontsForTest() async {
  for (final MapEntry(key: family, value: files) in _katexFonts.entries) {
    final loader = FontLoader('packages/flutter_math_fork/$family');
    for (final f in files) {
      loader.addFont(
        rootBundle.load('packages/flutter_math_fork/lib/katex_fonts/fonts/$f'),
      );
    }
    await loader.load();
  }
}

const Map<String, List<String>> _katexFonts = {
  'KaTeX_Main': [
    'KaTeX_Main-Regular.ttf',
    'KaTeX_Main-Italic.ttf',
    'KaTeX_Main-Bold.ttf',
    'KaTeX_Main-BoldItalic.ttf',
  ],
  'KaTeX_Math': ['KaTeX_Math-Italic.ttf', 'KaTeX_Math-BoldItalic.ttf'],
  'KaTeX_AMS': ['KaTeX_AMS-Regular.ttf'],
  'KaTeX_Caligraphic': [
    'KaTeX_Caligraphic-Regular.ttf',
    'KaTeX_Caligraphic-Bold.ttf',
  ],
  'KaTeX_Fraktur': ['KaTeX_Fraktur-Regular.ttf', 'KaTeX_Fraktur-Bold.ttf'],
  'KaTeX_SansSerif': [
    'KaTeX_SansSerif-Regular.ttf',
    'KaTeX_SansSerif-Bold.ttf',
    'KaTeX_SansSerif-Italic.ttf',
  ],
  'KaTeX_Script': ['KaTeX_Script-Regular.ttf'],
  'KaTeX_Typewriter': ['KaTeX_Typewriter-Regular.ttf'],
  'KaTeX_Size1': ['KaTeX_Size1-Regular.ttf'],
  'KaTeX_Size2': ['KaTeX_Size2-Regular.ttf'],
  'KaTeX_Size3': ['KaTeX_Size3-Regular.ttf'],
  'KaTeX_Size4': ['KaTeX_Size4-Regular.ttf'],
};

/// Makes InkFonts read its bytes from [source] instead of rootBundle (null restores). The
/// font state starts over (the next ensureLoaded loads from the new source).
void debugSetInkFontSource(
  Future<Uint8List> Function({required bool bold})? source,
) => InkFontsDebug.setSource(source);

/// Installs the small bundled test font (base64 Hangul + Latin subset) as the InkFonts source.
/// Every Chrome test that touches InkFonts / InkTextLayout (EDITOR, LIBRARY, PDF, INFRA) calls it
/// in setUpAll. Web safe.
/// (v2.1) = `debugSetInkFontSource(<bundled test font>)` + `await InkFonts.ensureLoaded()`.
/// Idempotent. The test font has one weight (bold asks get the same bytes) and only the
/// characters of tool/fonts/test_font_chars.txt: Chrome tests assert no sizes with it.
Future<void> useInkTestFonts() async {
  if (!identical(InkFontsDebug.source, _testFontSource)) {
    debugSetInkFontSource(_testFontSource);
  }
  await InkFonts.ensureLoaded();
}

Future<Uint8List> _testFontSource({required bool bold}) async => _testFontBytes;

final Uint8List _testFontBytes = base64Decode(inkTestFontBase64);

/// PNG bytes of a solid / two-tone image (dart:ui encode — web safe) for image tests.
/// Solid [argb]; the bottom-right quarter in the inverted color (two tones, so a decode
/// can be checked by position).
Future<Uint8List> testPngBytes({
  required int width,
  required int height,
  int argb = 0xFF3366CC,
}) async {
  if (width < 1) throw ArgumentError.value(width, 'width', 'must be >= 1');
  if (height < 1) throw ArgumentError.value(height, 'height', 'must be >= 1');
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder)
    ..drawRect(
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      Paint()..color = Color(argb),
    );
  if (width > 1 && height > 1) {
    final inverted = 0xFF000000 + (0xFFFFFF - argb % 0x1000000);
    canvas.drawRect(
      Rect.fromLTWH(width / 2, height / 2, width / 2, height / 2),
      Paint()..color = Color(inverted),
    );
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  picture.dispose();
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    image.dispose();
  }
}

/// Hand-built vector export values (PDF tests before INK T42). Each factory takes every public
/// field of its value type as a named argument with the same name and type.
/// Defaults: list fields const [], nullable fields null, InkFillShape.opacity 1.0, bounds (when
/// left out) the union of the content paths and frames (Rect.zero for an empty page); the
/// rest is required. They call the same internal constructors as exportPage, so == and
/// hashCode follow the same rules.
abstract final class InkVectorFixtures {
  static InkPageVectors pageVectors({
    List<InkHighlighterGroup> highlighterGroups = const [],
    List<InkFillShape> inkShapes = const [],
    List<InkImageVector> underlay = const [],
    List<InkAnnotationVector> annotations = const [],
    List<InkFillShape> cover = const [],
    Rect? bounds,
  }) {
    Rect? union;
    void include(Rect r) =>
        union = union == null ? r : union!.expandToInclude(r);
    for (final g in highlighterGroups) {
      for (final l in g.lines) {
        include(l.centerline.bounds.inflate(l.width / 2));
      }
    }
    for (final s in [...inkShapes, ...cover]) {
      include(s.path.bounds);
    }
    for (final i in underlay) {
      include(interop.rectOf(i.frame.bounds));
    }
    for (final a in annotations) {
      include(interop.rectOf(a.frame.bounds));
    }
    return newInkPageVectors(
      highlighterGroups: highlighterGroups,
      inkShapes: inkShapes,
      underlay: underlay,
      annotations: annotations,
      cover: cover,
      bounds: bounds ?? union ?? Rect.zero,
    );
  }

  static InkFillShape fillShape({
    required String strokeId,
    required core.PenTool tool,
    required InkVectorPath path,
    required int colorArgb,
    double opacity = 1.0,
    String? objectId,
  }) => newInkFillShape(
    strokeId: strokeId,
    tool: tool,
    path: path,
    colorArgb: colorArgb,
    opacity: opacity,
    objectId: objectId,
  );

  static InkHighlighterGroup highlighterGroup({
    required int colorArgb,
    required double opacity,
    required InkBlendMode blend,
    List<InkHighlighterLine> lines = const [],
  }) => newInkHighlighterGroup(
    colorArgb: colorArgb,
    opacity: opacity,
    blend: blend,
    lines: lines,
  );

  static InkHighlighterLine highlighterLine({
    required String strokeId,
    required InkVectorPath centerline,
    required double width,
    required InkCap cap,
  }) => newInkHighlighterLine(
    strokeId: strokeId,
    centerline: centerline,
    width: width,
    cap: cap,
  );

  static InkImageVector imageVector({
    required String assetId,
    required core.ElementFrame frame,
    required int pixelWidth,
    required int pixelHeight,
  }) => newInkImageVector(
    assetId: assetId,
    frame: frame,
    pixelWidth: pixelWidth,
    pixelHeight: pixelHeight,
  );

  static InkTextVector textVector({
    required core.TextBoxObject object,
    List<InkTextLine> lines = const [],
  }) => newInkTextVector(object: object, lines: lines);

  static InkTextLine textLine({
    required String text,
    required double x,
    required double baselineY,
    required double width,
  }) => newInkTextLine(text: text, x: x, baselineY: baselineY, width: width);

  static InkMathVector mathVector({required core.MathObject object}) =>
      newInkMathVector(object: object);
}
