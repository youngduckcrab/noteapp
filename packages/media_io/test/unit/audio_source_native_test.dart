// The native play cache (m5-7/06-pdf 6.11.3; 8.2 T34): `<cache>/media_io/play/<assetId>.<ext>`
// written once and reused (the asset id is the content hash), the first prepare trims the cache
// to playCacheMaxBytes least recently used first, a reused file is touched, the directory
// follows MediaTestHooks.directory (installFakeMediaPlatforms). VM (dart:io).
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_io/src/playback/audio_source.dart';
import 'package:media_io/src/playback/audio_source_native.dart';
import 'package:media_io/src/playback/player_port.dart';
import 'package:media_io/src/testing/test_hooks.dart';
import 'package:media_io/src/tuning.dart';

void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('media_io_cache_'));
  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  final id = 'a' * 64;
  final bytes = Uint8List.fromList(List.generate(100, (i) => i));

  NativeAudioSources sources({int? maxBytes, DateTime Function()? now}) =>
      NativeAudioSources(
        cacheRoot: () async => root.path,
        maxBytes: maxBytes ?? MediaTuning.playCacheMaxBytes,
        now: now,
      );

  String pathOf(PlayerSource? s) => (s! as PlayerFileSource).path;

  test('written once, then reused without reading the bytes again', () async {
    final s = sources();
    var reads = 0;
    Future<Uint8List?> read() async {
      reads++;
      return bytes;
    }

    final first = await s.prepare(
      id,
      mimeType: 'audio/mp4',
      fileName: null,
      bytes: read,
    );
    expect(pathOf(first), '${root.path}/media_io/play/$id.m4a');
    expect(File(pathOf(first)).readAsBytesSync(), bytes);
    expect(reads, 1);
    final second = await s.prepare(
      id,
      mimeType: 'audio/mp4',
      fileName: null,
      bytes: read,
    );
    expect(pathOf(second), pathOf(first));
    expect(reads, 1);
    // A new instance (the next app start) reuses it too.
    await sources().prepare(
      id,
      mimeType: 'audio/mp4',
      fileName: null,
      bytes: read,
    );
    expect(reads, 1);
    // No half-written file is left next to it.
    expect(
      Directory('${root.path}/media_io/play').listSync().map((e) => e.path),
      [pathOf(first)],
    );
    expect(s.usesRecordingDuration, isFalse);
  });

  test('no bytes on this device → null, nothing written', () async {
    final s = sources();
    final got = await s.prepare(
      id,
      mimeType: 'audio/mp4',
      fileName: null,
      bytes: () async => null,
    );
    expect(got, isNull);
    final dir = Directory('${root.path}/media_io/play');
    expect(
      dir.existsSync() ? dir.listSync() : const <FileSystemEntity>[],
      isEmpty,
    );
  });

  test('the first prepare trims to maxBytes, least recently used first; '
      'later prepares do not trim', () async {
    final dir = Directory('${root.path}/media_io/play')
      ..createSync(recursive: true);
    File make(String name, int day) {
      final f = File('${dir.path}/$name')..writeAsBytesSync(Uint8List(40));
      f.setLastModifiedSync(DateTime(2026, 1, day));
      return f;
    }

    final oldest = make('${'1' * 64}.m4a', 1);
    final middle = make('${'2' * 64}.m4a', 2);
    final newest = make('${'3' * 64}.m4a', 3);
    final s = sources(maxBytes: 100);
    await s.prepare(
      id,
      mimeType: 'audio/webm',
      fileName: null,
      bytes: () async => Uint8List(10),
    );
    // 120 B > 100 B before the new file: the oldest goes, then 80 B ≤ 100.
    expect(oldest.existsSync(), isFalse);
    expect(middle.existsSync(), isTrue);
    expect(newest.existsSync(), isTrue);
    expect(File('${dir.path}/$id.webm').existsSync(), isTrue);

    make('${'4' * 64}.m4a', 4);
    await s.prepare(
      'b' * 64,
      mimeType: 'audio/mp4',
      fileName: null,
      bytes: () async => Uint8List(10),
    );
    expect(
      middle.existsSync(),
      isTrue,
    ); // 140 B now, but only the first prepare trims
  });

  test('a reused file is touched (LRU order)', () async {
    final s = sources(now: () => DateTime(2026, 6, 1));
    final first = await s.prepare(
      id,
      mimeType: 'audio/mp4',
      fileName: null,
      bytes: () async => bytes,
    );
    final f = File(pathOf(first))..setLastModifiedSync(DateTime(2026, 1, 1));
    await s.prepare(
      id,
      mimeType: 'audio/mp4',
      fileName: null,
      bytes: () async => bytes,
    );
    expect(f.lastModifiedSync(), DateTime(2026, 6, 1));
  });

  test('the default directory is MediaTestHooks.directory when set', () async {
    MediaTestHooks.directory = root.path;
    addTearDown(MediaTestHooks.reset);
    final got = await NativeAudioSources().prepare(
      id,
      mimeType: 'audio/mp4',
      fileName: null,
      bytes: () async => bytes,
    );
    expect(pathOf(got), startsWith('${root.path}/media_io/play/'));
  });

  test('file extensions', () {
    expect(audioFileExtension(mimeType: 'audio/mp4'), 'm4a');
    expect(audioFileExtension(mimeType: 'audio/x-m4a'), 'm4a');
    expect(audioFileExtension(mimeType: 'audio/aac'), 'm4a');
    expect(audioFileExtension(mimeType: 'audio/webm;codecs=opus'), 'webm');
    expect(audioFileExtension(mimeType: 'audio/ogg;codecs=opus'), 'ogg');
    expect(audioFileExtension(mimeType: 'audio/mpeg'), 'mp3');
    expect(audioFileExtension(mimeType: 'audio/wav'), 'wav');
    expect(audioFileExtension(mimeType: '', fileName: 'x.FLAC'), 'flac');
    expect(audioFileExtension(mimeType: null, fileName: 'x.a/b'), 'bin');
    expect(audioFileExtension(), 'bin');
  });
}
