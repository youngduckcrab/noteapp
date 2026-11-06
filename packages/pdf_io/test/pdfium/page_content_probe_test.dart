// The content-stream probe V11 relies on (test/support/pdf_page_content.dart — m5-7/06-pdf 8.2
// T29), checked against the native compose backend on real PDFium now, so a V11 failure at the
// integration stage is about CORE / INK / the export and not about the probe: a page with five
// fills, one stroke, two text lines and a JPEG paints 6 paths (5 filled), 1+ text objects and 1
// XObject; a page whose ops came in two parts (two content generations) paints the paths of
// both; an empty blank page paints none. Also the operator scanner on hand-written content
// (strings, hex strings, names, arrays, dictionaries, inline images and comments skipped).
@Tags(['pdfium'])
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:pdf_io/pdf_io.dart';
import 'package:pdf_io/src/compose/compose_backend_native.dart'
    show NativePdfComposeBackend;
import 'package:pdf_io/testing.dart';

import '../support/compose_probes.dart';
import '../support/pdf_page_content.dart';
import '../support/pdfium_env.dart';

Future<Uint8List> _inflate(Uint8List data) async =>
    Uint8List.fromList(zlib.decode(data));

PdfFillItem _fill(double x) => PdfFillItem(
  path: PdfVectorPath.rect(ui.Rect.fromLTWH(x, 20, 30, 30)),
  colorArgb: 0xFF1A73E8,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await initPdfiumForTests();
    await PdfrxEngine.shared().ensureInitialized();
  });

  late NativePdfComposeBackend backend;
  late ComposeProbeContext ctx;

  setUp(() {
    backend = NativePdfComposeBackend();
    ctx = ComposeProbeContext(backend: backend, engine: PdfrxEngine.shared());
  });

  tearDown(() async {
    await ctx.dispose();
    await backend.dispose();
  });

  test(
    'paths, text and images counted per page; parts of one page add up',
    () async {
      const size = ui.Size(400, 300);
      const plan = PdfComposePlan(
        sources: [],
        pages: [
          PdfComposeBlankPage(noteSize: size),
          PdfComposeBlankPage(noteSize: size),
          PdfComposeBlankPage(noteSize: size),
        ],
      );
      final frame = core.ElementFrame(const core.PageRect(20, 100, 380, 200));
      final first = await partsOf(ctx, 0, [
        for (var i = 0; i < 5; i++) _fill(20 + 40.0 * i),
        PdfStrokeItem(
          path: PdfVectorPath.rect(const ui.Rect.fromLTWH(20, 220, 300, 40)),
          colorArgb: 0xFF202020,
          width: 2,
        ),
        textLine('한글 텍스트 상자', frame: frame, baselineY: 20),
        textLine('hello', frame: frame, baselineY: 60),
        imageAt(
          PdfJpegData(
            PdfObjectFixtures.jpegBaseline64x48,
            width: 64,
            height: 48,
          ),
          const ui.Rect.fromLTWH(300, 20, 64, 48),
        ),
      ]);
      // Page 2 in two parts: an image part between two path parts (images are cut into their
      // own part only when large — so send the parts as two addPages calls instead).
      final secondA = PdfComposeEncoder.encodeItems(
        outputIndex: 1,
        items: [_fill(20), _fill(60)],
        fontBytes: const {},
        sentFonts: {},
      );
      final secondB = PdfComposeEncoder.encodeItems(
        outputIndex: 1,
        items: [_fill(100)],
        fontBytes: const {},
        sentFonts: {},
      );
      final job = await backend.begin(plan);
      final Uint8List bytes;
      try {
        await job.addPages(first);
        await job.addPages(secondA);
        await job.addPages(secondB);
        bytes = await job.finish();
      } on Object {
        await job.abort();
        rethrow;
      }

      final pages = (await PdfPageContents.read(
        bytes,
        inflate: _inflate,
      )).pages;
      expect(pages, hasLength(3));
      expect(pages[0].paintedPaths, 6, reason: '${pages[0]}');
      expect(pages[0].filledPaths, 5, reason: '${pages[0]}');
      expect(pages[0].textObjects, greaterThanOrEqualTo(1));
      expect(pages[0].xObjects, 1, reason: 'the JPEG');
      expect(pages[1].paintedPaths, 3, reason: '${pages[1]}');
      expect(pages[1].textObjects, 0);
      expect(pages[1].xObjects, 0);
      expect(pages[2].paintedPaths, 0, reason: '${pages[2]}');

      final pdf = await ctx.open(bytes);
      expect(pdf.pageCount, 3);
    },
  );

  test('the operator scanner skips operands of every kind', () {
    final content = Uint8List.fromList(
      latin1.encode(
        '% a comment with f and S\n'
        'q 1 0 0 1 10 20 cm /GS0 gs 0 0 m 10 0 l 10 10 l h f\n'
        'BT /F1 12 Tf (f S \\) (nested) B) Tj <66205320> Tj [(a) -20 (b)] TJ ET\n'
        '<< /Name /f /K [1 2] >> BDC EMC\n'
        'BI /W 1 /H 1 /CS /G /BPC 8 ID \x66\x53 EI\n'
        '0 0 5 5 re S 0 0 5 5 re f* 0 0 1 1 re W n Q\n',
      ),
    );
    final counts = PdfPageContents.countOperators(content);
    expect(counts['f'], 1);
    expect(counts['S'], 1);
    expect(counts['f*'], 1);
    expect(counts['n'], 1);
    expect(counts['Tj'], 2);
    expect(counts['TJ'], 1);
    expect(counts['BT'], 1);
    expect(counts['ID'], 1);
    expect(counts['BDC'], 1);
    expect(PdfPageOps(counts).paintedPaths, 3);
    expect(PdfPageOps(counts).filledPaths, 2);
  });
}
