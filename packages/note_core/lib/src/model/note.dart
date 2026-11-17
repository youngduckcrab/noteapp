// lib/src/model/note.dart — contract 00-overview 7.2.6 / CORE 4.2.4.
import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import '../common/hlc.dart';
import '../common/ids.dart';
import '../common/json_read.dart';
import 'sync_entity.dart';

const ListEquality<String> _listEq = ListEquality<String>();

/// (v2.17-md, C217M-01) Schema version of an MD 문서 (markdown document) note. A note's
/// format is DERIVED from its `schemaVersion` range — there is no separate field, JSON key or
/// column, so every path that copies or rebuilds a Note (copy, recovery copy, row / JSON
/// mappers, sync) keeps the format as long as it keeps `schemaVersion`:
///
/// * 1..99 — handwriting (ink) note formats ([kNoteSchemaVersion] is the one this app edits);
/// * 100..199 — markdown document formats ([kMarkdownNoteSchemaVersion] is this app's);
/// * 200 and above — reserved for later formats ([NoteFormat.unknown]).
///
/// An app from before v2.17-md sees 100 > its kNoteSchemaVersion and opens the note read-only
/// ('새 버전 앱 필요'), so it can never add pages to an MD 문서.
const int kMarkdownNoteSchemaVersion = 100;

/// First schema version of the formats after markdown (see [kMarkdownNoteSchemaVersion]).
const int kLaterNoteFormatSchemaVersion = 200;

/// (v2.17-md, C217M-01) What a note holds. Derived from [Note.schemaVersion]; set when the
/// note is created and never changed (sync merges `schemaVersion` as the larger value, and
/// CORE refuses a write that moves a stored note into another format's range).
enum NoteFormat {
  /// Handwriting pages (schemaVersion 1..99).
  ink,

  /// MD 문서: the note's text lives in its markdown body (schemaVersion 100..199).
  markdown,

  /// A format of a later app version (schemaVersion ≥ 200): read-only, never opened.
  unknown;

  /// The format of a stored [schemaVersion] (values below 1 count as ink — the migrator's
  /// range).
  static NoteFormat ofSchemaVersion(int schemaVersion) =>
      schemaVersion < kMarkdownNoteSchemaVersion
      ? NoteFormat.ink
      : schemaVersion < kLaterNoteFormatSchemaVersion
      ? NoteFormat.markdown
      : NoteFormat.unknown;
}

@immutable
sealed class NoteCover {
  const NoteCover();
  Map<String, Object?> toJson();

  static NoteCover fromJson(Map<String, Object?> json) {
    final type = readString(json, 'type');
    return switch (type) {
      'firstPage' => const FirstPageCover(),
      'color' => ColorCover(readInt(json, 'color')),
      'asset' => AssetCover(readString(json, 'assetId')),
      _ => throw FormatException('Unknown note cover type', type),
    };
  }
}

final class FirstPageCover extends NoteCover {
  const FirstPageCover();

  @override
  Map<String, Object?> toJson() => {'type': 'firstPage'};

  @override
  bool operator ==(Object other) => other is FirstPageCover;

  @override
  int get hashCode => (FirstPageCover).hashCode;

  @override
  String toString() => 'FirstPageCover()';
}

final class ColorCover extends NoteCover {
  const ColorCover(this.colorArgb);
  final int colorArgb;

  @override
  Map<String, Object?> toJson() => {'type': 'color', 'color': colorArgb};

  @override
  bool operator ==(Object other) =>
      other is ColorCover && other.colorArgb == colorArgb;

  @override
  int get hashCode => Object.hash('color', colorArgb);

  @override
  String toString() => 'ColorCover(0x${colorArgb.toRadixString(16)})';
}

final class AssetCover extends NoteCover {
  const AssetCover(this.assetId);
  final AssetId assetId;

  @override
  Map<String, Object?> toJson() => {'type': 'asset', 'assetId': assetId};

  @override
  bool operator ==(Object other) =>
      other is AssetCover && other.assetId == assetId;

  @override
  int get hashCode => Object.hash('asset', assetId);

  @override
  String toString() => 'AssetCover($assetId)';
}

@immutable
final class Note implements SyncEntity {
  const Note({
    required this.id,
    required this.ownerId,
    this.folderId,
    required this.title,
    this.cover = const FirstPageCover(),
    this.tags = const [],
    this.isFavorite = false,
    required this.sortKey,
    this.schemaVersion = kNoteSchemaVersion,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    this.trashRootId,
    this.version,
    this.pageCount = 0,
    this.firstPageId,
    this.lastOpenedAt,
  });

  @override
  final NoteId id;
  final OwnerId ownerId;
  final FolderId? folderId; // null = top level
  final String title; // trimmed, 1..200 chars
  final NoteCover cover;
  final List<String> tags; // each 1..32 chars, <= 50 tags
  final bool isFavorite;
  final String sortKey;
  final int schemaVersion;
  final EpochMillis createdAt;
  final EpochMillis updatedAt; // bumped by any edit inside the note
  @override
  final EpochMillis? deletedAt;
  final String? trashRootId;
  @override
  final Hlc? version;
  final int pageCount; // local only, active pages
  final PageId? firstPageId; // local only, cover thumbnail source
  final EpochMillis? lastOpenedAt; // local only (12.1 Q11)
  @override
  EntityKind get kind => EntityKind.note;
  @override
  bool get isDeleted => deletedAt != null;

