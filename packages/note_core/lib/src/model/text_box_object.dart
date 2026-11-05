// lib/src/model/text_box_object.dart — (v2.0) part of stroke.dart. 2nd-round contract
// 7.2.2 / 02-core 4.2, 4.3.
part of 'stroke.dart';

final class TextBoxObject extends PageObject {
  TextBoxObject({
    required this.id,
    required this.pageId,
    required this.frame,
    required this.text,
    required this.style,
    required this.createdAt,
    int? updatedAt,
    this.deletedAt,
    this.version,
  }) : updatedAt = updatedAt ?? createdAt;
  @override
  String get type => 'text';

  /// frame.rect.width = wrap width; height = laid-out height written by EDITOR with
  /// INK InkTextLayout.measure (7.2.9). INK clips the text to the frame (K-6).
  @override
  final ElementFrame frame;
  final String text; // plain text, '\n' = line break, ≤ maxTextLength
  final TextBoxStyle style;
  @override
  PageRect get bounds => frame.bounds;
  TextBoxObject copyWith({
    ElementFrame? frame,
    String? text,
    TextBoxStyle? style,
    EpochMillis? updatedAt,
  }) => notYet('T20b', 'TextBoxObject.copyWith');

  // CORE 4.3: same member set as ShapeObject
  @override
  final ElementId id;
  @override
  final PageId pageId;
  @override
  final EpochMillis createdAt;
  @override
  final EpochMillis updatedAt; // constructor: updatedAt ?? createdAt (as Stroke)
  @override
  final EpochMillis? deletedAt;
  @override
  final Hlc? version;

  @override
  Set<AssetId> get referencedAssets => const {};

  @override
  PageObject transformed(Affine2 m, {bool scaleWidth = true}) =>
      notYet('T20b', 'TextBoxObject.transformed');

  @override
  PageObject copyTo({
    required ElementId id,
    required PageId pageId,
    required EpochMillis createdAt,
  }) => notYet('T20b', 'TextBoxObject.copyTo');

  @override
  PageObject copyWithMeta({
    EpochMillis? updatedAt,
    EpochMillis? deletedAt,
    bool clearDeletedAt = false,
    Hlc? version,
  }) => notYet('T20b', 'TextBoxObject.copyWithMeta');

  @override
  int get estimatedBytes => notYet('T20b', 'TextBoxObject.estimatedBytes');

  @override
  Map<String, Object?> toJson() => notYet('T20a', 'TextBoxObject.toJson');

  // CORE 4.3: ==, hashCode over every field
  @override
  bool operator ==(Object other) =>
      other is TextBoxObject &&
      other.id == id &&
      other.pageId == pageId &&
      other.frame == frame &&
      other.text == text &&
      other.style == style &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt &&
      other.deletedAt == deletedAt &&
      other.version == version;

  @override
  int get hashCode => Object.hash(
    id,
    pageId,
    frame,
    text,
    style,
    createdAt,
    updatedAt,
    deletedAt,
    version,
  );

  @override
  String toString() =>
      'TextBoxObject($id, page: $pageId, ${text.length} chars'
      '${isDeleted ? ', deleted' : ''})';
}
