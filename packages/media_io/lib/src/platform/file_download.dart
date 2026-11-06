// lib/src/platform/file_download.dart — (v2.1, D19 — 검토 S-5) the web '파일로 내려받기' port
// (m5-7/06-pdf 6.10.4). Internal.
//
// Two steps: [FileDownloads.prepare] makes a Blob + object URL from the bytes (the caller drops
// its byte reference right after), and [PreparedFileDownload.save] clicks an `<a download>`
// SYNCHRONOUSLY inside the user's tap — a click after an `await` may not count as a user action
// on iPad Safari [추측 — B-14]. The URL is revoked when the panel / sheet goes away. Native has
// no download (drafts stay in the app support directory and are recovered on the next launch).
// The browser body is platform/file_download_browser.dart (PDF T32b); until it is wired the
// panel uses [NoFileDownloads] (no download items).
import 'dart:typed_data';

abstract interface class FileDownloads {
  /// false: no download here (native, tests without a fake) — the panel shows no download item.
  bool get available;

  /// Blob(type: [mimeType]) + object URL for [bytes], saved as [fileName]. null = failed.
  PreparedFileDownload? prepare(
    Uint8List bytes, {
    required String mimeType,
    required String fileName,
  });
}

abstract interface class PreparedFileDownload {
  String get fileName;

  /// Clicks the download link — call it synchronously in the tap handler.
  void save();

  /// Revokes the object URL; a second call is a no-op. [save] after this does nothing.
  void revoke();
}

/// No download (native and the default until PDF T32b wires the browser body).
final class NoFileDownloads implements FileDownloads {
  const NoFileDownloads();

  @override
  bool get available => false;

  @override
  PreparedFileDownload? prepare(
    Uint8List bytes, {
    required String mimeType,
    required String fileName,
  }) => null;
}
