// PDF T25b — text box and formula references → draw items (m5-7/06-pdf 6.2.4 · 6.2.5 · 6.2.10,
// PDF-M2 · M3) with solid RGBA fake raster ports: the text object path (one item per line, F ∘ T,
// fonts read once), the background fill first, the raster fallback (fonts not ready, uncovered
// characters, no lines, font read failed) with its warning, formula contain + capped density,
// formula failures and timeout, the ledger, and the three big samples ≤ 4 Mpx each.
import 'dart:ui' as ui;

import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:pdf_io/pdf_io.dart';
import 'package:pdf_io/src/export/export_memory.dart';
import 'package:pdf_io/src/export/object_geometry.dart';
import 'package:pdf_io/src/export/object_resolver.dart';
import 'package:pdf_io/src/export/raster_ports.dart';
import 'package:pdf_io/testing.dart';

import '../support/fake_rasterizers.dart';
import '../support/object_fixtures.dart';

const int mib = 1024 * 1024;
const double dpi300 = 300 / 72;

final class _World {
  _World({
    FakeRasterMode textMode = FakeRasterMode.solid,
    FakeRasterMode mathMode = FakeRasterMode.solid,
    Map<core.ElementId, ui.Size?>? layouts,
    bool fontFails = false,
    Map<String, Uint8List> assets = const {},
  }) : text = FakeTextRasterizer(mode: textMode),
       math = FakeMathRasterizer(layoutSizes: layouts, mode: mathMode),
       fonts = FakeFontSource(fail: fontFails) {
    assets.forEach(gateway.arriveBytes);
    resolver = ObjectResolver(
      gateway: gateway,
      math: math,
      text: text,
      fontBytes: fonts.call,
    );
  }

  final FakePdfNoteGateway gateway = FakePdfNoteGateway();
  final FakeTextRasterizer text;
  final FakeMathRasterizer math;
  final FakeFontSource fonts;
  late final ObjectResolver resolver;
  ExportMemoryLedger get ledger => resolver.ledger;
}

core.ElementFrame _frame(
  double l,
  double t,
  double w,
  double h, [
  double r = 0,
]) => core.ElementFrame(core.PageRect(l, t, l + w, t + h), rotation: r);

core.TextBoxObject _box({
  String id = 'text-1',
  String text = '안녕 hello\n둘째 줄',
  core.ElementFrame? frame,
  bool bold = false,
  int? background,
}) => core.TextBoxObject(
  id: id,
  pageId: 'p1',
  frame: frame ?? _frame(100, 200, 160, 60),
  text: text,
  style: core.TextBoxStyle(
    fontSizePt: 14,
    colorArgb: 0xFF112233,
    bold: bold,
    backgroundArgb: background,
  ),
  createdAt: 1,
);

const List<PdfTextLine> _twoLines = [
  (text: '안녕 hello\n', x: 0, baselineY: 15, width: 70),
  (text: '둘째 줄', x: 2.5, baselineY: 34.6, width: 48),
];

core.MathObject _formula({String id = 'math-1', core.ElementFrame? frame}) =>
    core.MathObject(
      id: id,
      pageId: 'p1',
      frame: frame ?? _frame(50, 400, 200, 100),
      latex: r'\frac{a}{b}',
      style: const core.MathStyle(),
      createdAt: 1,
    );

PdfAffine _unitTo(double w, double h, core.ElementFrame f) =>
    unitSquareToRect(ui.Rect.fromLTWH(0, 0, w, h)).then(PdfAffine.frame(f));

