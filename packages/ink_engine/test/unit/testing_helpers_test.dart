// T12 (03-ink 8, 4.14): the test helpers other areas use (package:ink_engine/
// testing.dart) — SyntheticInk samples and pages, FakeInkClock,
// testInkCoreServices, MemoryPressureStore (= the provider notifier's rules),
// SolidBackgroundBuilder (widget + still) and createTestPageController.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/testing.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:riverpod/riverpod.dart';

void main() {
  group('SyntheticInk.line', () {
    test('evenly spaced samples from → to at hz, with the given fields', () {
      final s = SyntheticInk.line(
        const Offset(10, 20),
        const Offset(110, 70),
        samples: 11,
        hz: 240,
        startUs: 5000,
        kind: InkPointerKind.invertedStylus,
        pressure: 0.7,
        tilt: 0.4,
      );
      expect(s, hasLength(11));
      for (var i = 0; i < s.length; i++) {
        expect(s[i].position.dx, closeTo(10 + 10 * i, 1e-9));
        expect(s[i].position.dy, closeTo(20 + 5 * i, 1e-9));
        expect(s[i].timeUs, 5000 + (i * 1000000 / 240).round());
        expect(s[i].kind, InkPointerKind.invertedStylus);
        expect(s[i].pressure, 0.7);
        expect(s[i].tilt, 0.4);
      }
      expect(s.first.position, const Offset(10, 20));
      expect(s.last.position, const Offset(110, 70));
    });

    test('defaults: 32 stylus samples at 120 Hz, pressure 0.5, tilt 0', () {
      final s = SyntheticInk.line(Offset.zero, const Offset(31, 0));
      expect(s, hasLength(32));
      expect(s[1].timeUs, (1000000 / 120).round());
      expect(s.every((e) => e.kind == InkPointerKind.stylus), isTrue);
      expect(s.every((e) => e.pressure == 0.5 && e.tilt == 0), isTrue);
      expect(s.first.timeUs, 0);
    });

    test('one sample sits at from; null pressure; < 1 sample throws', () {
      final one = SyntheticInk.line(
        const Offset(3, 4),
        const Offset(50, 50),
        samples: 1,
        pressure: null,
        kind: InkPointerKind.mouse,
      );
      expect(one.single.position, const Offset(3, 4));
      expect(one.single.pressure, isNull);
      expect(
        () => SyntheticInk.line(Offset.zero, Offset.zero, samples: 0),
        throwsArgumentError,
      );
    });
  });

  group('SyntheticInk.wave', () {
    test('one sine period of [amplitude] over [length] from origin', () {
      final s = SyntheticInk.wave(
        const Offset(20, 100),
        length: 200,
        amplitude: 10,
        samples: 101,
        hz: 60,
      );
      expect(s, hasLength(101));
      expect(s.first.position, const Offset(20, 100));
      expect(s.last.position.dx, closeTo(220, 1e-9));
      expect(s.last.position.dy, closeTo(100, 1e-9));
      expect(s[25].position.dy, closeTo(110, 1e-9)); // quarter period
      expect(s[75].position.dy, closeTo(90, 1e-9));
      expect(s[50].timeUs, (50 * 1000000 / 60).round());
      // pressureAt null → constant 0.5
      expect(s.every((e) => e.pressure == 0.5), isTrue);
      expect(s.every((e) => e.kind == InkPointerKind.stylus), isTrue);
    });

    test('pressureAt maps progress 0..1 to the raw pressure', () {
      final seen = <double>[];
      final s = SyntheticInk.wave(
        Offset.zero,
        samples: 5,
        pressureAt: (t) {
          seen.add(t);
          return t == 1 ? null : 0.2 + t;
        },
        kind: InkPointerKind.touch,
      );
      expect(seen, [0, 0.25, 0.5, 0.75, 1]);
      expect(s.map((e) => e.pressure).toList(), [0.2, 0.45, 0.7, 0.95, null]);
      expect(s.every((e) => e.kind == InkPointerKind.touch), isTrue);
      expect(
        () => SyntheticInk.wave(Offset.zero, samples: 0),
        throwsArgumentError,
      );
    });
  });

  group('SyntheticInk.page / pageContent', () {
    test('page: noteId n1, sortKey a0, createdAt / updatedAt 0', () {
      final p = SyntheticInk.page();
      expect(p.id, 'p1');
      expect(p.noteId, 'n1');
      expect(p.sortKey, 'a0');
      expect(p.createdAt, 0);
      expect(p.updatedAt, 0);
      expect(p.size, core.PageSize.a4Portrait);
      expect(p.background, const core.BlankBackground());
      final bg = core.TemplateBackground(
        template: core.PageTemplate.defaults(core.PageTemplateKind.grid),
      );
      final q = SyntheticInk.page(
        pageId: 'q',
        size: core.PageSize.widescreen16x9,
        background: bg,
      );
      expect(
        (q.id, q.size, q.background),
        ('q', core.PageSize.widescreen16x9, bg),
      );
    });

    test(
      'pageContent = InkPageContent.fromCore(page(...), strokes, revision)',
      () {
        final c = SyntheticInk.pageContent();
        expect(c.pageId, 'p1');
        expect(c.strokes, isEmpty);
        expect(c.revision, 1);
        expect(c.pageSize, const Size(595.2756, 841.8898));
        expect(c.background.kind, InkBackgroundKind.blank);

        final ids = core.SequentialIdGenerator(prefix: 'k');
        final strokes = [
          _strokeAt(ids.newId(), 'p2', createdAt: 30),
          _strokeAt(ids.newId(), 'p2', createdAt: 10),
        ];
        final d = SyntheticInk.pageContent(
          pageId: 'p2',
          strokes: strokes,
          size: core.PageSize.letterPortrait,
          revision: 7,
        );
        expect(d.revision, 7);
        expect(d.page.size, core.PageSize.letterPortrait);
        // fromCore sorts by createdAt (z order) and wraps with InkStroke.of
        expect(d.strokes.map((s) => s.id).toList(), ['k-000002', 'k-000001']);
        expect(identical(d.strokes.first, InkStroke.of(strokes[1])), isTrue);
        expect(
          () => SyntheticInk.pageContent(strokes: strokes), // page p1
          throwsArgumentError,
        );
      },
    );
  });

  test('FakeInkClock: start, advanceMs, settable us, alignment flag', () {
    final c = FakeInkClock(startUs: 1000);
    expect(c.nowUs(), 1000);
    c.advanceMs(2.5);
    expect(c.nowUs(), 3500);
    c.us = 42;
    expect(c.nowUs(), 42);
    expect(c.alignedWithEventTimestamps, isTrue);
    expect(FakeInkClock().nowUs(), 0);
    expect(
      FakeInkClock(alignedWithEventTimestamps: false)
          .alignedWithEventTimestamps,
      isFalse,
    );
    expect(c, isA<InkClock>());
  });

  test(
    'testInkCoreServices: CORE sequential ids, +1 ms per nowMillis call',
    () {
      final a = testInkCoreServices();
      expect([a.newStrokeId(), a.newStrokeId()], ['s-000001', 's-000002']);
      expect([a.nowMillis(), a.nowMillis(), a.nowMillis()], [1000, 1001, 1002]);
      final b = testInkCoreServices(idPrefix: 'ink', startMillis: 500000);
      expect(b.newStrokeId(), 'ink-000001');
      expect(core.isValidEntityId(b.newStrokeId()), isTrue);
      expect(b.nowMillis(), 500000);
      // independent instances
      expect(testInkCoreServices().newStrokeId(), 's-000001');
    },
  );

  test('MemoryPressureStore follows the pressureCapabilityProvider rules', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(pressureCapabilityProvider.notifier);
    final memory = MemoryPressureStore();
    final reports = <(InkPointerKind, PressureCapability, double?)>[
      (InkPointerKind.touch, PressureCapability.supported, null),
      (InkPointerKind.stylus, PressureCapability.unsupported, 0.5),
      (InkPointerKind.mouse, PressureCapability.supported, null),
      (InkPointerKind.invertedStylus, PressureCapability.supported, 0.3),
      (InkPointerKind.stylus, PressureCapability.unknown, null),
    ];
    void same() {
      for (final kind in InkPointerKind.values) {
        expect(memory.capabilityOf(kind), notifier.capabilityOf(kind));
      }
    }

    same();
    expect(
      memory.capabilityOf(InkPointerKind.stylus),
      PressureCapability.unknown,
    );
    expect(
      memory.capabilityOf(InkPointerKind.touch),
      PressureCapability.unsupported,
    );
    for (final (kind, cap, value) in reports) {
      memory.report(kind, cap, constantValue: value);
      notifier.report(kind, cap, constantValue: value);
      same();
    }
    memory.report(InkPointerKind.stylus, PressureCapability.supported);
    expect(
      memory.capabilityOf(InkPointerKind.invertedStylus),
      PressureCapability.supported,
    );
  });

  group('SolidBackgroundBuilder', () {
    test('handles only its kind; is a still renderer', () {
      const pdf = SolidBackgroundBuilder();
      expect(pdf.kind, InkBackgroundKind.pdf);
      expect(pdf.colorArgb, 0xFFDDDDDD);
      expect(pdf.stillReturnsNull, isFalse);
      expect(pdf, isA<PageBackgroundStillRenderer>());
      final pdfSpec = InkBackgroundSpec.fromCore(
        const core.PdfBackground(assetId: 'a', pdfPageIndex: 0),
      );
      final blank = InkBackgroundSpec.fromCore(const core.BlankBackground());
      expect(pdf.handles(pdfSpec), isTrue);
      expect(pdf.handles(blank), isFalse);
      const solidBlank = SolidBackgroundBuilder(kind: InkBackgroundKind.blank);
      expect(solidBlank.handles(blank), isTrue);
      expect(solidBlank.handles(pdfSpec), isFalse);
    });

    test(
      'renderStill: pixelSize image of the opaque color; null on request',
      () async {
        final spec = InkBackgroundSpec.fromCore(
          const core.PdfBackground(assetId: 'a', pdfPageIndex: 0),
        );
        const b = SolidBackgroundBuilder(colorArgb: 0x80336699);
        final image = (await b.renderStill(
          spec,
          pageSize: const Size(595, 842),
          pixelSize: const Size(30.4, 41.6),
        ))!;
        addTearDown(image.dispose);
        expect((image.width, image.height), (30, 42));
        final bytes = (await image.toByteData())!;
        for (final o in [0, (image.width * image.height - 1) * 4]) {
          expect(
            [
              bytes.getUint8(o),
              bytes.getUint8(o + 1),
              bytes.getUint8(o + 2),
              bytes.getUint8(o + 3),
            ],
            [0x33, 0x66, 0x99, 0xFF],
          );
        }
        const missing = SolidBackgroundBuilder(stillReturnsNull: true);
        expect(
          await missing.renderStill(
            spec,
            pageSize: const Size(10, 10),
            pixelSize: const Size(10, 10),
          ),
          isNull,
        );
      },
    );

    testWidgets('build: pageSize × viewScale, filled with the color', (
      tester,
    ) async {
      const b = SolidBackgroundBuilder(colorArgb: 0xFF112233);
      final ctx = PageBackgroundContext(
        pageId: 'p1',
        pageSize: const Size(100, 50),
        background: InkBackgroundSpec.fromCore(
          const core.PdfBackground(assetId: 'a', pdfPageIndex: 0),
        ),
        viewScale: 1.5,
        ancestorScale: 2,
        devicePixelRatio: 3,
        isScaling: false,
      );
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: Builder(builder: (context) => b.build(context, ctx)),
          ),
        ),
      );
      final box = tester.getSize(find.byType(ColoredBox));
      expect(box, const Size(150, 75)); // not × ancestorScale (7.2.16 v1.1)
      final colored = tester.widget<ColoredBox>(find.byType(ColoredBox));
      expect(colored.color, const Color(0xFF112233));
    });
  });

  group('createTestPageController', () {
    test('defaults: page p1, no raster tiles, fakes, auto mode, templates', () {
      final c = createTestPageController();
      addTearDown(c.dispose);
      expect(c.pageId, 'p1');
      expect(c.config, const InkRenderConfig(rasterTiles: false));
      expect(c.clock, isA<FakeInkClock>());
      expect(c.pressureStore, isA<MemoryPressureStore>());
      expect(c.pressureMode(), PressureMode.auto);
      expect(c.backgroundBuilders, const [TemplateBackgroundLayerBuilder()]);
      expect(c.cachePool, isNotNull);
      expect(c.content, isNull);
      // services = testInkCoreServices(): a pen stroke gets s-000001 at 1000 ms
      c.updateContent(SyntheticInk.pageContent());
      final samples = SyntheticInk.line(
        const Offset(50, 50),
        const Offset(150, 80),
      );
      final s = c.beginStroke(
        samples.first,
        style: core.StrokeStyle.defaultsFor(core.PenTool.ballpoint),
        viewScale: 1,
      )..addSamples(samples.skip(1));
      final edit = s.end(samples.last)!;
      final command = edit.toCommand() as core.AddStrokes;
      expect(command.strokes.single.id, 's-000001');
      expect(command.strokes.single.createdAt, 1000);
      expect(command.strokes.single.pageId, 'p1');
    });

    test('arguments reach the controller', () {
      final clock = FakeInkClock(startUs: 77);
      final services = testInkCoreServices(idPrefix: 'x');
      const config = InkRenderConfig(rasterTiles: false, chunkSizePt: 128);
      const builders = [SolidBackgroundBuilder()];
      final c = createTestPageController(
        pageId: 'other',
        config: config,
        services: services,
        clock: clock,
        mode: PressureMode.alwaysSimulated,
        backgroundBuilders: builders,
      );
      addTearDown(c.dispose);
      expect(c.pageId, 'other');
      expect(c.config, config);
      expect(identical(c.services, services), isTrue);
      expect(identical(c.clock, clock), isTrue);
      expect(c.pressureMode(), PressureMode.alwaysSimulated);
      expect(c.backgroundBuilders, builders);
      expect(
        () => c.updateContent(SyntheticInk.pageContent()), // page p1
        throwsArgumentError,
      );
    });
  });
}

/// A one-point ballpoint stroke on [pageId] (fromCore ordering checks).
core.Stroke _strokeAt(String id, String pageId, {required int createdAt}) =>
    core.Stroke(
      id: id,
      pageId: pageId,
      style: core.StrokeStyle.defaultsFor(core.PenTool.ballpoint),
      points: core.StrokePoints.fromList(const [
        core.StrokePoint(10, 10, t: 0),
      ]),
      createdAt: createdAt,
    );
