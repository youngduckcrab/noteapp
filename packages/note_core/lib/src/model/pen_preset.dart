// lib/src/model/pen_preset.dart — contract 00-overview 7.2.6 / CORE 4.2.4.
import 'package:meta/meta.dart';

import '../common/hlc.dart';
import '../common/ids.dart';
import '../common/json_read.dart';
import 'pen_style.dart';
import 'sync_entity.dart';

@immutable
final class PenPreset implements SyncEntity {
  const PenPreset({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.style,
    this.group,
    this.pinned = true,
    required this.sortKey,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    this.version,
  });

  @override
  final PresetId id;
  final OwnerId ownerId;
  final String name; // 1..60 chars
  final StrokeStyle style;
  final String? group; // group name, e.g. '수업용'; null = ungrouped
  final bool pinned; // shown in the toolbar preset bar
  final String sortKey;
  final EpochMillis createdAt, updatedAt;
  @override
  final EpochMillis? deletedAt;
  @override
  final Hlc? version;
  @override
  EntityKind get kind => EntityKind.penPreset;
  @override
  bool get isDeleted => deletedAt != null;

  PenPreset copyWith({
    OwnerId? ownerId,
    String? name,
    StrokeStyle? style,
    String? group,
    bool clearGroup = false,
    bool? pinned,
    String? sortKey,
    EpochMillis? updatedAt,
    EpochMillis? deletedAt,
    bool clearDeletedAt = false,
    Hlc? version,
  }) => PenPreset(
    id: id,
    ownerId: ownerId ?? this.ownerId,
    name: name ?? this.name,
    style: style ?? this.style,
    group: clearGroup ? null : group ?? this.group,
    pinned: pinned ?? this.pinned,
    sortKey: sortKey ?? this.sortKey,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: clearDeletedAt ? null : deletedAt ?? this.deletedAt,
    version: version ?? this.version,
  );

  @override
  Map<String, Object?> toJson() => {
    'id': id,
    'ownerId': ownerId,
    'name': name,
    'style': style.toJson(),
    'group': group,
    'pinned': pinned,
    'sortKey': sortKey,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    'deletedAt': deletedAt,
    'version': version?.toString(),
  };

  factory PenPreset.fromJson(Map<String, Object?> json) => PenPreset(
    id: readString(json, 'id'),
    ownerId: readString(json, 'ownerId'),
    name: readString(json, 'name'),
    style: StrokeStyle.fromJson(readMap(json, 'style')),
    group: readStringOrNull(json, 'group'),
    pinned: readBoolOr(json, 'pinned', true),
    sortKey: readString(json, 'sortKey'),
    createdAt: readInt(json, 'createdAt'),
    updatedAt: readInt(json, 'updatedAt'),
    deletedAt: readIntOrNull(json, 'deletedAt'),
    version: readVersion(json),
  );

  @override
  bool operator ==(Object other) =>
      other is PenPreset &&
      other.id == id &&
      other.ownerId == ownerId &&
      other.name == name &&
      other.style == style &&
      other.group == group &&
      other.pinned == pinned &&
      other.sortKey == sortKey &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt &&
      other.deletedAt == deletedAt &&
      other.version == version;

  @override
  int get hashCode => Object.hash(
    id,
    ownerId,
    name,
    style,
    group,
    pinned,
    sortKey,
    createdAt,
    updatedAt,
    deletedAt,
    version,
  );

  @override
  String toString() => 'PenPreset($id, "$name", ${style.tool.name})';
}
