// lib/src/image/deferred_asset_store.dart — INTERNAL (m5-7/03-ink 6.11.4).
//
// An AssetStore that resolves the real one (core.assetStoreProvider) on first
// use, so pageBackgroundBuildersProvider, inkPageControllerProvider and
// inkImageCacheProvider can be read in a container without a NoteStore
// override (round-1 EDITOR / PDF tests — CORE's noteStoreProvider default
// throws UnimplementedError). When the store cannot be resolved, every call
// fails with [ImageStoreUnavailable] (images then draw placeholders and INK
// warns 'imageStoreUnavailable').
import 'dart:async';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:note_core/note_core.dart' as core;

/// The real store could not be resolved (no NoteStore in the container).
@internal
final class ImageStoreUnavailable implements Exception {
  const ImageStoreUnavailable(this.cause);
  final Object cause;

  @override
  String toString() => 'ImageStoreUnavailable($cause)';
}

@internal
final class DeferredAssetStore implements core.AssetStore {
  DeferredAssetStore(this._resolve);

  final core.AssetStore Function() _resolve;
  core.AssetStore? _store;

  /// The real store, or null when it cannot be resolved (never throws).
  core.AssetStore? tryResolve() {
    final cached = _store;
    if (cached != null) return cached;
    try {
      return _store = _resolve();
    } on Object {
      return null;
    }
  }

  core.AssetStore _require() {
    final cached = _store;
    if (cached != null) return cached;
    try {
      return _store = _resolve();
    } on Object catch (e) {
      throw ImageStoreUnavailable(e);
    }
  }

  Future<T> _call<T>(Future<T> Function(core.AssetStore s) f) {
    final core.AssetStore s;
    try {
      s = _require();
    } on ImageStoreUnavailable catch (e, st) {
      return Future<T>.error(e, st);
    }
    return f(s);
  }

  @override
  Future<core.Asset> put(
    Uint8List bytes, {
    required core.AssetType type,
    required String mimeType,
    String? fileName,
  }) => _call(
    (s) => s.put(bytes, type: type, mimeType: mimeType, fileName: fileName),
  );

  @override
  Future<core.Asset?> getAsset(core.AssetId id) => _call((s) => s.getAsset(id));

  @override
  Future<Uint8List?> readBytes(core.AssetId id) =>
      _call((s) => s.readBytes(id));

  @override
  Future<bool> hasBytes(core.AssetId id) => _call((s) => s.hasBytes(id));

  @override
  Future<void> putDownloadedBytes(core.AssetId id, Uint8List bytes) =>
      _call((s) => s.putDownloadedBytes(id, bytes));

  @override
  Future<List<core.Asset>> listAssets({bool? hasLocalBytes, bool? uploaded}) =>
      _call(
        (s) => s.listAssets(hasLocalBytes: hasLocalBytes, uploaded: uploaded),
      );

  @override
  Future<void> markUploaded(core.AssetId id, String storagePath) =>
      _call((s) => s.markUploaded(id, storagePath));

  @override
  Future<core.AssetStorageUsage> usage() => _call((s) => s.usage());

  /// The real store's stream once it resolves; an empty stream otherwise.
  @override
  Stream<core.AssetId> get bytesArrived {
    final s = tryResolve();
    return s == null ? const Stream<core.AssetId>.empty() : s.bytesArrived;
  }
}
