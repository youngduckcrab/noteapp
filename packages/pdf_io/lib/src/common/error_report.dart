// lib/src/common/error_report.dart — 06-pdf 6.13 'Error reporting' (contract 7.4.5).
//
// Internal (not exported): the one place pdf_io reports a recoverable error it does not
// show (the app shell collects FlutterError reports in AppErrorLog).
import 'package:flutter/foundation.dart';

/// FlutterError.reportError with library 'pdf_io' and [where] as the context. Never for
/// user-level results (cancelled, passwordCancelled, notPdf, …) or a missing asset (6.13).
void reportPdfError(Object error, StackTrace stack, String where) {
  FlutterError.reportError(
    FlutterErrorDetails(
      exception: error,
      stack: stack,
      library: 'pdf_io',
      context: ErrorDescription(where),
    ),
  );
}
