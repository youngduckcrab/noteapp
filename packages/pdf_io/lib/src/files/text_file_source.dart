// lib/src/files/text_file_source.dart — (v2.17-md, C217M-12, m5-7/08-markdown 10.1) picking
// text files (.md / .markdown / .txt) for 'MD 가져오기'. pdf_io is the one member allowed to
// use file_picker (R16), so the picker of every file kind lives here.
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import '../errors.dart';

/// A picked text file: its name and its bytes, read on demand (the size is known first, so
/// a caller can refuse a huge file without reading it).
@immutable
final class PickedTextFile {
  const PickedTextFile({
    required this.name,
    required this.readBytes,
    this.sizeBytes,
  });

  /// tests
  factory PickedTextFile.fromBytes(String name, Uint8List bytes) =>
      PickedTextFile(
        name: name,
        readBytes: () => Future<Uint8List>.value(bytes),
        sizeBytes: bytes.length,
      );

  /// The original file name with its extension (may be NFD on macOS / iOS).
  final String name;

  /// Known without I/O, or null.
  final int? sizeBytes;
  final Future<Uint8List> Function() readBytes;
}

abstract interface class TextFileSource {
  bool get isSupported;

  /// Web: MUST be called synchronously from a tap handler (the picker opens before the
  /// first await). Returns null when the user cancels. Throws PdfIoException(pickerFailed).
  Future<List<PickedTextFile>?> pickTextFiles({bool allowMultiple = true});
}

/// file_picker 13.3.2: FilePicker.pickFiles / pickFile with the md / markdown / txt
/// extensions. Android maps extensions to MIME types and may not know '.md': when the
/// filtered picker fails there, it is opened again for any file. Every picked file is
/// returned — the caller refuses one whose name does not pass [hasTextExtension] (and
/// says so, per file), since providers can return other files even after a filtered pick.
final class FilePickerTextSource implements TextFileSource {
  const FilePickerTextSource({this.platformIsWeb = kIsWeb});

  /// tests
  final bool platformIsWeb;

  static const List<String> extensions = ['md', 'markdown', 'txt'];

  @override
  bool get isSupported => true;

  /// Whether [name] ends with one of [extensions] (case-insensitive).
  static bool hasTextExtension(String name) {
    final lower = name.toLowerCase();
    return extensions.any((e) => lower.endsWith('.$e'));
  }

  @override
  Future<List<PickedTextFile>?> pickTextFiles({bool allowMultiple = true}) {
    // No await before the first picker call (web user activation).
    final first = _pick(FileType.custom, allowMultiple);
    return () async {
      List<PlatformFile>? files;
      try {
        files = await first;
      } on Object catch (e) {
        if (platformIsWeb) {
          throw PdfIoException(
            PdfErrorCode.pickerFailed,
            detail: 'file picker failed',
            cause: e,
          );
        }
        try {
          files = await _pick(FileType.any, allowMultiple);
        } on Object catch (e2) {
          throw PdfIoException(
            PdfErrorCode.pickerFailed,
            detail: 'file picker failed',
            cause: e2,
          );
        }
      }
      if (files == null || files.isEmpty) return null;
      return [
        for (final f in files)
          PickedTextFile(
            name: f.name,
            sizeBytes: f.lengthSync(),
            readBytes: f.readAsBytes,
          ),
      ];
    }();
  }

  static Future<List<PlatformFile>?> _pick(FileType type, bool multiple) {
    final ext = type == FileType.custom ? extensions : null;
    if (multiple) {
      return FilePicker.pickFiles(type: type, allowedExtensions: ext);
    }
    return FilePicker.pickFile(
      type: type,
      allowedExtensions: ext,
    ).then((f) => f == null ? null : [f]);
  }
}
