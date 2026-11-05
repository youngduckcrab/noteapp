// FilePickerPdfSource (06-pdf 4.5, 8 T6) over a scripted file_picker platform: options, the
// picked file as a PickedPdfFile (name, size known without I/O, bytes on demand), cancel →
// null, picker error → pickerFailed.
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_io/pdf_io.dart';

import '../support/fake_file_picker.dart';

final class _MemoryFile extends PlatformFile {
  _MemoryFile(this.name, this.bytes);

  @override
  final String name;
  final Uint8List bytes;
  int reads = 0;

  @override
  Uri get uri => Uri.parse('memory:$name');

  @override
  Never get xFile => throw UnimplementedError('xFile');

  @override
  int? lengthSync() => bytes.length;

  @override
  Future<int?> length() async => bytes.length;

  @override
  Future<Uint8List> readAsBytes() async {
    reads++;
    return bytes;
  }

  @override
  Stream<Uint8List> readAsByteStream() => Stream.value(bytes);
}

void main() {
  late FilePickerPlatform original;
  setUp(() => original = FilePickerPlatform.instance);
  tearDown(() => FilePickerPlatform.instance = original);

  test('picks one PDF; bytes are read only when asked', () async {
    final file = _MemoryFile(
      '강의.pdf',
      Uint8List.fromList('%PDF-1.7 x'.codeUnits),
    );
    final picker = ScriptedFilePicker([file]);
    FilePickerPlatform.instance = picker;
    const source = FilePickerPdfSource();
    expect(source.isSupported, isTrue);
    final picked = await source.pickPdf();
    expect(picker.calls.single.type, FileType.custom);
    expect(picker.calls.single.allowedExtensions, ['pdf']);
    expect(picked!.name, '강의.pdf');
    expect(picked.sizeBytes, file.bytes.length);
    expect(file.reads, 0);
    expect(await picked.readBytes(), file.bytes);
    expect(file.reads, 1);
  });

  test('cancelled picker → null', () async {
    FilePickerPlatform.instance = ScriptedFilePicker([null]);
    expect(await const FilePickerPdfSource().pickPdf(), isNull);
  });

  test('picker error → pickerFailed with the cause', () async {
    FilePickerPlatform.instance = ScriptedFilePicker([StateError('denied')]);
    await expectLater(
      const FilePickerPdfSource().pickPdf(),
      throwsA(
        isA<PdfIoException>()
            .having((e) => e.code, 'code', PdfErrorCode.pickerFailed)
            .having((e) => e.cause, 'cause', isA<StateError>()),
      ),
    );
  });
}
