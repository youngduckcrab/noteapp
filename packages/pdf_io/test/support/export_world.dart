// Shared set-up of the export service tests (T15 export_service_test, T15b batch_export_test,
// web/pure_logic_browser_test; (2차, T26) unit/export_service_objects_test,
// widget/export_flow_test v2): FakePdfNoteGateway (+ page objects — [ObjectsGateway]) +
// BoxInkVectorizer + RecordingComposeBackend on the src-only createPdfExportService with fake
// raster ports, a fake font wait and font bytes, and small helpers. Web-safe.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:pdf_io/pdf_io.dart';
import 'package:pdf_io/src/export/export_memory.dart';
import 'package:pdf_io/src/export/export_service.dart';
import 'package:pdf_io/testing.dart';

import 'fake_rasterizers.dart';

const core.PageDraft blankDraft = core.PageDraft.blankA4;

/// ExportWorld v2 (T26): [web] runs the web rules on the VM (S-12 stop, 16-part chunks, no
/// worker copy); [fontsReady] false → the font wait fails at once; every export's ledger is in
/// [ledgers].
final class ExportWorld {
  ExportWorld({
    RecordingComposeBackend? backend,
    FakeMathRasterizer? math,
    FakeTextRasterizer? text,
    FakeFontSource? fonts,
    this.web = kIsWeb,
    this.fontsReady = true,
    this.vectorizer = const BoxInkVectorizer(),
  }) : backend = backend ?? RecordingComposeBackend(),
       math = math ?? FakeMathRasterizer(),
       text = text ?? FakeTextRasterizer(),
       fonts = fonts ?? FakeFontSource();

  final FakePdfNoteGateway gateway = FakePdfNoteGateway();
  late final ObjectsGateway objects = ObjectsGateway(gateway);
  final RecordingComposeBackend backend;
  final FakeMathRasterizer math;
  final FakeTextRasterizer text;
  final FakeFontSource fonts;
  final bool web;

  /// What the next font waits end with (true = loaded, false = TimeoutException).
  bool fontsReady;

  /// How many times the service waited for the fonts.
  int fontWaits = 0;
  final List<ExportMemoryLedger> ledgers = [];
  final PdfInkVectorizer vectorizer;
  late final DefaultPdfExportService service = createPdfExportService(
    gateway: objects,
    vectorizer: vectorizer,
    backend: backend,
    math: math,
    text: text,
    loadFonts: () async {
      fontWaits++;
      if (!fontsReady) throw TimeoutException('fake font load');
    },
    fontBytes: fonts.call,
    web: web,
    onLedger: ledgers.add,
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

/// FakePdfNoteGateway with page objects: [loadPage] adds the objects given with [addObjects]
/// (live ones, Stroke.compareOrder — as CORE's PageContent.objects). Every port call goes to
/// the inner gateway (its `calls` log them).
final class ObjectsGateway implements PdfNoteGateway {
  ObjectsGateway(this.inner);

  final FakePdfNoteGateway inner;
  final Map<core.PageId, List<core.PageObject>> _objects = {};

  void addObjects(core.PageId pageId, List<core.PageObject> objects) =>
      (_objects[pageId] ??= []).addAll(objects);

  @override
  Future<core.PageContent> loadPage(core.PageId pageId) async {
    final content = await inner.loadPage(pageId);
    final objects = [
      for (final o in _objects[pageId] ?? const <core.PageObject>[])
        if (o.deletedAt == null) o,
    ]..sort(core.Stroke.compareOrder);
    return core.PageContent(
      page: content.page,
      strokes: content.strokes,
      objects: objects,
      revision: content.revision,
    );
  }

  @override
  Future<core.Asset> putPdf(Uint8List bytes, {required String fileName}) =>
      inner.putPdf(bytes, fileName: fileName);

  @override
  Future<Uint8List?> readAssetBytes(core.AssetId assetId) =>
      inner.readAssetBytes(assetId);

  @override
  Stream<core.AssetId> get bytesArrived => inner.bytesArrived;

  @override
  Future<core.Note> createNote({
    core.FolderId? folderId,
    required String title,
    required List<core.PageDraft> pages,
  }) => inner.createNote(folderId: folderId, title: title, pages: pages);

  @override
  Future<List<core.PageId>> insertPages(
    core.NoteId noteId,
    List<core.PageDraft> pages,
    core.PagePosition position,
  ) => inner.insertPages(noteId, pages, position);

  @override
  Future<void> flush() => inner.flush();

  @override
  Future<core.Note?> getNote(core.NoteId noteId) => inner.getNote(noteId);

  @override
  Future<List<core.Page>> pagesOf(core.NoteId noteId) => inner.pagesOf(noteId);

  @override
  Future<void> writeThumbnail(core.PageThumbnail thumbnail) =>
      inner.writeThumbnail(thumbnail);
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
