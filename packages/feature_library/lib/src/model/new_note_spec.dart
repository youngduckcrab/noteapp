// lib/src/model/new_note_spec.dart — 05-library 6.12. Page sizes, limits and
// paper colors are CORE's (contract 7.2.5 PageSizePreset, PageSizeLimits,
// PaperColors).
import 'package:flutter/foundation.dart' show immutable;
import 'package:note_core/note_core.dart';

import 'page_size_mm.dart';

enum PageOrientationChoice { portrait, landscape }

/// JSON field names of [NewNoteOptions.toJson].
abstract final class _Json {
  static const String size = 'size';
  static const String custom = 'custom';
  static const String orientation = 'orientation';
  static const String customW = 'customW';
  static const String customH = 'customH';
  static const String template = 'template';
  static const String paper = 'paper';
}

@immutable
final class NewNoteOptions {
  const NewNoteOptions({
    this.preset = PageSizePreset.a4,
    this.orientation = PageOrientationChoice.portrait,
    this.customWidthMm = 210,
    this.customHeightMm = 297,
    this.template = PageTemplateKind.lined,
    this.paperColorArgb = PaperColors.white,
  });

  /// Tolerant, never throws: unknown / missing fields → defaults; numbers
  /// accept int ((v as num).toDouble(), web JSON — contract 7.4.6); custom mm
  /// clamped with PageSizeMm.clampInput; paper not in PaperColors.all →
  /// PaperColors.white. "template": null = blank page; a missing or unknown
  /// template → the default (lined).
  factory NewNoteOptions.fromJson(Map<String, Object?> json) {
    const d = NewNoteOptions();
    final size = json[_Json.size];
    final PageSizePreset? preset = size == _Json.custom
        ? null
        : (size is String ? _byName(PageSizePreset.values, size) : null) ??
              d.preset;
    final orientation = json[_Json.orientation];
    final template = json[_Json.template];
    return NewNoteOptions(
      preset: preset,
      orientation:
          (orientation is String
              ? _byName(PageOrientationChoice.values, orientation)
              : null) ??
          d.orientation,
      customWidthMm: _mm(json[_Json.customW], d.customWidthMm),
      customHeightMm: _mm(json[_Json.customH], d.customHeightMm),
      template: json.containsKey(_Json.template) && template == null
          ? null
          : (template is String
                    ? _byName(PageTemplateKind.values, template)
                    : null) ??
                d.template,
      paperColorArgb: _paper(json[_Json.paper]),
    );
  }

  /// core.PageSizePreset (a4 595.2756×841.8898, letter 612×792,
  /// widescreen16x9 540×960 portrait form). null = custom: customWidthMm ×
  /// customHeightMm.
  final PageSizePreset? preset;

  /// Ignored for custom (width/height typed directly).
  final PageOrientationChoice orientation;

  /// Within PageSizeMm.minInputMm..maxInputMm.
  final double customWidthMm, customHeightMm;

  /// null = blank page.
  final PageTemplateKind? template;

  /// One of PaperColors.all.
  final int paperColorArgb;

  bool get isCustom => preset == null;

  /// preset != null → preset.portrait, then .landscape when orientation ==
  ///   landscape (a4 landscape 841.8898×595.2756, widescreen16x9 landscape
  ///   960×540).
  /// preset == null → PageSize(PageSizeMm.toPt(customWidthMm),
  ///   PageSizeMm.toPt(customHeightMm)), always within PageSizeLimits (fields
  ///   are validated, fromJson clamps).
  PageSize get pageSize {
    final p = preset;
    if (p == null) {
      return PageSize(
        PageSizeMm.toPt(customWidthMm),
        PageSizeMm.toPt(customHeightMm),
      );
    }
    return orientation == PageOrientationChoice.landscape
        ? p.portrait.landscape
        : p.portrait;
  }

  /// template == null → BlankBackground(paperColorArgb: paperColorArgb)
  /// else TemplateBackground(template: PageTemplate.defaults(kind),
  /// paperColorArgb: paperColorArgb) (all template parameters null → INK
  /// defaults; line color by paper luminance — contract 7.2.5).
  PageBackground get background {
    final kind = template;
    return kind == null
        ? BlankBackground(paperColorArgb: paperColorArgb)
        : TemplateBackground(
            template: PageTemplate.defaults(kind),
            paperColorArgb: paperColorArgb,
          );
  }

  /// [custom] = true selects the custom size (preset null); otherwise a
  /// non-null [preset] replaces the preset. [clearTemplate] selects the blank
  /// page.
  NewNoteOptions copyWith({
    PageSizePreset? preset,
    bool custom = false,
    PageOrientationChoice? orientation,
    double? customWidthMm,
    double? customHeightMm,
    PageTemplateKind? template,
    bool clearTemplate = false,
    int? paperColorArgb,
  }) => NewNoteOptions(
    preset: custom ? null : preset ?? this.preset,
    orientation: orientation ?? this.orientation,
    customWidthMm: customWidthMm ?? this.customWidthMm,
    customHeightMm: customHeightMm ?? this.customHeightMm,
    template: clearTemplate ? null : template ?? this.template,
    paperColorArgb: paperColorArgb ?? this.paperColorArgb,
  );

  /// Stored in LibrarySettingsKeys.newNoteDefaults (SettingKey.jsonMap,
  /// 6.3.4):
  /// {"size":"a4"|"letter"|"widescreen16x9"|"custom",
  ///  "orientation":"portrait"|"landscape", "customW":210.0,"customH":297.0,
  ///  "template":"lined"|…|null,"paper":4294967295}
  /// size = PageSizePreset.name or 'custom', template = PageTemplateKind.name.
  Map<String, Object?> toJson() => {
    _Json.size: preset?.name ?? _Json.custom,
    _Json.orientation: orientation.name,
    _Json.customW: customWidthMm,
    _Json.customH: customHeightMm,
    _Json.template: template?.name,
    _Json.paper: paperColorArgb,
  };

  @override
  bool operator ==(Object other) =>
      other is NewNoteOptions &&
      other.preset == preset &&
      other.orientation == orientation &&
      other.customWidthMm == customWidthMm &&
      other.customHeightMm == customHeightMm &&
      other.template == template &&
      other.paperColorArgb == paperColorArgb;

  @override
  int get hashCode => Object.hash(
    preset,
    orientation,
    customWidthMm,
    customHeightMm,
    template,
    paperColorArgb,
  );

  @override
  String toString() => 'NewNoteOptions(${toJson()})';
}

@immutable
final class NewNoteSpec {
  const NewNoteSpec({
    required this.title,
    required this.options,
    this.cover = const FirstPageCover(),
  });

  /// Validated, 1..200.
  final String title;
  final NewNoteOptions options;

  /// FirstPageCover or ColorCover.
  final NoteCover cover;

  PageDraft toPageDraft() =>
      PageDraft(size: options.pageSize, background: options.background);

  @override
  bool operator ==(Object other) =>
      other is NewNoteSpec &&
      other.title == title &&
      other.options == options &&
      other.cover == cover;

  @override
  int get hashCode => Object.hash(title, options, cover);
}

T? _byName<T extends Enum>(List<T> values, String name) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  return null;
}

double _mm(Object? v, double fallback) =>
    v is num ? PageSizeMm.clampInput(v.toDouble()) : fallback;

int _paper(Object? v) {
  if (v is num && v.isFinite && v == v.truncateToDouble()) {
    final argb = v.toInt();
    if (PaperColors.all.contains(argb)) return argb;
  }
  return PaperColors.white;
}
