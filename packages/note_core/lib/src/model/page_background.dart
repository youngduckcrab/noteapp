// lib/src/model/page_background.dart — contract 00-overview 7.2.5 / CORE 4.2.3.
import 'package:meta/meta.dart';

import '../common/ids.dart';
import '../common/json_read.dart';
import 'page_template.dart';

enum ImageFit { contain, cover, fill }

@immutable
sealed class PageBackground {
  const PageBackground({this.paperColorArgb = PaperColors.white});

  final int paperColorArgb;

  Set<AssetId> get referencedAssets;

  /// Includes "type".
  Map<String, Object?> toJson();

  static PageBackground fromJson(Map<String, Object?> json) {
    final paper = readIntOrNull(json, 'paperColor') ?? PaperColors.white;
    final type = readString(json, 'type');
    return switch (type) {
      'blank' => BlankBackground(paperColorArgb: paper),
      'template' => TemplateBackground(
        template: PageTemplate.fromJson(readMap(json, 'template')),
        paperColorArgb: paper,
      ),
      'pdf' => PdfBackground(
        assetId: readString(json, 'assetId'),
        pdfPageIndex: readInt(json, 'pdfPageIndex'),
        paperColorArgb: paper,
      ),
      'image' => ImageBackground(
        assetId: readString(json, 'assetId'),
        fit: _fitFromName(readStringOrNull(json, 'fit')),
        paperColorArgb: paper,
      ),
      _ => throw FormatException('Unknown page background type', type),
    };
  }

  static ImageFit _fitFromName(String? name) {
    if (name == null) return ImageFit.contain;
    for (final f in ImageFit.values) {
      if (f.name == name) return f;
    }
    throw FormatException('Unknown image fit', name);
  }
}

final class BlankBackground extends PageBackground {
  const BlankBackground({super.paperColorArgb});

  @override
  Set<AssetId> get referencedAssets => const {};

  @override
  Map<String, Object?> toJson() => {
    'type': 'blank',
    'paperColor': paperColorArgb,
  };

  @override
  bool operator ==(Object other) =>
      other is BlankBackground && other.paperColorArgb == paperColorArgb;

  @override
  int get hashCode => Object.hash('blank', paperColorArgb);

  @override
  String toString() => 'BlankBackground(0x${paperColorArgb.toRadixString(16)})';
}

final class TemplateBackground extends PageBackground {
  const TemplateBackground({required this.template, super.paperColorArgb});

  final PageTemplate template;

  @override
  Set<AssetId> get referencedAssets => const {};

  @override
  Map<String, Object?> toJson() => {
    'type': 'template',
    'paperColor': paperColorArgb,
    'template': template.toJson(),
  };

  @override
  bool operator ==(Object other) =>
      other is TemplateBackground &&
      other.paperColorArgb == paperColorArgb &&
      other.template == template;

  @override
  int get hashCode => Object.hash('template', paperColorArgb, template);

  @override
  String toString() => 'TemplateBackground(${template.kind.name})';
}

final class PdfBackground extends PageBackground {
  const PdfBackground({
    required this.assetId,
    required this.pdfPageIndex,
    super.paperColorArgb,
  });

  final AssetId assetId;
  final int pdfPageIndex; // 0-based

  @override
  Set<AssetId> get referencedAssets => {assetId};

  @override
  Map<String, Object?> toJson() => {
    'type': 'pdf',
    'paperColor': paperColorArgb,
    'assetId': assetId,
    'pdfPageIndex': pdfPageIndex,
  };

  @override
  bool operator ==(Object other) =>
      other is PdfBackground &&
      other.paperColorArgb == paperColorArgb &&
      other.assetId == assetId &&
      other.pdfPageIndex == pdfPageIndex;

  @override
  int get hashCode => Object.hash('pdf', paperColorArgb, assetId, pdfPageIndex);

  @override
  String toString() => 'PdfBackground($assetId #$pdfPageIndex)';
}

final class ImageBackground extends PageBackground {
  // used from M5
  const ImageBackground({
    required this.assetId,
    this.fit = ImageFit.contain,
    super.paperColorArgb,
  });

  final AssetId assetId;
  final ImageFit fit;

  @override
  Set<AssetId> get referencedAssets => {assetId};

  @override
  Map<String, Object?> toJson() => {
    'type': 'image',
    'paperColor': paperColorArgb,
    'assetId': assetId,
    'fit': fit.name,
  };

  @override
  bool operator ==(Object other) =>
      other is ImageBackground &&
      other.paperColorArgb == paperColorArgb &&
      other.assetId == assetId &&
      other.fit == fit;

  @override
  int get hashCode => Object.hash('image', paperColorArgb, assetId, fit);

  @override
  String toString() => 'ImageBackground($assetId, ${fit.name})';
}
