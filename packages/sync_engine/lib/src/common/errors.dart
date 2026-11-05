enum SyncErrorCode {
  network, // no connection, socket closed, offline
  unavailable, // Firestore 'unavailable'
  deadlineExceeded, // timeout (SyncConfig.operationTimeout)
  aborted,
  cancelled,
  resourceExhausted, // quota
  unauthenticated,
  permissionDenied,
  invalidArgument, // e.g. document too large
  notFound,
  alreadyExists,
  failedPrecondition, // e.g. missing index
  dataLoss,
  internal,
  unknown;

  /// network, unavailable, deadlineExceeded, aborted, internal, unknown.
  bool get isTransient => switch (this) {
    network || unavailable || deadlineExceeded || aborted => true,
    internal || unknown => true,
    _ => false,
  };

  /// network, unavailable, deadlineExceeded.
  bool get isConnectivity =>
      this == network || this == unavailable || this == deadlineExceeded;
}

final class SyncBackendException implements Exception {
  const SyncBackendException(this.code, this.message, {this.cause});
  final SyncErrorCode code;
  final String message;
  final Object? cause;

  @override
  String toString() => cause == null
      ? 'SyncBackendException(${code.name}): $message'
      : 'SyncBackendException(${code.name}): $message ($cause)';
}

enum SignInErrorCode {
  cancelled,
  popupBlocked,
  network,
  unsupportedPlatform,
  accountDisabled,
  misconfigured,
  unknown,
}

final class SignInException implements Exception {
  const SignInException(this.code, this.message, {this.cause});
  final SignInErrorCode code;
  final String message;
  final Object? cause;

  @override
  String toString() => 'SignInException(${code.name}): $message';
}
