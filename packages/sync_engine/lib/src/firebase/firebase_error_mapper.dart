// Firebase errors → the engine's error types (6.4.6 '오류', 6.10.1). Codes are the
// FirebaseException.code strings; the web SDK may prefix them ('auth/popup-blocked',
// 'firestore/unavailable'), so the part after the last '/' is used.
import 'dart:async';

import 'package:firebase_core/firebase_core.dart';

import '../common/errors.dart';

/// FirebaseException / FirebaseAuthException / TimeoutException → SyncBackendException.
SyncBackendException mapFirebaseError(Object error, {StackTrace? stackTrace}) {
  if (error is SyncBackendException) return error;
  if (error is TimeoutException) {
    return SyncBackendException(
      SyncErrorCode.deadlineExceeded,
      error.message ?? 'timed out',
      cause: error,
    );
  }
  if (error is FirebaseException) {
    final code = _codeOf(error.code);
    return SyncBackendException(
      _backendCodes[code] ?? SyncErrorCode.unknown,
      '${error.plugin}/$code: ${error.message ?? ''}'.trim(),
      cause: error,
    );
  }
  return SyncBackendException(SyncErrorCode.unknown, '$error', cause: error);
}

SignInException mapSignInError(Object error) {
  if (error is SignInException) return error;
  if (error is FirebaseException) {
    final code = _codeOf(error.code);
    return SignInException(
      _signInCodes[code] ?? SignInErrorCode.unknown,
      '$code: ${error.message ?? ''}'.trim(),
      cause: error,
    );
  }
  if (error is TimeoutException) {
    return SignInException(SignInErrorCode.network, 'timed out', cause: error);
  }
  return SignInException(SignInErrorCode.unknown, '$error', cause: error);
}

String _codeOf(String code) {
  final slash = code.lastIndexOf('/');
  return slash < 0 ? code : code.substring(slash + 1);
}

/// Firestore's 14 status codes (6.4.6), then the Auth and Storage codes the backend calls
/// can raise.
const Map<String, SyncErrorCode> _backendCodes = {
  'unavailable': SyncErrorCode.unavailable,
  'deadline-exceeded': SyncErrorCode.deadlineExceeded,
  'permission-denied': SyncErrorCode.permissionDenied,
  'unauthenticated': SyncErrorCode.unauthenticated,
  'resource-exhausted': SyncErrorCode.resourceExhausted,
  'invalid-argument': SyncErrorCode.invalidArgument,
  'aborted': SyncErrorCode.aborted,
  'not-found': SyncErrorCode.notFound,
  'already-exists': SyncErrorCode.alreadyExists,
  'failed-precondition': SyncErrorCode.failedPrecondition,
  'cancelled': SyncErrorCode.cancelled,
  'internal': SyncErrorCode.internal,
  'data-loss': SyncErrorCode.dataLoss,
  'unknown': SyncErrorCode.unknown,
  // Auth (refreshSession / getIdToken).
  'network-request-failed': SyncErrorCode.network,
  'user-token-expired': SyncErrorCode.unauthenticated,
  'invalid-user-token': SyncErrorCode.unauthenticated,
  'user-disabled': SyncErrorCode.unauthenticated,
  'user-not-found': SyncErrorCode.unauthenticated,
  'requires-recent-login': SyncErrorCode.unauthenticated,
  'too-many-requests': SyncErrorCode.resourceExhausted,
  // Storage.
  'unauthorized': SyncErrorCode.permissionDenied,
  'object-not-found': SyncErrorCode.notFound,
  'quota-exceeded': SyncErrorCode.resourceExhausted,
  'retry-limit-exceeded': SyncErrorCode.deadlineExceeded,
  'canceled': SyncErrorCode.cancelled,
  'invalid-checksum': SyncErrorCode.dataLoss,
  'unknown-error': SyncErrorCode.unknown,
};

/// FirebaseAuthException codes of signInWithPopup / signInWithRedirect / getRedirectResult /
/// signInWithCredential (6.10.1).
const Map<String, SignInErrorCode> _signInCodes = {
  'popup-closed-by-user': SignInErrorCode.cancelled,
  'cancelled-popup-request': SignInErrorCode.cancelled,
  'user-cancelled': SignInErrorCode.cancelled,
  'web-context-canceled': SignInErrorCode.cancelled,
  'web-context-cancelled': SignInErrorCode.cancelled,
  'popup-blocked': SignInErrorCode.popupBlocked,
  'network-request-failed': SignInErrorCode.network,
  'timeout': SignInErrorCode.network,
  'operation-not-supported-in-this-environment':
      SignInErrorCode.unsupportedPlatform,
  'web-storage-unsupported': SignInErrorCode.unsupportedPlatform,
  'user-disabled': SignInErrorCode.accountDisabled,
  'operation-not-allowed': SignInErrorCode.misconfigured,
  'unauthorized-domain': SignInErrorCode.misconfigured,
  'invalid-api-key': SignInErrorCode.misconfigured,
  'app-not-authorized': SignInErrorCode.misconfigured,
  'configuration-not-found': SignInErrorCode.misconfigured,
  'auth-domain-config-required': SignInErrorCode.misconfigured,
  'invalid-oauth-client-id': SignInErrorCode.misconfigured,
  'missing-or-invalid-nonce': SignInErrorCode.misconfigured,
};
