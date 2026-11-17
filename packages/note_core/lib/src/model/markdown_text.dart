// lib/src/model/markdown_text.dart — (v2.17-md) contract 00-overview 7.9 C217M-02,
// m5-7/08-markdown 4.2: the body of an MD 문서 (EntityKind.markdown, one per note,
// deterministic id 'md_<noteId>' — two devices never create two bodies for one document).
import 'package:meta/meta.dart';

import '../common/hlc.dart';
import '../common/ids.dart';
import '../common/json_read.dart';
import 'sync_entity.dart';

@immutable
final class MarkdownText implements SyncEntity {
  MarkdownText({
    required this.noteId,
    required this.text,
    required this.createdAt,
    int? updatedAt,
    this.deletedAt,
    this.version,
  }) : id = idFor(noteId),
       updatedAt = updatedAt ?? createdAt;

  /// The body id of the MD 문서 [noteId].
  static String idFor(NoteId noteId) => 'md_$noteId';

  @override
  final String id;
  final NoteId noteId;

  /// The original text, byte for byte (BOM and CRLF kept — 08-markdown 4.6).
  final String text;
  final EpochMillis createdAt;
  final EpochMillis updatedAt;

  /// Unused in v1 (the trash works on the note); kept like every other kind.
  @override
  final EpochMillis? deletedAt;
  @override
  final Hlc? version;

  @override
  EntityKind get kind => EntityKind.markdown;

  @override
  bool get isDeleted => deletedAt != null;

  /// `{id, noteId, text, createdAt, updatedAt, deletedAt, version}`.
  @override
  Map<String, Object?> toJson() => {
    'id': id,
    'noteId': noteId,
    'text': text,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    'deletedAt': deletedAt,
    'version': version?.toString(),
  };

  /// FormatException when `id` is not idFor(noteId).
  factory MarkdownText.fromJson(Map<String, Object?> json) {
    final id = readString(json, 'id');
    final noteId = readString(json, 'noteId');
    if (id != idFor(noteId)) {
      throw FormatException(
        'MarkdownText id "$id" is not idFor("$noteId") = "${idFor(noteId)}"',
      );
    }
    return MarkdownText(
      noteId: noteId,
      text: readString(json, 'text'),
      createdAt: readInt(json, 'createdAt'),
      updatedAt: readInt(json, 'updatedAt'),
      deletedAt: readIntOrNull(json, 'deletedAt'),
      version: readVersion(json),
    );
  }

  MarkdownText copyWith({
    String? text,
    EpochMillis? updatedAt,
    EpochMillis? deletedAt,
    bool clearDeletedAt = false,
    Hlc? version,
  }) => MarkdownText(
    noteId: noteId,
    text: text ?? this.text,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: clearDeletedAt ? null : deletedAt ?? this.deletedAt,
    version: version ?? this.version,
  );

  @override
  bool operator ==(Object other) =>
      other is MarkdownText &&
      other.id == id &&
      other.noteId == noteId &&
      other.text == text &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt &&
      other.deletedAt == deletedAt &&
      other.version == version;

  @override
  int get hashCode =>
      Object.hash(id, noteId, text, createdAt, updatedAt, deletedAt, version);

  @override
  String toString() =>
      'MarkdownText($id, ${text.length} chars${isDeleted ? ', deleted' : ''})';
}
