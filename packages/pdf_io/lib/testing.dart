/// Test helpers of pdf_io (06-pdf 4.14): PDF fixture builder and fakes of the pdf_io ports.
///
/// Web-safe; no flutter_test, no dart:io. Import from `test/` only (contract 7.1 rule 2).
/// Other areas (mainly INFRA app shell tests) may use it too. For CORE use the shared fake
/// `createFakeNoteStore()` (contract 7.4.8); FakePdfNoteGateway is a thin port fake for fast
/// unit tests.
///
/// Foundation step B4 (T0): the fixture value types are real; the builder and the fakes are
/// signatures only and come with the PDF task named in each UnimplementedError (T2 builder,
/// T4 gateway, T5 engine, T6 file source, T7 remote fetcher, T12–T16 export fakes).
library;

import 'package:flutter/foundation.dart';
import 'package:note_core/note_core.dart' as core;

import 'src/compose/compose_backend.dart';
import 'src/engine/page_info.dart';
import 'src/engine/pdf_engine.dart';
import 'src/export/compose_plan.dart';
import 'src/export/export_types.dart';
import 'src/export/vectors.dart';
import 'src/files/pdf_file_source.dart';
import 'src/gateway/pdf_note_gateway.dart';
import 'src/output/pdf_output_sink.dart';

Never _todo(String member, String task) =>
    throw UnimplementedError('$member (PDF $task)');

/// Text drawn with the base-14 Helvetica font. When [mapped] is true every distinct
/// UTF-16 code unit gets a single-byte code and a ToUnicode CMap entry, so ANY BMP text
/// (e.g. Korean, incl. NFD jamo) is extractable without embedding a font (verified V12).
@immutable
final class PdfFixtureText {
  const PdfFixtureText(
    this.text, {
    this.x = 72,
    this.y = 72,
    this.size = 18,
    this.mapped = false,
  });
  final String text;

  /// baseline origin in DISPLAYED page pt, y down; converted to
  /// user space with the inverse of D (6.11.3), text rotated with the page
  final double x, y;
  final double size;
  final bool mapped;
}

@immutable
final class PdfFixturePage {
  const PdfFixturePage({
    this.width = 595.2756,
    this.height = 841.8898,
    this.rotate = 0,
    this.mediaBox,
    this.cropBox,
    this.texts = const [],
    this.rawContent,
  });
  final double width, height; // used when mediaBox is null: [0 0 width height]
  final int rotate; // 0, 90, 180, 270
  final List<double>? mediaBox; // [l b r t]
  final List<double>? cropBox;
  final List<PdfFixtureText> texts;
  final String? rawContent; // appended verbatim (e.g. unbalanced 'cm')
}

/// Pure Dart raw PDF 1.4 writer (classic xref). Optional Standard security handler
/// R2 (RC4 40-bit) — PDFium opens it (verified V2).
final class PdfFixtureBuilder {
  PdfFixtureBuilder();

  PdfFixtureBuilder addPage(PdfFixturePage page) =>
      _todo('PdfFixtureBuilder.addPage', 'T2');

  PdfFixtureBuilder addPages(
    int count,
    PdfFixturePage Function(int index) page,
  ) => _todo('PdfFixtureBuilder.addPages', 'T2');

  /// userPassword '' + ownerPassword = permission-only encryption.
  PdfFixtureBuilder encrypt({
    required String userPassword,
    String ownerPassword = 'owner',
  }) => _todo('PdfFixtureBuilder.encrypt', 'T2');

  /// One shared Helvetica font object for all pages (resource sharing like real PDFs).
  Uint8List build() => _todo('PdfFixtureBuilder.build', 'T2');
}

/// pages/texts given in constructor; solid-color images
final class FakePdfEngine implements PdfEngine {
  FakePdfEngine();

  @override
  bool get isInitialized => _todo('FakePdfEngine.isInitialized', 'T5');

  @override
  Future<void> ensureInitialized() =>
      _todo('FakePdfEngine.ensureInitialized', 'T5');

  @override
  Future<PdfEngineDocument> open(
    Uint8List bytes, {
    required String sourceName,
    String fileName = '',
    PdfPasswordCallback? onPassword,
    int maxPasswordAttempts = 5,
    bool transferOwnership = false,
  }) => _todo('FakePdfEngine.open', 'T5');
}

/// In-memory notes/pages/strokes/assets/thumbnails. arriveBytes(id, bytes) stores the bytes and
/// emits bytesArrived (simulates a finished download). holdWrites() makes putPdf / createNote /
/// insertPages / flush stay pending (no completion, no error — CORE commit retry, contract
/// 7.2.9 v1.2) until releaseWrites(). Retry timing itself is tested with CORE
/// createFakeNoteStore(faults:) (T4, T6, T15).
final class FakePdfNoteGateway implements PdfNoteGateway {
  FakePdfNoteGateway();

  /// Stores [bytes] for [id] and emits it on [bytesArrived].
  void arriveBytes(core.AssetId id, Uint8List bytes) =>
      _todo('FakePdfNoteGateway.arriveBytes', 'T4');

