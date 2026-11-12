// lib/src/ondevice/math_model_manager.dart — (internal) the on-device math
// model's files: on-demand download, verification, install state, delete.
//
// Pure Dart over two ports: [MathModelStorage] (files —
// math_model_storage_native.dart: the app support directory, dart:io) and
// an http.Client (package:http, the same as the callable engine). Nothing
// is downloaded until the user turns on '기기에서 수식 인식' (settings ›
// 인식) — [download] is called from there only.
//
// - [restore] (once, at start): a complete install of the manifest's
//   version → [MathModelReady]; otherwise (or on any error) not installed.
// - [download]: one at a time (a second call joins the running one); each
//   file is streamed to a temporary file while its SHA-256 is computed, and
//   only a file of the manifest's size and hash is renamed into place
//   (atomic); the install marker is written last, so a half-finished set is
//   never "ready". Progress = bytes received / manifest total.
//   Failures → [MathModelFailed] (offline: no connection, a stall of
//   [stallTimeout]; server: a status other than 200; checksum: size or hash
//   differ; storage: the files could not be written); the temporary file and
//   every file already committed are removed. [cancel] aborts the request →
//   back to not installed (also without leftover files).
// - [delete]: cancels a running download, removes the files → not installed.
import 'dart:async';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier;
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';

import 'math_model_manifest.dart';

/// Where an installed model's files are (absolute paths by file name).
@immutable
final class MathModelInstall {
  const MathModelInstall(this.paths);
  final Map<String, String> paths;

  String path(String name) => paths[name]!;
}

sealed class MathModelState {
  const MathModelState();
}

/// Not on this device (the default; also after delete or cancel).
final class MathModelNotInstalled extends MathModelState {
  const MathModelNotInstalled();

  @override
  bool operator ==(Object other) => other is MathModelNotInstalled;
  @override
  int get hashCode => 0;
  @override
  String toString() => 'notInstalled';
}

final class MathModelDownloading extends MathModelState {
  const MathModelDownloading(this.receivedBytes, this.totalBytes);
  final int receivedBytes, totalBytes;

  /// 0…1
  double get progress =>
      totalBytes <= 0 ? 0 : (receivedBytes / totalBytes).clamp(0.0, 1.0);

  @override
  bool operator ==(Object other) =>
      other is MathModelDownloading &&
      other.receivedBytes == receivedBytes &&
      other.totalBytes == totalBytes;
  @override
  int get hashCode => Object.hash(receivedBytes, totalBytes);
  @override
  String toString() => 'downloading($receivedBytes/$totalBytes)';
}

final class MathModelReady extends MathModelState {
  const MathModelReady(this.install);
  final MathModelInstall install;

  @override
  String toString() => 'ready';
}

enum MathModelFailure { offline, server, checksum, storage, unknown }

final class MathModelFailed extends MathModelState {
  const MathModelFailed(this.reason);
  final MathModelFailure reason;

  @override
  bool operator ==(Object other) =>
      other is MathModelFailed && other.reason == reason;
  @override
  int get hashCode => reason.hashCode;
  @override
  String toString() => 'failed(${reason.name})';
}

/// The platform side has no on-device model (the web, desktops).
final class MathModelUnsupported extends MathModelState {
  const MathModelUnsupported();

  @override
  bool operator ==(Object other) => other is MathModelUnsupported;
  @override
  int get hashCode => 1;
  @override
  String toString() => 'unsupported';
}

/// A file could not be read or written (storage implementations wrap their
/// file system errors in it).
final class MathModelStorageException implements Exception {
  MathModelStorageException(this.message);
  final String message;

  @override
  String toString() => 'MathModelStorageException($message)';
}

/// One file being written: a temporary file until [commit].
abstract interface class MathModelSink {
  Future<void> add(List<int> chunk);

  /// Closes and renames the temporary file to its name (atomic).
  Future<void> commit();

  /// Closes and removes the temporary file (never throws).
  Future<void> abort();
}

abstract interface class MathModelStorage {
  /// The install of [manifest] when the marker and every file (by size) are
  /// there; else null.
  Future<MathModelInstall?> installed(MathModelManifest manifest);

  Future<MathModelSink> create(MathModelManifest manifest, MathModelFile file);

  /// Writes the install marker (after every file was committed).
  Future<MathModelInstall> markInstalled(MathModelManifest manifest);

  /// Removes the version's files (and temporary files).
  Future<void> delete(MathModelManifest manifest);
}

final class MathModelManager {
  MathModelManager({
    required this._storage,
    this._createClient = http.Client.new,
    this.manifest = kMathModelManifest,
    this.stallTimeout = const Duration(seconds: 30),
  });

  final MathModelStorage _storage;
  final http.Client Function() _createClient;
  final MathModelManifest manifest;
  final Duration stallTimeout;

  final ValueNotifier<MathModelState> _state = ValueNotifier(
    const MathModelNotInstalled(),
  );
  Future<void>? _restore;
  Future<void>? _running;
  Completer<void>? _abort;
  bool _disposed = false;

  ValueListenable<MathModelState> get state => _state;

  void _set(MathModelState s) {
    if (!_disposed) _state.value = s;
  }

  /// Reads the install state once (later calls return the same future).
  Future<void> restore() => _restore ??= () async {
    try {
      final install = await _storage.installed(manifest);
      if (install != null && _state.value is MathModelNotInstalled) {
        _set(MathModelReady(install));
      }
    } on Object {
      // unreadable → not installed (the user can download again)
    }
  }();

