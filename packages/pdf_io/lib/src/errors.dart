// lib/src/errors.dart — 06-pdf 4.2.
import 'package:flutter/foundation.dart';

enum PdfErrorCode {
  notPdf, // no '%PDF-' in the first 1024 bytes
  tooLarge, // > PdfImportLimits.maxBytes
  tooManyPages, // > PdfImportLimits.maxPages
  passwordCancelled, // user dismissed the password dialog / attempts exhausted
  userPasswordRefused, // PdfUserPasswordPolicy.refuse and the PDF needs a user password
  corrupt, // PDFium could not parse
  engineUnavailable, // wasm/native engine failed to initialize, incompatible compose extension
  assetMissing, // PDF bytes are not on this device (AssetStore.readBytes == null)
  noteNotFound, // core.EntityNotFoundException (note purged / unknown id)
  readOnlyNote, // core.ReadOnlyNoteException (trashed note, newer schema — N-4)
  /// Only for CORE writes that fail WITHOUT retry: AssetStore.put's byte-chunk write
  /// (that error at once, no metadata row — contract 7.2.11 v1.2) and any other
  /// core.NoteCoreException. NEVER a failed commit: CORE retries it and the write Future
  /// stays pending (contract 7.2.9 v1.2, 4.4).
  storageFailed,
  exportFailed, // compose backend error
  pickerFailed, // file picker error / unreadable file
  cancelled,
  busy, // another import/export job is running
  unsupportedPlatform,
}

@immutable
final class PdfIoException implements Exception {
  const PdfIoException(this.code, {this.detail, this.cause});
  final PdfErrorCode code;
  final String? detail; // developer detail (English), shown in debug only
  final Object? cause;

  /// Korean message for UI (table 6.14).
  String get userMessage =>
      throw UnimplementedError('PdfIoException.userMessage (PDF T1)');

  @override
  String toString() {
    final buffer = StringBuffer('PdfIoException(${code.name}');
    if (detail != null) buffer.write(', $detail');
    if (cause != null) buffer.write(', cause: $cause');
    buffer.write(')');
    return buffer.toString();
  }

  /// Equal when [code] and [detail] are equal; [cause] is ignored (job / search states
  /// compare their errors — contract 7.4.4).
  @override
  bool operator ==(Object other) =>
      other is PdfIoException && other.code == code && other.detail == detail;

  @override
  int get hashCode => Object.hash(code, detail);
}
