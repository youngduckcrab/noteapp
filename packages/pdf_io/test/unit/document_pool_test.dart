// DefaultPdfDocumentPool (06-pdf 4.7, 6.6; 8 T7) with FakePdfEngine, FakePdfNoteGateway and
// FakeRemoteAssetFetcher under fake_async: one open per asset, reference counts, idle close
// after 60 s, at most 2 idle documents, assetMissing, the 2-second failure memo, adopt,
// bytesArrived, and remote requests (P-2).
import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:pdf_io/pdf_io.dart';
import 'package:pdf_io/testing.dart';

Uint8List _pdf(String body) =>
    Uint8List.fromList('%PDF-1.7\n% $body\n%%EOF\n'.codeUnits);

TypeMatcher<PdfIoException> _code(PdfErrorCode code) =>
    isA<PdfIoException>().having((e) => e.code, 'code', code);

const core.RemoteAssetProgress _downloading = core.RemoteAssetProgress(
  core.RemoteAssetState.downloading,
  received: 10,
  total: 100,
);

final class _World {
  _World({List<String> local = const ['a', 'b', 'c'], this.fetcher}) {
    for (final id in local) {
      gateway.arriveBytes(id, _pdf(id));
    }
    pool = DefaultPdfDocumentPool(
      engine: engine,
      gateway: gateway,
      remoteAssets: fetcher,
    );
  }

  final FakePdfEngine engine = FakePdfEngine(pageCount: 2);
  final FakePdfNoteGateway gateway = FakePdfNoteGateway();
  final FakeRemoteAssetFetcher? fetcher;
  late final DefaultPdfDocumentPool pool;

  int get opens => engine.openCalls.length;
}

/// Runs [future] to its end inside fake_async and returns its value (or throws its error).
T _wait<T>(FakeAsync async, Future<T> future) {
  T? value;
  Object? error;
  var done = false;
  future.then(
    (v) {
      value = v;
      done = true;
    },
    onError: (Object e) {
      error = e;
      done = true;
    },
  );
  async.flushMicrotasks();
  expect(done, isTrue, reason: 'future did not complete');
  if (error != null) Error.throwWithStackTrace(error!, StackTrace.current);
  return value as T;
}

