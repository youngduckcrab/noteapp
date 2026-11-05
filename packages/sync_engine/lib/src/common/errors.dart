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
  bool get isTransient => throw UnimplementedError('SYNC T2');

  /// network, unavailable, deadlineExceeded.
  bool get isConnectivity => throw UnimplementedError('SYNC T2');
}

final class SyncBackendException implements Exception {
  const SyncBackendException(this.code, this.message, {this.cause});
  final SyncErrorCode code;
  final String message;
  final Object? cause;

  @override
  String toString() => throw UnimplementedError('SYNC T2');
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
}