/// FlutterError.reportError calls during [body].
Future<List<FlutterErrorDetails>> _reported(
  Future<void> Function() body,
) async {
  final reported = <FlutterErrorDetails>[];
  final previous = FlutterError.onError;
  FlutterError.onError = reported.add;
  try {
    await body();
  } finally {
    FlutterError.onError = previous;
  }
  return reported;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('text box — text objects (6.2.4 ②)', () {
    test('one PdfTextItem per line: F ∘ T(x, baseline), font, size, colour, no line break', () async {
      final w = _World();
      final frame = _frame(100, 200, 160, 60, 0.5);
      final ctx = ResolveContext();
      final items = await w.resolver.resolve(
        PdfTextBoxRef(_box(frame: frame), _twoLines),
        ctx,
      );
      expect(items, hasLength(2));
      final f = PdfAffine.frame(frame);
      expect(items[0], const TypeMatcher<PdfTextItem>());
      final first = items[0] as PdfTextItem, second = items[1] as PdfTextItem;
      expect(first.text, '안녕 hello');
      expect(second.text, '둘째 줄');
      expect(first.matrix, textSpaceAt(0, 15).then(f));
      expect(second.matrix, textSpaceAt(2.5, 34.6).then(f));
      for (final item in [first, second]) {
        expect(item.fontId, PdfComposeOpcodes.fontRegular);
        expect(item.fontSize, 14);
        expect(item.colorArgb, 0xFF112233);
      }
      // the baseline start lands on the rotated frame
      final origin = first.matrix.apply(ui.Offset.zero);
      final expected = f.apply(const ui.Offset(0, 15));
      expect(origin.dx, closeTo(expected.dx, 1e-9));
      expect(origin.dy, closeTo(expected.dy, 1e-9));
      // glyph up (+y in text space) is screen up (−y) in frame space
      final up = textSpaceAt(0, 15).apply(const ui.Offset(0, 1));
      expect(up.dy, 14);
      expect(ctx.fontBytes.keys, [PdfComposeOpcodes.fontRegular]);
      expect(
        ctx.fontBytes[PdfComposeOpcodes.fontRegular],
        FakeFontSource.regular,
      );
      expect(w.fonts.reads, [false]);
      expect(w.text.calls, isEmpty);
      expect(ctx.warnings, isEmpty);
      expect(
        w.ledger.peakBytes,
        0,
        reason: 'text objects hold no image memory',
      );
    });

    test('empty and whitespace-only lines are left out', () async {
      final w = _World();
      final items = await w.resolver.resolve(
        PdfTextBoxRef(_box(text: 'a\n\n  \nb'), const [
          (text: 'a\n', x: 0, baselineY: 15, width: 8),
          (text: '\n', x: 0, baselineY: 34, width: 0),
          (text: '  \n', x: 0, baselineY: 53, width: 6),
          (text: 'b', x: 0, baselineY: 72, width: 8),
        ]),
        ResolveContext(),
      );
      expect([for (final i in items) (i as PdfTextItem).text], ['a', 'b']);
    });

    test('bold → fontBold; each font file is read once per export', () async {
      final w = _World();
      final ctx = ResolveContext();
      final bold = await w.resolver.resolve(
        PdfTextBoxRef(_box(id: 'b1', bold: true), _twoLines),
        ctx,
      );
      await w.resolver.resolve(
        PdfTextBoxRef(_box(id: 'b2', bold: true), _twoLines),
        ctx,
      );
      await w.resolver.resolve(PdfTextBoxRef(_box(id: 'r1'), _twoLines), ctx);
      await w.resolver.resolve(PdfTextBoxRef(_box(id: 'r2'), _twoLines), ctx);
      expect((bold.first as PdfTextItem).fontId, PdfComposeOpcodes.fontBold);
      expect(w.fonts.reads, [true, false]);
      expect(ctx.fontBytes, {
        PdfComposeOpcodes.fontBold: FakeFontSource.bold,
        PdfComposeOpcodes.fontRegular: FakeFontSource.regular,
      });
      // a new export (context) reads again
      final next = ResolveContext();
      await w.resolver.resolve(PdfTextBoxRef(_box(id: 'r3'), _twoLines), next);
      expect(w.fonts.reads, [true, false, false]);
    });

    test('background → one fill under the text: the rotated frame corners, alpha → opacity', () async {
      final w = _World();
      final frame = _frame(100, 200, 160, 60, -0.4);
      final items = await w.resolver.resolve(
        PdfTextBoxRef(_box(frame: frame, background: 0x80FFEE00), _twoLines),
        ResolveContext(),
      );
      expect(items, hasLength(3));
      final fill = items.first as PdfFillItem;
      expect(fill.path.verbs, [0, 1, 1, 1, 3]);
      final corners = frame.corners;
      for (var i = 0; i < 4; i++) {
        expect(fill.path.coords[2 * i], closeTo(corners[i].x, 1e-3));
        expect(fill.path.coords[2 * i + 1], closeTo(corners[i].y, 1e-3));
      }
      expect(fill.colorArgb, 0xFFFFEE00);
      expect(fill.opacity, closeTo(0x80 / 255, 1e-12));
      expect(fill.alpha255, 0x80);
      expect(items.skip(1), everyElement(isA<PdfTextItem>()));
    });

    test('a fully transparent background draws no fill', () async {
      final w = _World();
      final items = await w.resolver.resolve(
        PdfTextBoxRef(_box(background: 0x00FFFFFF), _twoLines),
        ResolveContext(),
      );
      expect(items, everyElement(isA<PdfTextItem>()));
    });

    test(
      'empty text → only the background, nothing rasterized, no warning',
      () async {
        final w = _World();
        final ctx = ResolveContext();
        final items = await w.resolver.resolve(
          PdfTextBoxRef(_box(text: '  \n', background: 0xFFEEEEEE), const []),
          ctx,
        );
        expect(items.single, isA<PdfFillItem>());
        expect(w.text.calls, isEmpty);
        expect(w.fonts.reads, isEmpty);
        expect(ctx.warnings, isEmpty);
      },
    );
  });

  group('text box — raster fallback (6.2.4 ③ · 6.2.5, CP-PDF-8)', () {
    Future<void> expectRaster(
      _World w,
      ResolveContext ctx,
      core.TextBoxObject box,
      List<PdfTextLine> lines,
    ) async {
      ctx.notePageNumber = 4;
      final items = await w.resolver.resolve(PdfTextBoxRef(box, lines), ctx);
      final r = box.frame.rect;
      final size = ui.Size(r.width, r.height);
      final k = cappedPixelsPerPt(dpi300, size);
      expect(w.text.calls.last.pixelsPerPt, k, reason: 'the cap formula value');
      final image = items.whereType<PdfImageItem>().single;
      final data = image.image as PdfRgbaData;
      expect(
        (data.width, data.height),
        (rasterPixelSize(size, k).width, rasterPixelSize(size, k).height),
      );
      expect(data.hasAlpha, isTrue);
      expect(image.matrix, _unitTo(r.width, r.height, box.frame));
      expect(items.whereType<PdfTextItem>(), isEmpty);
      final warning = ctx.warnings.whereType<PdfExportRasterizedText>().single;
      expect(warning.notePageNumbers, [4]);
    }

    test('fonts not ready → raster, no font read', () async {
      final w = _World();
      final ctx = ResolveContext(fontsReady: false);
      await expectRaster(
        w,
        ctx,
        _box(frame: _frame(10, 10, 160, 60, 0.3)),
        _twoLines,
      );
      expect(w.fonts.reads, isEmpty);
      expect(ctx.fontBytes, isEmpty);
    });

    test('a character NoteSans does not cover → raster', () async {
      final w = _World();
      await expectRaster(
        w,
        ResolveContext(),
        _box(text: 'smile \u{1F600}'),
        _twoLines,
      );
      expect(w.fonts.reads, isEmpty);
    });

    test('INK gave no lines → raster', () async {
      final w = _World();
      await expectRaster(w, ResolveContext(), _box(), const []);
    });

    test(
      'font read failed → raster; not read again in the same export',
      () async {
        final w = _World(fontFails: true);
        final ctx = ResolveContext();
        await expectRaster(w, ctx, _box(id: 'a'), _twoLines);
        await expectRaster(w, ctx, _box(id: 'b'), _twoLines);
        expect(w.fonts.reads, [false]);
        expect(ctx.fontBytes, isEmpty);
        expect(ctx.failedFontIds, {PdfComposeOpcodes.fontRegular});
      },
    );

    test('the background stays under the raster', () async {
      final w = _World();
      final items = await w.resolver.resolve(
        PdfTextBoxRef(_box(background: 0xFFFFF59D), const []),
        ResolveContext(),
      );
      expect(items.map((i) => i.runtimeType), [PdfFillItem, PdfImageItem]);
    });

    for (final mode in [FakeRasterMode.fail, FakeRasterMode.throws]) {
      test(
        'raster ${mode.name} → the box is left out (background stays), warned, reported once',
        () async {
          final w = _World(textMode: mode);
          final ctx = ResolveContext()..notePageNumber = 2;
          late List<PdfDrawItem> first, second;
          final reported = await _reported(() async {
            first = await w.resolver.resolve(
              PdfTextBoxRef(_box(id: 'a', background: 0xFFEEEEEE), const []),
              ctx,
            );
            ctx.notePageNumber = 5;
            second = await w.resolver.resolve(
              PdfTextBoxRef(_box(id: 'b'), const []),
              ctx,
            );
          });
          expect(first.single, isA<PdfFillItem>());
          expect(second, isEmpty);
          expect(
            ctx.warnings
                .whereType<PdfExportRasterizedText>()
                .single
                .notePageNumbers,
            [2, 5],
          );
          expect(reported, hasLength(1));
          expect(reported.single.library, 'pdf_io');
          expect(w.ledger.heldBytes, 0);
          expect(w.resolver.heldImageCount, 0);
        },
      );
    }
  });

  group('formula (6.2.4 PdfMathRef)', () {
    test('contain-fitted raster: F ∘ U(contain), density = cap(s · 300 dpi) of the layout', () async {
      final w = _World(layouts: {'math-1': const ui.Size(40, 40)});
      final frame = _frame(50, 400, 200, 100, 0.25);
      final ctx = ResolveContext();
      final items = await w.resolver.resolve(
        PdfMathRef(_formula(frame: frame)),
        ctx,
      );
      final image = items.single as PdfImageItem;
      // s = min(200/40, 100/40) = 2.5 → contain (50, 0, 100, 100)
      const contain = ui.Rect.fromLTWH(50, 0, 100, 100);
      expect(
        image.matrix,
        unitSquareToRect(contain).then(PdfAffine.frame(frame)),
      );
      final k = cappedPixelsPerPt(
        2.5 * PdfTuning.mathRasterDpi / 72,
        const ui.Size(40, 40),
      );
      expect(k, closeTo(2.5 * dpi300, 1e-12), reason: 'small: not capped');
      expect(w.math.calls.single.pixelsPerPt, k);
      final data = image.image as PdfRgbaData;
      expect((data.width, data.height), (417, 417));
      expect(data.hasAlpha, isTrue);
      expect(ctx.warnings, isEmpty);
      expect(w.ledger.bytesOf(ExportMemoryKind.rgba), 417 * 417 * 4);
      w.resolver.sent([data]);
      expect(w.ledger.heldBytes, 0);
    });

    test(
      'invalid LaTeX (layout null) → left out and warned, nothing rasterized',
      () async {
        final w = _World(layouts: {'math-1': null});
        final ctx = ResolveContext()..notePageNumber = 6;
        expect(await w.resolver.resolve(PdfMathRef(_formula()), ctx), isEmpty);
        expect(w.math.calls, isEmpty);
        expect(
          ctx.warnings
              .whereType<PdfExportSkippedFormulas>()
              .single
              .notePageNumbers,
          [6],
        );
      },
    );

    for (final mode in [FakeRasterMode.fail, FakeRasterMode.throws]) {
      test('raster ${mode.name} → left out and warned, nothing held', () async {
        final w = _World(mathMode: mode);
        final ctx = ResolveContext()..notePageNumber = 3;
        expect(await w.resolver.resolve(PdfMathRef(_formula()), ctx), isEmpty);
        expect(
          ctx.warnings
              .whereType<PdfExportSkippedFormulas>()
              .single
              .notePageNumbers,
          [3],
        );
        expect(w.ledger.heldBytes, 0);
        expect(
          w.ledger.peakBytes,
          greaterThan(0),
          reason: 'room was taken before the call',
        );
      });
    }

    test('a raster slower than exportMathRasterTimeout (3 s) → left out and warned', () {
      fakeAsync((async) {
        final w = _World(mathMode: FakeRasterMode.hang);
        final ctx = ResolveContext()..notePageNumber = 8;
        List<PdfDrawItem>? items;
        w.resolver.resolve(PdfMathRef(_formula()), ctx).then((v) => items = v);
        async.elapse(
          PdfTuning.exportMathRasterTimeout - const Duration(milliseconds: 1),
        );
        expect(items, isNull);
        expect(w.ledger.heldBytes, greaterThan(0));
        async.elapse(const Duration(milliseconds: 1));
        expect(items, isEmpty);
        expect(
          ctx.warnings
              .whereType<PdfExportSkippedFormulas>()
              .single
              .notePageNumbers,
          [8],
        );
        expect(w.ledger.heldBytes, 0);
      });
    });

    test(
      'a cancel while the raster runs → PdfIoException(cancelled) at once',
      () async {
        final w = _World(mathMode: FakeRasterMode.hang);
        final cancel = PdfCancelSignal();
        final ctx = ResolveContext(cancel: cancel);
        final future = w.resolver.resolve(PdfMathRef(_formula()), ctx);
        await pumpEventQueue();
        cancel.cancel();
        await expectLater(
          future,
          throwsA(
            isA<PdfIoException>().having(
              (e) => e.code,
              'code',
              PdfErrorCode.cancelled,
            ),
          ),
        );
        expect(w.ledger.heldBytes, 0);
        expect(ctx.warnings, isEmpty);
      },
    );
  });

  group('ledger (6.2.10)', () {
    test(
      'a raster is held as rgba until sent; dispose releases the rest',
      () async {
        final w = _World();
        final ctx = ResolveContext(fontsReady: false);
        final a =
            (await w.resolver.resolve(
                  PdfTextBoxRef(_box(id: 'a'), _twoLines),
                  ctx,
                )).single
                as PdfImageItem;
        final b =
            (await w.resolver.resolve(PdfMathRef(_formula()), ctx)).single
                as PdfImageItem;
        expect(w.resolver.heldImageCount, 2);
        final aBytes = a.image.byteLength, bBytes = b.image.byteLength;
        expect(w.ledger.bytesOf(ExportMemoryKind.rgba), aBytes + bBytes);
        w.resolver.sent([a.image]);
        expect(w.ledger.bytesOf(ExportMemoryKind.rgba), bBytes);
        w.resolver.dispose();
        expect(w.ledger.heldBytes, 0);
        expect(w.ledger.peakCount, 2);
      },
    );

    test(
      'room for a raster is taken before the call: the JPEG cache gives way',
      () async {
        final ledger = ExportMemoryLedger();
        var cachedDuringCall = -1;
        final resolver = ObjectResolver(
          gateway: FakePdfNoteGateway(),
          text: _ProbeText(
            () => cachedDuringCall = ledger.bytesOf(ExportMemoryKind.cache),
          ),
          math: FakeMathRasterizer(),
          fontBytes: FakeFontSource().call,
          ledger: ledger,
        );
        expect(resolver.cache.offer('jpeg', Uint8List(14 * mib)), isTrue);
        expect(ledger.bytesOf(ExportMemoryKind.cache), 14 * mib);
        final items = await resolver.resolve(
          PdfTextBoxRef(pageSizeTextBox(), const []),
          ResolveContext(),
        );
        expect(items.single, isA<PdfImageItem>());
        expect(
          cachedDuringCall,
          0,
          reason: 'evicted before the raster was drawn',
        );
        expect(resolver.cache.length, 0);
        expect(ledger.peakBytes, lessThanOrEqualTo(16 * mib));
      },
    );
  });

  group('big samples (PDF-M3): each RGBA ≤ 4 Mpx, ledger ≤ 16 MiB', () {
    test('page-size text box 500 × 700 pt → ≈ 249 dpi raster', () async {
      final w = _World();
      final box = pageSizeTextBox();
      final ctx = ResolveContext();
      final image =
          (await w.resolver.resolve(PdfTextBoxRef(box, const []), ctx)).single
              as PdfImageItem;
      final k = w.text.calls.single.pixelsPerPt;
      expect(k, cappedPixelsPerPt(dpi300, const ui.Size(500, 700)));
      expect(k * 72, closeTo(249, 0.5));
      final data = image.image as PdfRgbaData;
      expect(
        data.width * data.height,
        lessThanOrEqualTo(PdfTuning.maxRasterPixels),
      );
      expect(w.ledger.peakBytes, lessThanOrEqualTo(16 * mib));
      expect(ctx.warnings.single, isA<PdfExportRasterizedText>());
    });

    test('700 × 700 pt formula → ≈ 211 dpi in the frame', () async {
      final formula = bigMathObject();
      // laid out at 350 × 350 pt → contain s = 2 → 300 dpi would be 8.33 px/pt of the layout
      final w = _World(layouts: {formula.id: const ui.Size(350, 350)});
      final image =
          (await w.resolver.resolve(
                PdfMathRef(formula),
                ResolveContext(),
              )).single
              as PdfImageItem;
      final k = w.math.calls.single.pixelsPerPt;
      expect(
        k,
        cappedPixelsPerPt(
          2 * PdfTuning.mathRasterDpi / 72,
          const ui.Size(350, 350),
        ),
      );
      expect(k / 2, closeTo(2.93, 0.01), reason: 'px per frame pt');
      final data = image.image as PdfRgbaData;
      expect(
        data.width * data.height,
        lessThanOrEqualTo(PdfTuning.maxRasterPixels),
      );
      expect(w.ledger.peakBytes, lessThanOrEqualTo(16 * mib));
    });

    test('the three in one page (PNG 6000 × 4000, text box, formula), sent one by one', () async {
      final formula = bigMathObject();
      final w = _World(
        layouts: {formula.id: const ui.Size(700, 700)},
        assets: {'big': bigPng6000x4000()},
      );
      final ctx = ResolveContext();
      final refs = <PdfPlanItem>[
        PdfAssetImageRef.object(assetId: 'big', frame: _frame(0, 0, 600, 400)),
        PdfTextBoxRef(pageSizeTextBox(), const []),
        PdfMathRef(formula),
      ];
      for (final ref in refs) {
        final items = await w.resolver.resolve(ref, ctx);
        final data = (items.single as PdfImageItem).image as PdfRgbaData;
        expect(
          data.width * data.height,
          lessThanOrEqualTo(PdfTuning.maxRasterPixels),
          reason: '$ref',
        );
        expect(w.ledger.heldBytes, lessThanOrEqualTo(16 * mib));
        w.resolver.sent([data]);
      }
      expect(w.ledger.peakBytes, lessThanOrEqualTo(16 * mib));
      expect(w.ledger.overBudget, 0);
      expect(w.ledger.heldBytes, 0);
    });
  });

  test(
    'warnings in the result order: images, rasterized text, formulas',
    () async {
      final w = _World(layouts: {'math-1': null});
      final ctx = ResolveContext();
      ctx.notePageNumber = 3;
      await w.resolver.resolve(PdfMathRef(_formula()), ctx);
      ctx.notePageNumber = 2;
      await w.resolver.resolve(PdfTextBoxRef(_box(), const []), ctx);
      ctx.notePageNumber = 1;
      await w.resolver.resolve(
        PdfAssetImageRef.object(assetId: 'nope', frame: _frame(0, 0, 10, 10)),
        ctx,
      );
      expect(ctx.warnings.map((e) => e.runtimeType), [
        PdfExportMissingImages,
        PdfExportRasterizedText,
        PdfExportSkippedFormulas,
      ]);
    },
  );
}

/// Text port that runs [onCall] when asked, then answers like the solid fake.
final class _ProbeText implements PdfTextRasterizer {
  _ProbeText(this.onCall);
  final void Function() onCall;
  final FakeTextRasterizer _inner = FakeTextRasterizer();

  @override
  Future<PdfRgbaData?> rasterize(
    core.TextBoxObject object, {
    required double pixelsPerPt,
  }) {
    onCall();
    return _inner.rasterize(object, pixelsPerPt: pixelsPerPt);
  }
}
