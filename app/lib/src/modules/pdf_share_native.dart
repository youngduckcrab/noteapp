/// Native side of [platformPdfShare] (pdf_share.dart): the system share sheet
/// (package:share_plus — Android ACTION_SEND through its FileProvider, iOS
/// UIActivityViewController) with every exported PDF as a file.
library;

import 'package:flutter/widgets.dart';
import 'package:pdf_io/pdf_io.dart';
import 'package:share_plus/share_plus.dart';

/// Native: [sharePdfFiles].
const PdfShareFiles platformPdfShare = sharePdfFiles;

/// The system share sheet with [results] as PDF files.
Future<PdfOutputOutcome> sharePdfFiles(List<PdfExportResult> results) =>
    sharePdfFilesWith(results, share: SharePlus.instance.share);

/// [sharePdfFiles] with the plugin call given (tests). The bytes go as
/// XFile.fromData — share_plus writes them to a temporary file under the
/// app's cache before handing them over — named after each result
/// (fileNameOverrides; XFile.fromData drops the name natively). [origin] is
/// the iPad popover anchor (required there); by default a point near the
/// bottom centre of the window, where the result sheet is.
@visibleForTesting
Future<PdfOutputOutcome> sharePdfFilesWith(
  List<PdfExportResult> results, {
  required Future<ShareResult> Function(ShareParams params) share,
  Rect? origin,
}) async {
  if (results.isEmpty) return PdfOutputOutcome.failed;
  final result = await share(
    ShareParams(
      files: [
        for (final r in results)
          XFile.fromData(r.bytes, mimeType: r.mimeType, name: r.fileName),
      ],
      fileNameOverrides: [for (final r in results) r.fileName],
      title: results.length == 1
          ? results.single.fileName
          : 'PDF ${results.length}개',
      sharePositionOrigin: origin ?? _windowOrigin(),
    ),
  );
  return switch (result.status) {
    ShareResultStatus.dismissed => PdfOutputOutcome.dismissedByUser,
    ShareResultStatus.success ||
    ShareResultStatus.unavailable => PdfOutputOutcome.done,
  };
}

/// A 2×2 rect at the bottom centre of the first window (logical pixels), or
/// null when there is no window.
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
