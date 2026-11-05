import 'dart:async';

import 'errors.dart';

final class SyncCancelToken {
  SyncCancelToken();

  final Completer<void> _cancelled = Completer<void>();

  bool get isCancelled => _cancelled.isCompleted;

  void cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }

  Future<void> get whenCancelled => _cancelled.future;

  /// Throws SyncBackendException(cancelled) if cancelled.
  void throwIfCancelled() {
    if (isCancelled) {
      throw const SyncBackendException(SyncErrorCode.cancelled, 'cancelled');
    }
  }
}
