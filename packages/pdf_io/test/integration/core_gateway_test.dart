// CorePdfNoteGateway over the REAL CORE store (06-pdf 8 T4, integration stage only —
// `ws test --run-skipped -t integration`, contract 7.7 step 5): every scenario of
// unit/core_gateway_fake_store_test.dart with the same assertions, except the commit-retry
// timing group (that needs FakeNoteStoreFaults): asset dedupe and bytesArrived, 500-page
// notes, insertPages as one undo step in the editor's session, exception mapping,
// loadPage / writeThumbnail, and a failed byte-chunk write → storageFailed.
@Tags(['integration'])
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing_vm.dart' as core_vm;
import 'package:pdf_io/pdf_io.dart';

Uint8List _bytes(String text) => Uint8List.fromList('%PDF-1.4 $text'.codeUnits);

core.PageDraft _pdfDraft(core.AssetId assetId, int index) => core.PageDraft(
  size: core.PageSize.letterPortrait,
  background: core.PdfBackground(assetId: assetId, pdfPageIndex: index),
);

const core.PageDraft _blank = core.PageDraft.blankA4;

/// A real 1×1 PNG (the real thumbnail cache may look at the bytes; the fake does not).
final Uint8List _png1x1 = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

TypeMatcher<PdfIoException> _code(PdfErrorCode code) =>
    isA<PdfIoException>().having((e) => e.code, 'code', code);

void main() {
  late core.NoteStore store;
  late CorePdfNoteGateway gateway;

  setUp(() async {
    store = await core_vm.openTestNoteStore();
    gateway = CorePdfNoteGateway(store);
  });
  tearDown(() => store.close());

  test('putPdf: same bytes → same asset; bytesArrived for new bytes', () async {
    final arrived = <core.AssetId>[];
    final sub = gateway.bytesArrived.listen(arrived.add);
    addTearDown(sub.cancel);
    final a = await gateway.putPdf(_bytes('one'), fileName: 'a.pdf');
    final b = await gateway.putPdf(_bytes('one'), fileName: 'b.pdf');
    expect(b.id, a.id);
    expect(a.type, core.AssetType.pdf);
    expect(a.mimeType, 'application/pdf');
    await pumpEventQueue();
    expect(arrived, [a.id]);
    expect(await gateway.readAssetBytes(a.id), _bytes('one'));
    expect(await gateway.readAssetBytes('0' * 64), isNull);
  });

  test('createNote with 500 PDF pages in one call', () async {
    final asset = await gateway.putPdf(_bytes('big'), fileName: 'big.pdf');
    final note = await gateway.createNote(
      folderId: null,
      title: '강의',
      pages: [for (var i = 0; i < 500; i++) _pdfDraft(asset.id, i)],
    );
    expect(note.title, '강의');
    final pages = await gateway.pagesOf(note.id);
    expect(pages, hasLength(500));
    expect((pages[499].background as core.PdfBackground).pdfPageIndex, 499);
    expect((await gateway.getNote(note.id))!.pageCount, 500);
  });

  test(
    'insertPages: one undo step in the editor session, which stays open',
    () async {
      final asset = await gateway.putPdf(_bytes('ins'), fileName: 'ins.pdf');
      final note = await gateway.createNote(title: 'n', pages: const [_blank]);
      final editor = await store.openSession(note.id);
      addTearDown(editor.close);

      final ids = await gateway.insertPages(note.id, [
        _pdfDraft(asset.id, 0),
        _pdfDraft(asset.id, 1),
        _pdfDraft(asset.id, 2),
      ], const core.PageAtEnd());
      expect(ids, hasLength(3));
      expect(
        editor.isClosed,
        isFalse,
        reason: 'PDF close() drops only its reference',
      );
      expect(editor.pages, hasLength(4));
      expect(editor.history.undoDepth, 1);

      await editor.undo();
      expect(editor.pages, hasLength(1));
      expect(editor.history.canUndo, isFalse, reason: 'one step only');
    },
  );

  test('trashed note → readOnlyNote, unknown note → noteNotFound', () async {
    final note = await gateway.createNote(title: 'n', pages: const [_blank]);
    await store.library.trashItems([core.NoteRef(note.id)]);
    expect((await gateway.getNote(note.id))!.deletedAt, isNotNull);
    await expectLater(
      gateway.insertPages(note.id, const [_blank], const core.PageAtEnd()),
      throwsA(_code(PdfErrorCode.readOnlyNote)),
    );
    await expectLater(
      gateway.insertPages('missing', const [_blank], const core.PageAtEnd()),
      throwsA(_code(PdfErrorCode.noteNotFound)),
    );
    expect(await gateway.getNote('missing'), isNull);
  });

  test('loadPage after flush and writeThumbnail', () async {
    final note = await gateway.createNote(title: 'n', pages: const [_blank]);
    await gateway.flush();
    final page = (await gateway.pagesOf(note.id)).single;
    final content = await gateway.loadPage(page.id);
    expect(content.page.id, page.id);
    final thumbnail = core.PageThumbnail(
      pageId: page.id,
      contentRevision: content.page.contentRevision,
      width: 1,
      height: 1,
      mimeType: 'image/png',
      bytes: _png1x1,
    );
    await gateway.writeThumbnail(thumbnail);
    final read = await store.thumbnails.read(page.id);
    expect(read?.pageId, page.id);
    expect(read?.contentRevision, content.page.contentRevision);
  });

  test(
    'a failed byte-chunk write → storageFailed with the cause kept',
    () async {
      final failure = StateError('chunk write failed');
      final failing = CorePdfNoteGateway(_PutFailsStore(store, failure));
      await expectLater(
        failing.putPdf(_bytes('x'), fileName: 'x.pdf'),
        throwsA(
          _code(PdfErrorCode.storageFailed)
              .having((e) => e.cause, 'cause', same(failure)),
        ),
      );
      // Nothing was stored, and the real store is still usable afterwards.
      final arrived = <core.AssetId>[];
      final sub = gateway.bytesArrived.listen(arrived.add);
      addTearDown(sub.cancel);
      final asset = await gateway.putPdf(_bytes('x'), fileName: 'x.pdf');
      await pumpEventQueue();
      expect(arrived, [asset.id], reason: 'first real put of these bytes');
      expect(await failing.readAssetBytes(asset.id), _bytes('x'));
    },
  );
}

