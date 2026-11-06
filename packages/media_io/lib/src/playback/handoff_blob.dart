// lib/src/playback/handoff_blob.dart — (v2.1, P-B) the stop path hands the saved recording's
// browser Blob to the player (m5-7/06-pdf 6.6.5 ③): a recording of at least stopHandoffMinBytes
// leaves Blob([bytes]) here, and the next open of that asset uses it instead of reading the bytes
// again. One slot, used once — every open takes (and so drops) it. Native and the VM make no Blob
// (createHandoffBlob is null there). Internal.
import 'dart:typed_data';

import 'package:note_core/note_core.dart' as core;

import '../tuning.dart';
import 'audio_source_factory.dart';

final class PlaybackHandoff {
  PlaybackHandoff({
    Object? Function(Uint8List bytes, String mimeType)? blobOf,
    this.minBytes = MediaTuning.stopHandoffMinBytes,
  }) : _blobOf = blobOf ?? createHandoffBlob;

  final Object? Function(Uint8List bytes, String mimeType) _blobOf;

  /// Smaller recordings are read again on open (MediaTuning.stopHandoffMinBytes).
  final int minBytes;

  core.AssetId? _assetId;
  Object? _blob;

  /// Whether a Blob waits for an open (tests).
  bool get holds => _blob != null;

  /// The stop path, right after the asset was stored.
  void offer(core.AssetId assetId, Uint8List bytes, String mimeType) {
    if (bytes.length < minBytes) return;
    final blob = _blobOf(bytes, mimeType);
    if (blob == null) return;
    _assetId = assetId;
    _blob = blob;
  }

  /// The Blob of [assetId] when it waits here, else null. Either way the slot is emptied.
  Object? take(core.AssetId assetId) {
    final blob = _assetId == assetId ? _blob : null;
    clear();
    return blob;
  }

  void clear() {
    _assetId = null;
    _blob = null;
  }
}
