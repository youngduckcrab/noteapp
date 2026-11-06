// A controllable core.AssetStore for the image cache tests (T35): bytes per id,
// read counts, a failing read, a bytesArrived stream the test drives. Members the
// image cache does not use throw UnimplementedError.
import 'dart:async';
import 'dart:typed_data';

import 'package:note_core/note_core.dart' as core;

final class MemoryAssetStore implements core.AssetStore {
  final Map<String, Uint8List> bytes = {};

  /// Ids whose readBytes fails with a StateError.
  final Set<String> failingReads = {};

  /// readBytes calls per id.
  final Map<String, int> reads = {};
  final StreamController<core.AssetId> _arrived = StreamController.broadcast();

  int readsOf(String id) => reads[id] ?? 0;

  /// The bytes of [id] are now on the device (bytesArrived emits it).
  void arrive(String id, Uint8List data) {
    bytes[id] = data;
    _arrived.add(id);
  }

  Future<void> close() => _arrived.close();

  @override
  Future<Uint8List?> readBytes(core.AssetId id) async {
    reads[id] = readsOf(id) + 1;
    if (failingReads.contains(id)) throw StateError('read failed: $id');
    return bytes[id];
  }

  @override
  Future<bool> hasBytes(core.AssetId id) async => bytes.containsKey(id);

  @override
  Stream<core.AssetId> get bytesArrived => _arrived.stream;

  @override
  Future<core.Asset> put(
    Uint8List bytes, {
    required core.AssetType type,
    required String mimeType,
    String? fileName,
  }) => throw UnimplementedError();

  @override
  Future<core.Asset?> getAsset(core.AssetId id) => throw UnimplementedError();

  @override
  Future<void> putDownloadedBytes(core.AssetId id, Uint8List bytes) =>
      throw UnimplementedError();

  @override
  Future<List<core.Asset>> listAssets({bool? hasLocalBytes, bool? uploaded}) =>
      throw UnimplementedError();

  @override
  Future<void> markUploaded(core.AssetId id, String storagePath) =>
      throw UnimplementedError();

  @override
  Future<core.AssetStorageUsage> usage() => throw UnimplementedError();
}
