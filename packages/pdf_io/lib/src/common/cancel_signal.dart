// lib/src/common/cancel_signal.dart — 06-pdf 4.2.
//
// Foundation step B4 (T0): signatures only; the behaviour comes with PDF T1.

final class PdfCancelSignal {
  PdfCancelSignal();

  bool get isCancelled =>
      throw UnimplementedError('PdfCancelSignal.isCancelled (PDF T1)');

  /// idempotent
  void cancel() => throw UnimplementedError('PdfCancelSignal.cancel (PDF T1)');

  Future<void> get whenCancelled =>
      throw UnimplementedError('PdfCancelSignal.whenCancelled (PDF T1)');

  /// Throws PdfIoException(cancelled) if cancelled.
  void throwIfCancelled() =>
      throw UnimplementedError('PdfCancelSignal.throwIfCancelled (PDF T1)');

  /// Completes like [future], or throws PdfIoException(cancelled) as soon as cancel() is
  /// called: Future.any([future, whenCancelled.then((_) => throw cancelled)]). For waits that
  /// may never end — NoteStore.flush() and putPdf's metadata commit while CORE retries a
  /// failed commit (contract 7.2.9 v1.2; 6.3, 6.10.2, 6.11.2). After a cancel [future] keeps
  /// running and its later value / error is ignored (Future.any handles it — no unhandled
  /// error, not reported); CORE's write queue keeps retrying. Already cancelled → throws at once.
  Future<T> raceCancel<T>(Future<T> future) =>
      throw UnimplementedError('PdfCancelSignal.raceCancel (PDF T1)');
}
