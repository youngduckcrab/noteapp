@TestOn('browser')
library;

// FilePickerPdfSource in the browser (06-pdf 4.5, 8 T6): a real web.File behind the picked
// file (as file_picker's web PlatformFile wraps it — size from File.size, bytes read on
// demand with arrayBuffer) → PickedPdfFile name, size and bytes.

import 'dart:js_interop';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_io/pdf_io.dart';
import 'package:web/web.dart' as web;

import '../support/fake_file_picker.dart';

final class _WebFile extends PlatformFile {
  _WebFile(this.file);

  final web.File file;
  int reads = 0;

  @override
  String get name => file.name;

  @override
  Uri get uri => Uri.parse('blob:pdf-io-test');

  @override
  Never get xFile => throw UnimplementedError('xFile');

  @override
  int? lengthSync() => file.size;

  @override
  Future<int?> length() async => file.size;

  @override
  Future<Uint8List> readAsBytes() async {
    reads++;
    final buffer = await file.arrayBuffer().toDart;
    return buffer.toDart.asUint8List();
  }

  @override
  Stream<Uint8List> readAsByteStream() => Stream.fromFuture(readAsBytes());
}

void main() {
  test('web.File → PickedPdfFile: name, size, bytes', () async {
    final bytes = Uint8List.fromList('%PDF-1.7\n% web file\n%%EOF\n'.codeUnits);
    // NFD name as Safari / iOS Files may give it: kept as is (composed only for display).
    const name = '강의.pdf';
    final file = web.File(
      <web.BlobPart>[bytes.toJS].toJS,
      name,
      web.FilePropertyBag(type: 'application/pdf'),
    );
    final platformFile = _WebFile(file);
    final original = FilePickerPlatform.instance;
    addTearDown(() => FilePickerPlatform.instance = original);
    final picker = ScriptedFilePicker([platformFile]);
    FilePickerPlatform.instance = picker;

    const source = FilePickerPdfSource();
    expect(source.isSupported, isTrue);
    final picked = await source.pickPdf();
    expect(picker.calls.single.allowedExtensions, ['pdf']);
    expect(picked!.name, name);
    expect(picked.sizeBytes, bytes.length);
    expect(platformFile.reads, 0);
    expect(await picked.readBytes(), bytes);
    expect(platformFile.reads, 1);
  });
}