/// The real store with only AssetStore.put failing at once (the blob store's chunk write —
/// no retry). Everything the gateway reads goes to the real store.
final class _PutFailsStore implements core.NoteStore {
  _PutFailsStore(this.real, Object failure)
    : assets = _PutFailsAssets(real.assets, failure);
  final core.NoteStore real;

  @override
  final core.AssetStore assets;

  @override
  core.LibraryRepository get library => real.library;

  @override
  core.NoteContentReader get content => real.content;

  @override
  core.ThumbnailCache get thumbnails => real.thumbnails;

  @override
  Future<core.NoteSession> openSession(
    core.NoteId noteId, {
    core.NoteSessionOptions options = const core.NoteSessionOptions(),
  }) => real.openSession(noteId, options: options);

  @override
  Future<void> flush() => real.flush();

  @override
  Future<void> close() async {} // the test's tearDown closes the real store

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _PutFailsAssets implements core.AssetStore {
  _PutFailsAssets(this.real, this.failure);
  final core.AssetStore real;
  final Object failure;

  @override
  Future<core.Asset> put(
    Uint8List bytes, {
    required core.AssetType type,
    required String mimeType,
    String? fileName,
  }) => Future.error(failure);

  @override
  Future<core.Asset?> getAsset(core.AssetId id) => real.getAsset(id);

  @override
  Future<Uint8List?> readBytes(core.AssetId id) => real.readBytes(id);

  @override
  Future<bool> hasBytes(core.AssetId id) => real.hasBytes(id);

  @override
  Future<void> putDownloadedBytes(core.AssetId id, Uint8List bytes) =>
      real.putDownloadedBytes(id, bytes);

  @override
  Future<List<core.Asset>> listAssets({bool? hasLocalBytes, bool? uploaded}) =>
      real.listAssets(hasLocalBytes: hasLocalBytes, uploaded: uploaded);

  @override
  Future<void> markUploaded(core.AssetId id, String storagePath) =>
      real.markUploaded(id, storagePath);

  @override
  Future<core.AssetStorageUsage> usage() => real.usage();

  @override
  Stream<core.AssetId> get bytesArrived => real.bytesArrived;
}
