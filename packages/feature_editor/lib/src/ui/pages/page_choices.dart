// lib/src/ui/pages/page_choices.dart — 04-editor 6.11.4: the add-page
// sheet's choices, built only from CORE values (no EDITOR tables).
import 'package:flutter/foundation.dart';
import 'package:note_core/note_core.dart' as core;

import '../../state/popup.dart';
import '../editor_strings.dart';

/// Template row: blank + every core.PageTemplateKind (6, contract 7.8).
/// Value equality: preview cells are keyed by ValueKey((choice, color, size)) (6.11.4).
@immutable
sealed class TemplateChoice {
  const TemplateChoice();

  /// Blank first, then every core.PageTemplateKind in declaration order.
  static const List<TemplateChoice> all = [
    BlankChoice(),
    KindChoice(core.PageTemplateKind.lined),
    KindChoice(core.PageTemplateKind.grid),
    KindChoice(core.PageTemplateKind.dotted),
    KindChoice(core.PageTemplateKind.cornell),
    KindChoice(core.PageTemplateKind.music),
    KindChoice(core.PageTemplateKind.planner),
  ];

  /// The choice that matches [background]: a template → its kind (template
  /// parameters are not kept — the new page gets the defaults), anything else
  /// (blank, PDF, image) → blank.
  static TemplateChoice of(core.PageBackground background) =>
      switch (background) {
        core.TemplateBackground(:final template) => KindChoice(template.kind),
        _ => const BlankChoice(),
      };
}

final class BlankChoice extends TemplateChoice {
  const BlankChoice();

  @override
  bool operator ==(Object other) => other is BlankChoice;

  @override
  int get hashCode => (BlankChoice).hashCode;

  @override
  String toString() => 'BlankChoice()';
}

final class KindChoice extends TemplateChoice {
  const KindChoice(this.kind);
  final core.PageTemplateKind kind;

  @override
  bool operator ==(Object other) => other is KindChoice && other.kind == kind;

  @override
  int get hashCode => Object.hash(KindChoice, kind);

  @override
  String toString() => 'KindChoice(${kind.name})';
}

/// Size row: core.PageSizePreset.values + custom (null).
/// Labels: a4 'A4', letter 'Letter', widescreen16x9 '16:9', null '사용자 지정'.
String pageSizeLabel(core.PageSizePreset? preset) => switch (preset) {
  core.PageSizePreset.a4 => 'A4',
  core.PageSizePreset.letter => 'Letter',
  core.PageSizePreset.widescreen16x9 => '16:9',
  null => EditorStrings.customSize,
};

/// Paper row: core.PaperColors.all with labels 흰색 · 미색 · 회색 · 검정.
String paperColorLabel(int argb) => switch (argb) {
  core.PaperColors.white => EditorStrings.paperWhite,
  core.PaperColors.ivory => EditorStrings.paperIvory,
  core.PaperColors.gray => EditorStrings.paperGray,
  core.PaperColors.black => EditorStrings.paperBlack,
  _ => EditorStrings.paperOther,
};

/// Labels: lined 줄 · grid 모눈 · dotted 점 · cornell 코넬 · music 악보 · planner 플래너, blank 빈 페이지.
String templateLabel(TemplateChoice choice) => switch (choice) {
  BlankChoice() => EditorStrings.templateBlank,
  KindChoice(:final kind) => switch (kind) {
    core.PageTemplateKind.lined => EditorStrings.templateLined,
    core.PageTemplateKind.grid => EditorStrings.templateGrid,
    core.PageTemplateKind.dotted => EditorStrings.templateDotted,
    core.PageTemplateKind.cornell => EditorStrings.templateCornell,
    core.PageTemplateKind.music => EditorStrings.templateMusic,
    core.PageTemplateKind.planner => EditorStrings.templatePlanner,
  },
};

/// background for a choice: BlankChoice → core.BlankBackground(paperColorArgb: color),
/// KindChoice → core.TemplateBackground(template: core.PageTemplate.defaults(kind),
/// paperColorArgb: color) (all template parameters null = INK defaults, line colour by
/// paper luminance — contract 7.2.5).
core.PageBackground backgroundFor(TemplateChoice choice, int paperColorArgb) =>
    switch (choice) {
      BlankChoice() => core.BlankBackground(paperColorArgb: paperColorArgb),
      KindChoice(:final kind) => core.TemplateBackground(
        template: core.PageTemplate.defaults(kind),
        paperColorArgb: paperColorArgb,
      ),
    };

/// The paper colour row's value for [argb]: itself when it is one of
/// core.PaperColors.all, else white (6.11.4 initial value).
int paperColorChoiceOf(int argb) =>
    core.PaperColors.all.contains(argb) ? argb : core.PaperColors.white;

@immutable
class AddPageRequest {
  const AddPageRequest({
    required this.placement,
    required this.size,
    required this.background,
    this.anchorPageId,
  });
  final AddPagePlacement placement;
  final core.PageSize size;
  final core.PageBackground background;
  final String? anchorPageId; // null = current page (before/after)

  /// before → core.PageBefore(anchor), after → core.PageAfter(anchor), end → core.PageAtEnd().
  core.PagePosition positionFor(String currentPageId) {
    final anchor = anchorPageId ?? currentPageId;
    return switch (placement) {
      AddPagePlacement.before => core.PageBefore(anchor),
      AddPagePlacement.after => core.PageAfter(anchor),
      AddPagePlacement.end => const core.PageAtEnd(),
    };
  }

  @override
  bool operator ==(Object other) =>
      other is AddPageRequest &&
      other.placement == placement &&
      other.size == size &&
      other.background == background &&
      other.anchorPageId == anchorPageId;

  @override
  int get hashCode => Object.hash(placement, size, background, anchorPageId);

  @override
  String toString() =>
      'AddPageRequest(${placement.name}, $size, $background, '
      'anchor: $anchorPageId)';
}
