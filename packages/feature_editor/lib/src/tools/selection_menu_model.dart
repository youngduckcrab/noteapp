// lib/src/tools/selection_menu_model.dart — m5-7/04-editor 6.7.1 (which
// selection menu items show), 6.7.2 (the representative colour of '색 ●').
import 'package:flutter/foundation.dart';
import 'package:note_core/note_core.dart' as core;

/// What the selection menu v2 offers for a selection (6.7.1), read from the
/// CORE values of its elements (session.pageIfLoaded(pageId) — z order).
///
/// - [canRecolor]: a stroke, a shape, a text box or a math object is there
///   (INK's recolor leaves images and unknown objects out — S-14): '색' is
///   hidden otherwise (images only, unknown objects only, or both).
/// - [colorArgb]: the colour of the first recolorable element in z order
///   (stroke colour, shape stroke colour, text / math colour), opaque; null
///   when nothing can be recolored.
/// - [canTransform]: something other than unknown objects is there — '90°
///   돌리기' (and the single shape's '스타일') are hidden for unknown objects
///   only.
/// - [single]: the selection's single object (no strokes, one object) — the
///   kind-specific '더보기' items (6.7.1: (단일 텍스트) 편집 …).
@immutable
final class SelectionMenuModel {
  const SelectionMenuModel({
    required this.canRecolor,
    required this.colorArgb,
    required this.canTransform,
    required this.single,
    required this.elementCount,
  });

  /// Nothing selected (or the page is not loaded).
  static const empty = SelectionMenuModel(
    canRecolor: false,
    colorArgb: null,
    canTransform: false,
    single: null,
    elementCount: 0,
  );

  final bool canRecolor;
  final int? colorArgb;
  final bool canTransform;
  final core.PageObject? single;

  /// How many of the ids CORE still has.
  final int elementCount;

  /// The model of [ids] on [content] (ids CORE no longer has are left out).
  factory SelectionMenuModel.of(core.PageContent? content, Set<String> ids) {
    if (content == null || ids.isEmpty) return empty;
    final elements = <core.PageElement>[
      for (final id in ids) ?content.elementById(id),
    ]..sort(core.Stroke.compareOrder);
    if (elements.isEmpty) return empty;
    int? color;
    var transform = false;
    for (final e in elements) {
      final c = recolorableColorOf(e);
      if (c != null) color ??= c;
      if (e is! core.UnknownObject) transform = true;
    }
    final single = elements.length == 1 && elements.single is core.PageObject
        ? elements.single as core.PageObject
        : null;
    return SelectionMenuModel(
      canRecolor: color != null,
      colorArgb: color,
      canTransform: transform,
      single: single,
      elementCount: elements.length,
    );
  }

  /// The colour INK's recolor changes on [element] (made opaque), or null
  /// for an image or an unknown object.
  static int? recolorableColorOf(core.PageElement element) => switch (element) {
    core.Stroke(:final style) => _opaque(style.colorArgb),
    core.ShapeObject(:final style) => _opaque(style.strokeColorArgb),
    core.TextBoxObject(:final style) => _opaque(style.colorArgb),
    core.MathObject(:final style) => _opaque(style.colorArgb),
    core.ImageObject() || core.UnknownObject() => null,
  };

  /// 0xFF000000 | rgb without bit operations (web-safe arithmetic, 7.4.3).
  static int _opaque(int argb) => 0xFF000000 + argb % 0x1000000;

  @override
  bool operator ==(Object other) =>
      other is SelectionMenuModel &&
      other.canRecolor == canRecolor &&
      other.colorArgb == colorArgb &&
      other.canTransform == canTransform &&
      other.single == single &&
      other.elementCount == elementCount;

  @override
  int get hashCode =>
      Object.hash(canRecolor, colorArgb, canTransform, single, elementCount);

  @override
  String toString() =>
      'SelectionMenuModel(recolor: $canRecolor, colour: $colorArgb, '
      'transform: $canTransform, single: ${single?.id}, '
      'elements: $elementCount)';
}
