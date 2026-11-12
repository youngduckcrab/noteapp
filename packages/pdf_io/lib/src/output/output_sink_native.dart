// lib/src/output/output_sink_native.dart — the native (dart:io) output sink: Android / iOS app
// builds (and the VM). Loaded only through output_sink_factory.dart.
//
// download ('저장' on its button): file_picker's system save dialog with the PDF bytes —
// Android ACTION_CREATE_DOCUMENT (SAF), iOS UIDocumentPickerViewController (export); one file
// per call (results.length == 1). A null answer (the dialog closed) → dismissedByUser, a
// throw → failed. share: every result at once through the [PdfShareFiles] the app provides
// (pdfShareFilesProvider — the share plugin is the app's, R16); without one, no share.
// openInNewTab is never available natively.
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import '../export/export_types.dart';
import '../ui/strings_ko.dart';
import 'pdf_output_sink.dart';

/// web: browser sink; native: save dialog + the app's share; others: unsupported
PdfOutputSink createPlatformOutputSink({PdfShareFiles? share}) =>
    NativePdfOutputSink(share: share);

/// The system save dialog: the saved file's Uri, or null when the user closed it.
typedef PdfSaveFile = Future<Uri?> Function({
  required String fileName,
  required Uint8List bytes,
  required String mimeType,
});

/// Internal (not exported): the native sink. [saveFile] is replaced by tests only (the
/// default is file_picker's FilePicker.saveFile).
final class NativePdfOutputSink
    implements PdfOutputSink, PdfOutputActionLabels {
  NativePdfOutputSink({this._share, PdfSaveFile? saveFile})
    : _saveFile = saveFile ?? _filePickerSave;

  final PdfShareFiles? _share;
  final PdfSaveFile _saveFile;

  static Future<Uri?> _filePickerSave({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
  }) =>
      FilePicker.saveFile(fileName: fileName, bytes: bytes, mimeType: mimeType);

  @override
  String labelOf(PdfOutputAction action) => switch (action) {
    PdfOutputAction.share => PdfStringsKo.share,
    PdfOutputAction.download => PdfStringsKo.save,
    PdfOutputAction.openInNewTab => PdfStringsKo.openInNewTab,
  };

  @override
  Set<PdfOutputAction> availableActions(List<PdfExportResult> results) {
    if (results.isEmpty) return const <PdfOutputAction>{};
    return {
      if (_share != null) PdfOutputAction.share,
      if (results.length == 1) PdfOutputAction.download,
    };
  }

  @override
  Future<PdfOutputOutcome> deliver(
    List<PdfExportResult> results,
    PdfOutputAction action,
  ) {
    if (!availableActions(results).contains(action)) {
      throw ArgumentError.value(action, 'action', 'not available');
    }
    return switch (action) {
      PdfOutputAction.share => _shareAll(results),
      PdfOutputAction.download => _save(results.single),
      PdfOutputAction.openInNewTab => throw StateError('unreachable'),
    };
  }

  Future<PdfOutputOutcome> _shareAll(List<PdfExportResult> results) async {
    try {
      return await _share!(List.unmodifiable(results));
    } on Object {
      return PdfOutputOutcome.failed;
    }
  }

  Future<PdfOutputOutcome> _save(PdfExportResult result) async {
    try {
      final uri = await _saveFile(
        fileName: result.fileName,
        bytes: result.bytes,
        mimeType: result.mimeType,
      );
      return uri == null
          ? PdfOutputOutcome.dismissedByUser
          : PdfOutputOutcome.done;
    } on Object {
      return PdfOutputOutcome.failed;
    }
  }
}
