// lib/src/files/pdf_file_source.dart — 06-pdf 4.5 (file picking, incoming files).
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import '../errors.dart';

@immutable
final class PickedPdfFile {
  const PickedPdfFile({
    required this.name,
    required this.readBytes,
    this.sizeBytes,
    this.mimeType,
  });

  /// tests, incoming files
  factory PickedPdfFile.fromBytes(String name, Uint8List bytes) =>
      PickedPdfFile(
        name: name,
        readBytes: () => Future<Uint8List>.value(bytes),
        sizeBytes: bytes.length,
      );
  final String name; // original file name incl. extension (may be NFD)
  final int? sizeBytes; // known without I/O, or null
  final String? mimeType;
  final Future<Uint8List> Function() readBytes;
}

abstract interface class PdfFileSource {
  bool get isSupported;

  /// Web: MUST be called synchronously from a tap handler (Safari user activation).
  /// Returns null when the user cancels. Throws PdfIoException(pickerFailed).
  Future<PickedPdfFile?> pickPdf();
}

/// file_picker 13.3.2: FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['pdf']).
///
/// One file: FilePicker.pickFile (same options) — the same API on the web and natively
/// (6.15), so there is no platform branch. On the web file_picker opens its <input type=file>
/// inside this call, so pickPdf() must run synchronously in the tap handler (it does: the
/// picker is called before the first await).
final class FilePickerPdfSource implements PdfFileSource {
  const FilePickerPdfSource();

  @override
  bool get isSupported => true;

  @override
  Future<PickedPdfFile?> pickPdf() async {
    final PlatformFile? file;
    try {
      file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
      );
    } on Object catch (e) {
      throw PdfIoException(
        PdfErrorCode.pickerFailed,
        detail: 'file picker failed',
        cause: e,
      );
    }
    return file == null ? null : pickedPdfFileFrom(file);
  }
}

/// Internal (not exported): a picked file_picker file as a PickedPdfFile. The size is the
/// one known without I/O (web: File.size); the bytes are read only when the import asks
/// (PdfImportService.open checks the size first — 6.3 step 1).
PickedPdfFile pickedPdfFileFrom(PlatformFile file) => PickedPdfFile(
  name: file.name,
  sizeBytes: file.lengthSync(),
  readBytes: file.readAsBytes,
);

/// Later (native share-to-open / "Open in"). Web implementation: empty stream.
abstract interface class PdfIncomingFileSource {
  Stream<PickedPdfFile> get incoming;
}

/// Default for web and this scope.
final class NoIncomingPdfFiles implements PdfIncomingFileSource {
  const NoIncomingPdfFiles();

  /// Stream.empty()
  @override
  Stream<PickedPdfFile> get incoming => const Stream<PickedPdfFile>.empty();
}
