// FakePdfNoteGateway (06-pdf 4.14, 8 T4): held writes stay pending until releaseWrites,
// plus the in-memory behaviour the import / render / export tests rely on.
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:pdf_io/pdf_io.dart';
import 'package:pdf_io/testing.dart';

final Uint8List _pdf = Uint8List.fromList('%PDF-1.4 fake'.codeUnits);

const core.PageDraft _draft = core.PageDraft(
  size: core.PageSize.letterPortrait,
  background: core.BlankBackground(),
);

TypeMatcher<PdfIoException> _code(PdfErrorCode code) =>
    isA<PdfIoException>().having((e) => e.code, 'code', code);

void main() {
  test(
    'holdWrites: putPdf, createNote, insertPages, flush pending until release',
    () {
      fakeAsync((async) {
        final gateway = FakePdfNoteGateway();
        core.Note? note;
        gateway
            .createNote(title: 'n', pages: const [_draft])
            .then((n) => note = n);
        async.flushMicrotasks();
        expect(note, isNotNull);

        gateway.holdWrites();
        final done = <String>[];
        final errors = <Object>[];
        void track(String name, Future<Object?> f) =>
            f.then((_) => done.add(name), onError: errors.add);
        track('putPdf', gateway.putPdf(_pdf, fileName: 'a.pdf'));
        track(
          'createNote',
          gateway.createNote(title: 'm', pages: const [_draft]),
        );
        track(
          'insertPages',
          gateway.insertPages(note!.id, const [_draft], const core.PageAtEnd()),
        );
        track('flush', gateway.flush());
        async.elapse(const Duration(minutes: 5));
        expect(done, isEmpty);
        expect(errors, isEmpty);
        expect(gateway.heldWriteCount, 4);

        gateway.releaseWrites();
        async.flushMicrotasks();
        expect(done, ['putPdf', 'createNote', 'insertPages', 'flush']);
        expect(errors, isEmpty);
        expect(gateway.heldWriteCount, 0);
      });
    },
  );

  test(
    'putPdf: same bytes → same asset, bytesArrived once, readAssetBytes',
    () async {
      final gateway = FakePdfNoteGateway();
      final arrived = <core.AssetId>[];
      final sub = gateway.bytesArrived.listen(arrived.add);
      addTearDown(sub.cancel);
      final a = await gateway.putPdf(_pdf, fileName: 'a.pdf');
      final b = await gateway.putPdf(
        Uint8List.fromList(_pdf),
        fileName: 'b.pdf',
      );
      expect(b.id, a.id);
      expect(a.id, hasLength(64)); // sha-256 hex
      expect(a.type, core.AssetType.pdf);
      expect(a.mimeType, 'application/pdf');
      expect(arrived, [a.id]);
      expect(await gateway.readAssetBytes(a.id), _pdf);
      expect(await gateway.readAssetBytes('missing'), isNull);
    },
  );

  test(
    'remote asset: no bytes until arriveBytes, which emits bytesArrived',
    () async {
      final gateway = FakePdfNoteGateway()..addRemoteAsset('remote-1');
      final arrived = <core.AssetId>[];
      final sub = gateway.bytesArrived.listen(arrived.add);
      addTearDown(sub.cancel);
      expect(await gateway.readAssetBytes('remote-1'), isNull);
      expect(gateway.assets['remote-1']!.hasLocalBytes, isFalse);
      gateway.arriveBytes('remote-1', _pdf);
      expect(arrived, ['remote-1']);
      expect(await gateway.readAssetBytes('remote-1'), _pdf);
      expect(gateway.assets['remote-1']!.hasLocalBytes, isTrue);
      gateway.dropAssetBytes('remote-1');
      expect(await gateway.readAssetBytes('remote-1'), isNull);
    },
  );

  test('createNote / insertPages / pagesOf / loadPage', () async {
    final gateway = FakePdfNoteGateway();
    final note = await gateway.createNote(
      folderId: 'f1',
      title: 'Lecture',
      pages: const [_draft, _draft],
    );
    expect(note.folderId, 'f1');
    expect(note.pageCount, 2);
    final pages = await gateway.pagesOf(note.id);
    expect(pages, hasLength(2));
    final inserted = await gateway.insertPages(note.id, const [
      _draft,
    ], core.PageAfter(pages.first.id));
    final after = await gateway.pagesOf(note.id);
    expect(after.map((p) => p.id), [pages[0].id, inserted.single, pages[1].id]);
    expect((await gateway.getNote(note.id))!.pageCount, 3);
    final content = await gateway.loadPage(inserted.single);
    expect(content.page.size, core.PageSize.letterPortrait);
    expect(content.strokes, isEmpty);
    expect(
      gateway.createNote(title: 'x', pages: const []),
      throwsArgumentError,
    );
  });

  test(
    'trashed note → readOnlyNote; unknown / purged → noteNotFound',
    () async {
      final gateway = FakePdfNoteGateway();
      final note = await gateway.createNote(title: 'n', pages: const [_draft]);
      gateway.trashNote(note.id);
      expect((await gateway.getNote(note.id))!.deletedAt, isNotNull);
      await expectLater(
        gateway.insertPages(note.id, const [_draft], const core.PageAtEnd()),
        throwsA(_code(PdfErrorCode.readOnlyNote)),
      );
      gateway.purgeNote(note.id);
      expect(await gateway.getNote(note.id), isNull);
      await expectLater(
        gateway.insertPages(note.id, const [_draft], const core.PageAtEnd()),
        throwsA(_code(PdfErrorCode.noteNotFound)),
      );
      await expectLater(
        gateway.pagesOf('nope'),
        throwsA(_code(PdfErrorCode.noteNotFound)),
      );
      await expectLater(
        gateway.loadPage('nope'),
        throwsA(_code(PdfErrorCode.noteNotFound)),
      );
    },
  );

  test('writeThumbnail is recorded; calls are logged', () async {
    final gateway = FakePdfNoteGateway();
    final thumbnail = core.PageThumbnail(
      pageId: 'p',
      contentRevision: 1,
      width: 1,
      height: 1,
      mimeType: 'image/png',
      bytes: Uint8List(0),
    );
    await gateway.writeThumbnail(thumbnail);
    expect(gateway.thumbnails['p'], same(thumbnail));
    await gateway.flush();
    expect(gateway.calls, ['writeThumbnail', 'flush']);
  });
}
