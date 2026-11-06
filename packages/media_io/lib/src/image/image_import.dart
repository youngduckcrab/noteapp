// lib/src/image/image_import.dart — supportedImageSources, importImageForNote (contract
// 7.2.12, m5-7/06-pdf 4.2.4, 6.12).
//
// 2차 foundation step R2-B4 (T30, contract 7.6.2): no source is offered and an import is
// always "cancelled" (null). PDF T36–T38 add the picker, the clipboard and the normalizer.
import 'package:flutter/widgets.dart';
import 'package:note_core/note_core.dart' as core;

/// EditorImageImporter parts (INFRA wraps them).
/// web: photos, camera, files (+ clipboard when navigator.clipboard.read exists)
///
/// R2-B4: the empty set (no image import yet).
Set<core.ImageImportSource> supportedImageSources() =>
    const <core.ImageImportSource>{};

/// Pick → decode → downscale to ImageImportLimits → re-encode (JPEG for photos, PNG when alpha)
/// → AssetStore.put(type: image). null = cancelled (or a handled error shown as a message).
/// (v2.1) Opens the system picker / clipboard read before its first await (7.2.10 rule); a long
/// normalization shows a preparing sheet (showModalBottomSheet — CP-PDF-11) after the pick.
/// Works without initializeMediaIo (image import is outside FEATURE_MEDIA — D17).
///
/// R2-B4: null (nothing is picked or stored).
Future<core.ImportedImage?> importImageForNote(
  BuildContext context,
  core.ImageImportSource source,
) => Future<core.ImportedImage?>.value();
