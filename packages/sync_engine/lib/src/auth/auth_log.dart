// Internal (not exported): the auth layer's log line (07-sync 4.2 — AuthService.idToken
// "logs and returns null"). AuthService has no log sink of its own (its constructor is the
// 1st-round contract's), so it goes to dart:developer (web-safe) under 'sync_engine.auth';
// tests see the lines through [authLogHook].
import 'dart:developer' as developer;

import 'package:meta/meta.dart';

/// Tests: called with every auth log line before it is logged (null = none).
@visibleForTesting
void Function(String message, Object? error)? authLogHook;

/// A warning of the auth layer. [message] and [error] never hold a token.
void authLog(String message, {Object? error, StackTrace? stackTrace}) {
  authLogHook?.call(message, error);
  developer.log(
    message,
    name: 'sync_engine.auth',
    level: 900, // WARNING
    error: error,
    stackTrace: stackTrace,
  );
}
