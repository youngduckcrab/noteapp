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
    this.recordingId,
    this.recordingOffsetMs,
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
  }) => TextBoxObject(
    id: id,
    pageId: pageId,
    frame: frame ?? this.frame,
    text: text ?? this.text,
    style: style ?? this.style,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt,
    version: version,
    recordingId: recordingId,
    recordingOffsetMs: recordingOffsetMs,
  );

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
  final RecordingId? recordingId;
  @override
  final int? recordingOffsetMs;

  @override
  Set<AssetId> get referencedAssets => const {};

  /// (CORE 6.2.5, CP-2) frame.transformed(m) + fontSizePt × s clamped [6, 144] — the wrap
  /// width and the text scale together, whatever [scaleWidth] says.
  @override
  PageObject transformed(Affine2 m, {bool scaleWidth = true}) => copyWith(
    frame: frame.transformed(m),
    style: style.copyWith(
      fontSizePt: _scaled(
        style.fontSizePt,
        m,
        TextBoxStyle.minFontSize,
        TextBoxStyle.maxFontSize,
      ),
    ),
  );

  @override
  PageObject copyTo({
    required ElementId id,
    required PageId pageId,
    required EpochMillis createdAt,
  }) => TextBoxObject(
    id: id,
    pageId: pageId,
    frame: frame,
    text: text,
    style: style,
    createdAt: createdAt,
    recordingId: recordingId,
    recordingOffsetMs: recordingOffsetMs,
  );

  @override
  PageObject copyWithMeta({
    EpochMillis? updatedAt,
    EpochMillis? deletedAt,
    bool clearDeletedAt = false,
    Hlc? version,
  }) => TextBoxObject(
    id: id,
    pageId: pageId,
    frame: frame,
    text: text,
    style: style,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: clearDeletedAt ? null : deletedAt ?? this.deletedAt,
    version: version ?? this.version,
    recordingId: recordingId,
    recordingOffsetMs: recordingOffsetMs,
  );

  @override
  int get estimatedBytes => 160 + 2 * text.length;

  @override
  Map<String, Object?> toJson() =>
      _objectJson(this, {'text': text, 'style': style.toJson()});

  factory TextBoxObject._fromJson(Map<String, Object?> json) => TextBoxObject(
    id: readString(json, 'id'),
    pageId: readString(json, 'pageId'),
    frame: _readFrame(json),
    text: readString(json, 'text'),
    style: TextBoxStyle.fromJson(readMap(json, 'style')),
    createdAt: readInt(json, 'createdAt'),
    updatedAt: readInt(json, 'updatedAt'),
    deletedAt: readIntOrNull(json, 'deletedAt'),
    version: readVersion(json),
    recordingId: readStringOrNull(json, 'recordingId'),
    recordingOffsetMs: readIntOrNull(json, 'recordingOffsetMs'),
  );

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
      other.version == version &&
      other.recordingId == recordingId &&
      other.recordingOffsetMs == recordingOffsetMs;

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
    recordingId,
    recordingOffsetMs,
  );

  @override
  String toString() =>
      'TextBoxObject($id, page: $pageId, ${text.length} chars'
      '${isDeleted ? ', deleted' : ''})';
}
