// MathModelManager (ondevice/math_model_manager.dart) over a fake HTTP
// server and an in-memory storage: success (progress, verified files, the
// marker last), a SHA-256 / size mismatch, a server error, offline, a full
// disk, cancel, delete, joined downloads, restore of an earlier install; the
// native FileMathModelStorage in a temporary directory (atomic rename, the
// marker, a new manager sees the install, delete frees the directory); the
// committed model files match the manifest constant.
@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:ink_recognition/src/ondevice/math_model_manager.dart';
import 'package:ink_recognition/src/ondevice/math_model_manifest.dart';
import 'package:ink_recognition/src/ondevice/math_model_storage_native.dart';

import '../support/math_model_fakes.dart';

MathModelManager _manager(MathModelStorage storage, FakeModelServer server) =>
    MathModelManager(
      storage: storage,
      createClient: server.client,
      manifest: fakeManifest,
    );

List<MathModelState> _record(MathModelManager m) {
  final states = <MathModelState>[];
  m.state.addListener(() => states.add(m.state.value));
  return states;
}

void main() {
  test('success: every file verified and committed, the marker last, '
      'progress up to the total, ready', () async {
    final storage = MemoryModelStorage();
    final server = FakeModelServer();
    final m = _manager(storage, server);
    final states = _record(m);
    await m.download();
    expect(m.state.value, isA<MathModelReady>());
    final ready = m.state.value as MathModelReady;
    expect(ready.install.paths.keys, fakeModelFiles.keys);
    expect(storage.marked, isTrue);
    for (final MapEntry(key: name, value: bytes) in fakeModelFiles.entries) {
      expect(storage.files[name], bytes, reason: name);
    }
    expect(server.requests, fakeModelFiles.keys);
    expect(server.closes, 1);
    final progress = states.whereType<MathModelDownloading>().toList();
    expect(progress.first.receivedBytes, 0);
    expect(progress.last.receivedBytes, fakeManifest.totalBytes);
    for (var i = 1; i < progress.length; i++) {
      expect(
        progress[i].receivedBytes,
        greaterThanOrEqualTo(progress[i - 1].receivedBytes),
      );
    }
    // ready → a second download does nothing
    await m.download();
    expect(server.requests, hasLength(3));
  });

  test('a file whose hash or size differs → failed(checksum), never '
      'committed, no marker', () async {
    final tampered = Map.of(fakeModelFiles);
    final bytes = Uint8List.fromList(tampered[kMathModelDecoderFile]!);
    bytes[100] ^= 0xff;
    tampered[kMathModelDecoderFile] = bytes;
    final storage = MemoryModelStorage();
    final m = _manager(storage, FakeModelServer(files: tampered));
    await m.download();
    expect(m.state.value, const MathModelFailed(MathModelFailure.checksum));
    expect(storage.files.containsKey(kMathModelDecoderFile), isFalse);
    expect(storage.parts, isEmpty);
    expect(storage.aborts, 1);
    expect(storage.marked, isFalse);

    // too long (e.g. index.html served for a missing file) → checksum
    final longer = Map.of(fakeModelFiles)
      ..[kMathModelTokenizerFile] = Uint8List(fakeModelFiles.length + 200000);
    final m2 = _manager(MemoryModelStorage(), FakeModelServer(files: longer));
    await m2.download();
    expect(m2.state.value, const MathModelFailed(MathModelFailure.checksum));

    // retry with a good server → ready
    final m3 = _manager(storage, FakeModelServer());
    await m3.download();
    expect(m3.state.value, isA<MathModelReady>());
  });

  test('server error → failed(server); no connection → failed(offline); '
      'a full disk → failed(storage)', () async {
    final m1 = _manager(
      MemoryModelStorage(),
      FakeModelServer(status: {kMathModelEncoderFile: 404}),
    );
    await m1.download();
    expect(m1.state.value, const MathModelFailed(MathModelFailure.server));

    final m2 = _manager(
      MemoryModelStorage(),
      FakeModelServer(failWith: http.ClientException('no route')),
    );
    await m2.download();
    expect(m2.state.value, const MathModelFailed(MathModelFailure.offline));

    final full = MemoryModelStorage()..failWrites = true;
    final m3 = _manager(full, FakeModelServer());
    await m3.download();
    expect(m3.state.value, const MathModelFailed(MathModelFailure.storage));
    expect(full.aborts, 1);
  });

  test('cancel aborts the request → not installed, the part removed', () async {
    final storage = MemoryModelStorage();
    final server = FakeModelServer()
      ..hold = Completer<void>()
      ..holdFile = kMathModelEncoderFile;
    final m = _manager(storage, server);
    final run = m.download();
    await pumpEventQueue();
    expect(m.state.value, isA<MathModelDownloading>());
    m.cancel();
    await run;
    expect(m.state.value, const MathModelNotInstalled());
    expect(storage.parts, isEmpty);
    expect(storage.files, isEmpty);
    expect(storage.marked, isFalse);
    expect(server.requests, [kMathModelEncoderFile]);
    server.hold!.complete();
  });

  test('cancel after a file was committed → the committed files are '
      'removed too', () async {
    final storage = MemoryModelStorage();
    final server = FakeModelServer()
      ..hold = Completer<void>()
      ..holdFile = kMathModelDecoderFile;
    final m = _manager(storage, server);
    final run = m.download();
    while (!server.requests.contains(kMathModelDecoderFile)) {
      await pumpEventQueue();
    }
    await pumpEventQueue();
    expect(storage.files.keys, [kMathModelEncoderFile]);
    m.cancel();
    await run;
    expect(m.state.value, const MathModelNotInstalled());
    expect(storage.files, isEmpty);
    expect(storage.parts, isEmpty);
    expect(storage.marked, isFalse);
    server.hold!.complete();
  });

  test('a failure after a file was committed → failed, the committed files '
      'are removed', () async {
    final tampered = Map.of(fakeModelFiles);
    final bytes = Uint8List.fromList(tampered[kMathModelTokenizerFile]!);
    bytes[10] ^= 0xff;
    tampered[kMathModelTokenizerFile] = bytes;
    final storage = MemoryModelStorage();
    final m = _manager(storage, FakeModelServer(files: tampered));
    await m.download();
    expect(m.state.value, const MathModelFailed(MathModelFailure.checksum));
    expect(storage.files, isEmpty);
    expect(storage.parts, isEmpty);
  });

  test('two downloads join; delete during a download stops it; delete '
      'frees the files', () async {
    final storage = MemoryModelStorage();
    final server = FakeModelServer();
    final m = _manager(storage, server);
    await Future.wait([m.download(), m.download()]);
    expect(server.requests, hasLength(3));
    expect(m.state.value, isA<MathModelReady>());
    await m.delete();
    expect(m.state.value, const MathModelNotInstalled());
    expect(storage.files, isEmpty);

    final slow = FakeModelServer()
      ..hold = Completer<void>()
      ..holdFile = kMathModelEncoderFile;
    final m2 = _manager(storage, slow);
    unawaited(m2.download());
    await pumpEventQueue();
    await m2.delete();
    expect(m2.state.value, const MathModelNotInstalled());
    slow.hold!.complete();
  });

  test('restore: an install from an earlier run is ready at once; a broken '
      'one is not installed', () async {
    final storage = MemoryModelStorage();
    await _manager(storage, FakeModelServer()).download();
    final server = FakeModelServer();
    final again = _manager(storage, server);
    expect(again.state.value, const MathModelNotInstalled());
    await again.restore();
    expect(again.state.value, isA<MathModelReady>());
    expect(server.requests, isEmpty);

    storage.files[kMathModelEncoderFile] = Uint8List(3);
    final broken = _manager(storage, FakeModelServer());
    await broken.restore();
    expect(broken.state.value, const MathModelNotInstalled());
  });

  group('FileMathModelStorage (dart:io)', () {
    late Directory root;
    setUp(() {
      root = Directory.systemTemp.createTempSync('math_model_');
      addTearDown(() {
        if (root.existsSync()) root.deleteSync(recursive: true);
      });
    });

    FileMathModelStorage storage() =>
        FileMathModelStorage(root: () async => root.path);

    test('download → files renamed into place + marker; a new manager '
        'restores it; delete removes the directory', () async {
      final m = MathModelManager(
        storage: storage(),
        createClient: FakeModelServer().client,
        manifest: fakeManifest,
      );
      await m.download();
      final ready = m.state.value as MathModelReady;
      final dir = Directory('${root.path}/${fakeManifest.version}');
      expect(dir.listSync().map((e) => e.uri.pathSegments.last).toSet(), {
        ...fakeModelFiles.keys,
        'installed.json',
      });
      for (final MapEntry(key: name, value: bytes) in fakeModelFiles.entries) {
        expect(File(ready.install.path(name)).readAsBytesSync(), bytes);
      }

      final next = MathModelManager(
        storage: storage(),
        createClient: FakeModelServer().client,
        manifest: fakeManifest,
      );
      await next.restore();
      expect(next.state.value, isA<MathModelReady>());

      // a file of the wrong size → not installed
      File(ready.install.path(kMathModelTokenizerFile)).writeAsStringSync('x');
      expect(await storage().installed(fakeManifest), isNull);

      await next.delete();
      expect(dir.existsSync(), isFalse);
      expect(next.state.value, const MathModelNotInstalled());
    });

    test('a failed file leaves no part, no marker and no earlier '
        'committed file', () async {
      final tampered = Map.of(fakeModelFiles)
        ..[kMathModelTokenizerFile] = Uint8List(
          fakeModelFiles[kMathModelTokenizerFile]!.length,
        );
      final m = MathModelManager(
        storage: storage(),
        createClient: FakeModelServer(files: tampered).client,
        manifest: fakeManifest,
      );
      await m.download();
      expect(m.state.value, const MathModelFailed(MathModelFailure.checksum));
      final dir = Directory('${root.path}/${fakeManifest.version}');
      expect(!dir.existsSync() || dir.listSync().isEmpty, isTrue);
    });

    test('an unreadable marker → not installed', () async {
      final dir = Directory('${root.path}/${fakeManifest.version}')
        ..createSync(recursive: true);
      File('${dir.path}/installed.json').writeAsStringSync('{oops');
      expect(await storage().installed(fakeManifest), isNull);
    });
  });

  test('the manifest constant matches the committed model files', () {
    expect(kMathModelManifest.version, 'pix2text-mfr-1.5-int8pc');
    expect(
      kMathModelManifest.baseUrl,
      'https://noteapp-3f44e.web.app/models/pix2text-mfr-1.5-int8pc/',
    );
    expect(kMathModelManifest.files.map((f) => f.name), [
      kMathModelEncoderFile,
      kMathModelDecoderFile,
      kMathModelTokenizerFile,
    ]);
    final dir = committedModelDir();
    final sums = {
      for (final line in File('$dir/SHA256SUMS').readAsLinesSync())
        if (line.trim().isNotEmpty)
          line.split(RegExp(r'\s+')).last: line.split(RegExp(r'\s+')).first,
    };
    for (final f in kMathModelManifest.files) {
      final file = File('$dir/${f.name}');
      expect(file.lengthSync(), f.bytes, reason: f.name);
      expect(
        crypto.sha256.convert(file.readAsBytesSync()).toString(),
        f.sha256,
        reason: f.name,
      );
      expect(sums[f.name], f.sha256, reason: 'SHA256SUMS ${f.name}');
      expect(kMathModelManifest.urlOf(f).toString(), endsWith('/${f.name}'));
    }
    expect((kMathModelManifest.totalBytes / 1e6).round(), 32);
  });
}
