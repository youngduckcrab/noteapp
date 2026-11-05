// CorePdfNoteGateway over the REAL CORE store (06-pdf 8 T4, integration stage only —
// `ws test --run-skipped -t integration`, contract 7.7 step 5): the fake-store scenarios of
// unit/core_gateway_fake_store_test.dart without the retry timing (that needs
// FakeNoteStoreFaults).
@Tags(['integration'])
@TestOn('vm')
library;

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

  test('putPdf dedupe, bytesArrived, readAssetBytes', () async {
    final arrived = <core.AssetId>[];
    final sub = gateway.bytesArrived.listen(arrived.add);
    addTearDown(sub.cancel);
    final a = await gateway.putPdf(_bytes('one'), fileName: 'a.pdf');
    final b = await gateway.putPdf(_bytes('one'), fileName: 'b.pdf');
    expect(b.id, a.id);
    await pumpEventQueue();
    expect(arrived, [a.id]);
    expect(await gateway.readAssetBytes(a.id), _bytes('one'));
    expect(await gateway.readAssetBytes('0' * 64), isNull);
  });

  test('createNote with 500 PDF pages', () async {
    final asset = await gateway.putPdf(_bytes('big'), fileName: 'big.pdf');
    final note = await gateway.createNote(
      title: '강의',
      pages: [for (var i = 0; i < 500; i++) _pdfDraft(asset.id, i)],
    );
    expect(await gateway.pagesOf(note.id), hasLength(500));
  });

  test('insertPages: one undo step, the editor session stays open', () async {
    final asset = await gateway.putPdf(_bytes('ins'), fileName: 'ins.pdf');
    final note = await gateway.createNote(
      title: 'n',
      pages: const [core.PageDraft.blankA4],
    );
    final editor = await store.openSession(note.id);
    addTearDown(editor.close);
    await gateway.insertPages(note.id, [
      _pdfDraft(asset.id, 0),
      _pdfDraft(asset.id, 1),
    ], const core.PageAtEnd());
    expect(editor.isClosed, isFalse);
    expect(editor.pages, hasLength(3));
    await editor.undo();
    expect(editor.pages, hasLength(1));
  });

  test('trashed → readOnlyNote, unknown → noteNotFound', () async {
    final note = await gateway.createNote(
      title: 'n',
      pages: const [core.PageDraft.blankA4],
    );
    await store.library.trashItems([core.NoteRef(note.id)]);
    await expectLater(
      gateway.insertPages(note.id, const [
        core.PageDraft.blankA4,
      ], const core.PageAtEnd()),
      throwsA(_code(PdfErrorCode.readOnlyNote)),
    );
    await expectLater(
      gateway.insertPages('missing', const [
        core.PageDraft.blankA4,
      ], const core.PageAtEnd()),
      throwsA(_code(PdfErrorCode.noteNotFound)),
    );
  });
}