  /// putPdf / createNote / insertPages / flush stay pending until [releaseWrites].
  void holdWrites() => _todo('FakePdfNoteGateway.holdWrites', 'T4');

  /// Completes the writes held since [holdWrites].
  void releaseWrites() => _todo('FakePdfNoteGateway.releaseWrites', 'T4');

  @override
  Future<core.Asset> putPdf(Uint8List bytes, {required String fileName}) =>
      _todo('FakePdfNoteGateway.putPdf', 'T4');

  @override
  Future<Uint8List?> readAssetBytes(core.AssetId assetId) =>
      _todo('FakePdfNoteGateway.readAssetBytes', 'T4');

  @override
  Stream<core.AssetId> get bytesArrived =>
      _todo('FakePdfNoteGateway.bytesArrived', 'T4');

  @override
  Future<core.Note> createNote({
    core.FolderId? folderId,
    required String title,
    required List<core.PageDraft> pages,
  }) => _todo('FakePdfNoteGateway.createNote', 'T4');

  @override
  Future<List<core.PageId>> insertPages(
    core.NoteId noteId,
    List<core.PageDraft> pages,
    core.PagePosition position,
  ) => _todo('FakePdfNoteGateway.insertPages', 'T4');

  @override
  Future<void> flush() => _todo('FakePdfNoteGateway.flush', 'T4');

  @override
  Future<core.Note?> getNote(core.NoteId noteId) =>
      _todo('FakePdfNoteGateway.getNote', 'T4');

  @override
  Future<List<core.Page>> pagesOf(core.NoteId noteId) =>
      _todo('FakePdfNoteGateway.pagesOf', 'T4');

  @override
  Future<core.PageContent> loadPage(core.PageId pageId) =>
      _todo('FakePdfNoteGateway.loadPage', 'T4');

  @override
  Future<void> writeThumbnail(core.PageThumbnail thumbnail) =>
      _todo('FakePdfNoteGateway.writeThumbnail', 'T4');
}

/// returns queued PickedPdfFile / null
final class FakePdfFileSource implements PdfFileSource {
  FakePdfFileSource();

  @override
  bool get isSupported => _todo('FakePdfFileSource.isSupported', 'T6');

  @override
  Future<PickedPdfFile?> pickPdf() => _todo('FakePdfFileSource.pickPdf', 'T6');
}

/// records deliveries (result lists)
final class FakePdfOutputSink implements PdfOutputSink {
  FakePdfOutputSink();

  @override
  Set<PdfOutputAction> availableActions(List<PdfExportResult> results) =>
      _todo('FakePdfOutputSink.availableActions', 'T16');

  @override
  Future<PdfOutputOutcome> deliver(
    List<PdfExportResult> results,
    PdfOutputAction action,
  ) => _todo('FakePdfOutputSink.deliver', 'T16');
}

/// records plan/ops, returns '%PDF-fake'
final class RecordingComposeBackend implements PdfComposeBackend {
  RecordingComposeBackend();

  @override
  bool get isSupported => _todo('RecordingComposeBackend.isSupported', 'T15');

  @override
  Future<PdfComposeJob> begin(PdfComposePlan plan) =>
      _todo('RecordingComposeBackend.begin', 'T15');

  @override
  Future<void> dispose() => _todo('RecordingComposeBackend.dispose', 'T15');
}

/// each stroke → filled rect of its bounds
final class BoxInkVectorizer implements PdfInkVectorizer {
  const BoxInkVectorizer();

  @override
  PdfPageVectors vectorize(
    core.Page page,
    List<core.Stroke> strokes, {
    required bool includeInk,
    required bool includeTemplate,
  }) => _todo('BoxInkVectorizer.vectorize', 'T15');
}

/// Scripted core.RemoteAssetFetcher (P-2 tests, also usable by INFRA before M4).
final class FakeRemoteAssetFetcher implements core.RemoteAssetFetcher {
  FakeRemoteAssetFetcher();

  List<core.AssetId> get ensureLocalCalls =>
      _todo('FakeRemoteAssetFetcher.ensureLocalCalls', 'T7');

  /// Pushes a progress value to watch(id) listeners (broadcast; replays the latest on listen).
  void emit(core.AssetId id, core.RemoteAssetProgress progress) =>
      _todo('FakeRemoteAssetFetcher.emit', 'T7');

  /// Completes the pending ensureLocal(id) future with [local].
  void completeEnsureLocal(core.AssetId id, bool local) =>
      _todo('FakeRemoteAssetFetcher.completeEnsureLocal', 'T7');

  @override
  Future<bool> ensureLocal(core.AssetId id) =>
      _todo('FakeRemoteAssetFetcher.ensureLocal', 'T7');

  @override
  Stream<core.RemoteAssetProgress> watch(core.AssetId id) =>
      _todo('FakeRemoteAssetFetcher.watch', 'T7');
}