void main() {
  test('concurrent acquires open once; leases share the document', () {
    fakeAsync((async) {
      final w = _World();
      final first = w.pool.acquire('a');
      final second = w.pool.acquire('a');
      final l1 = _wait(async, first);
      final l2 = _wait(async, second);
      expect(w.opens, 1);
      final call = w.engine.openCalls.single;
      expect(call.sourceName, 'asset:a');
      expect(call.transferOwnership, isTrue);
      expect(identical(l1.document, l2.document), isTrue);
      expect(l1.assetId, 'a');
      expect(w.pool.openCount, 1);
      expect(w.gateway.calls.where((c) => c == 'readAssetBytes'), hasLength(1));
    });
  });

  test('reference counts: idle only at zero, closed after 60 s', () {
    fakeAsync((async) {
      final w = _World();
      final l1 = _wait(async, w.pool.acquire('a'));
      final l2 = _wait(async, w.pool.acquire('a'));
      l1.release();
      l1.release(); // idempotent
      async.elapse(const Duration(seconds: 120));
      expect(w.pool.openCount, 1);
      expect(l2.document.isDisposed, isFalse);
      l2.release();
      async.elapse(const Duration(seconds: 59));
      expect(w.pool.openCount, 1);
      // Acquired again while idle: the timer stops, no second open.
      final l3 = _wait(async, w.pool.acquire('a'));
      expect(w.opens, 1);
      async.elapse(const Duration(seconds: 120));
      expect(l3.document.isDisposed, isFalse);
      l3.release();
      async.elapse(const Duration(seconds: 59));
      expect(w.pool.openCount, 1);
      async.elapse(const Duration(seconds: 1));
      expect(w.pool.openCount, 0);
      expect(l3.document.isDisposed, isTrue);
      expect(w.engine.openDocumentCount, 0);
      // Opens anew afterwards.
      _wait(async, w.pool.acquire('a')).release();
      expect(w.opens, 2);
    });
  });

  test('at most 2 idle documents: the oldest idle one is closed', () {
    fakeAsync((async) {
      final w = _World();
      final a = _wait(async, w.pool.acquire('a'));
      final b = _wait(async, w.pool.acquire('b'));
      final c = _wait(async, w.pool.acquire('c'));
      expect(w.pool.openCount, 3);
      a.release();
      b.release();
      expect(w.pool.openCount, 3); // 2 idle + 1 in use
      c.release();
      expect(w.pool.openCount, 2);
      expect(a.document.isDisposed, isTrue);
      expect(b.document.isDisposed, isFalse);
      expect(c.document.isDisposed, isFalse);
    });
  });

  test('closeIdle closes idle documents only', () {
    fakeAsync((async) {
      final w = _World();
      final a = _wait(async, w.pool.acquire('a'));
      final b = _wait(async, w.pool.acquire('b'));
      a.release();
      _wait(async, w.pool.closeIdle());
      expect(a.document.isDisposed, isTrue);
      expect(b.document.isDisposed, isFalse);
      expect(w.pool.openCount, 1);
    });
  });

  test('no bytes on this device → assetMissing, engine not asked', () {
    fakeAsync((async) {
      final w = _World(local: const []);
      w.gateway.addRemoteAsset('r');
      expect(
        () => _wait(async, w.pool.acquire('r')),
        throwsA(_code(PdfErrorCode.assetMissing)),
      );
      expect(w.opens, 0);
    });
  });

  test('failures are not cached, but repeated for 2 s', () {
    fakeAsync((async) {
      final w = _World();
      w.engine.openError = const PdfIoException(PdfErrorCode.corrupt);
      expect(
        () => _wait(async, w.pool.acquire('a')),
        throwsA(_code(PdfErrorCode.corrupt)),
      );
      expect(w.opens, 1);
      async.elapse(const Duration(milliseconds: 1900));
      expect(
        () => _wait(async, w.pool.acquire('a')),
        throwsA(_code(PdfErrorCode.corrupt)),
      );
      expect(w.opens, 1); // the memo answered
      async.elapse(const Duration(milliseconds: 100));
      w.engine.openError = null;
      final lease = _wait(async, w.pool.acquire('a'));
      expect(w.opens, 2);
      expect(lease.document.isDisposed, isFalse);
    });
  });

  test('a password-protected asset → passwordCancelled (needsPassword)', () {
    fakeAsync((async) {
      final w = _World();
      w.engine.userPassword = 'pw';
      expect(
        () => _wait(async, w.pool.acquire('a')),
        throwsA(_code(PdfErrorCode.passwordCancelled)),
      );
      expect(w.engine.passwordRequests, isEmpty); // never asks (6.4)
    });
  });

  test('adopt: no second open; idle rules apply; duplicates are closed', () {
    fakeAsync((async) {
      final w = _World();
      final imported = _wait(
        async,
        w.engine.open(_pdf('a'), sourceName: 'import:1'),
      );
      w.pool.adopt('a', imported);
      expect(w.pool.openCount, 1);
      final lease = _wait(async, w.pool.acquire('a'));
      expect(identical(lease.document, imported), isTrue);
      expect(w.opens, 1); // only the import's own open
      // The same file imported again: the pool keeps its document.
      final again = _wait(
        async,
        w.engine.open(_pdf('a'), sourceName: 'import:2'),
      );
      w.pool.adopt('a', again);
      async.flushMicrotasks();
      expect(again.isDisposed, isTrue);
      expect(imported.isDisposed, isFalse);
      lease.release();
      async.elapse(const Duration(seconds: 60));
      expect(imported.isDisposed, isTrue);
      expect(w.pool.openCount, 0);
    });
  });

  test('adopt clears a failure memo of the id', () {
    fakeAsync((async) {
      final w = _World(local: const []);
      expect(
        () => _wait(async, w.pool.acquire('a')),
        throwsA(_code(PdfErrorCode.assetMissing)),
      );
      final doc = _wait(async, w.engine.open(_pdf('a'), sourceName: 'i'));
      w.pool.adopt('a', doc);
      expect(_wait(async, w.pool.acquire('a')).document, same(doc));
    });
  });

  test('bytesArrived drops the failure memo and emits assetArrived', () {
    fakeAsync((async) {
      final w = _World(local: const []);
      final arrived = <core.AssetId>[];
      w.pool.assetArrived.listen(arrived.add);
      w.gateway.addRemoteAsset('r');
      expect(
        () => _wait(async, w.pool.acquire('r')),
        throwsA(_code(PdfErrorCode.assetMissing)),
      );
      w.gateway.arriveBytes('r', _pdf('r'));
      async.flushMicrotasks();
      expect(arrived, ['r']);
      // Within the 2 s memo, yet it opens now.
      final lease = _wait(async, w.pool.acquire('r'));
      expect(lease.document.isDisposed, isFalse);
      expect(w.opens, 1);
    });
  });

  group('requestRemote (P-2)', () {
    test('no fetcher → null', () {
      fakeAsync((async) {
        final w = _World(local: const []);
        expect(w.pool.requestRemote('r'), isNull);
      });
    });

    test('one ensureLocal for concurrent requests; shared progress', () {
      fakeAsync((async) {
        final fetcher = FakeRemoteAssetFetcher();
        final w = _World(local: const [], fetcher: fetcher);
        final first = <core.RemoteAssetProgress>[];
        final second = <core.RemoteAssetProgress>[];
        final s1 = w.pool.requestRemote('r')!.listen(first.add);
        final s2 = w.pool.requestRemote('r')!.listen(second.add);
        async.flushMicrotasks();
        expect(fetcher.ensureLocalCalls, ['r']);
        expect(fetcher.watchListenerCount('r'), 1); // one shared subscription
        fetcher.emit('r', _downloading);
        async.flushMicrotasks();
        expect(first, [_downloading]);
        expect(second, [_downloading]);
        // A late listener gets the latest value first.
        final third = <core.RemoteAssetProgress>[];
        final s3 = w.pool.requestRemote('r')!.listen(third.add);
        async.flushMicrotasks();
        expect(third, [_downloading]);
        expect(fetcher.ensureLocalCalls, ['r']);
        // Unsubscribed when the last listener leaves.
        s1.cancel();
        s2.cancel();
        expect(fetcher.watchListenerCount('r'), 1);
        s3.cancel();
        async.flushMicrotasks();
        expect(fetcher.watchListenerCount('r'), 0);
      });
    });

    test('ensureLocal true → assetArrived; a new request asks again', () {
      fakeAsync((async) {
        final fetcher = FakeRemoteAssetFetcher();
        final w = _World(local: const [], fetcher: fetcher);
        final arrived = <core.AssetId>[];
        w.pool.assetArrived.listen(arrived.add);
        final sub = w.pool.requestRemote('r')!.listen((_) {});
        // The download stores the bytes (SYNC → AssetStore), then ensureLocal is true.
        w.gateway.arriveBytes('r', _pdf('r'));
        fetcher.completeEnsureLocal('r', true);
        async.flushMicrotasks();
        expect(arrived, [
          'r',
          'r',
        ]); // bytesArrived and ensureLocal — acquire dedupes
        final l1 = w.pool.acquire('r');
        final l2 = w.pool.acquire('r');
        _wait(async, l1);
        _wait(async, l2);
        expect(w.opens, 1);
        w.pool.requestRemote('r');
        expect(fetcher.ensureLocalCalls, ['r', 'r']);
        sub.cancel();
      });
    });

    test('ensureLocal false → record dropped, asked again later', () {
      fakeAsync((async) {
        final fetcher = FakeRemoteAssetFetcher();
        final w = _World(local: const [], fetcher: fetcher);
        final arrived = <core.AssetId>[];
        w.pool.assetArrived.listen(arrived.add);
        w.pool.requestRemote('r');
        w.pool.requestRemote('r');
        expect(fetcher.ensureLocalCalls, ['r']);
        fetcher.completeEnsureLocal('r', false);
        async.flushMicrotasks();
        expect(arrived, isEmpty);
        w.pool.requestRemote('r');
        expect(fetcher.ensureLocalCalls, ['r', 'r']);
      });
    });

    test('ensureLocal / watch errors are reported and read as failed', () {
      fakeAsync((async) {
        final reports = <FlutterErrorDetails>[];
        final previous = FlutterError.onError;
        FlutterError.onError = reports.add;
        addTearDown(() => FlutterError.onError = previous);
        final fetcher = FakeRemoteAssetFetcher();
        final w = _World(local: const [], fetcher: fetcher);
        final seen = <core.RemoteAssetProgress>[];
        w.pool.requestRemote('r')!.listen(seen.add);
        fetcher.failEnsureLocal('r', StateError('network'));
        async.flushMicrotasks();
        expect(reports, hasLength(1));
        expect(reports.single.library, 'pdf_io');
        expect(reports.single.exception, isA<StateError>());
        expect(seen.last.state, core.RemoteAssetState.failed);
        w.pool.requestRemote('r');
        expect(fetcher.ensureLocalCalls, ['r', 'r']); // record dropped
      });
    });
  });

  test('dispose closes every document; acquire afterwards throws', () {
    fakeAsync((async) {
      final w = _World();
      final a = _wait(async, w.pool.acquire('a'));
      final b = _wait(async, w.pool.acquire('b'));
      b.release();
      _wait(async, w.pool.dispose());
      expect(a.document.isDisposed, isTrue);
      expect(b.document.isDisposed, isTrue);
      expect(w.pool.openCount, 0);
      expect(() => _wait(async, w.pool.acquire('a')), throwsStateError);
      a.release(); // harmless after dispose
      async.elapse(const Duration(minutes: 2));
      expect(async.pendingTimers, isEmpty);
    });
  });

  test('an open in flight when the pool is disposed is closed', () {
    fakeAsync((async) {
      final w = _World();
      final gate = Completer<void>();
      w.engine.beforeOpen = (_) => gate.future;
      Object? error;
      w.pool
          .acquire('a')
          .then(
            (_) {},
            onError: (Object e) {
              error = e;
            },
          );
      async.flushMicrotasks();
      _wait(async, w.pool.dispose());
      gate.complete();
      async.flushMicrotasks();
      expect(error, isStateError);
      expect(w.engine.openDocumentCount, 0);
    });
  });
}
