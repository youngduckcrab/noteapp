// Shared set-up of the export service tests (T15 export_service_test, T15b batch_export_test,
// web/pure_logic_browser_test): FakePdfNoteGateway + BoxInkVectorizer +
// RecordingComposeBackend, and small helpers. Web-safe.
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:pdf_io/pdf_io.dart';
import 'package:pdf_io/testing.dart';

const core.PageDraft blankDraft = core.PageDraft.blankA4;

final class ExportWorld {
  ExportWorld({RecordingComposeBackend? backend})
    : backend = backend ?? RecordingComposeBackend();

  final FakePdfNoteGateway gateway = FakePdfNoteGateway();
  final RecordingComposeBackend backend;
  late final DefaultPdfExportService service = DefaultPdfExportService(
    gateway: gateway,
    vectorizer: const BoxInkVectorizer(),
    backend: backend,
  );
  final Map<String, Uint8List> _bytes = {};
  int _strokes = 0;

  /// The bytes [addPdf] stored for [name].
  Uint8List bytesOf(String name) => _bytes[name]!;

  Future<core.AssetId> addPdf(String name) async {
    final bytes = _bytes[name] = Uint8List.fromList(
      '%PDF-1.7\n% $name\n%%EOF\n'.codeUnits,
    );
    return (await gateway.putPdf(bytes, fileName: '$name.pdf')).id;
  }

  core.PageDraft pdfPage(
    core.AssetId assetId,
    int index, {
    core.PageSize size = core.PageSize.a4Portrait,
  }) => core.PageDraft(
    size: size,
    background: core.PdfBackground(assetId: assetId, pdfPageIndex: index),
  );

  Future<core.Note> note(String title, List<core.PageDraft> pages) =>
      gateway.createNote(title: title, pages: pages);

  /// One ballpoint stroke from (x, 10) to (x + 40, 30) on [pageId].
  void addStroke(core.PageId pageId, {double x = 10}) {
    _strokes++;
    gateway.addStrokes(pageId, [
      testStroke('stroke-$_strokes', pageId, x: x, createdAt: _strokes),
    ]);
  }
}

core.Stroke testStroke(
  String id,
  core.PageId pageId, {
  double x = 10,
  int createdAt = 1,
}) => core.Stroke(
  id: id,
  pageId: pageId,
  style: core.StrokeStyle.defaultsFor(core.PenTool.ballpoint),
  points: core.StrokePoints.fromList([
    core.StrokePoint(x, 10),
    core.StrokePoint(x + 40, 30),
  ]),
  createdAt: createdAt,
);

/// 'source s:p' / 'blank' per output page.
List<String> describePlan(PdfComposePlan plan) => [
  for (final page in plan.pages)
    switch (page) {
      PdfComposeSourcePage(:final sourceIndex, :final pdfPageIndex) =>
        'source $sourceIndex:$pdfPageIndex',
      PdfComposeBlankPage() => 'blank',
    },
];

TypeMatcher<PdfIoException> hasCode(PdfErrorCode code) =>
    isA<PdfIoException>().having((e) => e.code, 'code', code);

/// FlutterError reports (reportPdfError) until the end of the test.
List<FlutterErrorDetails> captureFlutterErrors() {
  final reports = <FlutterErrorDetails>[];
  final previous = FlutterError.onError;
  FlutterError.onError = reports.add;
  addTearDown(() => FlutterError.onError = previous);
  return reports;
}

/// One stroke object per page whose path has [pointsByPage] points (big ops, chunk tests).
final class LongPathVectorizer implements PdfInkVectorizer {
  LongPathVectorizer(this.pointsByPage);

  final Map<core.PageId, int> pointsByPage;

  /// (2차) The [vectorize] items in order (the export service plans pages with
  /// vectorize until PDF T26).
  @override
  PdfPagePlan planPage(
    core.PageContent content, {
    required bool includeInk,
    required bool includeTemplate,
  }) {
    final v = vectorize(
      content.page,
      content.strokes,
      includeInk: includeInk,
      includeTemplate: includeTemplate,
    );
    return PdfPagePlan([...v.underlay, ...v.ink]);
  }

  @override
  PdfPageVectors vectorize(
    core.Page page,
    List<core.Stroke> strokes, {
    required bool includeInk,
    required bool includeTemplate,
  }) {
    final n = pointsByPage[page.id] ?? 0;
    if (n == 0) return PdfPageVectors.empty;
    final verbs = Uint8List(n + 1); // moveTo, then lineTo × n
    for (var i = 1; i <= n; i++) {
      verbs[i] = PdfComposeOpcodes.lineTo;
    }
    final coords = Float32List(2 * (n + 1));
    for (var i = 0; i <= n; i++) {
      coords[2 * i] = (i % 500).toDouble();
      coords[2 * i + 1] = (i ~/ 500).toDouble();
    }
    return PdfPageVectors(
      ink: [
        PdfStrokeItem(
          path: PdfVectorPath(verbs, coords),
          colorArgb: 0xFF000000,
          width: 1,
        ),
      ],
    );
  }
}
