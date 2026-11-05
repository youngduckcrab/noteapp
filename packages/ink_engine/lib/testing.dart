/// Test helpers of ink_engine (03-ink 4.14) — for test/ only (other areas' tests and
/// INK's own); no flutter_test dependency, web safe. Never import from lib/ (7.1 rule 2).
///
/// Ids come from core.SequentialIdGenerator (there is no `SequentialIds` here, 7.4.6);
/// synthetic CORE strokes come from InkDevTools.syntheticStrokes or CORE StrokeFixtures.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:note_core/note_core.dart' as core;

import 'src/background/background_builder.dart';
import 'src/background/background_spec.dart';
import 'src/background/template_builder.dart';
import 'src/diagnostics/diagnostics.dart';
import 'src/diagnostics/ink_clock.dart';
import 'src/input/ink_sample.dart';
import 'src/input/pressure_capability.dart';
import 'src/input/pressure_mode.dart';
import 'src/interop/core_interop.dart' as interop;
import 'src/render/cache_pool.dart';
import 'src/render/ink_page_content.dart';
import 'src/render/ink_page_controller.dart';
import 'src/render/pencil_grain.dart';
import 'src/render/render_config.dart';

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
InkPageController createTestPageController({
  String pageId = 'p1',
  InkRenderConfig config = const InkRenderConfig(rasterTiles: false),
  InkCoreServices? services, // default testInkCoreServices()
  InkClock? clock, // default FakeInkClock()
  PressureMode mode = PressureMode.auto,
  List<PageBackgroundLayerBuilder> backgroundBuilders = const [
    TemplateBackgroundLayerBuilder(),
  ],
}) {
  final c = clock ?? FakeInkClock();
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
  );
}
