// lib/src/sync/field_versions.dart — contract 00-overview 7.2.10 / CORE 4.6, 6.3, 6.10.2.
// Contract comments are kept verbatim (they contain <placeholders>).
// ignore_for_file: unintended_html_in_doc_comment
import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import '../common/hlc.dart';
import '../common/json_read.dart';
import '../model/sync_entity.dart';

const MapEquality<String, Hlc> _mapEq = MapEquality<String, Hlc>();

/// Per-field HLC of the last write. Fields without an override carry [base].
@immutable
final class EntityFieldVersions {
  // overrides only > base
  const EntityFieldVersions(this.base, [this.overrides = const {}]);

  final Hlc base;
  final Map<String, Hlc> overrides;

  Hlc of(String field) => overrides[field] ?? base;

  Hlc get max {
    var m = base;
    for (final v in overrides.values) {
      if (v > m) m = v;
    }
    return m;
  }

  /// {"b": "<hlc>", "o": {"<field>": "<hlc>"}} — "o" omitted when empty, keys sorted.
  Map<String, Object?> toJson() {
    final kept = [
      for (final e in overrides.entries)
        if (e.value > base) e,
    ]..sort((a, b) => a.key.compareTo(b.key));
    return {
      'b': base.toString(),
      if (kept.isNotEmpty)
        'o': {for (final e in kept) e.key: e.value.toString()},
    };
  }

  /// Throws FormatException. Overrides that are not newer than "b" are dropped.
  factory EntityFieldVersions.fromJson(Map<String, Object?> json) {
    final base = Hlc.parse(readString(json, 'b'));
    final o = readMapOrNull(json, 'o');
    if (o == null) return EntityFieldVersions(base);
    final overrides = <String, Hlc>{};
    final keys = o.keys.toList()..sort();
    for (final k in keys) {
      final v = Hlc.parse(asString(o[k], 'o.$k'));
      if (v > base) overrides[k] = v;
    }
    return EntityFieldVersions(base, Map.unmodifiable(overrides));
  }

  @override
  bool operator ==(Object other) =>
      other is EntityFieldVersions &&
      other.base == base &&
      _mapEq.equals(
        _normalized(other.overrides, other.base),
        _normalized(overrides, base),
      );

  static Map<String, Hlc> _normalized(Map<String, Hlc> o, Hlc base) => {
    for (final e in o.entries)
      if (e.value > base) e.key: e.value,
  };

  @override
  int get hashCode =>
      Object.hash(base, _mapEq.hash(_normalized(overrides, base)));

  @override
  String toString() => 'EntityFieldVersions(${toJson()})';
}

@immutable
final class VersionedEntity {
  // invariant: entity.version == versions.max
  const VersionedEntity(this.entity, this.versions);

  final SyncEntity entity;
  final EntityFieldVersions versions;

  @override
  bool operator ==(Object other) =>
      other is VersionedEntity &&
      other.entity == entity &&
      other.versions == versions;

  @override
  int get hashCode => Object.hash(entity, versions);
}
