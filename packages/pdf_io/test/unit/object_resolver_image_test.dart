// PDF T25a — image references → draw items (m5-7/06-pdf 6.2.4 · 6.2.10) with the fake gateway
// and the real engine decoder (VM): missing bytes, the JPEG fast path, the slow path (EXIF 6,
// Adobe CMYK, > 8 MiB, PNG alpha), background fit, the big samples against the 16 MiB ledger
// (PDF-M3, 수정 2회차, CP-PDF-14 ②) and the JPEG cache.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:pdf_io/pdf_io.dart';
import 'package:pdf_io/src/export/export_memory.dart';
import 'package:pdf_io/src/export/object_geometry.dart';
import 'package:pdf_io/src/export/object_resolver.dart';
import 'package:pdf_io/testing.dart';

import '../support/object_fixtures.dart';

const int mib = 1024 * 1024;

core.ElementFrame _frame(
  double l,
  double t,
  double w,
  double h, [
  double r = 0,
]) => core.ElementFrame(core.PageRect(l, t, l + w, t + h), rotation: r);

PdfAssetImageRef _object(String id, [core.ElementFrame? frame]) =>
    PdfAssetImageRef.object(
      assetId: id,
      frame: frame ?? _frame(10, 20, 64, 48),
    );

({FakePdfNoteGateway gateway, ObjectResolver resolver}) _world(
  Map<String, Uint8List> assets,
) {
  final gateway = FakePdfNoteGateway();
  assets.forEach(gateway.arriveBytes);
  return (gateway: gateway, resolver: ObjectResolver(gateway: gateway));
}

int _reads(FakePdfNoteGateway g) =>
    g.calls.where((c) => c == 'readAssetBytes').length;

