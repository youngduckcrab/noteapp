// lib/src/assets/image_import.dart — (v2.0) 2nd-round contract 7.2.6 / 02-core 4.7, 6.15.2:
// ImageImportSource, ImportedImage, ImageImportLimits. Picking, decoding and re-encoding are
// media_io's (M-3).
import 'package:meta/meta.dart';

import '../model/asset.dart';

enum ImageImportSource { photos, camera, files, clipboard }

@immutable
final class ImportedImage {
  const ImportedImage({
    required this.asset,
    required this.pixelWidth,
    required this.pixelHeight,
  });
  final Asset asset; // AssetType.image, already in AssetStore
  final int pixelWidth, pixelHeight;

  // CORE 4.7: ==, hashCode
  @override
  bool operator ==(Object other) =>
      other is ImportedImage &&
      other.asset == asset &&
      other.pixelWidth == pixelWidth &&
      other.pixelHeight == pixelHeight;

  @override
  int get hashCode => Object.hash(asset, pixelWidth, pixelHeight);

  @override
  String toString() => 'ImportedImage(${asset.id}, ${pixelWidth}x$pixelHeight)';
}

abstract final class ImageImportLimits {
  static const int maxLongSidePx =
      2048; // larger photos are downscaled (media_io)
  static const int maxBytes = 8 * 1024 * 1024; // after re-encoding
  // HEIC/WebP/GIF converted
  static const Set<String> storedMimeTypes = {'image/jpeg', 'image/png'};
}