  /// Downloads and installs the files (joins a running download; ready →
  /// done at once). Never throws: the outcome is [state].
  Future<void> download() {
    if (_disposed) return Future.value();
    final running = _running;
    if (running != null) return running;
    if (_state.value is MathModelReady) return Future.value();
    final run = _download().whenComplete(() => _running = null);
    _running = run;
    return run;
  }

  /// Stops a running download (→ not installed).
  void cancel() {
    final abort = _abort;
    if (abort != null && !abort.isCompleted) abort.complete();
  }

  /// Removes the files (after stopping a running download).
  Future<void> delete() async {
    cancel();
    final running = _running;
    if (running != null) await running;
    try {
      await _storage.delete(manifest);
      _set(const MathModelNotInstalled());
    } on Object {
      _set(const MathModelFailed(MathModelFailure.storage));
    }
  }

  void dispose() {
    cancel();
    _disposed = true;
    _state.dispose();
  }

  Future<void> _download() async {
    await restore();
    if (_state.value is MathModelReady) return;
    final abort = _abort = Completer<void>();
    final client = _createClient();
    final total = manifest.totalBytes;
    var done = 0;
    _set(MathModelDownloading(0, total));
    MathModelSink? sink;
    try {
      for (final file in manifest.files) {
        if (abort.isCompleted) throw const _Cancelled();
        sink = await _storage.create(manifest, file);
        await _fetch(client, file, sink, abort, (received) {
          _set(MathModelDownloading(done + received, total));
        });
        await sink.commit();
        sink = null;
        done += file.bytes;
        _set(MathModelDownloading(done, total));
      }
      if (abort.isCompleted) throw const _Cancelled();
      final install = await _storage.markInstalled(manifest);
      _set(MathModelReady(install));
    } on _Cancelled {
      await sink?.abort();
      await _discard();
      _set(const MathModelNotInstalled());
    } on http.RequestAbortedException {
      await sink?.abort();
      await _discard();
      _set(const MathModelNotInstalled());
    } on Object catch (e) {
      await sink?.abort();
      await _discard();
      if (abort.isCompleted) {
        _set(const MathModelNotInstalled());
      } else {
        _set(MathModelFailed(_failureOf(e)));
      }
    } finally {
      client.close();
      if (identical(_abort, abort)) _abort = null;
    }
  }

  /// Removes the files committed before a cancel or failure (an incomplete
  /// set is never installed, and the not-installed tile offers no delete —
  /// so nothing may stay behind). Never throws.
  Future<void> _discard() async {
    try {
      await _storage.delete(manifest);
    } on Object {
      // best effort: the next download overwrites, delete retries
    }
  }

  Future<void> _fetch(
    http.Client client,
    MathModelFile file,
    MathModelSink sink,
    Completer<void> abort,
    void Function(int received) progress,
  ) async {
    final request = http.AbortableRequest(
      'GET',
      manifest.urlOf(file),
      abortTrigger: abort.future,
    );
    final response = await Future.any<http.StreamedResponse?>([
      client.send(request),
      abort.future.then((_) => null),
    ]).timeout(stallTimeout);
    if (response == null) throw const _Cancelled();
    if (response.statusCode != 200) {
      throw _Failure(MathModelFailure.server);
    }
    final digest = _DigestSink();
    final hash = crypto.sha256.startChunkedConversion(digest);
    var received = 0;
    var reported = 0;
    // The body: chunks hashed and written in order (the subscription waits
    // for each write); no chunk for [stallTimeout] → offline; a cancel ends
    // it at once.
    final done = Completer<void>();
    Timer? stall;
    late final StreamSubscription<List<int>> subscription;
    void fail(Object error) {
      stall?.cancel();
      if (done.isCompleted) return;
      done.completeError(error);
      unawaited(subscription.cancel().then<void>((_) {}, onError: (_) {}));
    }

    void arm() {
      stall?.cancel();
      stall = Timer(stallTimeout, () => fail(TimeoutException('stalled')));
    }

    subscription = response.stream.listen(
      (chunk) {
        if (done.isCompleted) return;
        received += chunk.length;
        if (received > file.bytes) {
          fail(_Failure(MathModelFailure.checksum));
          return;
        }
        hash.add(chunk);
        subscription.pause();
        sink.add(chunk).then<void>((_) {
          if (done.isCompleted) return;
          if (received - reported >= 256 * 1024 || received == file.bytes) {
            reported = received;
            progress(received);
          }
          arm();
          subscription.resume();
        }, onError: fail);
      },
      onError: fail,
      onDone: () {
        stall?.cancel();
        if (!done.isCompleted) done.complete();
      },
      cancelOnError: true,
    );
    arm();
    unawaited(abort.future.then((_) => fail(const _Cancelled())));
    await done.future;
    hash.close();
    if (abort.isCompleted) throw const _Cancelled();
    if (received != file.bytes || digest.value?.toString() != file.sha256) {
      throw _Failure(MathModelFailure.checksum);
    }
  }

  static MathModelFailure _failureOf(Object e) => switch (e) {
    _Failure(:final reason) => reason,
    MathModelStorageException() => MathModelFailure.storage,
    TimeoutException() || http.ClientException() => MathModelFailure.offline,
    _
        when '${e.runtimeType}'.contains('Socket') ||
            '${e.runtimeType}'.contains('HttpException') ||
            '${e.runtimeType}'.contains('Handshake') =>
      MathModelFailure.offline,
    _ => MathModelFailure.unknown,
  };
}

final class _Cancelled implements Exception {
  const _Cancelled();
}

final class _Failure implements Exception {
  _Failure(this.reason);
  final MathModelFailure reason;
}

final class _DigestSink implements Sink<crypto.Digest> {
  crypto.Digest? value;

  @override
  void add(crypto.Digest data) => value = data;

  @override
  void close() {}
}
