// lib/src/background/background_spec.dart — contract 7.2.16 (03-ink 4.10).
import 'package:meta/meta.dart';
import 'package:note_core/note_core.dart' as core;

import '../interop/core_interop.dart' as interop;

enum InkBackgroundKind { blank, template, pdf, image, unknown }

@immutable
final class InkBackgroundSpec {
  const InkBackgroundSpec({
    required this.kind,
    this.paperColorArgb = core.PaperColors.white,
    this.template,
    this.assetId,
    this.pdfPageIndex,
  });

  /// BlankBackground → blank, TemplateBackground → template (+template), PdfBackground →
  /// pdf (+assetId, pdfPageIndex), ImageBackground → image (+assetId). Paper color =
  /// background.paperColorArgb. `unknown` is only for hand-made specs.
  factory InkBackgroundSpec.fromCore(core.PageBackground background) =>
      interop.backgroundSpecOf(background);

  final InkBackgroundKind kind;
  final int paperColorArgb;

  /// kind == template
  final core.PageTemplate? template;

  /// pdf / image
  final String? assetId;

  /// pdf, 0-based
  final int? pdfPageIndex;

  /// core.PaperColors.isDark(paperColorArgb)
  bool get isDarkPaper => core.PaperColors.isDark(paperColorArgb);

  @override
  bool operator ==(Object other) =>
      other is InkBackgroundSpec &&
      other.kind == kind &&
      other.paperColorArgb == paperColorArgb &&
      other.template == template &&
      other.assetId == assetId &&
      other.pdfPageIndex == pdfPageIndex;

  @override
  int get hashCode =>
      Object.hash(kind, paperColorArgb, template, assetId, pdfPageIndex);

  @override
  String toString() =>
      'InkBackgroundSpec(${kind.name}, 0x${paperColorArgb.toRadixString(16)})';
}
