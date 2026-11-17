/// Native side of [platformDocumentShare] (document_share.dart): the system share sheet
/// (package:share_plus) with one file — the bytes as they are, named after the file, with
/// the share MIME type (an MD 문서 goes as text/plain, still named '.md' — 08-markdown
/// 10.4).
library;

import 'package:flutter/widgets.dart';
import 'package:pdf_io/pdf_io.dart';
import 'package:share_plus/share_plus.dart';

/// Native: [shareDocumentFile].
const DocumentShareFile platformDocumentShare = shareDocumentFile;

Future<PdfOutputOutcome> shareDocumentFile(DocumentFile file) =>
    shareDocumentFileWith(file, share: SharePlus.instance.share);

/// [shareDocumentFile] with the plugin call given (tests).
@visibleForTesting
Future<PdfOutputOutcome> shareDocumentFileWith(
  DocumentFile file, {
  required Future<ShareResult> Function(ShareParams params) share,
  Rect? origin,
}) async {
  final result = await share(
    ShareParams(
      files: [
        XFile.fromData(
          file.bytes,
          mimeType: file.shareMimeType,
          name: file.name,
        ),
      ],
      fileNameOverrides: [file.name],
      title: file.name,
      sharePositionOrigin: origin ?? _windowOrigin(),
    ),
  );
  return switch (result.status) {
    ShareResultStatus.dismissed => PdfOutputOutcome.dismissedByUser,
    ShareResultStatus.success ||
    ShareResultStatus.unavailable => PdfOutputOutcome.done,
  };
}

Rect? _windowOrigin() {
  final views = WidgetsBinding.instance.platformDispatcher.views;
  if (views.isEmpty) return null;
  final view = views.first;
  final size = view.physicalSize / view.devicePixelRatio;
  if (size.isEmpty) return null;
  return Rect.fromCenter(
    center: Offset(size.width / 2, size.height * 0.8),
    width: 2,
    height: 2,
  );
}
