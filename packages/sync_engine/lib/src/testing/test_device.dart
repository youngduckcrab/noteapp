import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:note_core/note_core.dart';

import '../engine/connectivity.dart';
import '../engine/sync_engine.dart';
import '../model/sync_doc.dart';
import 'fake_auth_backend.dart';
import 'fake_local_store.dart';
import 'fake_network.dart';

/// A simulated device: FakeLocalStore + SyncEngine + FakeAuthBackend + link.
/// Edit helpers build CORE JSON (CORE 6.3 key table) and call FakeLocalStore.localWrite
/// with the changedFields CORE would record (CORE 6.5 table).
final class TestDevice {
  /// Via SyncTestHarness.device.
  @internal
  TestDevice.internal();

  String get name => throw UnimplementedError('SYNC T6');
  FakeLocalStore get store => throw UnimplementedError('SYNC T6');
  SyncEngine get engine => throw UnimplementedError('SYNC T6');
  FakeAuthBackend get auth => throw UnimplementedError('SYNC T6');
  FakeNetworkLink get link => throw UnimplementedError('SYNC T6');
  ManualConnectivitySignal get connectivity =>
      throw UnimplementedError('SYNC T6');

  /// Wall-clock offset of this device (S14, S14b). Changing it moves the device clock
  /// (HLC, timestamps) but not the engine's monotonic stopwatch (harness base clock).
  Duration get clockOffset => throw UnimplementedError('SYNC T6');
  set clockOffset(Duration offset) => throw UnimplementedError('SYNC T6');

  /// Link + connectivity.
  void goOffline() => throw UnimplementedError('SYNC T6');
  void goOnline() => throw UnimplementedError('SYNC T6');

  // folders & notes
  String createFolder(String name, {String? parentId}) =>
      throw UnimplementedError('SYNC T6');
  String createNote(String title, {String? folderId, int pages = 1}) =>
      throw UnimplementedError('SYNC T6');
  void renameNote(String noteId, String title) =>
      throw UnimplementedError('SYNC T6');
  void moveNote(String noteId, String? folderId) =>
      throw UnimplementedError('SYNC T6');

  /// Throws StateError on a local cycle (like CORE FolderCycleException).
  void moveFolder(String folderId, String? parentId) =>
      throw UnimplementedError('SYNC T6');
  void trashNote(String noteId) => throw UnimplementedError('SYNC T6');
  void restoreNote(String noteId) => throw UnimplementedError('SYNC T6');
  void purgeNote(String noteId) => throw UnimplementedError('SYNC T6');

  // pages & strokes
  /// Active, ordered by (sortKey, id).
  List<String> pageIdsOf(String noteId) => throw UnimplementedError('SYNC T6');
  String insertPage(String noteId, {String? afterPageId}) =>
      throw UnimplementedError('SYNC T6');
  void deletePage(String pageId) => throw UnimplementedError('SYNC T6');

  /// Points from synthetic_points.dart (StrokePointsBuilder + StrokePointsCodec, seeded).
  String addStroke(String pageId, {int seed = 0, int points = 100}) =>
      throw UnimplementedError('SYNC T6');
  void eraseStroke(String strokeId) => throw UnimplementedError('SYNC T6');
  void recolorStroke(String strokeId, int colorArgb) =>
      throw UnimplementedError('SYNC T6');
  void moveStroke(String strokeId, {double dx = 10, double dy = 0}) =>
      throw UnimplementedError('SYNC T6');
  List<SyncDoc> activeStrokesOf(String pageId) =>
      throw UnimplementedError('SYNC T6');

  // presets, settings, assets
  /// Rows of CORE ensureDefaults: `preset-default-<wireName>`, seed HLC Hlc(1, 0, '0'×16),
  /// outbox '*' (CD-07, CORE 6.2.2).
  void seedDefaultPresets() => throw UnimplementedError('SYNC T6');
  void renamePreset(String presetId, String name) =>
      throw UnimplementedError('SYNC T6');

  /// Synced scope only (contract 7.4.6).
  void setSetting(String key, Object? value) =>
      throw UnimplementedError('SYNC T6');

  /// store.assets.put(...) — CORE AssetStore semantics (sha-256 id, bytesArrived).
  Future<AssetId> putAsset(
    Uint8List bytes, {
    AssetType type = AssetType.pdf,
    String mimeType = 'application/pdf',
  }) => throw UnimplementedError('SYNC T6');

  SyncDoc? doc(EntityKind kind, String id) =>
      throw UnimplementedError('SYNC T6');
}
