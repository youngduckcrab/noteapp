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

/// Error objects already reported, per owner (the ProviderContainer).
final Expando<Set<Object>> _reportedErrors = Expando(
  'feature_library reported errors',
);

/// [reportLibraryError] at most once per [owner] and error object (6.19
/// '보고 1회'). For errors read from a provider while building: a part that
/// is built again — every rebuild, and the drawer builds a new sidebar each
/// time it opens — does not report the same provider error twice. [owner] is
/// the ProviderContainer (ProviderScope.containerOf(context, listen: false)),
/// so separate apps / tests never share the record.
void reportLibraryErrorOnce(
  Object owner,
  Object error,
  StackTrace? stack,
  String context,
) {
  final seen = _reportedErrors[owner] ??= Set<Object>.identity();
  if (!seen.add(error)) return;
  reportLibraryError(error, stack ?? StackTrace.empty, context);
}
