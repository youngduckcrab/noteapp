/// `tool/web_assets.yaml`: the static files that must be in `app/web/`
/// (docs/plans/01-infra.md 4.3, contract 00-overview 7.4.9).
///
/// Used by `ws check` R12, `ws web-assets verify|fetch` and `ws
/// finalize-web`. sha256 is computed with `package:crypto` (no external
/// `sha256sum`).
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// Repo-relative path of the manifest.
const String webAssetsManifestPath = 'tool/web_assets.yaml';

/// Repo-relative directory the asset paths are relative to.
const String appWebDirectory = 'app/web';

/// Thrown when `tool/web_assets.yaml` is malformed.
final class WebAssetsFormatException implements Exception {
  const WebAssetsFormatException(this.message);

  final String message;

  @override
  String toString() => 'WebAssetsFormatException: $message';
}

/// One entry of `tool/web_assets.yaml`.
final class WebAsset {
  const WebAsset({
    required this.path,
    required this.url,
    required this.bytes,
    required this.sha256,
    required this.owner,
    required this.reason,
    this.line = 1,
  });

  /// Path relative to `app/web/` (`/` separators).
  final String path;

  /// Where `web-assets fetch` downloads it from.
  final Uri url;

  /// Expected size in bytes.
  final int bytes;

  /// Expected lowercase hex sha256.
  final String sha256;

  /// Owning area (e.g. `CORE`).
  final String owner;

  final String reason;

  /// 1-based line of the entry in the manifest.
  final int line;
}

final RegExp _sha256Pattern = RegExp(r'^[0-9a-f]{64}$');

/// The parsed manifest.
final class WebAssetsManifest {
  const WebAssetsManifest(this.assets);

  /// Reads [path]; returns `null` when the file does not exist.
  static WebAssetsManifest? loadIfExists(String path) {
    final file = File(path);
    if (!file.existsSync()) return null;
    return parse(file.readAsStringSync(), sourceUrl: file.uri);
  }

  /// Parses the YAML [text]. Throws [WebAssetsFormatException].
  static WebAssetsManifest parse(String text, {Uri? sourceUrl}) {
    final Object? yaml;
    try {
      yaml = loadYaml(text, sourceUrl: sourceUrl);
    } on YamlException catch (e) {
      throw WebAssetsFormatException(e.toString());
    }
    if (yaml is! YamlMap || yaml['assets'] is! YamlList) {
      throw const WebAssetsFormatException(
        'web_assets.yaml must be a map with an `assets:` list',
      );
    }
    final list = yaml['assets'] as YamlList;
    final assets = <WebAsset>[];
    final seen = <String>{};
    for (final node in list.nodes) {
      final line = node.span.start.line + 1;
      if (node is! YamlMap) {
        throw WebAssetsFormatException('line $line: entry is not a map');
      }
      String field(String key) {
        final value = node[key];
        if (value == null || '$value'.isEmpty) {
          throw WebAssetsFormatException('line $line: missing `$key`');
        }
        return '$value';
      }

      final path = field('path');
      if (p.posix.isAbsolute(path) ||
          p.posix.normalize(path).startsWith('..') ||
          path.contains(r'\')) {
        throw WebAssetsFormatException(
          'line $line: `path` must be relative to app/web/ ($path)',
        );
      }
      if (!seen.add(path)) {
        throw WebAssetsFormatException('line $line: duplicate path $path');
      }
      final url = Uri.tryParse(field('url'));
      if (url == null || !url.hasScheme || url.host.isEmpty) {
        throw WebAssetsFormatException('line $line: `url` is not absolute');
      }
      final bytes = node['bytes'];
      if (bytes is! int || bytes < 0) {
        throw WebAssetsFormatException(
          'line $line: `bytes` must be a non-negative integer',
        );
      }
      final sha = field('sha256');
      if (!_sha256Pattern.hasMatch(sha)) {
        throw WebAssetsFormatException(
          'line $line: `sha256` must be 64 lowercase hex characters',
        );
      }
      assets.add(
        WebAsset(
          path: path,
          url: url,
          bytes: bytes,
          sha256: sha,
          owner: field('owner'),
          reason: field('reason'),
          line: line,
        ),
      );
    }
    return WebAssetsManifest(List.unmodifiable(assets));
  }

  final List<WebAsset> assets;
}

/// Lowercase hex sha256 of [bytes].
String sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();

/// One problem found by [verifyWebAssets].
final class WebAssetProblem {
  const WebAssetProblem(this.asset, this.message);

