// CorePdfNoteGateway over CORE createFakeNoteStore() (06-pdf 4.4, 8 T4): asset dedupe and
// bytesArrived, 500-page notes, insertPages as one undo step in the editor's session,
// exception mapping, and the write-Future rule while CORE retries a failed commit
// (contract 7.2.9 v1.2, PDF-3-1): pending, no error, storageFailed only for a failed chunk write.
import 'dart:async';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart' as core_testing;
import 'package:pdf_io/pdf_io.dart';

Uint8List _bytes(String text) => Uint8List.fromList('%PDF-1.4 $text'.codeUnits);

core.PageDraft _pdfDraft(core.AssetId assetId, int index) => core.PageDraft(
  size: core.PageSize.letterPortrait,
  background: core.PdfBackground(assetId: assetId, pdfPageIndex: index),
);

const core.PageDraft _blank = core.PageDraft.blankA4;

TypeMatcher<PdfIoException> _code(PdfErrorCode code) =>
    isA<PdfIoException>().having((e) => e.code, 'code', code);

core.StorageWarning? _warning(core.NoteStore store) =>
    core.storageWarningOf(store.storageInfo, store.persistenceStatus);

void main() {
  late core.NoteStore store;
  late CorePdfNoteGateway gateway;

  setUp(() {
    store = core_testing.createFakeNoteStore();
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
      bytes: Uint8List(4),
    );
    await gateway.writeThumbnail(thumbnail);
    expect((await store.thumbnails.read(page.id))?.pageId, page.id);
  });

  group('commit retry (fake_async): pending, never an error', () {
    test('createNote: pending at 1 s, done at 6 s', () {
      fakeAsync((async) {
        final faults = core_testing.FakeNoteStoreFaults();
        final store = core_testing.createFakeNoteStore(faults: faults);
        final gateway = CorePdfNoteGateway(store);
        faults.failNextCommits(3);
        core.Note? note;
        Object? error;
        gateway
            .createNote(title: 'n', pages: const [_blank])
            .then(
              (n) => note = n,
              onError: (Object e) {
                error = e;
              },
            );
        async.elapse(const Duration(seconds: 1));
        expect(note, isNull);
        expect(error, isNull);
        expect(_warning(store), core.StorageWarning.writeFailing);
        async.elapse(const Duration(seconds: 5));
        expect(error, isNull);
        expect(note, isNotNull);
        expect(_warning(store), isNull);
        store.close();
        async.flushMicrotasks();
      });
    });

    test(
      'putPdf with new bytes: pending, then done; bytesArrived after it',
      () {
        fakeAsync((async) {
          final faults = core_testing.FakeNoteStoreFaults();
          final store = core_testing.createFakeNoteStore(faults: faults);
          final gateway = CorePdfNoteGateway(store);
          final arrived = <core.AssetId>[];
          final sub = gateway.bytesArrived.listen(arrived.add);
          faults.failNextCommits(3);
          core.Asset? asset;
          Object? error;
          gateway
              .putPdf(_bytes('retry'), fileName: 'r.pdf')
              .then(
                (a) => asset = a,
                onError: (Object e) {
                  error = e;
                },
              );
          async.elapse(const Duration(seconds: 1));
          expect(asset, isNull);
          expect(error, isNull);
          expect(arrived, isEmpty);
          async.elapse(const Duration(seconds: 5));
          expect(error, isNull);
          expect(asset, isNotNull);
          expect(arrived, [asset!.id]);
          sub.cancel();
          store.close();
          async.flushMicrotasks();
        });
      },
    );

    test('flush: pending while an earlier write is retried', () {
      fakeAsync((async) {
        final faults = core_testing.FakeNoteStoreFaults();
        final store = core_testing.createFakeNoteStore(faults: faults);
        final gateway = CorePdfNoteGateway(store);
        faults.failNextCommits(3);
        var flushed = false;
        Object? error;
        unawaited(
          gateway.createNote(title: 'n', pages: const [_blank]).then((_) {}),
        );
        gateway.flush().then(
          (_) => flushed = true,
          onError: (Object e) {
            error = e;
          },
        );
        async.elapse(const Duration(seconds: 1));
        expect(flushed, isFalse);
        expect(error, isNull);
        async.elapse(const Duration(seconds: 5));
        expect(flushed, isTrue);
        expect(error, isNull);
        store.close();
        async.flushMicrotasks();
      });
    });
  });

  test(
    'a failed byte-chunk write → storageFailed with the cause kept',
    () async {
      final failure = StateError('chunk write failed');
      final gateway = CorePdfNoteGateway(_PutFailsStore(failure));
      await expectLater(
        gateway.putPdf(_bytes('x'), fileName: 'x.pdf'),
        throwsA(
          _code(PdfErrorCode.storageFailed)
              .having((e) => e.cause, 'cause', same(failure)),
        ),
      );
    },
  );
}

/// NoteStore whose AssetStore.put fails at once (blob store chunk write — no retry).
final class _PutFailsStore implements core.NoteStore {
  _PutFailsStore(this.failure);
  final Object failure;

  @override
  core.AssetStore get assets => _PutFailsAssets(failure);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _PutFailsAssets implements core.AssetStore {
  _PutFailsAssets(this.failure);
  final Object failure;

  @override
  Future<core.Asset> put(
    Uint8List bytes, {
    required core.AssetType type,
    required String mimeType,
    String? fileName,
  }) => Future.error(failure);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
