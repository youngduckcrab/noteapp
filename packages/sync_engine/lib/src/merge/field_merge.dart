// Internal (not exported). Field-level LWW merge of two snapshots of one entity
// (6.3.2): pure, commutative, associative and idempotent (equality = doc.json and
// versions.toJson()).
//
// Units cover every key of the kind (CORE 6.3 table) plus any other key present in
// either JSON or field-version overrides: a key a snapshot lacks takes part with that
// snapshot's version for it (its base), so a newer snapshot without the key beats an
// older one with it, the same way whichever order merges run in.
//
// Per merge unit (FieldUnits, 6.3.1) the whole unit comes from the snapshot with the
// larger unit version (max over its fields). Ties (only when the invariant 6.3.3 is
// broken) go to the larger member versions (sorted field names), then the larger
// canonical JSON of the unit values. Special keys: note `schemaVersion` = the larger
// value with the larger version; asset `storagePath` = a non-null value beats null,
// otherwise LWW. Meta keys: `version` = merged versions.max, `updatedAt` = larger,
// `createdAt` = smaller (equal on both sides in practice — symmetric so the merge
// stays commutative), `id` / `key` must be equal. Merged versions: base = the smaller
// base, overrides = unit fields whose version is above it.
//
// (2nd round, S2-1) For the one-unit kinds (FieldUnits.wholeUnitExcept — pageObject,
// handwriting) a key outside FieldUnits.keysOf is 'loose': where a snapshot lacks it,
// its version takes no part (no tie-break, no override in the result). Such a key is
// in the unit only while some snapshot has it, so its base version would otherwise
// make the result depend on the merge order (07-sync 6.2.2, S2-1 note).
import 'package:collection/collection.dart';
import 'package:note_core/note_core.dart';

import '../codec/canonical_json.dart';
import '../model/field_units.dart';
import '../model/records.dart';
import '../model/sync_doc.dart';

const DeepCollectionEquality _deepEq = DeepCollectionEquality();

/// A merge and, per side, the units whose merged state differs from that side.
final class FieldMergeResult {
  const FieldMergeResult(
    this.merged, {
    required this.changedForA,
    required this.changedForB,
  });

  final UpsertRecord merged;

  /// Units [merged] takes from b (or combines): a must change them — "b won".
  final List<Set<String>> changedForA;

  /// Units [merged] takes from a (or combines): b must change them — "a won".
  final List<Set<String>> changedForB;
}

abstract final class FieldMerge {
  /// Merge of two snapshots of the same entity. ArgumentError when kind, id or
  /// key differ.
  static UpsertRecord mergeRecords(UpsertRecord a, UpsertRecord b) =>
      merge(a, b).merged;

  static FieldMergeResult merge(UpsertRecord a, UpsertRecord b) {
    final kind = a.doc.kind;
    if (b.doc.kind != kind || b.doc.id != a.doc.id) {
      throw ArgumentError(
        'merge of different entities: ${a.doc.ref} and ${b.doc.ref}',
      );
    }
    final aj = a.doc.json, bj = b.doc.json;
    for (final k in const ['id', 'key']) {
      if (aj.containsKey(k) && bj.containsKey(k) && aj[k] != bj[k]) {
        throw ArgumentError('merge: $k differs (${aj[k]} / ${bj[k]})');
      }
    }

    final out = <String, Object?>{};
    final outVersions = <String, Hlc>{};
    final changedForA = <Set<String>>[];
    final changedForB = <Set<String>>[];
    final keys = {
      ...FieldUnits.keysOf(kind),
      ...aj.keys,
      ...bj.keys,
      ...a.versions.overrides.keys,
      ...b.versions.overrides.keys,
    };
    final known = FieldUnits.keysOf(kind);
    final whole = FieldUnits.wholeUnitExcept(kind) != null;
    for (final unit in FieldUnits.unitsFor(kind, keys)) {
      final fields = unit.toList()..sort();
      final loose = whole
          ? {
              for (final f in fields)
                if (!known.contains(f)) f,
            }
          : const <String>{};
      final sa = _UnitState.of(a, fields, loose);
      final sb = _UnitState.of(b, fields, loose);
      final merged = _mergeUnit(kind, sa, sb);
      merged.writeTo(out, outVersions);
      if (!merged.sameAs(sa)) changedForA.add(unit);
      if (!merged.sameAs(sb)) changedForB.add(unit);
    }

    // Meta keys (6.3.1).
    for (final k in const ['id', 'key']) {
      if (aj.containsKey(k) || bj.containsKey(k)) {
        out[k] = aj.containsKey(k) ? aj[k] : bj[k];
      }
    }
    _metaValue(out, 'createdAt', aj, bj, takeLarger: false);
    _metaValue(out, 'updatedAt', aj, bj, takeLarger: true);

    final base = a.versions.base < b.versions.base
        ? a.versions.base
        : b.versions.base;
    final overrideKeys = outVersions.keys.toList()..sort();
    final versions = EntityFieldVersions(
      base,
      Map<String, Hlc>.unmodifiable({
        for (final k in overrideKeys)
          if (outVersions[k]! > base) k: outVersions[k]!,
      }),
    );
    out['version'] = versions.max.toString();

    return FieldMergeResult(
      UpsertRecord(SyncDoc(kind: kind, id: a.doc.id, json: out), versions),
      changedForA: changedForA,
      changedForB: changedForB,
    );
  }