  final WebAsset asset;
  final String message;

  @override
  String toString() => '${asset.path}: $message';
}

/// Checks that every asset exists under [webDir] with the expected size and
/// sha256.
List<WebAssetProblem> verifyWebAssets(
  WebAssetsManifest manifest,
  String webDir,
) => [for (final asset in manifest.assets) ?verifyWebAsset(asset, webDir)];

/// The problem with one asset, or `null` when it is fine.
WebAssetProblem? verifyWebAsset(WebAsset asset, String webDir) {
  final file = File(p.join(webDir, asset.path));
  if (!file.existsSync()) return WebAssetProblem(asset, 'file is missing');
  final bytes = file.readAsBytesSync();
  if (bytes.length != asset.bytes) {
    return WebAssetProblem(
      asset,
      'size is ${bytes.length} bytes, expected ${asset.bytes}',
    );
  }
  final actual = sha256Hex(bytes);
  if (actual != asset.sha256) {
    return WebAssetProblem(
      asset,
      'sha256 is $actual, expected ${asset.sha256}',
    );
  }
  return null;
}

/// Downloads [url]; returns `null` on any failure.
typedef Downloader = Future<List<int>?> Function(Uri url);

/// Downloads with `dart:io` [HttpClient]: the environment proxy is used
/// except for loopback hosts, redirects are followed, non-200 = `null`.
Future<List<int>?> httpDownload(Uri url) async {
  final client = HttpClient()
    ..findProxy = (uri) => _isLoopback(uri.host)
        ? 'DIRECT'
        : HttpClient.findProxyFromEnvironment(uri);
  try {
    final request = await client.getUrl(url);
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      return null;
    }
    final builder = BytesBuilder(copy: false);
    await response.forEach(builder.add);
    return builder.takeBytes();
  } on Object {
    return null;
  } finally {
    client.close(force: true);
  }
}

bool _isLoopback(String host) =>
    host == 'localhost' || host == '127.0.0.1' || host == '::1';

/// What [fetchWebAssets] did with one asset.
enum FetchOutcome { alreadyValid, written, downloadFailed, mismatch }

/// Result of one asset in [fetchWebAssets].
final class FetchResult {
  const FetchResult(this.asset, this.outcome, [this.detail = '']);

  final WebAsset asset;
  final FetchOutcome outcome;
  final String detail;

  bool get isFailure =>
      outcome == FetchOutcome.downloadFailed ||
      outcome == FetchOutcome.mismatch;

  @override
  String toString() =>
      '${asset.path}: ${outcome.name}${detail.isEmpty ? '' : ' ($detail)'}';
}

/// Downloads every asset that is missing or wrong under [webDir]. A file is
/// written only when the downloaded size and sha256 match the manifest.
Future<List<FetchResult>> fetchWebAssets(
  WebAssetsManifest manifest,
  String webDir, {
  Downloader download = httpDownload,
}) async {
  final results = <FetchResult>[];
  for (final asset in manifest.assets) {
    if (verifyWebAsset(asset, webDir) == null) {
      results.add(FetchResult(asset, FetchOutcome.alreadyValid));
      continue;
    }
    final bytes = await download(asset.url);
    if (bytes == null) {
      results.add(
        FetchResult(asset, FetchOutcome.downloadFailed, '${asset.url}'),
      );
      continue;
    }
    final sha = sha256Hex(bytes);
    if (bytes.length != asset.bytes || sha != asset.sha256) {
      results.add(
        FetchResult(
          asset,
          FetchOutcome.mismatch,
          'got ${bytes.length} bytes, sha256 $sha',
        ),
      );
      continue;
    }
    final file = File(p.join(webDir, asset.path));
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes);
    results.add(FetchResult(asset, FetchOutcome.written));
  }
  return results;
}