  /// (v2.17-md) Derived from [schemaVersion] (see [kMarkdownNoteSchemaVersion]).
  NoteFormat get format => NoteFormat.ofSchemaVersion(schemaVersion);

  /// (v2.17-md) An MD 문서 (markdown document): no pages, the text is its markdown body.
  bool get isMarkdown => format == NoteFormat.markdown;

  /// True when this note was written by a newer app: an ink note above [kNoteSchemaVersion],
  /// an MD 문서 above [kMarkdownNoteSchemaVersion], any [NoteFormat.unknown] note
  /// (v2.17-md: compared with the version of the note's own format).
  bool get requiresNewerApp => switch (format) {
    NoteFormat.ink => schemaVersion > kNoteSchemaVersion,
    NoteFormat.markdown => schemaVersion > kMarkdownNoteSchemaVersion,
    NoteFormat.unknown => true,
  };

  Note copyWith({
    OwnerId? ownerId,
    FolderId? folderId,
    bool clearFolderId = false,
    String? title,
    NoteCover? cover,
    List<String>? tags,
    bool? isFavorite,
    String? sortKey,
    int? schemaVersion,
    EpochMillis? updatedAt,
    EpochMillis? deletedAt,
    bool clearDeletedAt = false,
    String? trashRootId,
    bool clearTrashRootId = false,
    Hlc? version,
    int? pageCount,
    PageId? firstPageId,
    bool clearFirstPageId = false,
    EpochMillis? lastOpenedAt,
  }) => Note(
    id: id,
    ownerId: ownerId ?? this.ownerId,
    folderId: clearFolderId ? null : folderId ?? this.folderId,
    title: title ?? this.title,
    cover: cover ?? this.cover,
    tags: tags ?? this.tags,
    isFavorite: isFavorite ?? this.isFavorite,
    sortKey: sortKey ?? this.sortKey,
    schemaVersion: schemaVersion ?? this.schemaVersion,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: clearDeletedAt ? null : deletedAt ?? this.deletedAt,
    trashRootId: clearTrashRootId ? null : trashRootId ?? this.trashRootId,
    version: version ?? this.version,
    pageCount: pageCount ?? this.pageCount,
    firstPageId: clearFirstPageId ? null : firstPageId ?? this.firstPageId,
    lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
  );

  @override
  Map<String, Object?> toJson() => {
    'id': id,
    'ownerId': ownerId,
    'folderId': folderId,
    'title': title,
    'cover': cover.toJson(),
    'tags': tags,
    'isFavorite': isFavorite,
    'sortKey': sortKey,
    'schemaVersion': schemaVersion,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    'deletedAt': deletedAt,
    'trashRootId': trashRootId,
    'version': version?.toString(),
  };

  /// Local-only fields get fixed values: pageCount 0, firstPageId null, lastOpenedAt null.
  factory Note.fromJson(Map<String, Object?> json) {
    final coverJson = readMapOrNull(json, 'cover');
    final tagsJson = json['tags'];
    return Note(
      id: readString(json, 'id'),
      ownerId: readString(json, 'ownerId'),
      folderId: readStringOrNull(json, 'folderId'),
      title: readString(json, 'title'),
      cover: coverJson == null
          ? const FirstPageCover()
          : NoteCover.fromJson(coverJson),
      tags: tagsJson == null
          ? const []
          : List<String>.unmodifiable([
              for (final t in asList(tagsJson, 'tags')) asString(t, 'tags'),
            ]),
      isFavorite: readBoolOr(json, 'isFavorite', false),
      sortKey: readString(json, 'sortKey'),
      schemaVersion: readIntOrNull(json, 'schemaVersion') ?? kNoteSchemaVersion,
      createdAt: readInt(json, 'createdAt'),
      updatedAt: readInt(json, 'updatedAt'),
      deletedAt: readIntOrNull(json, 'deletedAt'),
      trashRootId: readStringOrNull(json, 'trashRootId'),
      version: readVersion(json),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Note &&
      other.id == id &&
      other.ownerId == ownerId &&
      other.folderId == folderId &&
      other.title == title &&
      other.cover == cover &&
      _listEq.equals(other.tags, tags) &&
      other.isFavorite == isFavorite &&
      other.sortKey == sortKey &&
      other.schemaVersion == schemaVersion &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt &&
      other.deletedAt == deletedAt &&
      other.trashRootId == trashRootId &&
      other.version == version &&
      other.pageCount == pageCount &&
      other.firstPageId == firstPageId &&
      other.lastOpenedAt == lastOpenedAt;

  @override
  int get hashCode => Object.hash(
    id,
    ownerId,
    folderId,
    title,
    cover,
    _listEq.hash(tags),
    isFavorite,
    sortKey,
    schemaVersion,
    createdAt,
    updatedAt,
    deletedAt,
    trashRootId,
    version,
    pageCount,
    firstPageId,
    lastOpenedAt,
  );

  @override
  String toString() =>
      'Note($id, "$title", folder: $folderId, pages: $pageCount'
      '${isMarkdown ? ', markdown' : ''}'
      '${isDeleted ? ', deleted' : ''})';
}
