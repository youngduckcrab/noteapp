@TestOn('browser')
library;

// PDF T25a — the image resolver under CanvasKit (m5-7/06-pdf 6.2.4 [추측 — T25a 시험에서 VM·Chrome
// 확인]): the engine target-size decode gives the asked size as straight RGBA, the web
// ImageDescriptor has no size (engineImageSize decodes the first frame instead), and the
// resolver's fast / slow paths and ledger behave as on the VM.
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:pdf_io/pdf_io.dart';
import 'package:pdf_io/src/export/export_memory.dart';
import 'package:pdf_io/src/export/object_resolver.dart';
import 'package:pdf_io/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('target-size decode: PNG 200 × 100 → 100 × 50 straight RGBA', () async {
    final png = PdfObjectFixtures.png(width: 200, height: 100, alpha: true);
    final out = await engineDecodeRgba(png, width: 100, height: 50);
    expect(out, isNotNull);
    expect((out!.width, out.height), (100, 50));
    expect(out.rgba.length, 100 * 50 * 4);
    expect(out.rgba[3], closeTo(128, 1), reason: 'left half alpha 128');
    expect(out.rgba[2], closeTo(160, 2), reason: 'straight, not premultiplied');
    expect(rgbaHasAlpha(out.rgba), isTrue);
  });

  test('target-size decode: JPEG 64 × 48 → 32 × 24', () async {
    final out = await engineDecodeRgba(
      PdfObjectFixtures.jpegBaseline64x48,
      width: 32,
      height: 24,
    );
    expect((out!.width, out.height), (32, 24));
    expect(rgbaHasAlpha(out.rgba), isFalse);
  });

  test(
    'web ImageDescriptor.encoded has no size; engineImageSize decodes instead',
    () async {
      final png = PdfObjectFixtures.png(width: 30, height: 20);
      final buffer = await ui.ImmutableBuffer.fromUint8List(png);
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      expect(() => descriptor.width, throwsUnsupportedError);
      descriptor.dispose();
      buffer.dispose();
      expect(await engineImageSize(png), (width: 30, height: 20));
      expect(await engineImageSize(PdfObjectFixtures.jpegGray64x48), (
        width: 64,
        height: 48,
      ));
    },
  );

  test('resolver: fast path JPEG, slow path PNG alpha, ledger', () async {
    final gateway = FakePdfNoteGateway();
    final jpeg = PdfObjectFixtures.jpegProgressive64x48;
    gateway
      ..arriveBytes('j', jpeg)
      ..arriveBytes(
        'p',
        PdfObjectFixtures.png(width: 40, height: 30, alpha: true),
      );
    final resolver = ObjectResolver(gateway: gateway);
    final frame = PdfAssetImageRef.object(
      assetId: 'j',
      frame: core.ElementFrame(core.PageRect(0, 0, 64, 48)),
    );
    final j = await resolver.resolve(frame, ResolveContext());
    final jd = (j.single as PdfImageItem).image as PdfJpegData;
    expect(identical(jd.bytes, jpeg), isTrue);
    final p = await resolver.resolve(
      PdfAssetImageRef.object(
        assetId: 'p',
        frame: core.ElementFrame(core.PageRect(0, 0, 40, 30)),
      ),
      ResolveContext(),
    );
    final pd = (p.single as PdfImageItem).image as PdfRgbaData;
    expect((pd.width, pd.height, pd.hasAlpha), (40, 30, true));
    expect(
      resolver.ledger.heldBytes,
      jpeg.length + 40 * 30 * 4,
      reason: 'encoded JPEG + RGBA until sent',
    );
    resolver.sent([jd, pd]);
    expect(resolver.ledger.bytesOf(ExportMemoryKind.cache), jpeg.length);
    expect(resolver.ledger.bytesOf(ExportMemoryKind.rgba), 0);
    resolver.dispose();
    expect(resolver.ledger.heldBytes, 0);
  });

  test(
    'EXIF 6 JPEG (slow path): the web decoder turns it like the VM',
    () async {
      // Checked in Chrome (T25a): CanvasKit applies the EXIF orientation like the VM engine
      // (unit/object_resolver_image_test) — stored 64 × 48, decoded 48 × 64.
      final bytes = PdfObjectFixtures.jpegExif6_64x48;
      expect(await engineImageSize(bytes), (width: 48, height: 64));
      final out = await engineDecodeRgba(bytes, width: 48, height: 64);
      expect((out!.width, out.height), (48, 64));
    },
  );
}
