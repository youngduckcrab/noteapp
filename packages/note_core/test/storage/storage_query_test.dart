// CORE T16 — StorageInfo from navigator.storage (6.12 ①②), with a test StorageQuery and
// fake time: persist() is awaited at most 1 s at open, a late answer is read by
// refreshStorageInfo, failing or hanging calls leave their fields null / unchanged.
import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:note_core/note_core.dart';
import 'package:note_core/src/storage/web_storage/persistence.dart';
import 'package:note_core/src/storage/web_storage/storage_query.dart';
import 'package:test/test.dart';

/// A StorageQuery whose calls answer when the test says so.
final class _Query implements StorageQuery {
  bool persistedValue = false;
  Completer<bool>? persistAnswer; // null = answers true at once
  Error? persistedError;
  StorageEstimateBytes? estimateValue = (usage: 1200, quota: 50000);
  bool estimateHangs = false;
  final calls = <String>[];

  @override
  Future<bool> persisted() async {
    calls.add('persisted');
    if (persistedError case final e?) throw e;
    return persistedValue;
  }

  @override
  Future<bool> persist() {
    calls.add('persist');
    return persistAnswer?.future ?? Future.value(true);
  }

  @override
  Future<StorageEstimateBytes?> estimate() {
    calls.add('estimate');
    if (estimateHangs) return Completer<StorageEstimateBytes?>().future;
    return Future.value(estimateValue);
  }
}

const _base = StorageInfo(
  backend: StorageBackend.webSharedIndexedDb,
  missingBrowserFeatures: ['dedicatedWorkersInSharedWorkers'],
);

/// Advances fake time by [step] and returns the value of [future], which must be
/// complete by then.
T _run<T>(FakeAsync async, Future<T> future, {Duration step = Duration.zero}) {
  T? value;
  var done = false;
  future.then((v) {
    value = v;
    done = true;
  });
  async.elapse(step);
  async.flushMicrotasks();
  expect(done, isTrue, reason: 'not complete after $step');
  return value as T;
}

void main() {
  test(
    'off the web there is no StorageQuery: the info stays as given',
    () async {
      expect(platformStorageQuery(), isNull);
      expect(
        await storageInfoAtOpen(_base, null, requestPersist: true),
        same(_base),
      );
      expect(await refreshedStorageInfo(_base, null), same(_base));
    },
  );

  test('persisted() true: persist() is not called', () {
    fakeAsync((async) {
      final q = _Query()..persistedValue = true;
      final info = _run(
        async,
        storageInfoAtOpen(_base, q, requestPersist: true),
      );
      expect(q.calls, ['persisted', 'estimate']);
      expect(info.persistGranted, isTrue);
      expect(info.usageBytes, 1200);
      expect(info.quotaBytes, 50000);
      expect(info.backend, _base.backend);
      expect(info.missingBrowserFeatures, _base.missingBrowserFeatures);
    });
  });

  test('requestPersistentStorage false: persist() is not called', () {
    fakeAsync((async) {
      final q = _Query();
      final info = _run(
        async,
        storageInfoAtOpen(_base, q, requestPersist: false),
      );
      expect(q.calls, ['persisted', 'estimate']);
      expect(info.persistGranted, isFalse);
    });
  });

  test('persist() answering within 1 s: its result', () {
    fakeAsync((async) {
      final q = _Query()..persistAnswer = Completer<bool>();
      bool? granted;
      storageInfoAtOpen(
        _base,
        q,
        requestPersist: true,
      ).then((i) => granted = i.persistGranted);
      async.elapse(const Duration(milliseconds: 900));
      expect(granted, isNull, reason: 'still waiting for persist()');
      q.persistAnswer!.complete(true);
      async.flushMicrotasks();
      expect(granted, isTrue);
      expect(q.calls, ['persisted', 'persist', 'estimate']);
      expect(
        async.pendingTimers,
        isEmpty,
        reason: 'the 1 s timer is cancelled',
      );
    });
  });

  test('persist() not answering: cut off at 1 s with the persisted() value; '
      'refreshStorageInfo reads the later answer', () {
    fakeAsync((async) {
      final q = _Query()..persistAnswer = Completer<bool>();
      StorageInfo? info;
      storageInfoAtOpen(_base, q, requestPersist: true).then((i) => info = i);
      async.elapse(const Duration(milliseconds: 999));
      expect(info, isNull);
      async.elapse(const Duration(milliseconds: 1));
      expect(info, isNotNull);
      expect(info!.persistGranted, isFalse);
      expect(info!.usageBytes, 1200);

      // persist() goes on in the background and is granted later.
      q
        ..persistedValue = true
        ..estimateValue = (usage: 9000, quota: 50000);
      q.persistAnswer!.complete(true);
      final refreshed = _run(async, refreshedStorageInfo(info!, q));
      expect(refreshed.persistGranted, isTrue);
      expect(refreshed.usageBytes, 9000);
      expect(refreshed.backend, _base.backend);
      expect(refreshed.missingBrowserFeatures, _base.missingBrowserFeatures);
    });
  });

  test('failing persisted() and missing estimate(): null fields, no error', () {
    fakeAsync((async) {
      final q = _Query()
        ..persistedError = StateError('no storage')
        ..persistAnswer = Completer<bool>()
        ..estimateValue = null;
      final info = _run(
        async,
        storageInfoAtOpen(_base, q, requestPersist: true),
        step: const Duration(seconds: 1),
      );
      expect(info.persistGranted, isNull);
      expect(info.usageBytes, isNull);
      expect(info.quotaBytes, isNull);
    });
  });

  test('a hanging estimate() is cut off too (open never waits more than '
      'the limit per call)', () {
    fakeAsync((async) {
      final q = _Query()
        ..persistedValue = true
        ..estimateHangs = true;
      final info = _run(
        async,
        storageInfoAtOpen(_base, q, requestPersist: true),
        step: persistWaitLimit,
      );
      expect(info.persistGranted, isTrue);
      expect(info.usageBytes, isNull);
    });
  });

  test('refresh keeps the previous values of calls that fail', () {
    fakeAsync((async) {
      const before = StorageInfo(
        backend: StorageBackend.webSharedIndexedDb,
        persistGranted: true,
        usageBytes: 10,
        quotaBytes: 20,
      );
      final q = _Query()
        ..persistedError = StateError('gone')
        ..estimateValue = null;
      final info = _run(async, refreshedStorageInfo(before, q));
      expect(info, before);
    });
  });
}
