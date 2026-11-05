import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_engine/sync_engine.dart';

void main() {
  test('isTransient and isConnectivity follow 4.1', () {
    expect(
      {
        for (final c in SyncErrorCode.values)
          if (c.isTransient) c,
      },
      {
        SyncErrorCode.network,
        SyncErrorCode.unavailable,
        SyncErrorCode.deadlineExceeded,
        SyncErrorCode.aborted,
        SyncErrorCode.internal,
        SyncErrorCode.unknown,
      },
    );
    expect(
      {
        for (final c in SyncErrorCode.values)
          if (c.isConnectivity) c,
      },
      {
        SyncErrorCode.network,
        SyncErrorCode.unavailable,
        SyncErrorCode.deadlineExceeded,
      },
    );
  });

  test('exceptions name their code', () {
    const e = SyncBackendException(SyncErrorCode.permissionDenied, 'no');
    expect(e.toString(), contains('permissionDenied'));
    const s = SignInException(SignInErrorCode.popupBlocked, 'blocked');
    expect(s.toString(), contains('popupBlocked'));
  });

  test('SyncCancelToken cancels once', () {
    fakeAsync((async) {
      final token = SyncCancelToken();
      var fired = 0;
      token.whenCancelled.then((_) => fired++);
      expect(token.isCancelled, isFalse);
      token.throwIfCancelled();
      token
        ..cancel()
        ..cancel();
      async.flushMicrotasks();
      expect(token.isCancelled, isTrue);
      expect(fired, 1);
      expect(
        token.throwIfCancelled,
        throwsA(
          isA<SyncBackendException>().having(
            (e) => e.code,
            'code',
            SyncErrorCode.cancelled,
          ),
        ),
      );
    });
  });
}