  static _UnitState _mergeUnit(EntityKind kind, _UnitState a, _UnitState b) {
    final fields = a.fields;
    if (kind == EntityKind.note &&
        fields.length == 1 &&
        fields.single == 'schemaVersion') {
      return _UnitState.join(a, b);
    }
    final preferNonNull =
        kind == EntityKind.asset &&
        fields.length == 1 &&
        fields.single == 'storagePath';
    return _compare(a, b, preferNonNull: preferNonNull) >= 0 ? a : b;
  }

  /// > 0 when [a] wins, < 0 when [b] wins, 0 only for identical states.
  static int _compare(
    _UnitState a,
    _UnitState b, {
    required bool preferNonNull,
  }) {
    if (preferNonNull) {
      final an = a.hasNonNullValue, bn = b.hasNonNullValue;
      if (an != bn) return an ? 1 : -1;
    }
    final byMax = a.maxVersion.compareTo(b.maxVersion);
    if (byMax != 0) return byMax;
    for (final f in a.fields) {
      if (a.loose.contains(f)) {
        // Absent loose key: no version; a present one beats an absent one.
        final ap = a.present[f]!, bp = b.present[f]!;
        if (ap != bp) return ap ? 1 : -1;
        if (!ap) continue;
      }
      final c = a.versions[f]!.compareTo(b.versions[f]!);
      if (c != 0) return c;
    }
    return a.canonicalValues.compareTo(b.canonicalValues);
  }

  static void _metaValue(
    Map<String, Object?> out,
    String key,
    Map<String, Object?> aj,
    Map<String, Object?> bj, {
    required bool takeLarger,
  }) {
    final av = aj[key], bv = bj[key];
    if (av == null && bv == null) {
      if (aj.containsKey(key) || bj.containsKey(key)) out[key] = null;
      return;
    }
    if (av == null || bv == null) {
      out[key] = av ?? bv;
      return;
    }
    final c = av is num && bv is num
        ? av.compareTo(bv)
        : canonicalJson(av).compareTo(canonicalJson(bv));
    out[key] = (c >= 0) == takeLarger ? av : bv;
  }
}

/// One snapshot's values and versions of one unit.
final class _UnitState {
  _UnitState(
    this.fields,
    this.present,
    this.values,
    this.versions, [
    this.loose = const {},
  ]);

  factory _UnitState.of(
    UpsertRecord r,
    List<String> fields,
    Set<String> loose,
  ) {
    final json = r.doc.json;
    return _UnitState(
      fields,
      {for (final f in fields) f: json.containsKey(f)},
      {for (final f in fields) f: json[f]},
      {for (final f in fields) f: r.versions.of(f)},
      loose,
    );
  }

  /// Single-key unit combined by maximum (note schemaVersion).
  factory _UnitState.join(_UnitState a, _UnitState b) {
    final f = a.fields.single;
    final av = a.values[f], bv = b.values[f];
    final Object? value;
    final bool present;
    if (av is num && bv is num) {
      value = av >= bv ? av : bv;
      present = true;
    } else if (av != null || bv != null) {
      // Only one side has a number (or the data is malformed): LWW-like by
      // presence, then canonical order, to stay symmetric.
      final ac = canonicalJson(av), bc = canonicalJson(bv);
      value = av == null
          ? bv
          : (bv == null ? av : (ac.compareTo(bc) >= 0 ? av : bv));
      present = true;
    } else {
      value = null;
      present = a.present[f]! || b.present[f]!;
    }
    final va = a.versions[f]!, vb = b.versions[f]!;
    return _UnitState(a.fields, {f: present}, {f: value}, {
      f: va > vb ? va : vb,
    });
  }

  final List<String> fields;
  final Map<String, bool> present;
  final Map<String, Object?> values;
  final Map<String, Hlc> versions;

  /// Fields whose version counts only where present (see the file comment).
  final Set<String> loose;

  bool _versionless(String f) => !present[f]! && loose.contains(f);

  Hlc get maxVersion {
    var m = versions[fields.first]!;
    for (final f in fields) {
      if (versions[f]! > m) m = versions[f]!;
    }
    return m;
  }

  bool get hasNonNullValue => fields.any((f) => values[f] != null);

  String get canonicalValues => canonicalJson([
    for (final f in fields) present[f]! ? [1, values[f]] : [0],
  ]);

  bool sameAs(_UnitState other) {
    for (final f in fields) {
      if (present[f] != other.present[f]) return false;
      if (_versionless(f)) continue;
      if (versions[f] != other.versions[f]) return false;
      if (!_deepEq.equals(values[f], other.values[f])) return false;
    }
    return true;
  }

  void writeTo(Map<String, Object?> json, Map<String, Hlc> fieldVersions) {
    for (final f in fields) {
      if (present[f]!) json[f] = values[f];
      if (!_versionless(f)) fieldVersions[f] = versions[f]!;
    }
  }
}
