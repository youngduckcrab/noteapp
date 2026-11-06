// lib/src/playback/audio_source.dart — how a recording's asset becomes something the player opens
// (m5-7/06-pdf 6.11.3). The platform body comes from audio_source_factory.dart: the web makes a
// Blob object URL (preload: false, revoked on close), native writes a play cache file once per
// asset (LRU at 256 MiB). Internal.
import 'dart:typed_data';

import 'package:note_core/note_core.dart' as core;

import 'player_port.dart';

abstract interface class AudioSourceProvider {
  /// The source for [assetId] (content hash), or null when the bytes are not on this device.
  /// [bytes] is called only when the source needs them (web: always unless [handoff] is given;
  /// native: on a cache miss). [handoff] is the stop path's browser Blob (6.6.5 ③ — web only).
  Future<PlayerSource?> prepare(
    core.AssetId assetId, {
    required String? mimeType,
    required String? fileName,
    required Future<Uint8List?> Function() bytes,
    Object? handoff,
  });

  /// Frees what the last [prepare] made (web: revokeObjectURL). Idempotent.
  void release();

  /// Whether the length shown is Recording.durationMs (web — preload: false, S-7) rather than
  /// the length the player read (native).
  bool get usesRecordingDuration;
}

/// The play cache file extension of an audio asset (native — 6.11.3): from the MIME type, then
/// the file name, else 'bin'.
String audioFileExtension({String? mimeType, String? fileName}) {
  final mime = (mimeType ?? '').toLowerCase();
  if (mime.contains('mp4') || mime.contains('m4a') || mime.contains('aac')) {
    return 'm4a';
  }
  if (mime.contains('webm')) return 'webm';
  if (mime.contains('ogg') || mime.contains('opus')) return 'ogg';
  if (mime.contains('mpeg') || mime.contains('mp3')) return 'mp3';
  if (mime.contains('wav')) return 'wav';
  final name = fileName ?? '';
  final dot = name.lastIndexOf('.');
  if (dot >= 0 && dot < name.length - 1) {
    final ext = name.substring(dot + 1).toLowerCase();
    if (RegExp(r'^[a-z0-9]{1,8}$').hasMatch(ext)) return ext;
  }
  return 'bin';
}
