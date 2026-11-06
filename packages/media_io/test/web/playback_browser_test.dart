// The web playback path in Chrome (m5-7/06-pdf 6.11.3, 4.2.3; 8.2 T34): the Blob object URL
// (made, readable, revoked), just_audio_web opening a short sample after
// registerMediaWebPlugins, the service with preload: false (the length is the recording row's, a
// seek before the first play is kept for it) and the stop hand-off Blob (P-B — no byte read).
// Nothing here plays sound (the default Chrome of `ws test --platform chrome` has no autoplay
// flag; V8 in media/ plays — T39).
@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_io/src/playback/audio_source_browser.dart';
import 'package:media_io/src/playback/handoff_blob.dart';
import 'package:media_io/src/playback/playback_service.dart';
import 'package:media_io/src/playback/player_port.dart';
import 'package:media_io/testing.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart' as core_testing;
import 'package:web/web.dart' as web;

/// A mono 16-bit PCM WAV of [ms] milliseconds of silence at 8 kHz.
Uint8List silentWav(int ms) {
  const rate = 8000;
  final samples = rate * ms ~/ 1000;
  final data = samples * 2;
  final b = ByteData(44 + data);
  void ascii(int at, String s) {
    for (var i = 0; i < s.length; i++) {
      b.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  b.setUint32(4, 36 + data, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  b
    ..setUint32(16, 16, Endian.little)
    ..setUint16(20, 1, Endian.little) // PCM
    ..setUint16(22, 1, Endian.little) // mono
    ..setUint32(24, rate, Endian.little)
    ..setUint32(28, rate * 2, Endian.little)
    ..setUint16(32, 2, Endian.little)
    ..setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  b.setUint32(40, data, Endian.little);
  return b.buffer.asUint8List();
}

Future<Uint8List?> fetchBytes(String url) async {
  try {
    final response = await web.window.fetch(url.toJS).toDart;
    final buffer = await response.arrayBuffer().toDart;
    return buffer.toDart.asUint8List();
  } on Object {
    return null;
  }
}

/// Counts metadata and byte reads.
final class CountingAssets implements core.AssetStore {
  CountingAssets(this.inner);
  final core.AssetStore inner;
  int metaReads = 0;
  int byteReads = 0;

  @override
  Future<core.Asset?> getAsset(core.AssetId id) {
    metaReads++;
    return inner.getAsset(id);
  }

  @override
  Future<Uint8List?> readBytes(core.AssetId id) {
    byteReads++;
    return inner.readBytes(id);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

core.Recording recordingOf(core.Asset asset, {int durationMs = 1234}) =>
    core.Recording(
      id: 'rec-1',
      noteId: 'note-1',
      assetId: asset.id,
      durationMs: durationMs,
      startedAt: 1,
      createdAt: 1,
      updatedAt: 1,
    );

void main() {
  // just_audio's AudioPlayer sets up audio_session's method channel.
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(registerMediaWebPlugins);

  test('Blob object URL: made from the bytes (preload: false), readable, '
      'revoked on release', () async {
    final sources = BrowserAudioSources();
    final wav = silentWav(100);
    final source = await sources.prepare(
      'a' * 64,
      mimeType: 'audio/wav',
      fileName: null,
      bytes: () async => wav,
    );
    final urlSource = source! as PlayerUrlSource;
    final url = urlSource.url;
    expect(url, startsWith('blob:'));
    expect(urlSource.preload, isFalse);
    expect(sources.currentUrl, url);
    expect(await fetchBytes(url), wav);
    sources.release();
    sources.release();
    expect(sources.revokedCount, 1);
    expect(sources.currentUrl, isNull);
    expect(await fetchBytes(url), isNull);
    expect(sources.usesRecordingDuration, isTrue);

    // A new prepare revokes the previous URL.
    await sources.prepare(
      'a' * 64,
      mimeType: 'audio/wav',
      fileName: null,
      bytes: () async => wav,
    );
    final first = sources.currentUrl!;
    await sources.prepare(
      'b' * 64,
      mimeType: 'audio/wav',
      fileName: null,
      bytes: () async => wav,
    );
    expect(sources.revokedCount, 2);
    expect(await fetchBytes(first), isNull);
    sources.release();

    // No bytes → null and no URL.
    expect(
      await sources.prepare(
        'c' * 64,
        mimeType: 'audio/wav',
        fileName: null,
        bytes: () async => null,
      ),
      isNull,
    );
    expect(sources.currentUrl, isNull);
  });

  test('just_audio_web opens a short sample (preload: true reads its '
      'length)', () async {
    final url = web.URL.createObjectURL(
      createHandoffBlob(silentWav(500), 'audio/wav')! as web.Blob,
    );
    final port = JustAudioPlayerPort();
    try {
      final length = await port.load(PlayerUrlSource(url));
      expect(length, isNotNull);
      expect(length!.inMilliseconds, inInclusiveRange(450, 550));
      expect(port.snapshot.processing, PlayerProcessing.ready);
    } finally {
      await port.dispose();
      web.URL.revokeObjectURL(url);
    }
  });

  test('the service on the web: ready with the row\'s length, a seek before '
      'the first play is kept', () async {
    final store = core_testing.createFakeNoteStore();
    final asset = await store.assets.put(
      silentWav(500),
      type: core.AssetType.audio,
      mimeType: 'audio/wav',
    );
    final sources = BrowserAudioSources();
    final service = JustAudioPlaybackService(
      assets: () => store.assets,
      settings: () => store.settings,
      sources: sources,
    );
    try {
      await service.open(recordingOf(asset, durationMs: 1234));
      expect(service.status.phase, core.PlaybackPhase.ready);
      expect(service.status.durationMs, 1234);
      expect(sources.currentUrl, startsWith('blob:'));
      await service.seekMs(300);
      expect(service.positionMs(), 300);
      await service.seekMs(5000);
      expect(service.positionMs(), 1234);
      await service.close();
      expect(service.status.phase, core.PlaybackPhase.idle);
      expect(sources.currentUrl, isNull);
      expect(sources.revokedCount, 1);
    } finally {
      await service.dispose();
      await store.close();
    }
  });

  test('(P-B) with the stop hand-off Blob the open reads no bytes', () async {
    final store = core_testing.createFakeNoteStore();
    final wav = silentWav(200);
    final asset = await store.assets.put(
      wav,
      type: core.AssetType.audio,
      mimeType: 'audio/wav',
    );
    final assets = CountingAssets(store.assets);
    final handoff = PlaybackHandoff(minBytes: 1);
    final sources = BrowserAudioSources();
    final service = JustAudioPlaybackService(
      assets: () => assets,
      settings: () => store.settings,
      sources: sources,
      handoff: handoff,
    );
    try {
      handoff.offer(asset.id, wav, 'audio/wav');
      expect(handoff.holds, isTrue);
      await service.open(recordingOf(asset));
      expect(service.status.phase, core.PlaybackPhase.ready);
      expect(assets.metaReads, 0);
      expect(assets.byteReads, 0);
      expect(await fetchBytes(sources.currentUrl!), wav);
      // Used once: the next open reads the bytes.
      await service.open(recordingOf(asset));
      expect(assets.byteReads, 1);
    } finally {
      await service.dispose();
      await store.close();
    }
  });
}
