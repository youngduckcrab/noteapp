// T09 (03-ink 8, 6.23 function table, contract 7.2.15 / 7.2.16): the ONLY place
// that creates CORE objects — new pen strokes, fragments, duplicates, previews,
// thumbnails — and the CORE geometry conversions, plus InkPageContent.fromCore
// and InkBackgroundSpec.fromCore.
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/src/interop/core_interop.dart' as interop;
import 'package:ink_engine/src/render/ink_page_controller.dart'
    show inkPageRenderOf;
import 'package:ink_engine/src/stroke/stroke_builder.dart';
import 'package:ink_engine/testing.dart';
import 'package:note_core/note_core.dart' as core;

const _stride = core.StrokePoints.stride;

/// Interleaved data of [n] points along y = 50 with distinct t, tilt and azimuth.
Float32List _data(int n, {double x0 = 10.123456, double dx = 7.0}) {
  final d = Float32List(n * _stride);
  for (var i = 0; i < n; i++) {
    d[i * _stride] = x0 + dx * i;
    d[i * _stride + 1] = 50.004;
    d[i * _stride + 2] = 0.12345 + 0.01 * i;
    d[i * _stride + 3] = 0.3;
    d[i * _stride + 4] = 0.5;
    d[i * _stride + 5] = 12.34 + 8.33 * i;
  }
  return d;
}

core.Stroke _original({
  String id = 'orig',
  core.PenTool tool = core.PenTool.fountain,
  int n = 8,
  core.EpochMillis createdAt = 4242,
}) => interop.strokeFromData(
  _data(n),
  id: id,
  pageId: 'p1',
  style: core.StrokeStyle.defaultsFor(tool).copyWith(width: 2.4),
  createdAt: createdAt,
  hasTilt: true,
  hasAzimuth: true,
  recordingId: 'rec-1',
  recordingOffsetMs: 777,
);

/// A style outside every range (CORE normalizes it).
core.StrokeStyle _wildStyle() =>
    core.StrokeStyle.defaultsFor(core.PenTool.marker)
        .copyWith(colorArgb: 0x20123456, width: 99, opacity: 3, smoothing: -1);

