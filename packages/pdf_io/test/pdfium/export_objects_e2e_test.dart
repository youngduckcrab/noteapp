// Export v2 end to end on real PDFium (m5-7/06-pdf 6.2.2 · 6.2.10; 8.2 T26): FakePdfNoteGateway
// with page objects + hand-made page plans (image object, image background, text boxes,
// formula, an original PDF page) + the native compose backend + the real NoteSans bytes → the
// exported PDF, reopened with PdfrxEngine, has the text box lines as text, one image object per
// image (JPEG as /DCTDecode, the alpha PNG with an /SMask), the formula raster, both fonts once
// and the original page's text. The ledger values (peakBytes · peakCopyBytes · peakTotalBytes —
// CP-PDF-14 ①) are printed and checked against 16 / 32 MiB.
@Tags(['pdfium'])
@TestOn('vm')
library;

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:pdf_io/pdf_io.dart';
import 'package:pdf_io/src/compose/compose_backend_native.dart'
    show NativePdfComposeBackend, debugNativeComposeJobCount;
import 'package:pdf_io/src/export/export_memory.dart';
import 'package:pdf_io/src/export/export_service.dart';
import 'package:pdf_io/testing.dart';

import '../support/compose_probes.dart';
import '../support/export_world.dart';
import '../support/fake_rasterizers.dart';
import '../support/pdfium_env.dart';

const int _mib = 1024 * 1024;

/// planPage = the plan given for the page id (empty otherwise).
final class _PlanVectorizer implements PdfInkVectorizer {
  _PlanVectorizer(this.plans);

  final Map<core.PageId, List<PdfPlanItem>> plans;

  @override
  PdfPagePlan planPage(
    core.PageContent content, {
    required bool includeInk,
    required bool includeTemplate,
  }) => PdfPagePlan(plans[content.page.id] ?? const []);

  @override
  PdfPageVectors vectorize(
    core.Page page,
    List<core.Stroke> strokes, {
    required bool includeInk,
    required bool includeTemplate,
  }) => PdfPageVectors.empty;
}

core.ElementFrame _frame(double l, double t, double w, double h) =>
    core.ElementFrame(core.PageRect(l, t, l + w, t + h));

PdfTextBoxRef _box(
  String id,
  core.PageId pageId,
  String text, {
  bool bold = false,
  required core.ElementFrame frame,
}) => PdfTextBoxRef(
  core.TextBoxObject(
    id: id,
    pageId: pageId,
    frame: frame,
    text: text,
    style: core.TextBoxStyle(fontSizePt: 18, bold: bold),
    createdAt: 1,
  ),
  [
    (
      text: text,
      x: 0,
      baselineY: 18,
      width: frame.rect.right - frame.rect.left,
    ),
  ],
);

/// Extracted text as trimmed lines (NoteSans maps U+00A0 and U+0020 to one glyph — T22).
List<String> _lines(String text) => [
  for (final line in text.replaceAll(' ', ' ').split(RegExp(r'\r?\n')))
    if (line.trim().isNotEmpty) line.trim(),
];

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
    expect(backend.openJobCount, 0);
    await backend.dispose();
    expect(await debugNativeComposeJobCount(), 0);
  });

  test('objects on blank, image-background and original pages → text, image '
      'objects and fonts in the PDF; ledger within 16 / 32 MiB', () async {
    final gateway = FakePdfNoteGateway();
    final objects = ObjectsGateway(gateway);
    gateway
      ..arriveBytes('jpeg', PdfObjectFixtures.jpegBaseline64x48)
      ..arriveBytes('png', PdfObjectFixtures.png(alpha: true));
    final original = await gateway.putPdf(
      (PdfFixtureBuilder()..addPage(
            const PdfFixturePage(texts: [PdfFixtureText('Hello export')]),
          ))
          .build(),
      fileName: 'original.pdf',
    );
    final note = await gateway.createNote(
      title: 'e2e',
      pages: [
        blankDraft,
        const core.PageDraft(
          size: core.PageSize.a4Portrait,
          background: core.ImageBackground(assetId: 'png'),
        ),
        core.PageDraft(
          size: core.PageSize.a4Portrait,
          background: core.PdfBackground(assetId: original.id, pdfPageIndex: 0),
        ),
      ],
    );
    final pages = await gateway.pagesOf(note.id);
    final formula = core.MathObject(
      id: 'math',
      pageId: pages[0].id,
      frame: _frame(320, 500, 200, 100),
      latex: r'\frac{a}{b}',
      style: const core.MathStyle(),
      createdAt: 1,
    );
    final vectorizer = _PlanVectorizer({
      pages[0].id: [
        PdfAssetImageRef.object(
          assetId: 'jpeg',
          frame: _frame(60, 60, 160, 120),
        ),
        _box('t0', pages[0].id, '안녕하세요 PDF', frame: _frame(60, 300, 300, 40)),
        PdfMathRef(formula),
      ],
      pages[1].id: [
        PdfAssetImageRef.background(
          assetId: 'png',
          fit: core.ImageFit.contain,
          pageSize: ui.Size(pages[1].size.width, pages[1].size.height),
        ),
        _box(
          't1',
          pages[1].id,
          'Bold 굵게',
          bold: true,
          frame: _frame(60, 700, 300, 40),
        ),
      ],
      pages[2].id: [
        _box('t2', pages[2].id, '덧쓴 글자', frame: _frame(60, 400, 300, 40)),
      ],
    });
    final ledgers = <ExportMemoryLedger>[];
    final math = FakeMathRasterizer();
    final service = createPdfExportService(
      gateway: objects,
      vectorizer: vectorizer,
      backend: backend,
      math: math,
      text: FakeTextRasterizer(),
      onLedger: ledgers.add,
    );

    final result = await service.exportNote(note.id, const PdfExportOptions());

    expect(result.warnings, isEmpty);
    expect(math.calls, hasLength(1));
    final pdf = await ctx.open(result.bytes);
    expect(pdf.pageCount, 3);
    expect(_lines(await pdf.text(0)), contains('안녕하세요 PDF'));
    expect(_lines(await pdf.text(1)), contains('Bold 굵게'));
    final third = _lines(await pdf.text(2));
    expect(third, contains('Hello export'));
    expect(third, contains('덧쓴 글자'));

    final saved = ProbePdfObjects(result.bytes);
    final images = saved.images;
    expect(images, hasLength(3), reason: 'JPEG, formula raster, background');
    final jpeg = images.where((i) => i.filter == 'DCTDecode').toList();
    expect(jpeg.single.width, 64);
    expect(
      images.where((i) => i.smask != null),
      hasLength(2),
      reason: 'the formula raster and the alpha PNG have soft masks',
    );
    expect(saved.fontFiles, 2, reason: 'NoteSans regular + bold, once each');

    final ledger = ledgers.single;
    debugPrint(
      'T26 e2e ledger: peakBytes ${ledger.peakBytes} B, '
      'peakCopyBytes ${ledger.peakCopyBytes} B, '
      'peakTotalBytes ${ledger.peakTotalBytes} B, '
      'overBudget ${ledger.overBudget}',
    );
    expect(ledger.peakBytes, lessThanOrEqualTo(16 * _mib));
    expect(ledger.peakCopyBytes, greaterThan(0), reason: 'native worker copy');
    expect(ledger.peakCopyBytes, lessThanOrEqualTo(16 * _mib));
    expect(ledger.peakTotalBytes, lessThanOrEqualTo(32 * _mib));
    expect(ledger.heldBytes, 0);
    expect(ledger.copyBytes, 0);
  });
}
