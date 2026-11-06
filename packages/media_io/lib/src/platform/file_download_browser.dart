// lib/src/platform/file_download_browser.dart — the web '파일로 내려받기' body (m5-7/06-pdf 6.10.4):
// prepare = Blob([bytes], {type}) + URL.createObjectURL (the Dart bytes are not kept), save = a
// hidden `<a href=url download=fileName>` appended to the body, clicked synchronously and removed,
// revoke = URL.revokeObjectURL. Internal; behind file_download_factory.dart.
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'file_download.dart';

FileDownloads createPlatformFileDownloads() => const BrowserFileDownloads();

final class BrowserFileDownloads implements FileDownloads {
  const BrowserFileDownloads();

  @override
  bool get available => true;

  @override
  PreparedFileDownload? prepare(
    Uint8List bytes, {
    required String mimeType,
    required String fileName,
  }) {
    try {
      final blob = web.Blob(
        <JSAny>[bytes.toJS].toJS,
        web.BlobPropertyBag(type: mimeType),
      );
      return BrowserPreparedDownload(web.URL.createObjectURL(blob), fileName);
    } on Object {
      return null;
    }
  }
}

final class BrowserPreparedDownload implements PreparedFileDownload {
  BrowserPreparedDownload(this.url, this.fileName);

  /// The object URL (tests).
  final String url;

  @override
  final String fileName;

  bool _revoked = false;

  /// Whether [revoke] ran (tests).
  bool get revoked => _revoked;

  @override
  void save() {
    if (_revoked) return;
    final body = web.document.body;
    if (body == null) return;
    final a = web.HTMLAnchorElement()
      ..href = url
      ..download = fileName
      ..style.display = 'none';
    body.append(a);
    try {
      a.click(); // synchronous, inside the user's tap (6.10.4)
    } finally {
      a.remove();
    }
  }

  @override
  void revoke() {
    if (_revoked) return;
    _revoked = true;
    web.URL.revokeObjectURL(url);
  }
}
