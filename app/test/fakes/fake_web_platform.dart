// FakeWebPlatform (docs/plans/01-infra.md 5.7): a scriptable WebPlatform for
// VM tests.

import 'dart:async';
import 'dart:typed_data';

import 'package:noteapp/src/web/web_platform.dart';

/// One recorded [FakeWebPlatform.downloadBytes] / [FakeWebPlatform.shareFile]
/// call.
final class RecordedFile {
  RecordedFile(this.bytes, this.fileName, this.mimeType);

  final Uint8List bytes;
  final String fileName;
  final String mimeType;

  int get length => bytes.length;
}

/// A [WebPlatform] whose answers are fields and whose calls are recorded.
final class FakeWebPlatform implements WebPlatform {
  FakeWebPlatform({
    this.isSupported = true,
    this.userAgent = 'FakeBrowser/1.0',
    this.isStandalone = false,
    this.millisecondsSinceNavigationStart = 1200,
    Uri? baseUri,
    this.buildInfoJson,
    Map<String, String>? fetchResponses,
    this.downloadResult = true,
    this.canShareFilesResult = false,
    this.shareResult = WebShareResult.shared,
  }) : baseUri = baseUri ?? Uri.parse('https://noteapp.web.app/'),
       fetchResponses = fetchResponses ?? {};

  @override
  bool isSupported;

  @override
  String? userAgent;

  @override
  bool isStandalone;

  @override
  double? millisecondsSinceNavigationStart;

  /// `document.baseURI` of the fake page.
  Uri baseUri;

  /// Body returned for `build_info.json` (null = request fails).
  String? buildInfoJson;

  /// Bodies for other paths (missing = request fails).
  final Map<String, String> fetchResponses;

  /// How long [fetchTextNoStore] takes (fake time).
  Duration fetchDelay = Duration.zero;

  bool downloadResult;
  bool canShareFilesResult;
  WebShareResult shareResult;

  int fetchCount = 0;
  final List<String> fetchedPaths = [];
  int reloadCount = 0;
  final List<RecordedFile> downloads = [];
  final List<RecordedFile> shares = [];

  final StreamController<WebVisibility> _visibility =
      StreamController<WebVisibility>.broadcast(sync: true);

  /// Sends [value] to [visibilityChanges] listeners.
  void emitVisibility(WebVisibility value) => _visibility.add(value);

  /// Whether anything listens to [visibilityChanges].
  bool get hasVisibilityListener => _visibility.hasListener;

  Future<void> dispose() => _visibility.close();

  @override
  String resolveAppUrl(String relativePath) =>
      baseUri.resolve(relativePath).toString();

  @override
  Future<String?> fetchTextNoStore(
    String relativePath, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    fetchCount++;
    fetchedPaths.add(relativePath);
    if (fetchDelay > Duration.zero) await Future<void>.delayed(fetchDelay);
    if (relativePath == 'build_info.json') return buildInfoJson;
    return fetchResponses[relativePath];
  }

  @override
  Future<bool> downloadBytes(
    Uint8List bytes, {
    required String fileName,
    String mimeType = 'application/octet-stream',
  }) async {
    downloads.add(RecordedFile(bytes, fileName, mimeType));
    return downloadResult;
  }

  @override
  bool canShareFiles({String mimeType = 'application/octet-stream'}) =>
      canShareFilesResult;

  @override
  Future<WebShareResult> shareFile(
    Uint8List bytes, {
    required String fileName,
    String mimeType = 'application/octet-stream',
  }) async {
    shares.add(RecordedFile(bytes, fileName, mimeType));
    return shareResult;
  }

  @override
  Stream<WebVisibility> get visibilityChanges => _visibility.stream;

  @override
  void reload() => reloadCount++;
}