void main() {
  group('strokeFromData', () {
    test('normalized style, quantized points, fields as given', () {
      final s = interop.strokeFromData(
        _data(3),
        id: 'a1',
        pageId: 'p1',
        style: _wildStyle(),
        createdAt: 1234,
        hasTilt: true,
        recordingId: 'r',
        recordingOffsetMs: 5,
      );
      expect(s.style, _wildStyle().normalized());
      expect(s.style.colorArgb, 0xFF123456);
      expect(s.style.width, core.StrokeStyle.maxWidth);
      expect(s.version, isNull);
      expect(s.deletedAt, isNull);
      expect(
        (s.id, s.pageId, s.createdAt, s.updatedAt),
        ('a1', 'p1', 1234, 1234),
      );
      expect((s.recordingId, s.recordingOffsetMs), ('r', 5));
      expect(s.points.hasTilt, isTrue);
      expect(s.points.hasAzimuth, isFalse);
      // CORE quantization grid (02-core 4.2): x/y 0.01 pt, widthQ 0.001, t 0.1 ms
      expect(s.points.x(0), closeTo(10.12, 1e-5));
      expect(s.points.y(0), closeTo(50.0, 1e-5));
      expect(s.points.widthQ(0), closeTo(0.123, 1e-6));
      expect(s.points.t(0), closeTo(12.3, 1e-4));
      expect(s.points.azimuth(0), 0, reason: 'hasAzimuth false');
    });

    test('rejects data that is not a multiple of the stride', () {
      expect(
        () => interop.strokeFromData(
          Float32List(_stride + 1),
          id: 'a1',
          pageId: 'p1',
          style: core.StrokeStyle.defaultsFor(core.PenTool.ballpoint),
          createdAt: 0,
        ),
        throwsArgumentError,
      );
    });
  });

  group('newCoreStroke', () {
    FinishedStroke finished({
      int createdAtOffsetMs = 0,
      InkStrokeMeta meta = const InkStrokeMeta(),
    }) => FinishedStroke(
      style: _wildStyle(),
      data: _data(5),
      hasTilt: true,
      hasAzimuth: false,
      startTimeUs: 0,
      pressureSource: PressureSource.real,
      meta: meta,
      createdAtOffsetMs: createdAtOffsetMs,
    );

    test('normalized style, version null, pageId, createdAt = pen down', () {
      final s = interop.newCoreStroke(
        finished(),
        id: 'k1',
        pageId: 'pg',
        penDownMillis: 9000,
      );
      expect(s.style, _wildStyle().normalized());
      expect(s.version, isNull);
      expect((s.id, s.pageId), ('k1', 'pg'));
      expect(s.createdAt, 9000);
      expect(s.updatedAt, 9000);
      expect(s.recordingId, isNull);
      expect(s.recordingOffsetMs, isNull);
      expect((s.points.hasTilt, s.points.hasAzimuth), (true, false));
    });

    test('recording fields from the meta; rollover part adds Σ⌊t_b⌋', () {
      final s = interop.newCoreStroke(
        finished(
          createdAtOffsetMs: 500000,
          meta: const InkStrokeMeta(
            recordingId: 'rec',
            recordingOffsetMs: 500100,
          ),
        ),
        id: 'k2',
        pageId: 'pg',
        penDownMillis: 9000,
      );
      expect(s.createdAt, 509000);
      expect(s.recordingId, 'rec');
      // meta.recordingOffsetMs already includes the rollover offset (6.7 F8)
      expect(s.recordingOffsetMs, 500100);
    });

    test('INK renders the quantized rawData, not the builder data', () {
      final f = finished();
      final s = interop.newCoreStroke(
        f,
        id: 'k3',
        pageId: 'pg',
        penDownMillis: 1,
      );
      final ink = InkStroke.of(s);
      // CORE's rawData is a fresh unmodifiable view per call in debug runs
      // (ink_points_test): compare values, and InkStroke keeps one view.
      expect(ink.points.raw, s.points.rawData);
      expect(InkStroke.of(s).points.raw, same(ink.points.raw));
      expect(ink.points.length, 5);
      expect(f.data[0], isNot(closeTo(ink.points.x(0), 1e-6)));
      for (var i = 0; i < ink.points.length; i++) {
        expect(ink.points.x(i), s.points.x(i));
        expect(ink.points.y(i), s.points.y(i));
        expect(ink.points.widthQ(i), s.points.widthQ(i));
        expect(ink.points.t(i), s.points.t(i));
      }
      expect(ink.bounds.left, closeTo(s.bounds.left, 1e-9));
    });

    test('a controller session: createdAt = nowMillis at pen down, meta', () {
      var now = 5000;
      var ids = 0;
      final c = createTestPageController(
        services: InkCoreServices(
          newStrokeId: () => 'n${++ids}',
          nowMillis: () => now,
        ),
      )..updateContent(SyntheticInk.pageContent());
      addTearDown(c.dispose);
      final samples = SyntheticInk.line(
        const ui.Offset(50, 50),
        const ui.Offset(200, 80),
      );
      final session = c.beginStroke(
        samples.first,
        style: core.StrokeStyle.defaultsFor(core.PenTool.ballpoint),
        viewScale: 1,
        meta: const InkStrokeMeta(recordingId: 'rec-9', recordingOffsetMs: 42),
      );
      now = 9999; // the pen is lifted later
      session.addSamples(samples.skip(1));
      final s = session.end(samples.last)!.added.single;
      expect(s.createdAt, 5000);
      expect(s.id, 'n1');
      expect(s.pageId, 'p1');
      expect(s.version, isNull);
      expect(s.recordingId, 'rec-9');
      expect(s.recordingOffsetMs, 42);
      expect(s.points.t(0), 0, reason: 't = ms since pen down');
      expect(s.style, s.style.normalized());
    });
  });

  group('fragmentOf / previewFragmentOf', () {
    test('fragment: new id, createdAt, style, recording and t kept', () {
      final o = _original();
      final raw = o.points.rawData;
      final piece = Float32List.fromList(raw.sublist(2 * _stride, 5 * _stride));
      final f = interop.fragmentOf(o, piece, id: 'frag-1');
      expect(f.id, 'frag-1');
      expect(f.pageId, o.pageId);
      expect(f.style, o.style);
      expect(f.createdAt, o.createdAt);
      expect(f.recordingId, 'rec-1');
      expect(f.recordingOffsetMs, 777);
      expect(f.version, isNull);
      expect(f.points.length, 3);
      expect(f.points.hasTilt, o.points.hasTilt);
      expect(f.points.hasAzimuth, o.points.hasAzimuth);
      for (var i = 0; i < 3; i++) {
        expect(f.points.t(i), o.points.t(i + 2), reason: 't kept (P7)');
        expect(f.points.x(i), o.points.x(i + 2));
        expect(f.points.widthQ(i), o.points.widthQ(i + 2));
        expect(f.points.azimuth(i), o.points.azimuth(i + 2));
      }
      expect(f, isNot(same(o)));
    });

    test('preview piece: id pv-<n> (valid entity id), original style and '
        'createdAt, never in InkCachePool', () {
      final o = _original();
      final pool = InkCachePool(const InkRenderConfig(rasterTiles: false));
      addTearDown(pool.dispose);
      pool.outlineFor(InkStroke.of(o));
      final before = pool.stats;
      final piece = Float32List.fromList(o.points.rawData.sublist(0, 12));
      for (final seq in [0, 7, 123456]) {
        final p = interop.previewFragmentOf(o, piece, seq: seq);
        expect(p.id, 'pv-$seq');
        expect(core.isValidEntityId(p.id), isTrue);
        expect(p.style, o.style);
        expect(p.createdAt, o.createdAt);
        expect(p.recordingId, o.recordingId);
        expect(p.points.t(1), o.points.t(1));
      }
      expect(pool.stats, before);
    });

    test('fragmentFromPreview = fragmentOf of the same data (T22 B5)', () {
      final o = _original();
      final piece = Float32List.fromList(
        o.points.rawData.sublist(1 * _stride, 4 * _stride),
      );
      final preview = interop.previewFragmentOf(o, piece, seq: 3);
      final a = interop.fragmentFromPreview(o, preview, id: 'frag-2');
      final b = interop.fragmentOf(o, piece, id: 'frag-2');
      expect(a.id, 'frag-2');
      expect(a.points, same(preview.points));
      expect(a.points.rawData, b.points.rawData);
      expect(a.points.hasTilt, b.points.hasTilt);
      expect(a.points.hasAzimuth, b.points.hasAzimuth);
      expect(a.bounds, b.bounds);
      expect(
        (a.pageId, a.style, a.createdAt, a.updatedAt, a.recordingId),
        (b.pageId, b.style, b.createdAt, b.updatedAt, b.recordingId),
      );
      expect(a.recordingOffsetMs, b.recordingOffsetMs);
      expect(a.version, isNull);
    });
  });

  group('duplicateOf', () {
    test('new id and createdAt, moved by the offset, width kept', () {
      final o = _original();
      final d = interop.duplicateOf(
        o,
        id: 'dup-1',
        createdAt: 8000,
        offset: const ui.Offset(16, 16),
      );
      expect(d.id, 'dup-1');
      expect(d.createdAt, 8000);
      expect(d.updatedAt, 8000);
      expect(d.version, isNull);
      expect(d.style, o.style, reason: 'no width scaling');
      expect(d.recordingId, o.recordingId);
      expect(d.points.length, o.points.length);
      for (var i = 0; i < o.points.length; i++) {
        expect(d.points.x(i), closeTo(o.points.x(i) + 16, 0.006));
        expect(d.points.y(i), closeTo(o.points.y(i) + 16, 0.006));
        expect(d.points.widthQ(i), o.points.widthQ(i));
        expect(d.points.t(i), o.points.t(i));
      }
      expect(d.bounds.left, closeTo(o.bounds.left + 16, 0.01));
    });

    test('selection.duplicate: createdAt base + k in z order, 16 pt', () {
      expect(InkTuning.duplicateOffsetPt, 16);
      final a = _original(id: 'a', createdAt: 10);
      final b = _original(id: 'b', createdAt: 20);
      var now = 70000;
      var ids = 0;
      final c = createTestPageController(
        services: InkCoreServices(
          newStrokeId: () => 'copy${++ids}',
          nowMillis: () => now++,
        ),
      )..updateContent(SyntheticInk.pageContent(strokes: [a, b]));
      addTearDown(c.dispose);
      final edit = c.select({'b', 'a'}).duplicate();
      expect(edit.kind, InkEditKind.duplicateStrokes);
      expect(edit.added.map((s) => s.id), ['copy1', 'copy2']);
      expect(edit.added.map((s) => s.createdAt), [70000, 70001]);
      expect(edit.added[0].points.x(0), closeTo(a.points.x(0) + 16, 0.006));
      expect(edit.added[1].points.y(0), closeTo(b.points.y(0) + 16, 0.006));
      for (final s in edit.added) {
        expect(s.version, isNull);
        expect(s.pageId, 'p1');
        expect(s.style.width, 2.4);
      }
    });
  });

  group('previewTransformedOf', () {
    test('= core.Stroke.transformed(m): same id, width scaled', () {
      final o = _original();
      final m = core.Affine2.scaling(
        2,
        2,
        originX: 30,
        originY: 50,
      ).then(core.Affine2.rotation(0.3, originX: 30, originY: 50));
      final p = interop.previewTransformedOf(o, m);
      final want = o.transformed(m);
      expect(p.id, o.id);
      expect(p.style, want.style);
      expect(p.style.width, closeTo(4.8, 1e-9));
      expect(p.points.rawData, want.points.rawData);
      expect(p.createdAt, o.createdAt);
    });

    test('a selection preview leaves the pool cache of the original', () {
      final a = _original(id: 'a', tool: core.PenTool.ballpoint);
      final c = createTestPageController()
        ..updateContent(SyntheticInk.pageContent(strokes: [a]));
      addTearDown(c.dispose);
      final cached = c.cachePool.outlineFor(InkStroke.of(a));
      final before = c.cachePool.stats;
      c.select({'a'}).setPreviewTransform(core.Affine2.scaling(3, 1));
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      for (final layer in InkRenderLayer.values) {
        inkPageRenderOf(c).paint(canvas, layer, 1);
      }
      recorder.endRecording().dispose();
      // (T19: the pool stats also count the chunk pictures painting made)
      final after = c.cachePool.stats;
      expect(
        (after.outlineEntries, after.outlineBytes),
        (before.outlineEntries, before.outlineBytes),
      );
      expect(c.cachePool.outlineFor(InkStroke.of(a)), same(cached));
    });
  });

  group('geometry', () {
    final transforms = <core.Affine2>[
      core.Affine2.identity,
      core.Affine2.translation(12.5, -3),
      core.Affine2.scaling(2, 0.5, originX: 100, originY: 40),
      core.Affine2.rotation(math.pi / 5, originX: 10, originY: 20),
      const core.Affine2(1.2, 0.3, -0.4, 0.9, 7, -11),
    ];
    const points = [
      ui.Offset.zero,
      ui.Offset(1, 0),
      ui.Offset(0, 1),
      ui.Offset(123.4, -56.7),
      ui.Offset(595.28, 841.89),
    ];

    test('applyAffine and matrix4Of agree with core.Affine2.apply', () {
      for (final m in transforms) {
        final m4 = interop.matrix4Of(m);
        expect(m4.length, 16);
        expect(InkPageGeometry.matrix4Of(m), m4);
        for (final p in points) {
          final (x, y) = m.apply(p.dx, p.dy);
          final q = interop.applyAffine(m, p);
          expect(q.dx, closeTo(x, 1e-9));
          expect(q.dy, closeTo(y, 1e-9));
          expect(InkPageGeometry.applyAffine(m, p), q);
          // column-major: x' = m4[0]·x + m4[4]·y + m4[12]
          expect(m4[0] * p.dx + m4[4] * p.dy + m4[12], closeTo(x, 1e-9));
          expect(m4[1] * p.dx + m4[5] * p.dy + m4[13], closeTo(y, 1e-9));
          expect(m4[15], 1);
        }
      }
    });

    test('matrix4Of is what the engine applies (Path.transform)', () {
      for (final m in transforms) {
        for (final p in points) {
          final path = ui.Path()
            ..moveTo(p.dx, p.dy)
            ..lineTo(p.dx, p.dy);
          final b = path.transform(interop.matrix4Of(m)).getBounds();
          final (x, y) = m.apply(p.dx, p.dy);
          expect(b.left, closeTo(x, 1e-3));
          expect(b.top, closeTo(y, 1e-3));
        }
      }
    });

    test('size / rect conversions round-trip', () {
      expect(
        interop.sizeOf(core.PageSize.a4Portrait),
        ui.Size(
          core.PageSize.a4Portrait.width,
          core.PageSize.a4Portrait.height,
        ),
      );
      const r = ui.Rect.fromLTRB(1.5, -2, 300.25, 400);
      final pr = interop.pageRectOf(r);
      expect(
        (pr.left, pr.top, pr.right, pr.bottom),
        (1.5, -2.0, 300.25, 400.0),
      );
      expect(interop.rectOf(pr), r);
      expect(InkPageGeometry.rectOf(pr), r);
      expect(InkPageGeometry.pageRectOf(r), pr);
    });

    test('filterAccepts: 3 filters × 5 tools', () {
      for (final tool in core.PenTool.values) {
        final hl = tool == core.PenTool.highlighter;
        expect(interop.filterAccepts(core.StrokeFilter.all, tool), isTrue);
        expect(
          interop.filterAccepts(core.StrokeFilter.highlighterOnly, tool),
          hl,
        );
        expect(
          interop.filterAccepts(core.StrokeFilter.exceptHighlighter, tool),
          !hl,
        );
      }
    });

    test('opaqueArgb forces alpha 0xFF (arithmetic)', () {
      expect(interop.opaqueArgb(0x00112233), 0xFF112233);
      expect(interop.opaqueArgb(0x80FFFFFF), 0xFFFFFFFF);
      expect(interop.opaqueArgb(0xFF000000), 0xFF000000);
      expect(interop.opaqueArgb(0x7F000001), 0xFF000001);
    });
  });

  group('thumbnailOf', () {
    test('pageId / contentRevision from the page, PNG bytes as is', () {
      final page = SyntheticInk.page(pageId: 'pg-7')
          .copyWith(contentRevision: 31);
      final png = Uint8List.fromList([137, 80, 78, 71, 1, 2, 3]);
      final t = interop.thumbnailOf(page, width: 320, height: 452, png: png);
      expect(t.pageId, 'pg-7');
      expect(t.contentRevision, 31);
      expect(t.mimeType, 'image/png');
      expect((t.width, t.height), (320, 452));
      expect(t.bytes, same(png));
      expect(t.isStaleFor(page), isFalse);
      expect(t.isStaleFor(page.copyWith(contentRevision: 32)), isTrue);
    });
  });

  group('InkPageContent.fromCore', () {
    core.Stroke s(String id, int createdAt, {String pageId = 'p1'}) =>
        interop.strokeFromData(
          _data(2),
          id: id,
          pageId: pageId,
          style: core.StrokeStyle.defaultsFor(core.PenTool.ballpoint),
          createdAt: createdAt,
        );

    test('drops deleted strokes, sorts by compareOrder, keeps identity', () {
      final a = s('a', 5);
      final b = s('b', 1);
      final c = s('c', 5); // same createdAt as a → id order
      final gone = s('d', 2).copyWith(deletedAt: 10);
      final content = InkPageContent.fromCore(
        page: SyntheticInk.page(),
        strokes: [c, a, gone, b],
        revision: 4,
      );
      expect(content.strokes.map((x) => x.id), ['b', 'a', 'c']);
      expect(content.strokeById('d'), isNull);
      expect(content.zIndexOf('d'), -1);
      expect(content.revision, 4);
      expect(content.strokes[1], same(InkStroke.of(a)));
      expect(InkStroke.of(a), same(interop.inkStrokeOf(a)));
      final again = InkPageContent.fromCore(
        page: SyntheticInk.page(),
        strokes: [b, a, c],
        revision: 4,
      );
      expect(again.strokeById('a'), same(content.strokeById('a')));
      expect(again, content);
      expect(
        () => content.strokes.add(InkStroke.of(a)),
        throwsUnsupportedError,
      );
    });

    test('a stroke of another page → ArgumentError', () {
      expect(
        () => InkPageContent.fromCore(
          page: SyntheticInk.page(),
          strokes: [
            s('a', 1),
            s('x', 2, pageId: 'p2'),
          ],
          revision: 1,
        ),
        throwsArgumentError,
      );
    });

    test('page values: size, background spec', () {
      final content = InkPageContent.fromCore(
        page: SyntheticInk.page(
          size: const core.PageSize(841.8898, 595.2756),
          background: const core.BlankBackground(
            paperColorArgb: core.PaperColors.black,
          ),
        ),
        strokes: const [],
        revision: 0,
      );
      expect(content.pageSize, const ui.Size(841.8898, 595.2756));
      expect(content.background.kind, InkBackgroundKind.blank);
      expect(content.background.isDarkPaper, isTrue);
    });
  });

  group('InkBackgroundSpec.fromCore', () {
    test('the 4 CORE backgrounds', () {
      const template = core.PageTemplate(
        kind: core.PageTemplateKind.grid,
        spacing: 20,
      );
      expect(
        InkBackgroundSpec.fromCore(const core.BlankBackground()),
        const InkBackgroundSpec(kind: InkBackgroundKind.blank),
      );
      expect(
        InkBackgroundSpec.fromCore(
          const core.TemplateBackground(
            template: template,
            paperColorArgb: 0xFFFFF8E7,
          ),
        ),
        const InkBackgroundSpec(
          kind: InkBackgroundKind.template,
          paperColorArgb: 0xFFFFF8E7,
          template: template,
        ),
      );
      expect(
        InkBackgroundSpec.fromCore(
          const core.PdfBackground(assetId: 'asset-1', pdfPageIndex: 3),
        ),
        const InkBackgroundSpec(
          kind: InkBackgroundKind.pdf,
          assetId: 'asset-1',
          pdfPageIndex: 3,
        ),
      );
      expect(
        InkBackgroundSpec.fromCore(
          const core.ImageBackground(
            assetId: 'img-1',
            paperColorArgb: core.PaperColors.black,
          ),
        ),
        // (v2.0) the image fit comes along (ImageBackground default: contain)
        const InkBackgroundSpec(
          kind: InkBackgroundKind.image,
          paperColorArgb: core.PaperColors.black,
          assetId: 'img-1',
          imageFit: core.ImageFit.contain,
        ),
      );
      expect(
        InkBackgroundSpec.fromCore(
          const core.ImageBackground(
            assetId: 'img-1',
            fit: core.ImageFit.cover,
          ),
        ).imageFit,
        core.ImageFit.cover,
      );
      expect(
        interop.backgroundSpecOf(const core.BlankBackground()),
        InkBackgroundSpec.fromCore(const core.BlankBackground()),
      );
    });
  });
}
