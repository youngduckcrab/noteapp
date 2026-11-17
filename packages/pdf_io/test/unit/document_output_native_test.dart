// (v2.17-md, C217M-12) The native DocumentFileOutput and the text file helpers: save goes to
// the system save dialog with the exact bytes, name and MIME; share goes to the app's share
// function with the share MIME; outcomes and failures map like the PDF sink.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_io/pdf_io.dart';
import 'package:pdf_io/src/output/output_sink_native.dart'
    show NativeDocumentOutput;

void main() {
  final bytes = Uint8List.fromList([
    0xEF,
    0xBB,
    0xBF,
    ...utf8.encode('# 제목\r\n'),
  ]);
  final file = DocumentFile(
    name: '회의 메모.md',
    bytes: bytes,
    mimeType: 'text/markdown',
    shareMimeType: 'text/plain',
  );

  test(
    'save: the system dialog gets the bytes, name and MIME as they are',
    () async {
      ({String fileName, Uint8List bytes, String mimeType})? saved;
      final out = NativeDocumentOutput(
        saveFile:
            ({required fileName, required bytes, required mimeType}) async {
              saved = (fileName: fileName, bytes: bytes, mimeType: mimeType);
              return Uri.parse('content://x/1');
            },
      );
      expect(out.availableActions(file), {DocumentOutputAction.save});
      expect(out.labelOf(DocumentOutputAction.save), '저장');
      expect(
        await out.deliver(file, DocumentOutputAction.save),
        PdfOutputOutcome.done,
      );
      expect(saved!.fileName, '회의 메모.md');
      expect(saved!.bytes, bytes);
      expect(saved!.mimeType, 'text/markdown');
      expect(
        () => out.deliver(file, DocumentOutputAction.share),
        throwsArgumentError,
      );
    },
  );

  test('save closed → dismissedByUser; a throw → failed', () async {
    var closed = NativeDocumentOutput(
      saveFile: ({
        required fileName,
        required bytes,
        required mimeType,
      }) async => null,
    );
    expect(
      await closed.deliver(file, DocumentOutputAction.save),
      PdfOutputOutcome.dismissedByUser,
    );
    closed = NativeDocumentOutput(
      saveFile: ({required fileName, required bytes, required mimeType}) =>
          Future.error(StateError('no')),
    );
    expect(
      await closed.deliver(file, DocumentOutputAction.save),
      PdfOutputOutcome.failed,
    );
  });

  test('share: the app function gets the file; its throw → failed', () async {
    DocumentFile? shared;
    final out = NativeDocumentOutput(
      share: (f) async {
        shared = f;
        return PdfOutputOutcome.done;
      },
    );
    expect(out.availableActions(file), {
      DocumentOutputAction.share,
      DocumentOutputAction.save,
    });
    expect(
      await out.deliver(file, DocumentOutputAction.share),
      PdfOutputOutcome.done,
    );
    expect(shared!.shareMimeType, 'text/plain');
    expect(shared!.bytes, bytes);
    final failing = NativeDocumentOutput(share: (f) => throw StateError('x'));
    expect(
      await failing.deliver(file, DocumentOutputAction.share),
      PdfOutputOutcome.failed,
    );
  });

  test('createPlatformDocumentOutput on the VM is the native output', () {
    expect(createPlatformDocumentOutput(), isA<NativeDocumentOutput>());
    expect(
      DocumentFile(name: 'a', bytes: Uint8List(0), mimeType: 'x').shareMimeType,
      'x',
    );
  });

  test('text files: md / markdown / txt only, any case', () {
    for (final name in ['a.md', 'B.MD', 'c.markdown', 'd.TXT', '한글.md']) {
      expect(FilePickerTextSource.hasTextExtension(name), isTrue, reason: name);
    }
    for (final name in ['a.pdf', 'md', 'a.md.pdf', 'a.mdx', 'a']) {
      expect(
        FilePickerTextSource.hasTextExtension(name),
        isFalse,
        reason: name,
      );
    }
    expect(FilePickerTextSource.extensions, ['md', 'markdown', 'txt']);
  });

  test('PickedTextFile.fromBytes', () async {
    final f = PickedTextFile.fromBytes('a.md', bytes);
    expect(f.sizeBytes, bytes.length);
    expect(await f.readBytes(), bytes);
  });
}