PdfImageItem _single(List<PdfDrawItem> items) {
  expect(items, hasLength(1));
  return items.single as PdfImageItem;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('missing bytes', () {
    test(
      'default policy: left out, PdfExportMissingImages with the page',
      () async {
        final w = _world({});
        final ctx = ResolveContext()..notePageNumber = 3;
        expect(await w.resolver.resolve(_object('nope'), ctx), isEmpty);
        ctx.notePageNumber = 1;
        await w.resolver.resolve(_object('nope'), ctx);
        final warnings = ctx.warnings;
        expect(warnings, hasLength(1));
        expect((warnings.single as PdfExportMissingImages).notePageNumbers, [
          1,
          3,
        ]);
        expect(w.resolver.ledger.peakBytes, 0);
      },
    );

    test('fail policy: PdfIoException(assetMissing) with the page', () async {
      final w = _world({});
      final ctx = ResolveContext(missingAssetPolicy: PdfMissingAssetPolicy.fail)
        ..notePageNumber = 7;
      await expectLater(
        w.resolver.resolve(_object('nope'), ctx),
        throwsA(
          isA<PdfIoException>()
              .having((e) => e.code, 'code', PdfErrorCode.assetMissing)
              .having((e) => e.detail, 'detail', '7'),
        ),
      );
    });

    test(
      'not decodable → left out with the same warning, ledger back to 0',
      () async {
        final broken = Uint8List.fromList(
          PdfObjectFixtures.png().sublist(0, 60),
        ); // IHDR kept, IDAT cut
        final w = _world({'b': broken});
        final ctx = ResolveContext()..notePageNumber = 2;
        expect(await w.resolver.resolve(_object('b'), ctx), isEmpty);
        expect(ctx.missingImagePages, [2]);
        expect(w.resolver.ledger.heldBytes, 0);
        expect(w.resolver.heldImageCount, 0);
      },
    );
  });

  group('JPEG fast path: bytes as stored', () {
    for (final (name, bytes) in [
      ('baseline', PdfObjectFixtures.jpegBaseline64x48),
      ('progressive', PdfObjectFixtures.jpegProgressive64x48),
      ('gray', PdfObjectFixtures.jpegGray64x48),
    ]) {
      test(name, () async {
        final w = _world({'j': bytes});
        final item = _single(
          await w.resolver.resolve(_object('j'), ResolveContext()),
        );
        final data = item.image as PdfJpegData;
        expect(identical(data.bytes, bytes), isTrue);
        expect((data.width, data.height), (64, 48));
        // held as `encoded` until sent
        expect(
          w.resolver.ledger.bytesOf(ExportMemoryKind.encoded),
          bytes.length,
        );
        expect(w.resolver.ledger.bytesOf(ExportMemoryKind.rgba), 0);
      });
    }
  });

  group('slow path: engine decode → RGBA', () {
    test('EXIF 6 → turned 48 × 64, opaque', () async {
      final w = _world({'e': PdfObjectFixtures.jpegExif6_64x48});
      final data =
          _single(await w.resolver.resolve(_object('e'), ResolveContext()))
                  .image
              as PdfRgbaData;
      expect((data.width, data.height), (48, 64));
      expect(data.rgba.length, 48 * 64 * 4);
      expect(data.hasAlpha, isFalse);
      expect(w.resolver.ledger.bytesOf(ExportMemoryKind.rgba), 48 * 64 * 4);
      expect(
        w.resolver.ledger.bytesOf(ExportMemoryKind.encoded),
        0,
        reason: 'the input is released once decoded',
      );
    });

    test('Adobe CMYK → RGB pixels (S-9)', () async {
      final w = _world({'c': PdfObjectFixtures.jpegAdobeCmyk64x48});
      final data =
          _single(await w.resolver.resolve(_object('c'), ResolveContext()))
                  .image
              as PdfRgbaData;
      expect((data.width, data.height, data.hasAlpha), (64, 48, false));
      // the sample is a gradient with blue 128 on the left: not inverted to yellow-ish
      final left = data.rgba.sublist((24 * 64 + 4) * 4, (24 * 64 + 4) * 4 + 4);
      expect(left[2], greaterThan(left[0]), reason: 'blue > red at x = 4');
    });

    test('JPEG over 8 MiB → slow path', () async {
      final big = paddedJpeg(
        PdfObjectFixtures.jpegBaseline64x48,
        PdfTuning.exportJpegInlineMaxBytes,
      );
      final w = _world({'big': big});
      final data =
          _single(await w.resolver.resolve(_object('big'), ResolveContext()))
                  .image
              as PdfRgbaData;
      expect((data.width, data.height), (64, 48));
      expect(w.resolver.ledger.peakBytes, big.length + 64 * 48 * 4);
    });

    test(
      'PNG alpha: RGBA PNG with alpha → hasAlpha, RGB PNG → opaque',
      () async {
        final w = _world({
          'a': PdfObjectFixtures.png(width: 20, height: 10, alpha: true),
          'o': PdfObjectFixtures.png(width: 20, height: 10),
        });
        final a =
            _single(await w.resolver.resolve(_object('a'), ResolveContext()))
                    .image
                as PdfRgbaData;
        final o =
            _single(await w.resolver.resolve(_object('o'), ResolveContext()))
                    .image
                as PdfRgbaData;
        expect((a.width, a.height, a.hasAlpha), (20, 10, true));
        expect(a.rgba[3], 128, reason: 'straight alpha of the left half');
        expect(a.rgba[19 * 4 + 3], 255);
        expect(a.rgba[0], 0, reason: 'red = x, not premultiplied away');
        // straight, not premultiplied (the engine's premultiplied store rounds by one)
        expect(a.rgba[2], closeTo(160, 1));
        expect((o.width, o.height, o.hasAlpha), (20, 10, false));
      },
    );
  });

  group('placement (6.2.3)', () {
    test('object: F ∘ U maps the unit square onto the frame corners', () async {
      for (final rotation in [0.0, 0.5, -1.2, 3.14159]) {
        final frame = _frame(30, 40, 120, 60, rotation);
        final m = imagePlacement(_object('x', frame), 1, 1);
        final c = frame.corners;
        void near(ui.Offset p, core.PagePoint q) {
          expect(p.dx, closeTo(q.x, 1e-6));
          expect(p.dy, closeTo(q.y, 1e-6));
        }

        near(m.apply(const ui.Offset(0, 1)), c[0]); // top-left pixel row
        near(m.apply(const ui.Offset(1, 1)), c[1]);
        near(m.apply(const ui.Offset(1, 0)), c[2]);
        near(m.apply(ui.Offset.zero), c[3]);
      }
    });

    test(
      'background fit: contain / cover / fill × landscape / portrait / square',
      () {
        const page = ui.Size(600, 800);
        // (pixel w, h) → expected rect per fit, by the INK formula (03-ink 6.11.5):
        // contain k = min(W/pw, H/ph), cover k = max(…), centered; fill = the page.
        final table = <(int, int, core.ImageFit?, ui.Rect)>[
          (
            1200,
            600,
            core.ImageFit.contain,
            const ui.Rect.fromLTWH(0, 250, 600, 300),
          ),
          (
            1200,
            600,
            core.ImageFit.cover,
            const ui.Rect.fromLTWH(-500, 0, 1600, 800),
          ),
          (
            1200,
            600,
            core.ImageFit.fill,
            const ui.Rect.fromLTWH(0, 0, 600, 800),
          ),
          (
            300,
            900,
            core.ImageFit.contain,
            const ui.Rect.fromLTWH(
              166.66666666666669,
              0,
              266.66666666666663,
              800,
            ),
          ),
          (
            300,
            900,
            core.ImageFit.cover,
            const ui.Rect.fromLTWH(0, -500, 600, 1800),
          ),
          (
            300,
            900,
            core.ImageFit.fill,
            const ui.Rect.fromLTWH(0, 0, 600, 800),
          ),
          (
            500,
            500,
            core.ImageFit.contain,
            const ui.Rect.fromLTWH(0, 100, 600, 600),
          ),
          (
            500,
            500,
            core.ImageFit.cover,
            const ui.Rect.fromLTWH(-100, 0, 800, 800),
          ),
          (
            500,
            500,
            core.ImageFit.fill,
            const ui.Rect.fromLTWH(0, 0, 600, 800),
          ),
          (500, 500, null, const ui.Rect.fromLTWH(0, 100, 600, 600)),
        ];
        for (final (pw, ph, fit, want) in table) {
          final got = backgroundFitRect(
            pw.toDouble(),
            ph.toDouble(),
            page,
            fit,
          );
          for (final (g, e) in [
            (got.left, want.left),
            (got.top, want.top),
            (got.width, want.width),
            (got.height, want.height),
          ]) {
            expect(g, closeTo(e, 1e-9), reason: '$pw x $ph ${fit?.name}');
          }
          if (fit != null) {
            final ref = PdfAssetImageRef.background(
              assetId: 'bg',
              fit: fit,
              pageSize: page,
            );
            expect(imagePlacement(ref, pw, ph), unitSquareToRect(got));
          }
        }
      },
    );

    test('background resolves with the image size as shown', () async {
      final w = _world({'bg': PdfObjectFixtures.jpegExif6_64x48});
      final item = _single(
        await w.resolver.resolve(
          const PdfAssetImageRef.background(
            assetId: 'bg',
            fit: core.ImageFit.contain,
            pageSize: ui.Size(480, 480),
          ),
          ResolveContext(),
        ),
      );
      // shown 48 × 64 → contain in 480² = 360 × 480 centered
      expect(
        item.matrix,
        unitSquareToRect(const ui.Rect.fromLTWH(60, 0, 360, 480)),
      );
    });

    test('draw items pass through unchanged', () async {
      final w = _world({});
      final fill = PdfFillItem(
        path: PdfVectorPath.rect(const ui.Rect.fromLTWH(0, 0, 1, 1)),
        colorArgb: 0xFF000000,
        opacity: 1,
      );
      expect(await w.resolver.resolve(fill, ResolveContext()), [fill]);
    });
  });

  group('big samples against the 16 MiB ledger (PDF-M3)', () {
    test('6000 × 4000 PNG → RGBA 2048 × 1365, peak ≤ 16 MiB', () async {
      final png = bigPng6000x4000();
      final w = _world({'big': png});
      final data =
          _single(await w.resolver.resolve(_object('big'), ResolveContext()))
                  .image
              as PdfRgbaData;
      expect((data.width, data.height), (2048, 1365));
      expect(
        data.width * data.height,
        lessThanOrEqualTo(PdfTuning.maxRasterPixels),
      );
      expect(w.resolver.ledger.peakBytes, lessThanOrEqualTo(16 * mib));
      expect(w.resolver.ledger.overBudget, 0);
    });

    test('6 MiB noise PNG 2048² → ≤ 2.5 Mpx, peak ≤ 16 MiB', () async {
      final png = noisePng2048();
      expect(png.length, greaterThanOrEqualTo(6 * mib));
      final w = _world({'n': png});
      final data =
          _single(await w.resolver.resolve(_object('n'), ResolveContext()))
                  .image
              as PdfRgbaData;
      expect(data.width * data.height, lessThanOrEqualTo(2621440));
      expect(data.width, data.height, reason: 'square stays square');
      expect(w.resolver.ledger.peakBytes, lessThanOrEqualTo(16 * mib));
      expect(w.resolver.ledger.overBudget, 0);
    });

    test('20 MiB input → 1 Mpx, overBudget 1, peak ≤ input + 4 MiB ≤ 24 MiB (CP-PDF-14 ②)', () async {
      final png = noisePngOver();
      expect(png.length, greaterThanOrEqualTo(20 * mib));
      final w = _world({'x': png});
      final data =
          _single(await w.resolver.resolve(_object('x'), ResolveContext()))
                  .image
              as PdfRgbaData;
      expect(
        data.width * data.height,
        lessThanOrEqualTo(PdfTuning.exportMinDecodePixels),
      );
      expect(
        data.width * data.height,
        greaterThan(PdfTuning.exportMinDecodePixels * 0.99),
      );
      final l = w.resolver.ledger;
      expect(l.overBudget, 1);
      expect(l.peakBytes, lessThanOrEqualTo(png.length + 4 * mib));
      expect(png.length + 4 * mib, lessThanOrEqualTo(25 * mib));
      w.resolver.sent([data]);
      expect(l.heldBytes, 0);
    });

    test('decodeTargetSize: caps, aspect, no upscaling', () {
      expect(decodeTargetSize(6000, 4000, 100000), (width: 2048, height: 1365));
      expect(decodeTargetSize(64, 48, 1000), (width: 64, height: 48));
      expect(decodeTargetSize(2048, 2048, 4 * mib), (
        width: 1773,
        height: 1773,
      ));
      final t = decodeTargetSize(2048, 2048, 6 * mib);
      expect(t.width * t.height, lessThanOrEqualTo((10 * mib) ~/ 4));
      final low = decodeTargetSize(5000, 5000, 30 * mib);
      expect(low.width * low.height, lessThanOrEqualTo(1048576));
      expect(low.width, 1024);
      final thin = decodeTargetSize(100000, 10, 1000);
      expect(thin, (width: 2048, height: 1), reason: 'min 1 px');
    });
  });

  group('JPEG cache (6.2.10 ②)', () {
    test(
      'sent fast path JPEG comes back to the cache: no second read',
      () async {
        final w = _world({'j': PdfObjectFixtures.jpegBaseline64x48});
        final n = PdfObjectFixtures.jpegBaseline64x48.length;
        final first = _single(
          await w.resolver.resolve(_object('j'), ResolveContext()),
        );
        expect(
          w.resolver.cache.length,
          0,
          reason: 'in a part: counted once as encoded',
        );
        expect(w.resolver.ledger.heldBytes, n);
        w.resolver.sent([first.image]);
        expect(w.resolver.cache.assetIds, ['j']);
        expect(w.resolver.ledger.bytesOf(ExportMemoryKind.cache), n);
        expect(w.resolver.ledger.bytesOf(ExportMemoryKind.encoded), 0);
        final second = _single(
          await w.resolver.resolve(_object('j'), ResolveContext()),
        );
        expect(
          identical(
            (second.image as PdfJpegData).bytes,
            (first.image as PdfJpegData).bytes,
          ),
          isTrue,
        );
        expect(_reads(w.gateway), 1);
        expect(
          w.resolver.ledger.heldBytes,
          n,
          reason: 'taken out of the cache: once',
        );
        w.resolver.sent([second.image]);
        w.resolver.dispose();
        expect(w.resolver.ledger.heldBytes, 0);
        expect(w.resolver.cache.length, 0);
      },
    );

    test('not enough room → the oldest entry goes first', () async {
      final six = 6 * mib;
      final w = _world({
        'a': paddedJpeg(PdfObjectFixtures.jpegBaseline64x48, six),
        'b': paddedJpeg(PdfObjectFixtures.jpegProgressive64x48, six),
        'c': paddedJpeg(PdfObjectFixtures.jpegGray64x48, six),
      });
      Future<void> roundTrip(String id) async {
        final item = _single(
          await w.resolver.resolve(_object(id), ResolveContext()),
        );
        expect(
          item.image,
          isA<PdfJpegData>(),
          reason: '$id ≤ 8 MiB: fast path',
        );
        w.resolver.sent([item.image]);
      }

      await roundTrip('a');
      await roundTrip('b');
      expect(w.resolver.cache.assetIds, ['a', 'b']);
      await roundTrip('c'); // 12 + 6 > 16 → 'a' evicted
      expect(w.resolver.cache.assetIds, ['b', 'c']);
      expect(w.resolver.ledger.peakBytes, lessThanOrEqualTo(16 * mib));
      await roundTrip('a'); // read again
      expect(_reads(w.gateway), 4);
      expect(w.resolver.cache.assetIds, ['c', 'a']);
    });

    test(
      'an RGBA raster evicts the whole cache when it needs the room',
      () async {
        final w = _world({
          'j': paddedJpeg(PdfObjectFixtures.jpegBaseline64x48, 6 * mib),
          'big': bigPng6000x4000(),
        });
        final j = _single(
          await w.resolver.resolve(_object('j'), ResolveContext()),
        );
        w.resolver.sent([j.image]);
        expect(w.resolver.cache.length, 1);
        final big = _single(
          await w.resolver.resolve(_object('big'), ResolveContext()),
        );
        expect(
          w.resolver.cache.length,
          0,
          reason: '6 MiB cache + 10.7 MiB RGBA + input > 16 MiB',
        );
        expect(w.resolver.ledger.peakBytes, lessThanOrEqualTo(16 * mib));
        w.resolver.sent([big.image]);
      },
    );
  });

  test('cancelled → PdfIoException(cancelled), nothing held', () async {
    final w = _world({'j': PdfObjectFixtures.jpegBaseline64x48});
    final cancel = PdfCancelSignal()..cancel();
    await expectLater(
      () => w.resolver.resolve(_object('j'), ResolveContext(cancel: cancel)),
      throwsA(
        isA<PdfIoException>().having(
          (e) => e.code,
          'code',
          PdfErrorCode.cancelled,
        ),
      ),
    );
    expect(w.resolver.ledger.heldBytes, 0);
  });
}
