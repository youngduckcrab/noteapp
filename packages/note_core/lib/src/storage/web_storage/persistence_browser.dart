// lib/src/storage/web_storage/persistence_browser.dart (internal) — CORE 6.12:
// navigator.storage (persisted / persist / estimate). Missing pieces (no secure
// context, Safari < 17 without estimate()) are detected, not called.
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import 'storage_query.dart';

StorageQuery? platformStorageQuery() {
  final navigator = web.window.navigator;
  if (!(navigator as JSObject).has('storage')) return null;
  return _BrowserStorageQuery(navigator.storage);
}

final class _BrowserStorageQuery implements StorageQuery {
  _BrowserStorageQuery(this._manager);

  final web.StorageManager _manager;

  bool _has(String method) => (_manager as JSObject).has(method);

  @override
  Future<bool> persisted() async {
    if (!_has('persisted')) throw UnsupportedError('persisted()');
    return (await _manager.persisted().toDart).toDart;
  }

  @override
  Future<bool> persist() async {
    if (!_has('persist')) throw UnsupportedError('persist()');
    return (await _manager.persist().toDart).toDart;
  }

  @override
  Future<StorageEstimateBytes?> estimate() async {
    if (!_has('estimate')) return null;
    final JSObject e = await _manager.estimate().toDart;
    final usage = _bytes(e['usage']);
    final quota = _bytes(e['quota']);
    if (usage == null || quota == null) return null;
    return (usage: usage, quota: quota);
  }

  /// A JS number of bytes (below 2^53) as an int; null if it is not a number.
  static int? _bytes(JSAny? value) =>
      value.isA<JSNumber>() ? (value! as JSNumber).toDartDouble.round() : null;
}
