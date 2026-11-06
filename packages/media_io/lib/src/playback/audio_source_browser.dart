// lib/src/playback/audio_source_browser.dart — the web player source (m5-7/06-pdf 6.11.3): the
// hand-off Blob of the stop path when there is one (P-B, 6.6.5 ③), else Blob([bytes], {type:
// Asset.mimeType}) (the Dart bytes are dropped right after) → URL.createObjectURL → setUrl(url,
// preload: false) — the length is Recording.durationMs (S-7). The URL is revoked on close and on
// the next open. No StreamAudioSource (a base64 data URL on the web — 6.11.3). Internal.
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:note_core/note_core.dart' as core;
import 'package:web/web.dart' as web;

import 'audio_source.dart';
import 'player_port.dart';

AudioSourceProvider createPlatformAudioSources() => BrowserAudioSources();

Object? createHandoffBlob(Uint8List bytes, String mimeType) =>
    web.Blob(<JSAny>[bytes.toJS].toJS, web.BlobPropertyBag(type: mimeType));

final class BrowserAudioSources implements AudioSourceProvider {
  String? _url;

  /// The object URL of the open recording (tests).
  String? get currentUrl => _url;

  /// How many object URLs were revoked (tests).
  int revokedCount = 0;

  @override
  Future<PlayerSource?> prepare(
    core.AssetId assetId, {
    required String? mimeType,
    required String? fileName,
    required Future<Uint8List?> Function() bytes,
    Object? handoff,
  }) async {
    release();
    final web.Blob blob;
    if (handoff case final web.Blob given) {
      blob = given;
    } else {
      final data = await bytes();
      if (data == null) return null;
      blob = web.Blob(
        <JSAny>[data.toJS].toJS,
        web.BlobPropertyBag(type: mimeType ?? ''),
      );
    }
    final url = _url = web.URL.createObjectURL(blob);
    return PlayerUrlSource(url, preload: false);
  }

  @override
  void release() {
    final url = _url;
    if (url == null) return;
    _url = null;
    web.URL.revokeObjectURL(url);
    revokedCount++;
  }

  @override
  bool get usesRecordingDuration => true;
}
