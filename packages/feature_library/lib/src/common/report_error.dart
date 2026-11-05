// lib/src/common/report_error.dart — contract 7.4.5: recoverable errors are
// reported with FlutterError.reportError(library: 'feature_library').
import 'package:flutter/foundation.dart'
    show ErrorDescription, FlutterError, FlutterErrorDetails;

/// Reports [error] for the app shell's error log (AppErrorLog).
void reportLibraryError(Object error, StackTrace stack, String context) {
  FlutterError.reportError(
    FlutterErrorDetails(
      exception: error,
      stack: stack,
      library: 'feature_library',
      context: ErrorDescription(context),
    ),
  );
}
