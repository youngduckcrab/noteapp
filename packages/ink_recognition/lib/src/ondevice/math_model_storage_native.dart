// lib/src/ondevice/math_model_storage_native.dart — (internal) the
// on-device math model's files on Android / iOS (dart:io, path_provider —
// native_only_imports): <application support>/models/<version>/ on
// Android (the app sets allowBackup="false"), <Library/Caches>/models/
// <version>/ on iOS — Application Support is in every iCloud backup there,
// and a downloadable 32 MB model must not be (if iOS purges the caches, the
// install reads as not installed and the user downloads it again).
//
// A file is written as '<name>.part' and renamed to '<name>' on commit (the
// same directory → atomic); 'installed.json' (version + every file's size)
// is written the same way, last. installed() trusts the marker and the
// sizes — the SHA-256 sums were checked while downloading (the manager).
// Every file system error is a MathModelStorageException.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:path_provider/path_provider.dart' as path_provider;

import 'math_model_manager.dart';
import 'math_model_manifest.dart';

const String _marker = 'installed.json';

final class FileMathModelStorage implements MathModelStorage {
  /// [root] = the directory that holds one directory per model version
  /// (default: `<application support>/models`; iOS: `<caches>/models`).
  FileMathModelStorage({Future<String> Function()? root})
    : _root = root ?? _defaultRoot;

  final Future<String> Function() _root;

  static Future<String> _defaultRoot() async {
    final base = defaultTargetPlatform == TargetPlatform.iOS
        ? await path_provider.getApplicationCacheDirectory()
        : await path_provider.getApplicationSupportDirectory();
    return '${base.path}/models';
  }

  Future<Directory> _dir(MathModelManifest manifest) async =>
      Directory('${await _root()}/${manifest.version}');

  @override
  Future<MathModelInstall?> installed(MathModelManifest manifest) =>
      _guard(() async {
        final dir = await _dir(manifest);
        final marker = File('${dir.path}/$_marker');
        if (!marker.existsSync()) return null;
        final Object? json;
        try {
          json = jsonDecode(await marker.readAsString());
        } on FormatException {
          return null;
        }
        if (json is! Map || json['version'] != manifest.version) return null;
        final sizes = json['files'];
        if (sizes is! Map) return null;
        final paths = <String, String>{};
        for (final file in manifest.files) {
          if (sizes[file.name] != file.bytes) return null;
          final f = File('${dir.path}/${file.name}');
          if (!f.existsSync() || f.lengthSync() != file.bytes) return null;
          paths[file.name] = f.path;
        }
        return MathModelInstall(Map.unmodifiable(paths));
      });

  @override
  Future<MathModelSink> create(
    MathModelManifest manifest,
    MathModelFile file,
  ) => _guard(() async {
    final dir = await _dir(manifest);
    await dir.create(recursive: true);
    // a stale marker would claim a set that is being replaced
    final marker = File('${dir.path}/$_marker');
    if (marker.existsSync()) marker.deleteSync();
    final part = File('${dir.path}/${file.name}.part');
    if (part.existsSync()) part.deleteSync();
    final raf = await part.open(mode: FileMode.writeOnly);
    return _FileSink(raf, part, '${dir.path}/${file.name}');
  });

  @override
  Future<MathModelInstall> markInstalled(MathModelManifest manifest) =>
      _guard(() async {
        final dir = await _dir(manifest);
        final part = File('${dir.path}/$_marker.part');
        await part.writeAsString(
          jsonEncode({
            'version': manifest.version,
            'files': {for (final f in manifest.files) f.name: f.bytes},
          }),
          flush: true,
        );
        await part.rename('${dir.path}/$_marker');
        return MathModelInstall(
          Map.unmodifiable({
            for (final f in manifest.files) f.name: '${dir.path}/${f.name}',
          }),
        );
      });

  @override
  Future<void> delete(MathModelManifest manifest) => _guard(() async {
    final dir = await _dir(manifest);
    if (dir.existsSync()) await dir.delete(recursive: true);
  });
}

Future<T> _guard<T>(Future<T> Function() body) async {
  try {
    return await body();
  } on FileSystemException catch (e) {
    throw MathModelStorageException('${e.message} ${e.path ?? ''}'.trim());
  }
}

final class _FileSink implements MathModelSink {
  _FileSink(this._raf, this._part, this._target);

  final RandomAccessFile _raf;
  final File _part;
  final String _target;
  bool _closed = false;

  @override
  Future<void> add(List<int> chunk) =>
      _guard(() => _raf.writeFrom(chunk).then((_) {}));

  @override
  Future<void> commit() => _guard(() async {
    _closed = true;
    await _raf.flush();
    await _raf.close();
    await _part.rename(_target);
  });

  @override
  Future<void> abort() async {
    try {
      if (!_closed) {
        _closed = true;
        await _raf.close();
      }
      if (_part.existsSync()) _part.deleteSync();
    } on Object {
      // best effort
    }
  }
}
