// PdfCancelSignal (06-pdf 4.2, 8 T1) incl. raceCancel with fake_async (no real waits).
import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_io/pdf_io.dart';

Matcher _cancelled() =>
    isA<PdfIoException>().having((e) => e.code, 'code', PdfErrorCode.cancelled);

void main() {
  test('cancel is idempotent; whenCancelled completes once', () {
    fakeAsync((async) {
      final signal = PdfCancelSignal();
      var completions = 0;
      signal.whenCancelled.then((_) => completions++);
      expect(signal.isCancelled, isFalse);
      signal.throwIfCancelled(); // no throw
      signal.cancel();
      signal.cancel();
      async.flushMicrotasks();
      expect(signal.isCancelled, isTrue);
      expect(completions, 1);
      expect(signal.throwIfCancelled, throwsA(_cancelled()));
    });
  });

  test('raceCancel: a never-ending future → cancelled at once on cancel()', () {
    final errors = <Object>[];
    runZonedGuarded(() {
      fakeAsync((async) {
        final signal = PdfCancelSignal();
        final never = Completer<int>();
        Object? error;
        int? value;
        signal
            .raceCancel(never.future)
            .then<void>(
              (v) => value = v,
              onError: (Object e) {
                error = e;
              },
            );
        async.elapse(const Duration(minutes: 10));
        expect(error, isNull);
        expect(value, isNull);

        signal.cancel();
        async.flushMicrotasks();
        expect(error, _cancelled());

        // The original future fails later: handled by Future.any, nothing unhandled.
        never.completeError(StateError('commit failed later'));
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 5));
        expect(value, isNull);
      });
    }, (e, _) => errors.add(e));
    expect(errors, isEmpty);
  });

  test('raceCancel: a later value after the cancel is ignored', () {
    fakeAsync((async) {
      final signal = PdfCancelSignal();
      final later = Completer<String>();
      final results = <Object>[];
      signal
          .raceCancel(later.future)
          .then<void>(results.add, onError: results.add);
      signal.cancel();
      async.flushMicrotasks();
      later.complete('late');
      async.flushMicrotasks();
      expect(results, [_cancelled()]);
    });
  });

  test('raceCancel: already cancelled → throws at once', () {
    final errors = <Object>[];
    runZonedGuarded(() {
      fakeAsync((async) {
        final signal = PdfCancelSignal()..cancel();
        final pending = Completer<int>();
        expect(() => signal.raceCancel(pending.future), throwsA(_cancelled()));
        // The ignored future fails afterwards: no unhandled error.
        pending.completeError(StateError('late'));
        async.flushMicrotasks();
      });
    }, (e, _) => errors.add(e));
    expect(errors, isEmpty);
  });

  test('raceCancel: normal completion passes the value through', () {
    fakeAsync((async) {
      final signal = PdfCancelSignal();
      int? value;
      signal
          .raceCancel(Future.delayed(const Duration(seconds: 1), () => 42))
          .then((v) => value = v);
      async.elapse(const Duration(seconds: 1));
      expect(value, 42);
      // A cancel after completion changes nothing and reports nothing.
      signal.cancel();
      async.flushMicrotasks();
      expect(value, 42);
    });
  });

  test('raceCancel: an error of the future passes through before a cancel', () {
    fakeAsync((async) {
      final signal = PdfCancelSignal();
      Object? error;
      signal
          .raceCancel(
            Future<int>.error(const PdfIoException(PdfErrorCode.corrupt)),
          )
          .then<void>(
            (_) {},
            onError: (Object e) {
              error = e;
            },
          );
      async.flushMicrotasks();
      expect(
        error,
        isA<PdfIoException>().having(
          (e) => e.code,
          'code',
          PdfErrorCode.corrupt,
        ),
      );
    });
  });
}
