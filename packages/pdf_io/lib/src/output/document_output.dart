// lib/src/output/document_output.dart — (v2.17-md, C217M-12, m5-7/08-markdown 10.4) saving
// and sharing ONE file of any type (an MD 문서 as .md): bytes + name + MIME. The platform
// implementation comes from document_output_factory.dart; it shares the save dialog and the
// browser download / share helpers of the PDF output sinks (PdfOutputSink is unchanged).
import 'package:flutter/foundation.dart';

import 'pdf_output_sink.dart';

/// One file to deliver.
@immutable
final class DocumentFile {
  const DocumentFile({
    required this.name,
    required this.bytes,
    required this.mimeType,
    String? shareMimeType,
  }) : shareMimeType = shareMimeType ?? mimeType;

  /// The file name with its extension ('회의 메모.md').
  final String name;
  final Uint8List bytes;

  /// The type of a saved / downloaded file ('text/markdown').
  final String mimeType;

  /// The type handed to a share target (08-markdown 10.4: 'text/plain' — some messengers
  /// refuse 'text/markdown'); [mimeType] when not given.
  final String shareMimeType;
}

/// share: the system share sheet (native: the app's share plugin; web: Web Share).
/// save: native — the system save dialog ('저장'); web — a download ('다운로드').
enum DocumentOutputAction { share, save }

/// The native share of one file (the app's share plugin — R16). Completes with done /
/// dismissedByUser / failed; may throw (the output answers failed).
typedef DocumentShareFile = Future<PdfOutputOutcome> Function(
  DocumentFile file,
);

abstract interface class DocumentFileOutput {
  /// Native: {share} when the app gives a [DocumentShareFile], plus {save}. Web: {share}
  /// when navigator.canShare({files: [file]}), plus {save}. Others: none.
  Set<DocumentOutputAction> availableActions(DocumentFile file);

  /// The button label of [action] ('공유' / '저장', web '다운로드').
  String labelOf(DocumentOutputAction action);

  /// Web: MUST be called synchronously from a tap handler. ArgumentError when [action]
  /// is not available.
  Future<PdfOutputOutcome> deliver(
    DocumentFile file,
    DocumentOutputAction action,
  );
}
