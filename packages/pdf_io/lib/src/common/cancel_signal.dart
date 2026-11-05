// lib/src/common/cancel_signal.dart — 06-pdf 4.2.
import 'dart:async';

import '../errors.dart';

final class PdfCancelSignal {
  PdfCancelSignal();

  final Completer<void> _cancelled = Completer<void>();

  static const PdfIoException _cancelledError = PdfIoException(
    PdfErrorCode.cancelled,
  );

  bool get isCancelled => _cancelled.isCompleted;

  /// idempotent
  void cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }

  Future<void> get whenCancelled => _cancelled.future;

  /// Throws PdfIoException(cancelled) if cancelled.
  void throwIfCancelled() {
    if (isCancelled) throw _cancelledError;
  }

  /// Completes like [future], or throws PdfIoException(cancelled) as soon as cancel() is
  /// called: Future.any([future, whenCancelled.then((_) => throw cancelled)]). For waits that
  /// may never end — NoteStore.flush() and putPdf's metadata commit while CORE retries a
  /// failed commit (contract 7.2.9 v1.2; 6.3, 6.10.2, 6.11.2). After a cancel [future] keeps
  /// running and its later value / error is ignored (Future.any handles it — no unhandled
  /// error, not reported); CORE's write queue keeps retrying. Already cancelled → throws at once.
  Future<T> raceCancel<T>(Future<T> future) {
    if (isCancelled) {
      // Nobody listens to [future] any more: keep its later error from being unhandled.
      future.ignore();
      throw _cancelledError;
    }
    return Future.any<T>([
      future,
      whenCancelled.then<T>((_) => throw _cancelledError),
    ]);
  }
}
