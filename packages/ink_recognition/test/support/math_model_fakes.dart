// Fakes for the on-device math engine's model files: a small manifest with
// real SHA-256 sums, an in-memory MathModelStorage, an http.Client serving
// the files (MockClient.streaming — the AbortableRequest reaches the
// handler), and the repository paths of the committed model files.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ink_recognition/src/ondevice/math_model_manager.dart';
import 'package:ink_recognition/src/ondevice/math_model_manifest.dart';

/// Three small files with their real sizes and hashes.
final Map<String, Uint8List> fakeModelFiles = {
  kMathModelEncoderFile: Uint8List.fromList(
    List.generate(300 * 1024, (i) => (i * 7) & 0xff),
  ),
  kMathModelDecoderFile: Uint8List.fromList(
    List.generate(120 * 1024, (i) => (i * 13) & 0xff),
  ),
  kMathModelTokenizerFile: Uint8List.fromList(utf8.encode('{"model": {}}')),
};

final MathModelManifest fakeManifest = MathModelManifest(
  version: 'fake-model-1',
  baseUrl: 'https://models.test/fake-model-1/',
  files: [
    for (final MapEntry(key: name, value: bytes) in fakeModelFiles.entries)
      MathModelFile(
        name: name,
        sha256: crypto.sha256.convert(bytes).toString(),
        bytes: bytes.length,
      ),
  ],
);

/// Files kept in memory; a commit moves `<name>.part` to `<name>`.
final class MemoryModelStorage implements MathModelStorage {
  final Map<String, Uint8List> files = {};
  final Set<String> parts = {};
  bool marked = false;
  int aborts = 0;
  bool failWrites = false;

  @override
  Future<MathModelInstall?> installed(MathModelManifest manifest) async {
    if (!marked) return null;
    for (final f in manifest.files) {
      if (files[f.name]?.length != f.bytes) return null;
    }
    return MathModelInstall({
      for (final f in manifest.files) f.name: '/m/${f.name}',
    });
  }

  @override
  Future<MathModelSink> create(
    MathModelManifest manifest,
    MathModelFile file,
  ) async {
    marked = false;
    parts.add(file.name);
    return _MemorySink(this, file.name);
  }

  @override
  Future<MathModelInstall> markInstalled(MathModelManifest manifest) async {
    marked = true;
    return (await installed(manifest))!;
  }

  @override
  Future<void> delete(MathModelManifest manifest) async {
    files.clear();
    parts.clear();
    marked = false;
  }
}

final class _MemorySink implements MathModelSink {
  _MemorySink(this.storage, this.name);
  final MemoryModelStorage storage;
  final String name;
  final BytesBuilder bytes = BytesBuilder();

  @override
  Future<void> add(List<int> chunk) async {
    if (storage.failWrites) throw MathModelStorageException('disk full');
    bytes.add(chunk);
  }

  @override
  Future<void> commit() async {
    storage.parts.remove(name);
    storage.files[name] = bytes.takeBytes();
  }

  @override
  Future<void> abort() async {
    storage.aborts++;
    storage.parts.remove(name);
  }
}

/// Serves [files] by URL file name in chunks of [chunk] bytes; [hold]
/// (when given) is awaited before the body of [holdFile]; [status] per
/// file; [requests] counts every request.
final class FakeModelServer {
  FakeModelServer({
    Map<String, Uint8List>? files,
    this.chunk = 64 * 1024,
    this.status = const {},
    this.failWith,
  }) : files = files ?? fakeModelFiles;

  final Map<String, Uint8List> files;
  final int chunk;
  final Map<String, int> status;
  final Exception? failWith;
  final List<String> requests = [];
  Completer<void>? hold;
  String? holdFile;
  int closes = 0;

  http.Client client() => _ClosingClient(
    MockClient.streaming((request, _) async {
      final name = request.url.pathSegments.last;
      requests.add(name);
      if (failWith != null) throw failWith!;
      final code = status[name] ?? 200;
      final body = files[name] ?? Uint8List(0);
      final abort = request is http.Abortable ? request.abortTrigger : null;
      final controller = StreamController<List<int>>();
      Future<void> pump() async {
        for (var i = 0; i < body.length; i += chunk) {
          if (name == holdFile && hold != null && i >= chunk) {
            await hold!.future;
          }
          if (controller.isClosed) return;
          controller.add(body.sublist(i, (i + chunk).clamp(0, body.length)));
          await Future<void>.delayed(Duration.zero);
        }
        if (!controller.isClosed) await controller.close();
      }

      unawaited(
        abort?.then((_) {
          if (!controller.isClosed) {
            controller.addError(http.RequestAbortedException(request.url));
            unawaited(controller.close());
          }
        }),
      );
      unawaited(pump());
      return http.StreamedResponse(
        controller.stream,
        code,
        contentLength: body.length,
      );
    }),
    this,
  );
}

final class _ClosingClient extends http.BaseClient {
  _ClosingClient(this._inner, this._server);
  final http.Client _inner;
  final FakeModelServer _server;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _inner.send(request);

  @override
  void close() {
    _server.closes++;
    _inner.close();
  }
}

/// The repository root (the directory holding hosting/models).
Directory repoRoot() {
  var dir = Directory.current.absolute;
  while (!Directory('${dir.path}/hosting/models').existsSync()) {
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError('hosting/models not found above ${Directory.current}');
    }
    dir = parent;
  }
  return dir;
}

/// The committed model directory (`hosting/models/<version>`).
String committedModelDir() =>
    '${repoRoot().path}/hosting/models/${kMathModelManifest.version}';

/// The package's test fixture directory (test/fixtures/mfr).
String mfrFixtures() {
  final root = repoRoot().path;
  return '$root/packages/ink_recognition/test/fixtures/mfr';
}
