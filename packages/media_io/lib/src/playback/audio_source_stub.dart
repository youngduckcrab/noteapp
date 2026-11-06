// lib/src/playback/audio_source_stub.dart — no player source on a platform with neither dart:io
// nor JS interop (audio_source_factory.dart). Internal.
import 'dart:typed_data';

import 'package:note_core/note_core.dart' as core;

import 'audio_source.dart';
import 'player_port.dart';

AudioSourceProvider createPlatformAudioSources() => const _NoAudioSources();

Object? createHandoffBlob(Uint8List bytes, String mimeType) => null;

final class _NoAudioSources implements AudioSourceProvider {
  const _NoAudioSources();

  @override
  Future<PlayerSource?> prepare(
    core.AssetId assetId, {
    required String? mimeType,
    required String? fileName,
    required Future<Uint8List?> Function() bytes,
    Object? handoff,
  }) => throw UnsupportedError('No audio playback on this platform');

  @override
  void release() {}

  @override
  bool get usesRecordingDuration => true;
}
