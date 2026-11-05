final class SyncCancelToken {
  SyncCancelToken();

  bool get isCancelled => throw UnimplementedError('SYNC T2');

  void cancel() => throw UnimplementedError('SYNC T2');

  Future<void> get whenCancelled => throw UnimplementedError('SYNC T2');

  /// Throws SyncBackendException(cancelled) if cancelled.
  void throwIfCancelled() => throw UnimplementedError('SYNC T2');
}
