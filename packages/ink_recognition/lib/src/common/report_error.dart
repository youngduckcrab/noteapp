// lib/src/common/report_error.dart — (internal) contract 7.4.5: recoverable
// errors are reported with FlutterError.reportError(library:
// 'ink_recognition') — the app shell's error log keeps them (05-library 6.22).
// Expected failures (RecognitionFailure in a sheet, clipboard refusals) are
// NOT reported.
import 'package:flutter/foundation.dart'
    show ErrorDescription, FlutterError, FlutterErrorDetails;

/// Reports [error] once to the app shell's error log.
void reportRecognitionError(Object error, StackTrace stack, String context) {
  FlutterError.reportError(
    FlutterErrorDetails(
      exception: error,
      stack: stack,
      library: 'ink_recognition',
      context: ErrorDescription(context),
    ),
  );
}
