// lib/src/storage/web_storage/storage_query.dart (internal) — CORE 6.12 ①②:
// persisted() / persist() / estimate() → StorageInfo. Pure Dart; the browser
// binding is persistence_browser.dart, tests pass their own StorageQuery.
import 'dart:async';

import '../../repo/status.dart';

/// navigator.storage as CORE uses it (6.12). Only CORE calls these (7.2.12).
abstract interface class StorageQuery {
  /// navigator.storage.persisted().
  Future<bool> persisted();

  /// navigator.storage.persist(); may take long (the browser decides).
  Future<bool> persist();

  /// navigator.storage.estimate(); null when the browser has none (Safari < 17).
  Future<StorageEstimateBytes?> estimate();
}

/// usage / quota of StorageManager.estimate().
typedef StorageEstimateBytes = ({int usage, int quota});

/// How long open waits for persist() (6.12 ①), and for persisted() / estimate().
const Duration persistWaitLimit = Duration(seconds: 1);

/// The StorageInfo of a store being opened (6.12 ①): persisted(); when false and
/// [requestPersist], persist() is awaited at most [wait] — its result if it
/// answers in time, else the persisted() value, while persist() goes on in the
/// background (refreshStorageInfo reads the later value). estimate() once.
/// Never throws: a failing or hanging call leaves its field null.
Future<StorageInfo> storageInfoAtOpen(
  StorageInfo base,
  StorageQuery? query, {
  required bool requestPersist,
  Duration wait = persistWaitLimit,
}) async {
  if (query == null) return base;
  var granted = await _within(query.persisted, wait);
  if (granted != true && requestPersist) {
    granted = await _within(query.persist, wait) ?? granted;
  }
  final estimate = await _within(query.estimate, wait);
  return _with(base, granted, estimate);
}

/// refreshStorageInfo (6.12 ②): persisted() and estimate() again. A call that
/// fails or does not answer within [wait] keeps the previous value.
Future<StorageInfo> refreshedStorageInfo(
  StorageInfo current,
  StorageQuery? query, {
  Duration wait = persistWaitLimit,
}) async {
  if (query == null) return current;
  final granted = await _within(query.persisted, wait);
  final estimate = await _within(query.estimate, wait);
  return StorageInfo(
    backend: current.backend,
    missingBrowserFeatures: current.missingBrowserFeatures,
    persistGranted: granted ?? current.persistGranted,
    usageBytes: estimate?.usage ?? current.usageBytes,
    quotaBytes: estimate?.quota ?? current.quotaBytes,
  );
}

StorageInfo _with(
  StorageInfo base,
  bool? granted,
  StorageEstimateBytes? estimate,
) => StorageInfo(
  backend: base.backend,
  missingBrowserFeatures: base.missingBrowserFeatures,
  persistGranted: granted,
  usageBytes: estimate?.usage,
  quotaBytes: estimate?.quota,
);

/// The value of [call] if it answers within [wait]; null if it throws or takes
/// longer (the call itself goes on; its late result or error is dropped).
Future<T?> _within<T extends Object>(
  Future<T?> Function() call,
  Duration wait,
) {
  final result = Completer<T?>();
  final timer = Timer(wait, () {
    if (!result.isCompleted) result.complete(null);
  });
  Future<T?>.sync(call).then(
    (v) {
      timer.cancel();
      if (!result.isCompleted) result.complete(v);
    },
    onError: (Object _) {
      timer.cancel();
      if (!result.isCompleted) result.complete(null);
    },
  );
  return result.future;
}
