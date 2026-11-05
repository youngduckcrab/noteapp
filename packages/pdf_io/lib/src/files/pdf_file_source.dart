// lib/src/files/pdf_file_source.dart — 06-pdf 4.5 (file picking, incoming files).
import 'package:flutter/foundation.dart';

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
/// Foundation step B4 (T0): not supported yet; the picker comes with PDF T6.
final class FilePickerPdfSource implements PdfFileSource {
  const FilePickerPdfSource();

  @override
  bool get isSupported => false;

  @override
  Future<PickedPdfFile?> pickPdf() =>
      throw UnimplementedError('FilePickerPdfSource.pickPdf (PDF T6)');
}

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
