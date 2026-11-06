// lib/src/playback/audio_source_native.dart — the native (and VM) player source (m5-7/06-pdf
// 6.11.3): `<getApplicationCacheDirectory()>/media_io/play/<assetId>.<ext>` is written once when
// it is missing (the asset id is the content hash, so an existing file is the same bytes) →
// setFilePath. The first prepare after start-up trims the cache to playCacheMaxBytes, least
// recently used first; a reused file is touched. Tests point the directory at
// MediaTestHooks.directory (installFakeMediaPlatforms) or pass [cacheRoot]. Internal.
import 'dart:io';
import 'dart:typed_data';

import 'package:note_core/note_core.dart' as core;
import 'package:path_provider/path_provider.dart';

import '../testing/test_hooks.dart';
import '../tuning.dart';
import 'audio_source.dart';
import 'player_port.dart';

AudioSourceProvider createPlatformAudioSources() => NativeAudioSources();

Object? createHandoffBlob(Uint8List bytes, String mimeType) => null;

final class NativeAudioSources implements AudioSourceProvider {
  NativeAudioSources({
    Future<String> Function()? cacheRoot,
    this.maxBytes = MediaTuning.playCacheMaxBytes,
    DateTime Function()? now,
  }) : _cacheRoot = cacheRoot ?? _defaultRoot,
       _now = now ?? DateTime.now;

  final Future<String> Function() _cacheRoot;
  final DateTime Function() _now;

  /// The cache size the first prepare trims to (MediaTuning.playCacheMaxBytes).
  final int maxBytes;

  bool _trimmed = false;

  static Future<String> _defaultRoot() async =>
      MediaTestHooks.directory ?? (await getApplicationCacheDirectory()).path;

  /// The play cache directory.
  Future<Directory> directory() async =>
      Directory('${await _cacheRoot()}/${MediaTuning.playCacheDir}');

  @override
  Future<PlayerSource?> prepare(
    core.AssetId assetId, {
    required String? mimeType,
    required String? fileName,
    required Future<Uint8List?> Function() bytes,
    Object? handoff,
  }) async {
    final dir = await directory();
    if (!_trimmed) {
      _trimmed = true;
      await trim(dir);
    }
    final ext = audioFileExtension(mimeType: mimeType, fileName: fileName);
    final file = File('${dir.path}/${_safeName(assetId)}.$ext');
    if (file.existsSync()) {
      try {
        file.setLastModifiedSync(_now());
      } on FileSystemException {
        // Only the LRU order suffers.
      }
      return PlayerFileSource(file.path);
    }
    final data = await bytes();
    if (data == null) return null;
    dir.createSync(recursive: true);
    // Written next to the target and renamed, so a half-written file is never reused.
    final part = File('${file.path}.part');
    await part.writeAsBytes(data, flush: true);
    await part.rename(file.path);
    return PlayerFileSource(file.path);
  }

  /// Deletes the least recently used files until the cache is at most [maxBytes].
  Future<void> trim(Directory dir) async {
    if (!dir.existsSync()) return;
    final files = <(File, int, DateTime)>[];
    for (final entity in dir.listSync()) {
      if (entity is! File) continue;
      try {
        final stat = entity.statSync();
        files.add((entity, stat.size, stat.modified));
      } on FileSystemException {
        continue;
      }
    }
    var total = files.fold<int>(0, (sum, f) => sum + f.$2);
    if (total <= maxBytes) return;
    files.sort((a, b) => a.$3.compareTo(b.$3));
    for (final (file, size, _) in files) {
      if (total <= maxBytes) break;
      try {
        file.deleteSync();
        total -= size;
      } on FileSystemException {
        continue;
      }
    }
  }

  @override
  void release() {}

  @override
  bool get usesRecordingDuration => false;
}

String _safeName(core.AssetId id) =>
    id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
